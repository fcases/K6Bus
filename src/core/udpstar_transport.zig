// ============================================================================
// udp_star_transport.zig
//
// UDPStarTransport
//
// Transporte UDP punto-a-muchos basado en sockets UDP IPv4.
//
// A diferencia de MCastTransport y BCastTransport, UDPStarTransport no utiliza
// direcciones multicast ni broadcast. Envia cada paquete explicitamente a una
// lista de endpoints UDP configurados.
//
// Arquitectura:
//
//   Domain
//      |
//      +--> ifcTransport
//               |
//               +--> UDPStarTransport
//                        |
//                        +--> PacketProcessor
//                                 |
//                                 +--> QueueMgr
//
// Responsabilidades:
//
//   - crear socket TX UDP
//   - crear socket RX UDP
//   - bind del socket RX a local_address:port
//   - bind del socket TX a local_address:tx_port
//   - enviar cada WireBytes a todos los endpoints configurados
//   - recibir datagramas UDP mediante recvfrom()
//   - filtrar paquetes propios por puerto origen TX
//   - invocar PacketProcessor.receiveBytes()
//
// No realiza:
//
//   - serializacion/deserializacion
//   - cifrado/descifrado
//   - codificacion/decodificacion
//   - gestion de Msg/Packet
//
// Todo eso pertenece a PacketProcessor.
//
// ============================================================================

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const PacketProcessor = @import("packet_processor.zig").PacketProcessor;
const Logger = @import("logger.zig").Logger;
const ifcTransport = @import("ifc_transport.zig").ifcTransport;

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Config = @import("../generated/Config.zig").k6bus.config;

var logger: *Logger = undefined;

// ============================================================================
// CONSTANTS
// ============================================================================

const MAX_PACKET_SIZE: usize = 64 * 1024;

const is_windows = @import("builtin").os.tag == .windows;
const is_bsd = switch (@import("builtin").os.tag) {
    .freebsd,
    .openbsd,
    .netbsd,
    .dragonfly,
    => true,

    else => false,
};

// ============================================================================
// PUBLIC TYPES
// ============================================================================

pub const EndPoint = struct {
    host: []const u8,
    port: u16,
};

const UdpDestination = struct {
    addr: std.posix.sockaddr.in,
};

// ============================================================================
// UDPStarTransport
// ============================================================================

