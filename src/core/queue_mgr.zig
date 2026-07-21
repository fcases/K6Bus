// queue_mgr.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const BatchMode = @import("formats.zig").BatchMode;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

pub const DispatchFn = *const fn (
    owner: *anyopaque,
    msg_list: []const Msg,
) void;

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
        return .{
            .domain = domain,
            .name = try domain.allocator.dupe(u8, name),
            .batch_mode = batch_mode,
            .batch_wait_ms = batch_wait_ms,
            .owner = owner,
            .dispatch_fn = dispatch_fn,

            .queue = std.ArrayList(Msg).init(domain.allocator),
        };
    }

    pub fn deinit(self: *QueueMgr) void {
        self.queue.deinit();
        self.domain.allocator.free(self.name);
    }

    pub fn start(self: *QueueMgr) !void {
        if (self.running) return;

        self.finished = false;
        self.worker =
            try std.Thread.spawn(
                .{},
                mainLoop,
                .{self},
            );
        self.running = true;
    }

    pub fn pause(self: *QueueMgr) void {
        if (!self.running) return;

        self.stop();
        self.join();

        self.running = false;
    }

    fn stop(self: *QueueMgr) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.finished = true;

        self.cond.broadcast();
    }

    pub fn join(self: *QueueMgr) void {
        if (self.worker) |t| {
            t.join();
        }

        self.worker = null;
    }

    pub fn close(self: *QueueMgr) void {
        self.pause();
        self.deinit();
    }

    pub fn enqueue(self: *QueueMgr, msg: Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.append(msg);

        self.cond.signal();
    }

    pub fn enqueueMany(self: *QueueMgr, msgs: []const Msg) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.appendSlice(msgs);

        self.cond.signal();
    }

    fn waitAndFetch(self: *QueueMgr, out_msgs: *std.ArrayList(Msg)) !bool {
        out_msgs.clearRetainingCapacity();

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

        try out_msgs.appendSlice(self.queue.items);

        self.queue.clearRetainingCapacity();

        self.mutex.unlock();

        return true;
    }

    fn mainLoop(self: *QueueMgr) void {
        var msg_list = std.ArrayList(Msg).init(self.domain.allocator);
        defer msg_list.deinit();

        while (self.waitAndFetch(&msg_list) catch false) {
            self.dispatch_fn(self.owner, msg_list.items);
        }
    }
};
