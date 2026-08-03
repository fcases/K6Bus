// udp_transport.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const Transport = @import("transport.zig").Transport;
const Logger = @import("logger.zig").Logger;

const Config = @import("../generated/Config.zig").k6bus.config;

var logger: *Logger = undefined;

pub const UdpMode = enum {
    multicast,
    broadcast,
};

fn UdpTransport(comptime mode: UdpMode) type {
    return struct {
        allocator: std.mem.Allocator,
        transport: Transport,

        target_addr: []const u8,
        local_addr: []const u8,

        target_port: u16,

        ttl: u8 = 1,
        send_buffer: u32 = 134_217_727,
        receive_buffer: u32 = 134_217_727,

        tx_socket: ?std.posix.socket_t = null,
        rx_socket: ?std.posix.socket_t = null,

        const Self = @This();

        // ============================================================
        // CREATE
        // ============================================================
        pub fn create(
            domain: *Domain,
            name: []const u8,
            target_addr: []const u8,
            local_addr: []const u8,
            port: u16,
            ttl: u8,
        ) !*Self {
            const self = try domain.allocator.create(Self);
            errdefer domain.allocator.destroy(self);

            self.target_addr = try domain.allocator.dupe(u8, target_addr);
            self.local_addr = try domain.allocator.dupe(u8, local_addr);
            self.target_port = port;
            self.ttl = ttl;
            // self.send_buffer = send_buffer;
            // self.receive_buffer = receive_buffer;

            self.allocator = domain.allocator;

            try self.init(domain, name);

            logger = &domain.logger;

            return self;
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

            self.target_addr = try domain.allocator.dupe(u8, target_addr);
            self.local_addr = try domain.allocator.dupe(u8, local_addr);
            self.target_port = port;
            self.ttl = ttl;
            self.send_buffer = send_buffer;
            self.receive_buffer = receive_buffer;

            self.allocator = domain.allocator;

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

            try self.initSockets();
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.target_addr);
            self.allocator.free(self.local_addr);

            self.allocator.destroy(self);
        }

        // ============================================================
        // SOCKET INIT
        // ============================================================
        fn initSockets(self: *Self) !void {
            const timeout_ms: c_int = 100;

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

            try std.posix.setsockopt(
                rx,
                std.posix.SOL.SOCKET,
                std.posix.SO.RCVTIMEO,
                std.mem.asBytes(&timeout_ms),
            );

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

            const bind_addr =
                try buildBindAddress(
                    self.local_addr,
                    self.target_port,
                );

            try std.posix.bind(
                rx,
                @ptrCast(&bind_addr),
                @sizeOf(std.posix.sockaddr.in),
            );

            switch (mode) {
                .multicast => {
                    const ttl_int: c_int =
                        @intCast(self.ttl);

                    try std.posix.setsockopt(
                        tx,
                        std.posix.IPPROTO.IP,
                        std.posix.IP.MULTICAST_TTL,
                        std.mem.asBytes(&ttl_int),
                    );

                    var mreq = std.posix.ip_mreq{
                        .multiaddr = try parseIPv4(self.target_addr),
                        .interface = std.mem.zeroes(std.posix.in_addr),
                    };
                    try std.posix.setsockopt(
                        rx,
                        std.posix.IPPROTO.IP,
                        std.posix.IP.ADD_MEMBERSHIP,
                        std.mem.asBytes(&mreq),
                    );

                    const loop: u8 = 0;
                    try std.posix.setsockopt(
                        tx,
                        std.posix.IPPROTO.IP,
                        std.posix.IP.MULTICAST_LOOP,
                        std.mem.asBytes(&loop),
                    );
                },

                .broadcast => {
                    const flag: c_int = 1;

                    try std.posix.setsockopt(
                        tx,
                        std.posix.SOL.SOCKET,
                        std.posix.SO.BROADCAST,
                        std.mem.asBytes(&flag),
                    );
                },
            }
        }

        // ============================================================
        // LIFECYCLE
        // ============================================================
        pub fn start(self: *Self) !void {
            try self.transport.start();

            logger.info(
                "{s} started.",
                .{self.transport.name},
                @src(),
            );
        }

        pub fn stop(self: *Self) void {
            self.transport.stop();

            logger.info(
                "{s} stopped.",
                .{self.transport.name},
                @src(),
            );
        }

        pub fn close(self: *Self) void {
            if (self.rx_socket) |s| std.posix.close(s);
            if (self.tx_socket) |s| std.posix.close(s);
            self.deinit();

            logger.info(
                "{s} terminated.",
                .{
                    switch (mode) {
                        .multicast => "MCastTransport",
                        .broadcast => "BCastTransport",
                    },
                },
                @src(),
            );
        }

        // ============================================================
        // TX
        // ============================================================
        fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
            const self: *Self = @ptrCast(@alignCast(owner));

            const sock = self.tx_socket orelse return false;

            if (wire_bytes.len > 64_000) {
                logger.err(
                    "Serialized packet bigger than 64KB",
                    .{},
                    @src(),
                );

                return false;
            }

            var dst =
                parseIPv4SockAddr(
                    self.target_addr,
                    self.target_port,
                ) catch return false;

            const bytes_sent =
                std.posix.sendto(
                    sock,
                    wire_bytes,
                    0,
                    @ptrCast(&dst),
                    @sizeOf(
                        std.posix.sockaddr.in,
                    ),
                ) catch |err| {
                    logger.warning(
                        "{s} send error: {}",
                        .{
                            self.transport.name,
                            err,
                        },
                        @src(),
                    );

                    return false;
                };

            logger.trace(
                "{s} sent {d} bytes",
                .{
                    self.transport.qm.name,
                    bytes_sent,
                },
                @src(),
            );

            return bytes_sent ==
                wire_bytes.len;
        }

        // ============================================================
        // RX MAIN LOOP
        // ============================================================
        fn mainLoop(owner: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            const sock = self.rx_socket orelse return;
            var buffer: [64 * 1024]u8 = undefined;

            logger.info(
                "{s} RX loop started",
                .{self.transport.name},
                @src(),
            );

            while (self.transport.running) {
                const bytes_read =
                    std.posix.recvfrom(
                        sock,
                        &buffer,
                        0,
                        null,
                        null,
                    ) catch |err| {
                        switch (err) {
                            // Timeout configurado mediante SO_RCVTIMEO.
                            // Se usa únicamente para revisar periódicamente
                            // self.transport.running durante shutdown.
                            error.WouldBlock, error.ConnectionTimedOut => continue,

                            else => {
                                if (!self.transport.running) break;
                                logger.warning("{s} recvfrom error: {}", .{ self.transport.name, err }, @src());
                                continue;
                            },
                        }
                    };

                if (bytes_read == 0) continue;

                self.transport.receiveBytes(buffer[0..bytes_read]) catch |err| {
                    logger.warning("{s} receiveBytes failed: {}", .{ self.transport.name, err }, @src());
                };
            }

            logger.info(
                "{s} RX loop finished",
                .{self.transport.name},
                @src(),
            );
        }

        // ============================================================
        // OWNER
        // ============================================================
        fn closeOwner(owner: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            logger.info(
                "closing {s}",
                .{
                    switch (mode) {
                        .multicast => "MCastTransport",
                        .broadcast => "BCastTransport",
                    },
                },
                @src(),
            );

            self.close();
        }
    };
}

// ========================================================================
// PUBLIC TYPES
// ========================================================================
pub const MCastTransport = UdpTransport(.multicast);
pub const BCastTransport = UdpTransport(.broadcast);

// ========================================================================
// HELPERS
// ========================================================================
fn parseIPv4(text: []const u8) !std.posix.in_addr {
    const addr =
        try std.net.Address.parseIp4(
            text,
            0,
        );

    return addr.in.sa.addr;
}

fn parseIPv4SockAddr(text: []const u8, port: u16) !std.posix.sockaddr.in {
    const addr =
        try std.net.Address.parseIp4(
            text,
            port,
        );

    return addr.in.sa;
}

fn buildBindAddress(local_addr: []const u8, port: u16) !std.posix.sockaddr.in {
    if (std.mem.eql(u8, local_addr, "Any") or
        std.mem.eql(u8, local_addr, "any"))
    {
        return parseIPv4SockAddr("0.0.0.0", port);
    }

    if (std.mem.eql(u8, local_addr, "Loopback") or
        std.mem.eql(u8, local_addr, "loopback"))
    {
        return parseIPv4SockAddr("127.0.0.1", port);
    }

    return parseIPv4SockAddr(local_addr, port);
}
