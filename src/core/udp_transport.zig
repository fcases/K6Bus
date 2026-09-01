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
const PacketProcessor = @import("packet_processor.zig").PacketProcessor;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Logger = @import("logger.zig").Logger;
const ifcTransport = @import("ifc_transport.zig").ifcTransport;
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

// TODO: verify constants on Windows and BSD.
const IP_MULTICAST_LOOP =
    if (is_windows) 11 // revisar
    else if (is_bsd) 11 // revisar
    else std.os.linux.IP.MULTICAST_LOOP;

const IP_MULTICAST_TTL =
    if (is_windows) 10 // revisar
    else if (is_bsd) 10 // revisar
    else std.os.linux.IP.MULTICAST_TTL;

// ============================================================================
// TYPES
// ============================================================================
pub const UdpMode = enum {
    multicast,
    broadcast,
};

const JoinRequest = extern struct {
    imr_multiaddr: u32,
    imr_address: u32,
};

fn UdpTransport(comptime mode: UdpMode) type {
    return struct {
        domain: *Domain,
        name: []const u8,

        allocator: std.mem.Allocator,
        pck_processor: PacketProcessor,

        rx_thread: ?std.Thread = null,
        running: std.atomic.Value(bool) = .init(false),

        stopping: bool = false,
        mutex: std.Thread.Mutex = .{},
        cond: std.Thread.Condition = .{},

        target_addr: []const u8,
        target_port: u16,
        local_addr: []const u8,
        tx_port: u16 = 0,
        ttl: u8 = 1,

        send_buffer: u32 = 1 * 1024 * 1024,
        receive_buffer: u32 = 1 * 1024 * 1024,

        tx_socket: ?std.posix.socket_t = null,
        rx_socket: ?std.posix.socket_t = null,

        ifc_transport: ifcTransport,

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

        pub fn createMCastFromConfig(domain: *Domain, name: []const u8, cfg: Config.MCastConfig) !*Self {
            if (mode != .multicast)
                @compileError("createMCastFromConfig is only valid for MCastTransport");

            return createEx(
                domain,
                name,
                cfg.mcast_address,
                cfg.local_address orelse "Any",
                @intCast(cfg.port),
                @intCast(cfg.ttl orelse 1),
                @intCast(cfg.send_buffer orelse 134217727),
                @intCast(cfg.receive_buffer orelse 134217727),
            );
        }

        pub fn createBCastFromConfig(domain: *Domain, name: []const u8, cfg: Config.BCastConfig) !*Self {
            if (mode != .broadcast)
                @compileError("createBCastFromConfig is only valid for BCastTransport");

            return createEx(
                domain,
                name,
                cfg.bcast_address,
                cfg.local_address orelse "Any",
                @intCast(cfg.port),
                1,
                @intCast(cfg.send_buffer orelse 134217727),
                @intCast(cfg.receive_buffer orelse 134217727),
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
                .domain = domain,
                .name = try domain.allocator.dupe(u8, name),
                .allocator = domain.allocator,
                .pck_processor = undefined,

                .running = .init(false),
                .rx_thread = null,

                .stopping = false,
                .mutex = .{},
                .cond = .{},

                .target_addr = try domain.allocator.dupe(u8, target_addr),
                .local_addr = try domain.allocator.dupe(u8, local_addr),
                .target_port = port,
                .ttl = ttl,

                .send_buffer = send_buffer,
                .receive_buffer = receive_buffer,
                .ifc_transport = undefined,
            };
            try self.init(domain, self.name);
            self.ifc_transport = ifcTransport.init(self);

            logger = &domain.logger;

            return self;
        }

        fn init(self: *Self, domain: *Domain, name: []const u8) !void {
            try self.pck_processor.init(
                domain,
                name,
                switch (mode) {
                    .multicast => .MCAST,
                    .broadcast => .BCAST,
                },
                Config.Encoding.RAW,
                self,
                sendBytes,
            );

            try self.validateConfig();
            try self.initSockets();
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.name);
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

            try self.bindSender();
            self.tx_port = try getSocketPort(tx);

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

            try setRecvTimeout(rx, 100_000); // 100 ms
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

        fn bindSender(self: *Self) !void {
            const bind_ip =
                if (isAny(self.local_addr))
                    "0.0.0.0"
                else
                    self.local_addr;

            const preferred_port = preferredTxPort();

            const preferred_addr = try parseIPv4SockAddr(bind_ip, preferred_port);

            std.posix.bind(
                self.tx_socket.?,
                @ptrCast(&preferred_addr),
                @sizeOf(std.posix.sockaddr.in),
            ) catch {
                // Fallback seguro: puerto efímero elegido por el SO.
                const fallback_addr = try parseIPv4SockAddr(bind_ip, 0);

                try std.posix.bind(
                    self.tx_socket.?,
                    @ptrCast(&fallback_addr),
                    @sizeOf(std.posix.sockaddr.in),
                );
            };
        }

        fn configureBroadcast(self: *Self) !void {
            const on: c_int = 1;

            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.SOL.SOCKET,
                std.posix.SO.BROADCAST,
                std.mem.asBytes(&on),
            );
        }

        fn configureMulticast(self: *Self) !void {
            // const loop: u8 = 0;
            const loop: u8 = 1;
            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.IPPROTO.IP,
                IP_MULTICAST_LOOP,
                std.mem.asBytes(&loop),
            );

            const ttl: c_int = @intCast(self.ttl);
            try std.posix.setsockopt(
                self.tx_socket.?,
                std.posix.IPPROTO.IP,
                IP_MULTICAST_TTL,
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

        fn setRecvTimeout(sock: std.posix.socket_t, micros: u32) !void {
            var tv = std.posix.timeval{
                .sec = @intCast(micros / std.time.us_per_s),
                .usec = @intCast(micros % std.time.us_per_s),
            };

            try std.posix.setsockopt(
                sock,
                std.posix.SOL.SOCKET,
                std.posix.SO.RCVTIMEO,
                std.mem.asBytes(&tv),
            );
        }

        fn getSocketPort(sock: std.posix.socket_t) !u16 {
            var addr: std.posix.sockaddr.in = undefined;
            var len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

            try std.posix.getsockname(sock, @ptrCast(&addr), &len);

            return std.mem.bigToNative(u16, addr.port);
        }

        fn preferredTxPort() u16 {
            const pid: u32 = getProcessId();

            return @intCast(
                50_000 + (pid % 14_000),
            );
        }

        fn getProcessId() u32 {
            // Ojo, habra que ponerlo para bsd y windows
            if (!is_windows and !is_bsd)
                return @intCast(std.os.linux.getpid())
            else
                unreachable;
        }

        fn flushReceiveSocket(self: *Self) !void {
            const sock = self.rx_socket orelse return;

            var buffer: [64 * 1024]u8 = undefined;
            var from_addr: std.posix.sockaddr.in = undefined;

            while (true) {
                var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

                _ = std.posix.recvfrom(sock, &buffer, std.posix.MSG.DONTWAIT, @ptrCast(&from_addr), &from_len) catch |err| {
                    switch (err) {
                        error.WouldBlock, error.ConnectionTimedOut => return,
                        else => return err,
                    }
                };
            }
        }

        // ============================================================================
        // ifcTransport interface implementation
        // ============================================================================
        pub fn start(self: *Self) !void {
            self.mutex.lock();

            if (self.stopping) {
                self.mutex.unlock();
                return error.TransportStopping;
            }
            if (self.running.load(.acquire)) {
                self.mutex.unlock();
                return;
            }
            self.flushReceiveSocket() catch |err| {
                self.mutex.unlock();
                return err;
            };
            self.pck_processor.start() catch |err| {
                self.mutex.unlock();
                return err;
            };

            self.running.store(true, .release);
            self.rx_thread = std.Thread.spawn(.{}, mainLoop, .{self}) catch |err| {
                self.running.store(false, .release);
                self.mutex.unlock();
                self.pck_processor.stop();
                return err;
            };

            self.mutex.unlock();

            logger.info("{s} started.", .{self.name}, @src());
        }

        pub fn stop(self: *Self) void {
            self.mutex.lock();
            while (self.stopping) {
                self.cond.wait(&self.mutex);
            }
            if (!self.running.load(.acquire)) {
                self.mutex.unlock();
                return;
            }
            self.stopping = true;
            self.mutex.unlock();

            // Deja de aceptar nuevos mensajes TX y termina los ya aceptados.
            self.pck_processor.stop();
            // Ya no se generarán nuevos envíos desde PacketProcessor.
            // El hilo RX saldrá cuando recvfrom() despierte por timeout.
            self.running.store(false, .release);
            self.join();

            self.mutex.lock();
            self.stopping = false;
            self.cond.broadcast();
            self.mutex.unlock();

            logger.info("{s} stopped.", .{self.name}, @src());
        }

        pub fn close(self: *Self) void {
            self.stop();

            if (self.rx_socket) |s| {
                std.posix.close(s);
                self.rx_socket = null;
            }
            if (self.tx_socket) |s| {
                std.posix.close(s);
                self.tx_socket = null;
            }

            self.pck_processor.close();

            logger.info("UDP terminated.", .{}, @src());
            self.deinit();
        }

        fn join(self: *Self) void {
            if (self.rx_thread) |t| {
                t.join();
            }

            self.rx_thread = null;
            logger.info("{s} rx_thread finished", .{self.name}, @src());
        }

        pub fn enqueue(self: *Self, msg: Msg) !void {
            try self.pck_processor.enqueue(msg);
        }

        pub fn enqueueMany(self: *Self, msg_list: []const Msg) !void {
            try self.pck_processor.enqueueMany(msg_list);
        }

        pub fn crossConnect(self: *Self, other: ifcTransport) !void {
            try self.pck_processor.crossConnect(other);
        }

        pub fn getName(self: *Self) []const u8 {
            return self.name;
        }

        // ====================================================================
        // TX: from domain thru PacketProcessor to network
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
                    logger.warning("{s} send error: {}", .{ self.name, err }, @src());
                    return false;
                };

            return sent == wire_bytes.len;
        }

        // ====================================================================
        // RX: from network to domain thru PacketProcessor
        // ====================================================================
        fn mainLoop(owner: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            const sock = self.rx_socket orelse return;
            var buffer: [64 * 1024]u8 = undefined;
            var from_addr: std.posix.sockaddr.in = undefined;

            while (self.running.load(.acquire)) {
                var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
                const bytes =
                    std.posix.recvfrom(
                        sock,
                        &buffer,
                        0,
                        @ptrCast(&from_addr),
                        &from_len,
                    ) catch |err| {
                        switch (err) {
                            error.WouldBlock,
                            error.ConnectionTimedOut,
                            => continue,

                            else => {
                                if (!self.running.load(.acquire)) break;
                                logger.warning("{s} recvfrom: {}", .{ self.name, err }, @src());
                                continue;
                            },
                        }
                    };

                if (bytes == 0) continue;

                const from_port = std.mem.bigToNative(u16, from_addr.port);
                if (from_port == self.tx_port) {
                    logger.trace(
                        "{s} ignoring own UDP packet from tx port {d}",
                        .{ self.name, from_port },
                        @src(),
                    );

                    continue;
                }

                self.pck_processor.receiveBytes(buffer[0..bytes]) catch |err| {
                    logger.warning("{s} receiveBytes: {}", .{ self.name, err }, @src());
                };
            }

            logger.info("{s} salida de while en mainloop", .{self.name}, @src());
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
