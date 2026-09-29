// ============================================================================
// LoopTransport
// ============================================================================
//
// In-memory local transport used for:
//
//   - unit tests
//   - integration tests
//   - local loops inside the same Domain
//   - PacketProcessor debugging
//
// It uses no sockets, multicast, broadcast or other network resources.
//
// The transport receives lists of Msg from its PacketProcessor,
// turns them back into bytes through the same PacketProcessor
// and reinjects them locally, simulating a physical link.
//
// Responsibilities:
//
//   - start and stop the local RX thread
//   - manage the simulated local byte queue
//   - wake up the RX thread during shutdown
//   - call PacketProcessor.receiveBytes()
//
// Does not do:
//
//   - serialization
//   - deserialization
//   - encryption
//   - decryption
//   - Base64 encoding
//   - cross-connections handling
//
// All those functions belong to PacketProcessor.
//
// Architecture:
//
//   Domain
//      |
//      +--> ifcTransport
//               |
//               +--> LoopTransport
//                        |
//                        +--> PacketProcessor
//                                 |
//                                 +--> QueueMgr
//
// ============================================================================
const std = @import("std");

const PacketProcessor = @import("packet_processor.zig").PacketProcessor;
const Domain = @import("domain.zig").Domain;
const Logger = @import("logger.zig").Logger;
const ifcTransport = @import("ifc_transport.zig").ifcTransport;

const Config = @import("../generated/Config.zig").k6bus.config;
const Msg = @import("../generated/types.zig").k6bus.Msg;


pub const LoopTransport = struct {
    domain: *Domain,
    logger: *Logger = undefined,
    name: []const u8,

    pck_processor: PacketProcessor,

    rx_thread: ?std.Thread = null,
    running: bool = false,

    stopping: bool = false,
    cond: std.Thread.Condition = .{},

    mutex: std.Thread.Mutex = .{},
    loop_queue: std.ArrayList([]const u8),

    delay_ms: u32 = 300,

    ifc_transport: ifcTransport,

    const Self = @This();

    pub fn create(domain: *Domain, name: []const u8, delay_ms: u32) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        try self.init(domain, name, delay_ms);

        self.logger = &domain.logger;

        return self;
    }

    fn init(self: *Self, domain: *Domain, name: []const u8, delay_ms: u32) !void {
        self.domain = domain;

        self.name = try domain.allocator.dupe(u8, name);
        errdefer domain.allocator.free(self.name);

        self.pck_processor = undefined;
        self.rx_thread = null;
        self.running = false;
        self.mutex = .{};
        self.loop_queue = .empty;
        self.delay_ms = delay_ms;
        self.ifc_transport = undefined;
        self.stopping = false;
        self.cond = .{};

        try self.pck_processor.init(domain, self.name, PacketProcessor.Encoding.RAW, self, sendBytes);
        self.ifc_transport = ifcTransport.init(self);
    }

    fn deinit(self: *Self) void {
        self.domain.allocator.free(self.name);
        self.domain.allocator.destroy(self);
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
        if (self.running) {
            self.mutex.unlock();
            return;
        }

        self.pck_processor.start() catch |err| {
            self.mutex.unlock();
            return err;
        };

        self.running = true;

        self.rx_thread = std.Thread.spawn(.{}, mainLoop, .{self}) catch |err| {
            self.running = false;
            self.mutex.unlock();

            self.pck_processor.stop();
            return err;
        };

        self.mutex.unlock();
        self.logger.info("{s} started.", .{self.name}, @src());
    }

    pub fn stop(self: *Self) void {
        self.mutex.lock();
        while (self.stopping) self.cond.wait(&self.mutex);

        if (!self.running) {
            self.mutex.unlock();
            return;
        }
        self.stopping = true;
        self.mutex.unlock();

        // Stop accepting new messages and finish processing
        // the messages that were already in the TX queue.
        self.pck_processor.stop();

        self.mutex.lock();
        // PacketProcessor* can no longer add new items.
        // mainLoop will drain the pending bytes and then exit.
        self.running = false;
        self.mutex.unlock();

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

        self.mutex.lock();

        for (self.loop_queue.items) |bytes| {
            self.domain.allocator.free(bytes);
        }

        self.loop_queue.deinit(self.domain.allocator);
        self.mutex.unlock();

        self.pck_processor.close();

        self.logger.info("loopT terminated.", .{}, @src());
        self.deinit();
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

    // ============================================================================
    // TX: from Domain thru PacketProcessor to network(fake)
    // ============================================================================
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));

        const copia = self.domain.allocator.dupe(u8, wire_bytes) catch return false;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.loop_queue.append(self.domain.allocator, copia) catch {
            self.domain.allocator.free(copia);
            return false;
        };

        self.logger.info("{s} queued {d} bytes to fake network", .{ self.name, wire_bytes.len }, @src());

        return true;
    }

    // ============================================================================
    // RX: MainLoop, from network(fake) to domain thru PacketProcessor
    // ============================================================================
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        while (true) {
            var wire_bytes: ?[]const u8 = null;

            self.mutex.lock();

            if (self.loop_queue.items.len > 0) {
                wire_bytes = self.loop_queue.orderedRemove(0);
            }

            const running = self.running;
            const pending = self.loop_queue.items.len;

            self.mutex.unlock();

            if (wire_bytes) |bytes| {
                std.Thread.sleep(@as(u64, self.delay_ms) * std.time.ns_per_ms);

                self.pck_processor.receiveBytes(bytes) catch {};
                self.domain.allocator.free(bytes);

                self.logger.info(
                    "{s} queued {d} bytes received from fake network, ready for sending back to domain",
                    .{ self.name, bytes.len },
                    @src(),
                );

                continue;
            }

            //
            // Exit only when:
            //   transport stopped
            //   and no pending packets left
            //
            if (!running and pending == 0) {
                break;
            }

            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }
};
