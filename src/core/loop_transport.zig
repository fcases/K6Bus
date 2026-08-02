// loop_transport.zig

const std = @import("std");

const Transport = @import("transport.zig").Transport;
const Domain = @import("domain.zig").Domain;
const Logger = @import("logger.zig").Logger;

const Config = @import("../generated/Config.zig").k6bus.config;

var logger: *Logger = undefined;

pub const LoopTransport = struct {
    transport: Transport,
    delay_ms: u32 = 300,

    mutex: std.Thread.Mutex = .{},
    loop_queue: std.ArrayList([]const u8),

    const Self = @This();

    pub fn create(domain: *Domain, name: []const u8, delay_ms: u32) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        try self.init(domain, name, delay_ms);

        logger = &domain.logger;

        return self;
    }

    fn init(self: *Self, domain: *Domain, name: []const u8, delay_ms: u32) !void {
        self.delay_ms = delay_ms;

        // self.queue = std.ArrayList([]const u8).init(domain.allocator);
        self.loop_queue = .empty;

        try self.transport.init(domain, name, .LOOP, Config.Encoding.RAW, self, sendBytes, mainLoop, closeOwner);
    }

    fn deinit(self: *LoopTransport, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn start(self: *Self) !void {
        try self.transport.start();

        logger.info("{s} started.", .{self.transport.qm.name}, @src());
    }

    pub fn stop(self: *Self) void {
        self.transport.stop();

        logger.info("{s} stopped.", .{self.transport.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();

        // logger.info(
        //     "LoopTransport before closing queue.len={d}",
        //     .{self.loop_queue.items.len},
        //     @src(),
        // );

        for (self.loop_queue.items) |bytes| {
            self.transport.domain.allocator.free(bytes);
        }
        // logger.info(
        //     "LoopTransport after closing queue.len={d}",
        //     .{self.loop_queue.items.len},
        //     @src(),
        // );
        self.loop_queue.deinit(self.transport.domain.allocator);
        self.mutex.unlock();
        self.deinit(self.transport.domain.allocator);

        logger.info("LoopTransport terminated.", .{}, @src());
    }

    // ------------------------------------------------------------------------
    // RX MainLoop
    // ------------------------------------------------------------------------
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        while (true) {
            var wire_bytes: ?[]const u8 = null;

            self.mutex.lock();

            if (self.loop_queue.items.len > 0) {
                wire_bytes = self.loop_queue.orderedRemove(0);
            }

            const running = self.transport.running;
            const pending = self.loop_queue.items.len;

            self.mutex.unlock();

            if (wire_bytes) |bytes| {
                std.Thread.sleep(@as(u64, self.delay_ms) * std.time.ns_per_ms);

                self.transport.receiveBytes(bytes) catch {};
                self.transport.domain.allocator.free(bytes);

                logger.info(
                    "{s} queued {d} bytes received from fake network, ready for sending back to domain",
                    .{ self.transport.qm.name, bytes.len },
                    @src(),
                );

                continue;
            }

            //
            // Salir solamente cuando:
            //   transport parado
            //   y no quedan paquetes pendientes
            //
            if (!running and pending == 0) {
                break;
            }

            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    // fn mainLoop(owner: *anyopaque) void {
    //     const self: *Self = @ptrCast(@alignCast(owner));

    //     while (self.transport.running) {
    //         var wire_bytes: ?[]const u8 = null;

    //         self.mutex.lock();
    //         if (self.loop_queue.items.len > 0) {
    //             wire_bytes = self.loop_queue.orderedRemove(0);
    //         }
    //         self.mutex.unlock();

    //         if (wire_bytes) |bytes| {
    //             std.Thread.sleep(@as(u64, self.delay_ms) * std.time.ns_per_ms);

    //             self.transport.receiveBytes(bytes) catch {};
    //             self.transport.domain.allocator.free(bytes);

    //             logger.info("{s} queued {d} bytes received from fake network, ready for sending back to domain", .{ self.transport.qm.name, bytes.len }, @src());
    //         } else {
    //             std.Thread.sleep(10 * std.time.ns_per_ms);
    //         }
    //     }
    // }

    // ------------------------------------------------------------------------
    // TX
    // ------------------------------------------------------------------------
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));

        const copia = self.transport.domain.allocator.dupe(u8, wire_bytes) catch return false;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.loop_queue.append(self.transport.domain.allocator, copia) catch {
            self.transport.domain.allocator.free(copia);
            return false;
        };

        logger.info("{s} queued {d} bytes to fake network", .{ self.transport.qm.name, wire_bytes.len }, @src());

        return true;
    }

    // ------------------------------------------------------------------------
    // closeOwner
    // ------------------------------------------------------------------------
    fn closeOwner(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));
        logger.info("closing LoopTransport", .{}, @src());
        self.close();
    }
};
