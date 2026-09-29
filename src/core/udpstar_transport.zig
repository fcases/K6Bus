// ============================================================================
// udp_star_transport.zig
//
// UDPStarTransport
//
// Point-to-many UDP transport based on IPv4 UDP sockets.
//
// Unlike MCastTransport and BCastTransport, UDPStarTransport uses neither
// multicast nor broadcast addresses. It sends every packet explicitly to a
// list of configured UDP endpoints.
//
// Architecture:
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
// Responsibilities:
//
//   - create the UDP TX socket
//   - create the UDP RX socket
//   - bind the RX socket to local_address:port
//   - bind the TX socket to local_address:tx_port
//   - send every WireBytes to all configured endpoints
//   - receive UDP datagrams via recvfrom()
//   - filter own packets out by TX source port
//   - call PacketProcessor.receiveBytes()
//
// Does not do:
//
//   - serialization/deserialization
//   - encryption/decryption
//   - encoding/decoding
//   - Msg/Packet handling
//
// All of that belongs to PacketProcessor.
//
// ============================================================================

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const PacketProcessor = @import("packet_processor.zig").PacketProcessor;
const Logger = @import("logger.zig").Logger;
const soketo = @import("socket_auks.zig");
const ifcTransport = @import("ifc_transport.zig").ifcTransport;

const Msg = @import("../generated/types.zig").k6bus.Msg;
const Config = @import("../generated/Config.zig").k6bus.config;


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
    // host is OWNED (dupe of cfg in createEx): the transport owns everything
    // it receives from the config (uniform rule with mcast). Available for
    // future logging/reconnection; it is freed in deinit.
    host: []const u8,
    addr: std.posix.sockaddr.in,
};

// ============================================================================
// UDPStarTransport
// ============================================================================

pub const UDPStarTransport = struct {
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
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        // Safe initialization WITHOUT try: nothing can fail, nothing to clean up.
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

            .local_addr = &.{},
            .local_port = port,

            .send_buffer = send_buffer,
            .receive_buffer = receive_buffer,

            .tx_socket = null,
            .rx_socket = null,

            .destinations = .empty,

            .ifc_transport = undefined,
        };

        // Each resource gets its own errdefer right after it is assigned:
        // errdefers run in reverse order of registration, so everything is
        // released exactly once, in reverse order of how it was allocated.
        self.name = try domain.allocator.dupe(u8, name);
        errdefer domain.allocator.free(self.name);

        self.local_addr = try domain.allocator.dupe(u8, local_addr);
        errdefer domain.allocator.free(self.local_addr);

        // Destination list: if an append fails halfway, the errdefer (already
        // registered) frees the duplicated hosts and the partial list.
        errdefer {
            for (self.destinations.items) |d| {
                self.allocator.free(d.host);
            }
            self.destinations.deinit(self.allocator);
        }
        for (endpoints) |ep| {
            const addr = try parseIPv4SockAddr(ep.host, ep.port);
            const host_dupe = try self.allocator.dupe(u8, ep.host);
            self.destinations.append(
                self.allocator,
                .{ .host = host_dupe, .addr = addr },
            ) catch |err| {
                self.allocator.free(host_dupe);
                return err;
            };
        }

        try self.pck_processor.init(
            domain,
            self.name,
            PacketProcessor.Encoding.RAW,
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
    // Adjust names if ProtobuZig generates fields with different names.
    pub fn createFromConfig(domain: *Domain, name: []const u8, cfg: Config.UDPStarConfig) !*Self {
        var endpoints: std.ArrayList(EndPoint) = .empty;
        defer endpoints.deinit(domain.allocator);

        for (cfg.end_points) |ep| {
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

        // Buffer sizes are a hint, not a requirement: every OS limits them
        // its own way (FreeBSD rejects with ENOBUFS, Linux silently
        // truncates). We warn and carry on (F10).
        soketo.agorduBufon(
            &self.domain.logger,
            self.name,
            rx,
            std.posix.SO.RCVBUF,
            "SO_RCVBUF",
            self.receive_buffer,
        );

        soketo.agorduBufon(
            &self.domain.logger,
            self.name,
            tx,
            std.posix.SO.SNDBUF,
            "SO_SNDBUF",
            self.send_buffer,
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
        // Close contract (D1, 2026-09-10): close() is SINGLE-USE and
        // destructive (like free()): first it UNREGISTERS (so the Domain no
        // longer holds references; the exclusive lock waits for in-flight
        // dispatches), then it stops the threads, frees resources and frees
        // the struct. Any later call through this pointer is UB, and calling
        // close() twice is UB as well.
        self.domain.unregisterTransport(self.transport());

        self.stop();
        self.closeSockets();
        self.pck_processor.close();

        self.logger.info("{s} UDPStar terminated.", .{self.name}, @src());
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

    /// ifcTransport interface of the transport, to register/connect/close it.
    /// Style: allocator = gpa.allocator()  ->  dom.registerTransport(t.transport()).
    pub fn transport(self: *Self) ifcTransport {
        return self.ifc_transport;
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
        for (self.destinations.items) |dst| {
            const sent =
                std.posix.sendto(sock, wire_bytes, 0, @ptrCast(&dst.addr), @sizeOf(std.posix.sockaddr.in)) catch |err| {
                    self.logger.warning("{s} UDPStar send error: {}", .{ self.name, err }, @src());
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
                            self.logger.warning("{s} UDPStar recvfrom: {}", .{ self.name, err }, @src());
                            continue;
                        },
                    }
                };

            if (bytes == 0) continue;

            const from_port = std.mem.bigToNative(u16, from_addr.port);

            if (from_port == self.tx_port) {
                self.logger.trace("{s} ignoring own UDPStar packet from tx port {d}", .{ self.name, from_port }, @src());

                continue;
            }

            self.pck_processor.receiveBytes(buffer[0..bytes]) catch |err| {
                self.logger.warning("{s} UDPStar receiveBytes: {}", .{ self.name, err }, @src());
            };
        }

        self.logger.info("{s} UDPStar RX loop finished", .{self.name}, @src());
    }

    // ========================================================================
    // DEINIT
    // ========================================================================
    fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.local_addr);

        for (self.destinations.items) |d| {
            self.allocator.free(d.host);
        }
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
    // The previous `unreachable` blew up on FreeBSD as soon as
    // preferredTxPort() was called (bindSender): in Debug, unreachable = panic.
    // BSD goes through libc, which exposes getpid() in this Zig version.
    return switch (@import("builtin").os.tag) {
        .windows => @intCast(std.os.windows.GetCurrentProcessId()),
        .linux => @intCast(std.os.linux.getpid()),
        else => @intCast(std.c.getpid()),
    };
}
