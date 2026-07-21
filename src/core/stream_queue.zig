// stream_queue.zig

const std = @import("std");

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;
const Logger = @import("logger.zig").Logger;

pub const BatchMode = enum { INMEDIATE, BATCH };
pub const StreamMode = enum { UP, DOWN };

pub const StreamQueue = struct {
    domain: *Domain,
    mode: StreamMode,
    qm: QueueMgr,
    logger: Logger,

    const Self = @This();

    pub fn init(
        self: *Self,
        domain: *Domain,
        mode: StreamMode,
        batch_mode: BatchMode,
        batch_wait_ms: u32,
    ) !void {
        self.domain = domain;
        self.mode = mode;
        self.logger = domain.logger;

        const DispatchMsg =
            if (mode == .UP) dispatchToSubscribers else dispatchToTransports;

        self.qm = try QueueMgr.create(
            domain,
            if (mode == .UP)
                "StreamQueueUP"
            else
                "StreamQueueDOWN",
            batch_mode,
            batch_wait_ms,
            self,
            DispatchMsg,
        );

        self.logger.info("{s} initialized", .{self.qm.name}, @src());
    }

    pub fn start(self: *StreamQueue) !void {
        try self.qm.start();

        self.logger.info("{s} started", .{self.qm.name}, @src());
    }

    pub fn pause(self: *Self) void {
        self.qm.pause();

        self.logger.info("{s} paused", .{self.qm.name}, @src());
    }

    pub fn join(self: *Self) void {
        self.qm.join();

        self.logger.info("{s} joined", .{self.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.qm.close();

        self.logger.info("{s} closed", .{self.qm.name}, @src());
    }

    fn dispatchToSubscribers(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *StreamQueue = @ptrCast(@alignCast(owner));

        self.domain.registry_lock.lockShared();
        defer self.domain.registry_lock.unlockShared();

        const registry = &self.domain.registry();

        for (msg_list) |msg| {
            for (msg.channels) |channel| {
                for (registry.items) |entry| {
                    if (entry.channel == channel) {
                        entry.qm.enqueue(msg) catch {};
                    }
                }
            }
        }

        self.logger.info("{s} dispatched  messages to subscribers", .{self.qm.name}, @src());
    }

    fn dispatchToTransports(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *StreamQueue = @ptrCast(@alignCast(owner));

        self.domain.transport_lock.lockShared();
        defer self.domain.transport_lock.unlockShared();

        const transports = &self.domain.transports;

        for (transports.items) |transport| {
            transport.qm.enqueueMany(msg_list) catch {};
        }

        self.logger.info("{s} dispatched messages to transports", .{self.qm.name}, @src());
    }
};
