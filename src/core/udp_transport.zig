// ============================================================================
// udp_transport.zig
//
// Common implementation for:
//
//      MCastTransport
//      BCastTransport
//
// Notes:
//
//  * RX always binds to 0.0.0.0
//  * MCast local address selects join interface
//  * BCast local address selects outgoing interface (future)
//  * Loopback is rejected for multicast
//  * recvfrom() only, no Reader API
//  * Linux / BSD / Windows friendly design
//
// ============================================================================

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const Transport = @import("transport.zig").Transport;
const Logger = @import("logger.zig").Logger;
const Config = @import("../generated/Config.zig").k6bus.config;

var logger: *Logger = undefined;

// ============================================================================
// CONSTANTS
// ============================================================================
const is_windows = @import("builtin").os.tag == .windows;
const is_bsd = switch (@import("builtin").os.tag) {
    .freebsd,
    .openbsd,
    .netbsd,
    .dragonfly,
    => true,

    else => false,
};

// Linux value.
// BSD / Windows use different values.
const IP_ADD_MEMBERSHIP =
    if (is_windows) 5 else if (is_bsd) 12 else 35;

// ============================================================================
// TYPES
// ============================================================================
pub const UdpMode = enum {
    multicast,
    broadcast,
};

const LocalAddressKind = enum {
    any,
    ipv4,
};

const JoinRequest = extern struct {
    imr_multiaddr: u32,
    imr_address: u32,
};

