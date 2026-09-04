// ============================================================================
// usox_star_transport.zig
//
// USOXStarTransport
//
// Transporte estrella basado en sockets Unix datagram.
//
// USOX = Unix Socket.
//
// Este transporte es conceptualmente similar a UDPStarTransport, pero utiliza
// sockets Unix de tipo datagram en lugar de sockets UDP IPv4.
//
// Arquitectura:
//
//   Domain
//      |
//      +--> ifcTransport
//               |
//               +--> USOXStarTransport
//                        |
//                        +--> PacketProcessor
//                                 |
//                                 +--> QueueMgr
//
// Responsabilidades:
//
//   - crear socket TX Unix datagram
//   - crear socket RX Unix datagram
//   - bind del socket RX a local_socket_path
//   - bind del socket TX a un path derivado del proceso
//   - enviar cada WireBytes a todos los remote_socket_paths configurados
//   - recibir datagramas Unix mediante recvfrom()
//   - filtrar paquetes propios por path origen TX
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

const Msg = @import("../generated/types.zig").k6bus.Msg;
const Config = @import("../generated/Config.zig").k6bus.config;


// ============================================================================
// CONSTANTS
// ============================================================================
const MAX_PACKET_SIZE: usize = 64 * 1024;

// ============================================================================
// USOXStarTransport
// ============================================================================
pub const USOXStarTransport = struct {
    domain: *Domain,
    logger: *Logger = undefined,
    allocator: std.mem.Allocator,

    name: []const u8,

    pck_processor: PacketProcessor,

    rx_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
    stopping: bool = false,

    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    local_socket_path: []const u8,
    tx_socket_path: []const u8,

    send_buffer: u32 = 1 * 1024 * 1024,
    receive_buffer: u32 = 1 * 1024 * 1024,

    tx_socket: ?std.posix.socket_t = null,
    rx_socket: ?std.posix.socket_t = null,

    remote_socket_paths: std.ArrayList([]const u8) = .empty,

    ifc_transport: ifcTransport,

    const Self = @This();

    // ========================================================================
    // CREATE
    // ========================================================================
    pub fn create(
        domain: *Domain,
        name: []const u8,
        local_socket_path: []const u8,
        remote_socket_paths: []const []const u8,
    ) !*Self {
        return createEx(
            domain,
            name,
            local_socket_path,
            remote_socket_paths,
            1 * 1024 * 1024,
            1 * 1024 * 1024,
        );
    }

    pub fn createEx(
        domain: *Domain,
        name: []const u8,
        local_socket_path: []const u8,
        remote_socket_paths: []const []const u8,
        send_buffer: u32,
        receive_buffer: u32,
    ) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        // Inicializacion segura SIN try: nada que pueda fallar, nada que limpiar.
        self.* = .{
            .domain = domain,
            .allocator = domain.allocator,
            .name = &.{},

            .pck_processor = undefined,
            .rx_thread = null,
            .running = .init(false),
            .stopping = false,
            .mutex = .{},
            .cond = .{},

            .local_socket_path = &.{},
            .tx_socket_path = &.{},

            .send_buffer = send_buffer,
            .receive_buffer = receive_buffer,

            .tx_socket = null,
            .rx_socket = null,
            .remote_socket_paths = .empty,

            .ifc_transport = undefined,
        };

        // Cada recurso con su propio errdefer justo despues de asignarse:
        // los errdefers corren en orden inverso al registro, asi cada cosa se
        // libera exactamente una vez, en orden inverso a como se aloco.
        self.name = try domain.allocator.dupe(u8, name);
        errdefer domain.allocator.free(self.name);

        self.local_socket_path = try domain.allocator.dupe(u8, local_socket_path);
        errdefer domain.allocator.free(self.local_socket_path);

        self.tx_socket_path = try buildTxUnixSocketPath(
            domain.allocator,
            local_socket_path,
        );
        errdefer domain.allocator.free(self.tx_socket_path);

        // Lista de paths remotos: el errdefer queda registrado ANTES del bucle
        // para cubrir appends a medias; libera los dupe ya encolados y el
        // array (igual que deinit()); si el append de un dupe falla, ese dupe
        // se libera explicitamente en el catch.
        errdefer {
            for (self.remote_socket_paths.items) |path_item| {
                self.allocator.free(path_item);
            }
            self.remote_socket_paths.deinit(self.allocator);
        }
        for (remote_socket_paths) |path| {
            const dupe_path = try self.allocator.dupe(u8, path);
            self.remote_socket_paths.append(
                self.allocator,
                dupe_path,
            ) catch |err| {
                self.allocator.free(dupe_path);
                return err;
            };
        }

        try self.pck_processor.init(
            domain,
            self.name,
            .USOXSTAR,
            Config.Encoding.RAW,
            self,
            sendBytes,
        );

        try self.initSockets();
        self.ifc_transport = ifcTransport.init(self);
        self.logger = &domain.logger;

        return self;
    }

    // ========================================================================
    // CREATE FROM CONFIG
    // ========================================================================
    // Ajustar nombres si ProtobuZig genera campos con nombres distintos.
    pub fn createFromConfig(
        domain: *Domain,
        name: []const u8,
        cfg: Config.UnixSocketStarConfig,
    ) !*Self {
        return createEx(
            domain,
            name,
            cfg.local_socket_path,
            cfg.remote_socket_paths,
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
                std.posix.AF.UNIX,
                std.posix.SOCK.DGRAM,
                0,
            );

        errdefer std.posix.close(tx);

        const rx =
            try std.posix.socket(
                std.posix.AF.UNIX,
                std.posix.SOCK.DGRAM,
                0,
            );

        errdefer std.posix.close(rx);

        self.tx_socket = tx;
        self.rx_socket = rx;

        try self.configureCommonSocketOptions(tx, rx);

        try self.bindSender();
        try self.bindReceiver();
    }

    fn configureCommonSocketOptions(self: *Self, tx: std.posix.socket_t, rx: std.posix.socket_t) !void {
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

        try setRecvTimeout(rx, 100_000);
    }

    fn bindSender(self: *Self) !void {
        deleteSocketPathIfExists(self.tx_socket_path);

        const addr = try buildUnixSockAddr(self.tx_socket_path);

        try std.posix.bind(
            self.tx_socket.?,
            @ptrCast(&addr),
            unixSockAddrLen(
                self.tx_socket_path,
            ),
        );
    }

    fn bindReceiver(self: *Self) !void {
        deleteSocketPathIfExists(self.local_socket_path);

        const addr = try buildUnixSockAddr(self.local_socket_path);

        try std.posix.bind(
            self.rx_socket.?,
            @ptrCast(&addr),
            unixSockAddrLen(
                self.local_socket_path,
            ),
        );
    }

    fn flushReceiveSocket(self: *Self) !void {
        const sock = self.rx_socket orelse return;

        var buffer: [MAX_PACKET_SIZE]u8 = undefined;
        var from_addr: std.posix.sockaddr.un = undefined;

        while (true) {
            var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.un);

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

        self.logger.info("{s} started.", .{self.name}, @src());
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

        self.logger.info("{s} stopped.", .{self.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.stop();

        self.closeSockets();
        self.pck_processor.close();

        self.logger.info("{s} USOXStar terminated.", .{self.name}, @src());
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

        deleteSocketPathIfExists(self.local_socket_path);
        deleteSocketPathIfExists(self.tx_socket_path);
    }

    fn join(self: *Self) void {
        if (self.rx_thread) |t| {
            t.join();
        }

        self.rx_thread = null;

        self.logger.info("{s} rx_thread finished", .{self.name}, @src());
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
            self.logger.err("{s} serialized packet bigger than 64 KiB", .{self.name}, @src());
            return false;
        }

        const sock = self.tx_socket orelse return false;

        var ok = true;
        for (self.remote_socket_paths.items) |path| {
            const addr =
                buildUnixSockAddr(path) catch |err| {
                    self.logger.warning("{s} invalid unix remote path {s}: {}", .{ self.name, path, err }, @src());
                    ok = false;
                    continue;
                };

            const sent =
                std.posix.sendto(
                    sock,
                    wire_bytes,
                    0,
                    @ptrCast(&addr),
                    unixSockAddrLen(path),
                ) catch |err| {
                    self.logger.warning("{s} USOXStar send error to {s}: {}", .{ self.name, path, err }, @src());
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
        var from_addr: std.posix.sockaddr.un = undefined;

        while (self.running.load(.acquire)) {
            var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.un);

            const bytes =
                std.posix.recvfrom(
                    sock,
                    &buffer,
                    0,
                    @ptrCast(&from_addr),
                    &from_len,
                ) catch |err| {
                    switch (err) {
                        error.WouldBlock, error.ConnectionTimedOut => continue,
                        else => {
                            if (!self.running.load(.acquire)) break;
                            self.logger.warning("{s} USOXStar recvfrom: {}", .{ self.name, err }, @src());
                            continue;
                        },
                    }
                };

            if (bytes == 0) continue;

            const from_path = unixSockAddrPath(&from_addr);

            if (std.mem.eql(u8, from_path, self.tx_socket_path)) {
                self.logger.trace("{s} ignoring own USOXStar packet from {s}", .{ self.name, self.tx_socket_path }, @src());
                continue;
            }

            self.pck_processor.receiveBytes(buffer[0..bytes]) catch |err| {
                self.logger.warning("{s} USOXStar receiveBytes: {}", .{ self.name, err }, @src());
            };
        }

        self.logger.info("{s} USOXStar RX loop finished", .{self.name}, @src());
    }

    // ========================================================================
    // DEINIT
    // ========================================================================
    fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.local_socket_path);
        self.allocator.free(self.tx_socket_path);

        for (self.remote_socket_paths.items) |path| {
            self.allocator.free(path);
        }

        self.remote_socket_paths.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// ============================================================================
// HELPERS
// ============================================================================
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

fn buildTxUnixSocketPath(allocator: std.mem.Allocator, local_socket_path: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}.tx.{d}",
        .{
            local_socket_path,
            getProcessId(),
        },
    );
}

