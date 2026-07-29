// queue_mgr.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const Utils = @import("msg_utils.zig");
const Logger = @import("logger.zig").Logger;

const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

pub const DispatchFn = *const fn (
    owner: *anyopaque,
    msg_list: []const Msg,
) void;

var logger: *Logger = undefined;

pub const QueueMgr = struct {
    domain: *Domain,
    name: []const u8,

    batch_mode: BatchMode,
    batch_wait_ms: u32,

    owner: *anyopaque,
    dispatch_fn: DispatchFn,

    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    queue: std.ArrayList(Msg),
    worker: ?std.Thread = null,

    finished: bool = false,
    running: bool = false,

    pub fn create(
        domain: *Domain,
        name: []const u8,
        batch_mode: BatchMode,
        batch_wait_ms: u32,
        owner: *anyopaque,
        dispatch_fn: DispatchFn,
    ) !QueueMgr {
        logger = &domain.logger;

        return .{
            .domain = domain,
            .name = try domain.allocator.dupe(u8, name),
            .batch_mode = batch_mode,
            .batch_wait_ms = batch_wait_ms,
            .owner = owner,
            .dispatch_fn = dispatch_fn,
            .queue = .empty,
        };
    }

    pub fn deinit(self: *QueueMgr) void {
        self.queue.deinit(self.domain.allocator);
        self.domain.allocator.free(self.name);
    }

    pub fn start(self: *QueueMgr) !void {
        if (self.running) return;

        if (std.mem.startsWith(u8, self.name, "EstacionSubscriber")) {
            logger.trace("{s} starting", .{self.name}, @src());
        }

        self.finished = false;
        self.worker =
            try std.Thread.spawn(
                .{},
                mainLoop,
                .{self},
            );

        logger.info("{s} worker started", .{self.name}, @src());
        self.running = true;
    }

    pub fn stop(self: *QueueMgr) void {
        if (!self.running) return;

        // Liberamos el mutex antes de esperar al hilo.
        // Así el worker puede salir del wait() y finalizar.
        self.mutex.lock();
        self.finished = true;
        self.mutex.unlock();

        self.cond.broadcast();
        self.join();

        self.running = false;

        logger.info("{s} stopped", .{self.name}, @src());
    }

    pub fn join(self: *QueueMgr) void {
        if (self.worker) |t| {
            t.join();
        }

        self.worker = null;
        logger.info("{s} worker finished", .{self.name}, @src());
    }

    pub fn close(self: *QueueMgr) void {
        logger.info("{s} closing", .{self.name}, @src());
        self.stop();
        self.deinit();
    }

    pub fn enqueue(self: *QueueMgr, msg: Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.append(self.domain.allocator, msg);

        self.cond.signal();
    }

    pub fn enqueueMany(self: *QueueMgr, msgs: []const Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.appendSlice(self.domain.allocator, msgs);

        self.cond.signal();
    }

    fn waitAndFetch(self: *QueueMgr, out_msgs: *std.ArrayList(Msg)) !bool {
        logger.trace("{s} ENTER waitAndFetch queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());
        out_msgs.clearRetainingCapacity();
        logger.trace("{s} after clear out.len={d}", .{ self.name, out_msgs.items.len }, @src());

        self.mutex.lock();

        while (self.queue.items.len == 0 and !self.finished) {
            self.cond.wait(&self.mutex);
        }

        if (self.finished) {
            self.mutex.unlock();
            return false;
        }

        if (self.batch_mode == .BATCH and
            self.batch_wait_ms > 0)
        {
            self.mutex.unlock();
            std.Thread.sleep(
                @as(u64, self.batch_wait_ms) * std.time.ns_per_ms,
            );
            self.mutex.lock();

            if (self.finished) {
                self.mutex.unlock();
                return false;
            }
        }

        try out_msgs.appendSlice(self.domain.allocator, self.queue.items);
        logger.trace("{s} after appendSlice queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());

        self.queue.clearRetainingCapacity();
        logger.trace("{s} after clearRetainingCapacity queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());

        self.mutex.unlock();

        return true;
    }

    fn mainLoop(self: *QueueMgr) void {
        var msg_list: std.ArrayList(Msg) = .empty;
        defer msg_list.deinit(self.domain.allocator);

        // if (std.mem.startsWith(u8, self.name, "EstacionSubscriber")) {
        //     self.domain.logger.trace("{s} starting mainLoop", .{self.name}, @src());
        // }

        while (self.waitAndFetch(&msg_list) catch false) {
            // if (std.mem.startsWith(u8, self.name, "EstacionSubscriber")) {
            //     self.domain.logger.trace("{s} about to call the callback", .{self.name}, @src());
            //     const stop_here = true;
            //     _ = stop_here;
            // }

            if (msg_list.items.len > 0) {
                logger.trace("{s} dispatching {d} messages", .{ self.name, msg_list.items.len }, @src());
                self.dispatch_fn(self.owner, msg_list.items);
            }
        }
    }
};