fn UdpTransport(comptime mode: UdpMode) type {
    return struct {
        allocator: std.mem.Allocator,
        transport: Transport,

        target_addr: []const u8,
        local_addr: []const u8,
        target_port: u16,
        ttl: u8 = 1,

        send_buffer: u32 = 1 * 1024 * 1024,
        receive_buffer: u32 = 1 * 1024 * 1024,

        tx_socket: ?std.posix.socket_t = null,
        rx_socket: ?std.posix.socket_t = null,

        const Self = @This();

        // ====================================================================
        // CREATE
        // ====================================================================
        pub fn create(
            domain: *Domain,
            name: []const u8,
            target_addr: []const u8,
            local_addr: []const u8,
            port: u16,
            ttl: u8,
        ) !*Self {
            return createEx(
                domain,
                name,
                target_addr,
                local_addr,
                port,
                ttl,
                1 * 1024 * 1024,
                1 * 1024 * 1024,
            );
        }

        pub fn createEx(
            domain: *Domain,
            name: []const u8,
            target_addr: []const u8,
            local_addr: []const u8,
            port: u16,
            ttl: u8,
            send_buffer: u32,
            receive_buffer: u32,
        ) !*Self {
            const self = try domain.allocator.create(Self);
            errdefer domain.allocator.destroy(self);

            self.* = .{
                .allocator = domain.allocator,
                .transport = undefined,

                .target_addr = try domain.allocator.dupe(u8, target_addr),
                .local_addr = try domain.allocator.dupe(u8, local_addr),
                .target_port = port,
                .ttl = ttl,

                .send_buffer = send_buffer,
                .receive_buffer = receive_buffer,
            };
            try self.init(domain, name);

            logger = &domain.logger;

            return self;
        }

        fn init(self: *Self, domain: *Domain, name: []const u8) !void {
            try self.transport.init(
                domain,
                name,
                switch (mode) {
                    .multicast => .MCAST,
                    .broadcast => .BCAST,
                },
                Config.Encoding.RAW,
                self,
                sendBytes,
                mainLoop,
                closeOwner,
            );

            try self.validateConfig();
            try self.initSockets();
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.target_addr);
            self.allocator.free(self.local_addr);

            self.allocator.destroy(self);
        }

        // ====================================================================
        // VALIDATION
        // ====================================================================
        fn validateConfig(self: *Self) !void {
            switch (mode) {
                .broadcast => {},
                .multicast => {
                    if (isLoopback(self.local_addr))
                        return error.InvalidMulticastInterface;

                    const addr =
                        try std.net.Address.parseIp4(self.target_addr, 0);

                    const ip =
                        std.mem.nativeToBig(u32, addr.in.sa.addr);

                    if (ip < 0xE0000000 or ip > 0xEFFFFFFF)
                        return error.InvalidMulticastAddress;
                },
            }
        }

        // ====================================================================
        // SOCKETS
        // ====================================================================
        fn initSockets(self: *Self) !void {
            const tx =
                try std.posix.socket(
                    std.posix.AF.INET,
                    std.posix.SOCK.DGRAM,
                    std.posix.IPPROTO.UDP,
                );
            errdefer std.posix.close(tx);

            const rx =
                try std.posix.socket(
                    std.posix.AF.INET,
                    std.posix.SOCK.DGRAM,
                    std.posix.IPPROTO.UDP,
                );
            errdefer std.posix.close(rx);

            self.tx_socket = tx;
            self.rx_socket = rx;

            try self.configureCommonSocketOptions(tx, rx);
            try self.bindReceiver();

            switch (mode) {
                .broadcast => {
                    try self.configureBroadcast();
                },
                .multicast => {
                    try self.configureMulticast();
                },
            }
        }

        fn configureCommonSocketOptions(self: *Self, tx: std.posix.socket_t, rx: std.posix.socket_t) !void {
            const reuse: c_int = 1;

            try std.posix.setsockopt(
                rx,
                std.posix.SOL.SOCKET,
                std.posix.SO.REUSEADDR,
                std.mem.asBytes(&reuse),
            );

            try std.posix.setsockopt(
                rx,
                std.posix.SOL.SOCKET,
                std.posix.SO.RCVBUF,
                std.mem.asBytes(&self.receive_buffer),
            );

            try std.posix.setsockopt(
                tx,
                std.posix.SOL.SOCKET,
                std.posix.SO.SNDBUF,
                std.mem.asBytes(&self.send_buffer),
            );

            //
            // TODO:
            // Windows/Linux/BSD specific timeout wrapper.
            //
        }

        fn bindReceiver(self: *Self) !void {
            // IMPORTANT
            // RX ALWAYS BINDS TO ANY.
            // Multicast proved to work correctly this way.

            const bind_addr = try parseIPv4SockAddr("0.0.0.0", self.target_port);
            try std.posix.bind(
                self.rx_socket.?,
                @ptrCast(&bind_addr),
                @sizeOf(std.posix.sockaddr.in),
            );
        }

        fn configureBroadcast(self: *Self) !void {
            _ = self.*;

            const on: c_int = 1;

            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.SOL.SOCKET,
                std.posix.SO.BROADCAST,
                std.mem.asBytes(&on),
            );
        }

        fn configureMulticast(self: *Self) !void {
            const loop: u8 = 0;
            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.IPPROTO.IP,
                std.os.linux.IP.MULTICAST_LOOP,
                std.mem.asBytes(&loop),
            );

            const ttl: c_int = @intCast(self.ttl);
            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.IPPROTO.IP,
                std.os.linux.IP.MULTICAST_TTL,
                std.mem.asBytes(&ttl),
            );

            const interface = try multicastInterfaceAddress(self.local_addr);
            const group = try parseIPv4U32(
                self.target_addr,
            );
            const request = JoinRequest{
                .imr_multiaddr = group,
                .imr_address = interface,
            };

            try std.posix.setsockopt(
                self.rx_socket.?,
                std.posix.IPPROTO.IP,
                IP_ADD_MEMBERSHIP,
                std.mem.asBytes(&request),
            );
        }

        // ====================================================================
        // START / STOP
        // ====================================================================
        pub fn start(self: *Self) !void {
            try self.transport.start();

            logger.info("{s} started.", .{self.transport.name}, @src());
        }

        pub fn stop(self: *Self) void {
            self.transport.stop();

            logger.info("{s} stopped.", .{self.transport.name}, @src());
        }

        pub fn close(self: *Self) void {
            if (self.rx_socket) |s| {
                std.posix.close(s);
                self.rx_socket = null;
            }

            if (self.tx_socket) |s| {
                std.posix.close(s);
                self.tx_socket = null;
            }

            // self.deinit();

            logger.info("{s} terminated.", .{self.transport.name}, @src());
        }

        // ====================================================================
        // TX
        // ====================================================================
        fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
            const self: *Self = @ptrCast(@alignCast(owner));

            const sock = self.tx_socket orelse return false;
            var dst = parseIPv4SockAddr(self.target_addr, self.target_port) catch return false;

            const sent =
                std.posix.sendto(
                    sock,
                    wire_bytes,
                    0,
                    @ptrCast(&dst),
                    @sizeOf(std.posix.sockaddr.in),
                ) catch |err| {
                    logger.warning("{s} send error: {}", .{ self.transport.name, err }, @src());
                    return false;
                };

            return sent == wire_bytes.len;
        }

        // ====================================================================
        // RX
        // ====================================================================
        fn mainLoop(owner: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            const sock = self.rx_socket orelse return;

            var buffer: [64 * 1024]u8 = undefined;

            var from_addr: std.posix.sockaddr = undefined;
            var from_len: std.posix.socklen_t = @sizeOf(@TypeOf(from_addr));

            while (self.transport.running) {
                const bytes =
                    std.posix.recvfrom(
                        sock,
                        &buffer,
                        0,
                        &from_addr,
                        &from_len,
                    ) catch |err| {
                        switch (err) {
                            error.WouldBlock,
                            error.ConnectionTimedOut,
                            => continue,

                            else => {
                                if (!self.transport.running) break;
                                logger.warning("{s} recvfrom: {}", .{ self.transport.name, err }, @src());
                                continue;
                            },
                        }
                    };

                if (bytes == 0) continue;

                self.transport.receiveBytes(buffer[0..bytes]) catch |err| {
                    logger.warning("{s} receiveBytes: {}", .{ self.transport.name, err }, @src());
                };
            }
            logger.trace("{s} salida de while en mainloop", .{self.transport.name}, @src());
        }

        // ====================================================================
        // OWNER
        // ====================================================================
        fn closeOwner(owner: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            self.close();
        }
    };
}

// ============================================================================
// PUBLIC
// ============================================================================
pub const MCastTransport = UdpTransport(.multicast);
pub const BCastTransport = UdpTransport(.broadcast);

// ============================================================================
// HELPERS
// ============================================================================
fn isAny(text: []const u8) bool {
    return std.ascii.eqlIgnoreCase(text, "any");
}

fn isLoopback(text: []const u8) bool {
    return std.ascii.eqlIgnoreCase(text, "loopback");
}

fn parseIPv4U32(text: []const u8) !u32 {
    const addr = try std.net.Address.parseIp4(text, 0);
    return addr.in.sa.addr;
}

fn parseIPv4SockAddr(text: []const u8, port: u16) !std.posix.sockaddr.in {
    const addr = try std.net.Address.parseIp4(text, port);
    return addr.in.sa;
}

fn multicastInterfaceAddress(text: []const u8) !u32 {
    if (isAny(text)) return @bitCast([4]u8{ 0, 0, 0, 0 });
    if (isLoopback(text)) return error.InvalidMulticastInterface;

    return parseIPv4U32(text);
}
