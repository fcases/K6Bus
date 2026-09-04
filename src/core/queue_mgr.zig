// queue_mgr.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const Utils = @import("msg_utils.zig");
const Logger = @import("logger.zig").Logger;

const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;
const Msg = @import("../generated/types.zig").k6bus.Msg;

pub const DispatchFn = *const fn (owner: *anyopaque, msg_list: []const Msg) void;


pub const QueueStats = struct {
    total_enqueued: u64 = 0,
    total_dispatched: u64 = 0,
    total_batches: u64 = 0,
    max_batch_size: usize = 0,
    max_queue_depth: usize = 0,
    max_capacity: usize = 0,
    dispatch_time_ns: u64 = 0,
    max_dispatch_time_ns: u64 = 0,
};

pub const QueueMgr = struct {
    domain: *Domain,
    logger: *Logger = undefined,
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
    closed: bool = false,
    stopping: bool = false,

    stats: QueueStats = .{},

    pub fn create(
        domain: *Domain,
        name: []const u8,
        batch_mode: BatchMode,
        batch_wait_ms: u32,
        owner: *anyopaque,
        dispatch_fn: DispatchFn,
    ) !QueueMgr {
        return .{
            .domain = domain,
            .logger = &domain.logger,
            // name is borrowed.
            // The owner must keep it alive until QueueMgr.close() has completed.
            .name = name,
            .batch_mode = batch_mode,
            .batch_wait_ms = batch_wait_ms,
            .owner = owner,
            .dispatch_fn = dispatch_fn,
            .queue = .empty,
        };
    }

    fn deinit(self: *QueueMgr) void {
        if (self.queue.items.len > 0) {
            self.logger.warning("{s}: dropping {d} pending messages on shutdown", .{ self.name, self.queue.items.len }, @src());

            Utils.freeMsgsFromSlice(self.domain.allocator, self.queue.items);
        }
        self.logger.info("{s}: remaining queue items={d}", .{ self.name, self.queue.items.len }, @src());

        const avg: f64 =
            if (self.stats.total_batches == 0) 0 else @as(f64, @floatFromInt(self.stats.total_dispatched)) /
            @as(f64, @floatFromInt(self.stats.total_batches));

        const avg_dispatch_ms =
            if (self.stats.total_batches == 0) 0.0 else (@as(f64, @floatFromInt(self.stats.dispatch_time_ns)) /
                @as(f64, @floatFromInt(self.stats.total_batches))) /
            std.time.ns_per_ms;

        self.logger.info(
            "{s} stats: enqueued={d} dispatched={d} batches={d} max_batch={d} max_depth={d} max_cap={d} avg/batch={d:.2} avg_dispatch_ms={d:.2} max_dispatch_ms={d:.2}",
            .{
                self.name,
                self.stats.total_enqueued,
                self.stats.total_dispatched,
                self.stats.total_batches,
                self.stats.max_batch_size,
                self.stats.max_queue_depth,
                self.stats.max_capacity,
                avg,
                avg_dispatch_ms,
                self.stats.max_dispatch_time_ns / std.time.ns_per_ms,
            },
            @src(),
        );

        self.queue.deinit(self.domain.allocator);
    }

    pub fn start(self: *QueueMgr) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;
        if (self.stopping) return error.QueueStopping;
        if (self.running) return;

        self.finished = false;
        self.running = true;

        self.worker =
            std.Thread.spawn(
                .{},
                mainLoop,
                .{self},
            ) catch |err| {
                self.running = false;
                self.finished = true;
                self.worker = null;
                return err;
            };

        self.logger.info("queue from {s} worker started", .{self.name}, @src());
    }

    pub fn stop(self: *QueueMgr) void {
        self.mutex.lock();

        while (self.stopping) {
            self.cond.wait(&self.mutex);
        }
        if (!self.running) {
            self.mutex.unlock();
            return;
        }

        self.stopping = true;
        self.finished = true;

        self.mutex.unlock();

        self.cond.broadcast();
        self.join();

        self.mutex.lock();
        self.running = false;
        self.stopping = false;
        // Despierta a otros stop()/close() que esperan el final de la parada.
        self.cond.broadcast();
        self.mutex.unlock();

        self.logger.info("queue from {s} stopped", .{self.name}, @src());
    }

    fn join(self: *QueueMgr) void {
        if (self.worker) |t| {
            t.join();
        }

        self.worker = null;
        self.logger.info("queue from {s} worker finished", .{self.name}, @src());
    }

    pub fn close(self: *QueueMgr) void {
        self.mutex.lock();

        if (self.closed) {
            self.mutex.unlock();
            return;
        }
        self.closed = true;
        self.mutex.unlock();

        self.stop();
        self.deinit();

        self.logger.info("QM closed", .{}, @src());
    }

    pub fn enqueue(self: *QueueMgr, msg: Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;
        if (!self.domain.running.load(.acquire)) return error.DomainClosed;
        if (self.stopping) return error.QueueStopping;
        if (!self.running or self.finished) return error.QueueNotRunning;

        try self.queue.append(self.domain.allocator, msg);

        self.stats.total_enqueued += 1;
        if (self.queue.items.len > self.stats.max_queue_depth) {
            self.stats.max_queue_depth = self.queue.items.len;
        }

        if (self.queue.capacity > self.stats.max_capacity)
            self.stats.max_capacity = self.queue.capacity;

        self.cond.signal();
    }

    /// Ownership contract:
    /// - Success: QueueMgr acquires ownership of every Msg and its payload.
    /// - Error: ownership remains with the caller.
    /// - The backing slice is never owned by QueueMgr.
    pub fn enqueueMany(self: *QueueMgr, msgs: []const Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;
        if (!self.domain.running.load(.acquire)) return error.DomainClosed;
        if (self.stopping) return error.QueueStopping;
        if (!self.running or self.finished) return error.QueueNotRunning;

        try self.queue.appendSlice(self.domain.allocator, msgs);

        self.stats.total_enqueued += msgs.len;
        if (self.queue.items.len > self.stats.max_queue_depth) {
            self.stats.max_queue_depth = self.queue.items.len;
        }

        if (self.queue.capacity > self.stats.max_capacity)
            self.stats.max_capacity = self.queue.capacity;

        self.cond.signal();
    }

    fn waitAndFetch(self: *QueueMgr, out_msgs: *std.ArrayList(Msg)) !bool {
        // logger.trace("{s} ENTER waitAndFetch queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());
        out_msgs.clearRetainingCapacity();
        // logger.trace("{s} after clear out.len={d}", .{ self.name, out_msgs.items.len }, @src());

        self.mutex.lock();

        while (self.queue.items.len == 0 and !self.finished) {
            self.cond.wait(&self.mutex);
        }

        if (self.finished and self.queue.items.len == 0) {
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

            if (self.finished and self.queue.items.len == 0) {
                self.mutex.unlock();
                return false;
            }
        }

        try out_msgs.appendSlice(self.domain.allocator, self.queue.items);
        // logger.trace("{s} after appendSlice queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());

        self.queue.clearRetainingCapacity();
        // logger.trace("{s} after clearRetainingCapacity queue.len={d} out.len={d}", .{ self.name, self.queue.items.len, out_msgs.items.len }, @src());

        self.mutex.unlock();

        return true;
    }

    fn mainLoop(self: *QueueMgr) void {
        var msg_list: std.ArrayList(Msg) = .empty;
        defer msg_list.deinit(self.domain.allocator);

        while (self.waitAndFetch(&msg_list) catch false) {
            if (msg_list.items.len > 0) {
                const batch_len = msg_list.items.len;

                self.stats.total_batches += 1;
                self.stats.total_dispatched += batch_len;

                if (batch_len > self.stats.max_batch_size) {
                    self.stats.max_batch_size = batch_len;
                }

                const strt = std.time.nanoTimestamp();

                self.dispatch_fn(self.owner, msg_list.items);

                const elapsed: u64 = @intCast(std.time.nanoTimestamp() - strt);
                self.stats.dispatch_time_ns += elapsed;
                if (elapsed > self.stats.max_dispatch_time_ns) {
                    self.stats.max_dispatch_time_ns = elapsed;
                }
            }
        }
    }
};