fn buildUnixSockAddr(path: []const u8) !std.posix.sockaddr.un {
    var addr =
        std.mem.zeroes(std.posix.sockaddr.un);

    if (path.len + 1 > addr.path.len)
        return error.UnixSocketPathTooLong;

    addr.family = std.posix.AF.UNIX;
    @memcpy(addr.path[0..path.len], path);
    addr.path[path.len] = 0;

    return addr;
}

fn unixSockAddrLen(path: []const u8) std.posix.socklen_t {
    return @intCast(@offsetOf(
        std.posix.sockaddr.un,
        "path",
    ) + path.len + 1);
}

fn unixSockAddrPath(addr: *const std.posix.sockaddr.un) []const u8 {
    var len: usize = 0;

    while (len < addr.path.len and
        addr.path[len] != 0)
    {
        len += 1;
    }

    return addr.path[0..len];
}

fn deleteSocketPathIfExists(path: []const u8) void {
    if (path.len == 0) return;

    if (std.fs.path.isAbsolute(path)) {
        std.fs.deleteFileAbsolute(path) catch {};
    } else {
        std.fs.cwd().deleteFile(path) catch {};
    }
}

fn getProcessId() u32 {
    // TODO:
    // Implement Windows and BSD variants.
    const is_windows = @import("builtin").os.tag == .windows;

    const is_bsd = switch (@import("builtin").os.tag) {
        .freebsd,
        .openbsd,
        .netbsd,
        .dragonfly,
        => true,

        else => false,
    };

    if (!is_windows and !is_bsd) {
        return @intCast(std.os.linux.getpid());
    }

    unreachable;
}