pub const UDPStarTransport = struct {
    domain: *Domain,
    allocator: std.mem.Allocator,

    name: []const u8,

    pck_processor: PacketProcessor,

    rx_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
    stopping: bool = false,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    local_addr: []const u8,
    local_port: u16,
    tx_port: u16 = 0,

    send_buffer: u32 = 1 * 1024 * 1024,
    receive_buffer: u32 = 1 * 1024 * 1024,

    tx_socket: ?std.posix.socket_t = null,
    rx_socket: ?std.posix.socket_t = null,

    destinations: std.ArrayList(UdpDestination) = .empty,

    ifc_transport: ifcTransport,

    const Self = @This();

    // ========================================================================
    // CREATE
    // ========================================================================

    pub fn create(
        domain: *Domain,
        name: []const u8,
        local_addr: []const u8,
        port: u16,
        endpoints: []const EndPoint,
    ) !*Self {
        return createEx(
            domain,
            name,
            local_addr,
            port,
            endpoints,
            1 * 1024 * 1024,
            1 * 1024 * 1024,
        );
    }

    pub fn createEx(
        domain: *Domain,
        name: []const u8,
        local_addr: []const u8,
        port: u16,
        endpoints: []const EndPoint,
        send_buffer: u32,
        receive_buffer: u32,
    ) !*Self {
        const self =
            try domain.allocator.create(Self);

        errdefer domain.allocator.destroy(self);

        self.* = .{
            .domain = domain,
            .allocator = domain.allocator,

            .name = try domain.allocator.dupe(u8, name),

            .pck_processor = undefined,

            .rx_thread = null,
            .running = .init(false),
            .stopping = false,
            .mutex = .{},
            .cond = .{},

            .local_addr = try domain.allocator.dupe(u8, local_addr),
            .local_port = port,

            .send_buffer = send_buffer,
            .receive_buffer = receive_buffer,

            .tx_socket = null,
            .rx_socket = null,

            .destinations = .empty,

            .ifc_transport = undefined,
        };

        errdefer self.deinit();

        for (endpoints) |ep| {
            try self.destinations.append(
                self.allocator,
                .{
                    .addr = try parseIPv4SockAddr(ep.host, ep.port),
                },
            );
        }

        try self.pck_processor.init(
            domain,
            self.name,
            .UDPSTAR,
            Config.Encoding.RAW,
            self,
            sendBytes,
        );

        try self.initSockets();

        self.ifc_transport = ifcTransport.init(self);

        logger = &domain.logger;

        return self;
    }

    // ========================================================================
    // CREATE FROM CONFIG
    // ========================================================================
    // Ajustar nombres si ProtobuZig genera campos con nombres distintos.
    pub fn createFromConfig(domain: *Domain, name: []const u8, cfg: Config.UDPStarConfig) !*Self {
        var endpoints: std.ArrayList(EndPoint) = .empty;
        defer endpoints.deinit(domain.allocator);

        for (cfg.end_point) |ep| {
            try endpoints.append(
                domain.allocator,
                .{
                    .host = ep.host,
                    .port = @intCast(ep.port orelse 40069),
                },
            );
        }

        return createEx(
            domain,
            name,
            cfg.local_address orelse "Any",
            @intCast(cfg.port),
            endpoints.items,
            @intCast(cfg.send_buffer orelse 1 * 1024 * 1024),
            @intCast(cfg.receive_buffer orelse 1 * 1024 * 1024),
        );
    }

    // ========================================================================
    // SOCKET INITIALIZATION
    // ========================================================================
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
    }

    fn configureCommonSocketOptions(
        self: *Self,
        tx: std.posix.socket_t,
        rx: std.posix.socket_t,
    ) !void {
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

        try setRecvTimeout(
            rx,
            100_000,
        );
    }

    fn bindSender(self: *Self) !void {
        const bind_ip =
            if (isAny(self.local_addr))
                "0.0.0.0"
            else if (isLoopback(self.local_addr))
                "127.0.0.1"
            else
                self.local_addr;

        const preferred_port =
            preferredTxPort();

        const preferred_addr =
            try parseIPv4SockAddr(
                bind_ip,
                preferred_port,
            );

        std.posix.bind(
            self.tx_socket.?,
            @ptrCast(&preferred_addr),
            @sizeOf(std.posix.sockaddr.in),
        ) catch {
            const fallback_addr =
                try parseIPv4SockAddr(
                    bind_ip,
                    0,
                );

            try std.posix.bind(
                self.tx_socket.?,
                @ptrCast(&fallback_addr),
                @sizeOf(std.posix.sockaddr.in),
            );
        };
    }

    fn bindReceiver(self: *Self) !void {
        const bind_ip =
            if (isAny(self.local_addr))
                "0.0.0.0"
            else if (isLoopback(self.local_addr))
                "127.0.0.1"
            else
                self.local_addr;

        const bind_addr =
            try parseIPv4SockAddr(
                bind_ip,
                self.local_port,
            );

        try std.posix.bind(
            self.rx_socket.?,
            @ptrCast(&bind_addr),
            @sizeOf(std.posix.sockaddr.in),
        );
    }

    fn flushReceiveSocket(self: *Self) !void {
        const sock = self.rx_socket orelse return;

        var buffer: [MAX_PACKET_SIZE]u8 = undefined;
        var from_addr: std.posix.sockaddr.in = undefined;

        while (true) {
            var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
            _ = std.posix.recvfrom(
                sock,
                &buffer,
                std.posix.MSG.DONTWAIT,
                @ptrCast(&from_addr),
                &from_len,
            ) catch |err| {
                switch (err) {
                    error.WouldBlock, error.ConnectionTimedOut => return,
                    else => return err,
                }
            };
        }
    }

    // ========================================================================
    // ifcTransport implementation
    // ========================================================================
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

        self.pck_processor.stop();
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
        self.closeSockets();
        self.pck_processor.close();

        logger.info("{s} UDPStar terminated.", .{self.name}, @src());
        self.deinit();
    }

    fn closeSockets(self: *Self) void {
        if (self.rx_socket) |s| {
            std.posix.close(s);
            self.rx_socket = null;
        }

        if (self.tx_socket) |s| {
            std.posix.close(s);
            self.tx_socket = null;
        }
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

    // ========================================================================
    // TX
    // ========================================================================
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));

        if (wire_bytes.len > MAX_PACKET_SIZE) {
            logger.err("{s} serialized packet bigger than 64 KiB", .{self.name}, @src());
            return false;
        }

        const sock = self.tx_socket orelse return false;

        var ok = true;
        for (self.destinations.items) |dst| {
            const sent =
                std.posix.sendto(sock, wire_bytes, 0, @ptrCast(&dst.addr), @sizeOf(std.posix.sockaddr.in)) catch |err| {
                    logger.warning("{s} UDPStar send error: {}", .{ self.name, err }, @src());
                    ok = false;
                    continue;
                };

            if (sent != wire_bytes.len)
                ok = false;
        }

        return ok;
    }

    // ========================================================================
    // RX
    // ========================================================================
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        const sock = self.rx_socket orelse return;

        var buffer: [MAX_PACKET_SIZE]u8 = undefined;
        var from_addr: std.posix.sockaddr.in = undefined;

        while (self.running.load(.acquire)) {
            var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

            const bytes =
                std.posix.recvfrom(sock, &buffer, 0, @ptrCast(&from_addr), &from_len) catch |err| {
                    switch (err) {
                        error.WouldBlock, error.ConnectionTimedOut => continue,
                        else => {
                            if (!self.running.load(.acquire)) break;
                            logger.warning("{s} UDPStar recvfrom: {}", .{ self.name, err }, @src());
                            continue;
                        },
                    }
                };

            if (bytes == 0) continue;

            const from_port = std.mem.bigToNative(u16, from_addr.port);

            if (from_port == self.tx_port) {
                logger.trace("{s} ignoring own UDPStar packet from tx port {d}", .{ self.name, from_port }, @src());

                continue;
            }

            self.pck_processor.receiveBytes(buffer[0..bytes]) catch |err| {
                logger.warning("{s} UDPStar receiveBytes: {}", .{ self.name, err }, @src());
            };
        }

        logger.info("{s} UDPStar RX loop finished", .{self.name}, @src());
    }

    // ========================================================================
    // DEINIT
    // ========================================================================
    fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.local_addr);

        self.destinations.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// ============================================================================
// HELPERS
// ============================================================================
fn isAny(text: []const u8) bool {
    return std.ascii.eqlIgnoreCase(text, "any");
}

fn isLoopback(text: []const u8) bool {
    return std.ascii.eqlIgnoreCase(text, "loopback");
}

fn parseIPv4SockAddr(text: []const u8, port: u16) !std.posix.sockaddr.in {
    const addr = try std.net.Address.parseIp4(text, port);

    return addr.in.sa;
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

    return @intCast(50_000 + (pid % 14_000));
}

fn getProcessId() u32 {
    // TODO:
    // Implement Windows and BSD variants.
    const is_windows_local = @import("builtin").os.tag == .windows;

    const is_bsd_local = switch (@import("builtin").os.tag) {
        .freebsd,
        .openbsd,
        .netbsd,
        .dragonfly,
        => true,

        else => false,
    };

    if (!is_windows_local and !is_bsd_local) {
        return @intCast(
            std.os.linux.getpid(),
        );
    }

    unreachable;
}
