// stream_queue.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;
const Logger = @import("logger.zig").Logger;
const Utils = @import("msg_utils.zig");

const DispatchFn = @import("queue_mgr.zig").DispatchFn;

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;
pub const StreamMode = enum { UP, DOWN };

var logger: *Logger = undefined;

pub const StreamQueue = struct {
    domain: *Domain,
    mode: StreamMode,
    qm: QueueMgr,
    dispatch_fn: DispatchFn,
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

        self.dispatch_fn =
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
            self.dispatch_fn,
        );

        logger = &domain.logger;
        logger.info("{s} initialized", .{self.qm.name}, @src());
    }

    pub fn start(self: *StreamQueue) !void {
        try self.qm.start();

        logger.info("{s} started", .{self.qm.name}, @src());
    }

    pub fn stop(self: *Self) void {
        self.qm.stop();

        logger.info("{s} stopped", .{self.qm.name}, @src());
    }

    pub fn join(self: *Self) void {
        self.qm.join();

        logger.info("{s} joined", .{self.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.qm.close();

        logger.info("{s} closed", .{self.qm.name}, @src());
    }

    pub fn dispatchToSubscribersDirect(
        self: *StreamQueue,
        msg_list: []const Msg,
    ) void {
        dispatchToSubscribers(self, msg_list);
    }

    fn dispatchToSubscribers(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *StreamQueue = @ptrCast(@alignCast(owner));

        self.domain.registry_lock.lockShared();
        defer self.domain.registry_lock.unlockShared();

        const registry = &self.domain.registry;

        for (msg_list) |*msg| {
            defer Utils.freeMsg(self.domain.allocator, @constCast(msg));

            for (msg.channels) |channel| {
                for (registry.items) |entry| {
                    if (entry.channel == channel) {
                        var cloned =
                            Utils.cloneMsg(self.domain.allocator, msg) catch continue;

                        entry.subscriber.enqueue(cloned) catch {
                            Utils.freeMsg(self.domain.allocator, &cloned);
                        };
                    }
                }
            }
        }

        logger.info("{s} dispatched messages to subscribers", .{self.qm.name}, @src());
    }

    fn dispatchToTransports(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *StreamQueue = @ptrCast(@alignCast(owner));

        self.domain.transport_lock.lockShared();
        defer self.domain.transport_lock.unlockShared();

        const transports = &self.domain.transports;
        for (transports.items) |transport| {
            const clonList = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch {
                logger.warning("{s} failed to clone messages for transport {s}", .{ self.qm.name, transport.name }, @src());
                continue;
            };

            transport.qm.enqueueMany(clonList) catch {
                Utils.freeClonedMsgSlice(self.domain.allocator, clonList);
                logger.warning("{s} failed to enqueue messages for transport {s}", .{ self.qm.name, transport.name }, @src());
                continue;
            };
            self.domain.allocator.free(clonList);
        }
        logger.info("{s} dispatched messages to transports", .{self.qm.name}, @src());

        const clonList2 = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch {
            logger.warning("{s} failed to clone messages for upstream {s}", .{ self.qm.name, self.domain.upstream.qm.name }, @src());
            return;
        };
        logger.trace("{s} dispatching messages in local loop to upstream {s}", .{ self.qm.name, self.domain.upstream.qm.name }, @src());
        self.domain.upstream.qm.enqueueMany(clonList2) catch {
            Utils.freeClonedMsgSlice(self.domain.allocator, clonList2);
            logger.warning("{s} failed to dispatch messages to upstream", .{self.qm.name}, @src());
        };
        self.domain.allocator.free(clonList2);
        logger.info("{s} dispatched messages to upstream {s}", .{ self.qm.name, self.domain.upstream.qm.name }, @src());

        Utils.freeMsgsFromSlice(self.domain.allocator, @constCast(msg_list));
    }
};
