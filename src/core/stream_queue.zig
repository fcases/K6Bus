// ============================================================================
// StreamQueue
// ============================================================================
//
// Main distribution queue of Domain.
//
// StreamQueue decouples message producers and consumers, providing a
// central routing point inside the K6Bus domain.
//
// There are two instances:
//
//   StreamQueueDOWN
//       Receives locally produced messages and distributes them
//       to the registered transports.
//
//   StreamQueueUP
//       Receives messages coming in from the transports and
//       distributes them to the registered subscribers.
//
// Responsibilities:
//
//   - hold lists of Msg temporarily
//   - process messages through QueueMgr
//   - decouple producers and consumers
//   - distribute messages to transports or subscribers
//   - apply the DispatchMode policies
//
// StreamQueue does not do:
//
//   - serialization/deserialization
//   - encryption/decryption
//   - encoding/decoding
//   - network operations
//
// Those belong to PacketProcessor and to the concrete transports.
//
// Architecture:
//
//                    +----------------+
//                    |     Domain     |
//                    +----------------+
//                              |
//                 +------------+------------+
//                 |                         |
//                 v                         v
//         StreamQueueDOWN           StreamQueueUP
//                 |                         |
//                 v                         v
//            Transports                Subscribers
//
// ============================================================================
const std = @import("std");

const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;
const Logger = @import("logger.zig").Logger;
const Utils = @import("msg_utils.zig");

const DispatchFn = @import("queue_mgr.zig").DispatchFn;

const Msg = @import("../generated/types.zig").k6bus.Msg;
const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;

pub const StreamMode = enum { UP, DOWN };


fn StreamQueue(comptime mode: StreamMode) type {
    return struct {
        domain: *Domain,
        logger: *Logger = undefined,
        name: []const u8,
        qm: QueueMgr,

        /// false until init() finishes. A half-initialized queue (a failed
        /// QueueMgr.create) has NO qm: close() must not touch it (L1).
        kreita: bool = false,

        const Self = @This();

        pub fn init(
            self: *Self,
            domain: *Domain,
            batch_mode: BatchMode,
            batch_wait_ms: u32,
        ) !void {
            self.kreita = false;
            self.domain = domain;
            self.name = if (mode == .UP) try domain.allocator.dupe(u8, "StreamQueueUP") else try domain.allocator.dupe(u8, "StreamQueueDOWN");
            errdefer domain.allocator.free(self.name);

            const dispatch_fn: DispatchFn =
                if (mode == .UP) dispatchToSubscribers else dispatchToTransports;

            self.qm = try QueueMgr.create(domain, self.name, batch_mode, batch_wait_ms, self, dispatch_fn);
            errdefer self.qm.close();

            self.logger = &domain.logger;
            self.logger.info("{s} initialized", .{self.name}, @src());

            self.kreita = true;
        }

        fn deinit(self: *Self) void {
            self.domain.allocator.free(self.name);
            self.kreita = false;
        }

        pub fn start(self: *Self) !void {
            try self.qm.start();

            self.logger.info("{s} started", .{self.name}, @src());
        }

        pub fn stop(self: *Self) void {
            self.qm.stop();

            self.logger.info("{s} stopped", .{self.name}, @src());
        }

        // Nothing calls it
        // pub fn join(self: *Self) void {
        //     self.qm.join();

        //     logger.info("{s} joined", .{self.name}, @src());
        // }

        /// Called only by Domain.close().
        /// Concurrent calls are not part of this function's contract.
        pub fn close(self: *Self) void {
            // Queue that never finished initializing (its init already cleaned
            // itself up): there is no qm to close. Without this guard, the
            // cleanup of a failed Domain init touched uninitialized memory (L1).
            if (!self.kreita) return;

            self.qm.close();
            self.deinit();

            if (mode == .UP)
                self.logger.info("UpStreamQ closed", .{}, @src())
            else
                self.logger.info("DownStreamQ closed", .{}, @src());
        }

        pub fn enqueue(self: *Self, msg: Msg) !void {
            self.qm.enqueue(msg) catch {
                self.logger.err("{s} failed to enqueue message", .{self.name}, @src());
                return error.EnqueueFailed;
            };
        }

        pub fn enqueueMany(self: *Self, msgs: []const Msg) !void {
            self.qm.enqueueMany(msgs) catch {
                self.logger.err("{s} failed to enqueue messages", .{self.name}, @src());
                return error.EnqueueFailed;
            };
        }

        pub fn dispatchToSubscribersDirect(self: *Self, msg_list: []const Msg) void {
            comptime {
                if (mode != .UP)
                    @compileError("dispatchToSubscribersDirect only valid for UpStreamQ");
            }

            dispatchToSubscribers(self, msg_list);
        }

        fn dispatchToSubscribers(owner: *anyopaque, msg_list: []const Msg) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            self.domain.registry_lock.lockShared();
            defer self.domain.registry_lock.unlockShared();

            const registry = &self.domain.registry;

            for (msg_list) |*msg| {
                defer Utils.freeMsg(self.domain.allocator, @constCast(msg));

                for (msg.channels) |channel| {
                    // R4: the registry is ordered by (channel, msgType), so all
                    // matching entries are one contiguous run: binary-search its
                    // start (Domain.registryIndex) and walk it. Before, every
                    // channel of every message scanned the whole registry
                    // (O(channels x subscribers) per message).
                    var i = self.domain.registryIndex(channel, msg.msgType);
                    while (i < registry.items.len) : (i += 1) {
                        const entry = registry.items[i];
                        if (entry.channel != channel or entry.msgType != msg.msgType) break;

                        var cloned =
                            Utils.cloneMsg(self.domain.allocator, msg) catch continue;

                        entry.subscriber.enqueue(cloned) catch {
                            Utils.freeMsg(self.domain.allocator, &cloned);
                        };
                    }
                }
            }

            self.logger.info("{s} dispatched messages to subscribers", .{self.name}, @src());
        }

        fn dispatchToTransports(owner: *anyopaque, msg_list: []const Msg) void {
            const self: *Self = @ptrCast(@alignCast(owner));

            defer Utils.freeMsgsFromSlice(self.domain.allocator, @constCast(msg_list));

            self.domain.transport_lock.lockShared();
            defer self.domain.transport_lock.unlockShared();

            const transports = &self.domain.transports;
            for (transports.items) |transport| {
                const clonList = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch {
                    self.logger.warning("{s} failed to clone messages for transport {s}", .{ self.name, transport.getName() }, @src());
                    continue;
                };

                transport.enqueueMany(clonList) catch {
                    Utils.freeClonedMsgSlice(self.domain.allocator, clonList);
                    self.logger.warning("{s} failed to enqueue messages for transport {s}", .{ self.name, transport.getName() }, @src());
                    continue;
                };
                self.domain.allocator.free(clonList);
            }
            self.logger.info("{s} dispatched messages to transports", .{self.name}, @src());

            if (self.domain.subscriber_count.load(.monotonic) > 0) {
                const clonList2 = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch {
                    self.logger.warning("{s} failed to clone messages for upstream {s}", .{ self.name, self.domain.upstream.name }, @src());
                    return;
                };

                self.logger.trace("{s} dispatching messages in local loop to upstream {s}", .{ self.name, self.domain.upstream.name }, @src());

                if (self.domain.upstream.enqueueMany(clonList2)) |_| {
                    self.domain.allocator.free(clonList2);
                    self.logger.info("{s} dispatched messages to upstream {s}", .{ self.name, self.domain.upstream.name }, @src());
                } else |err| {
                    Utils.freeClonedMsgSlice(self.domain.allocator, clonList2);
                    self.logger.warning("{s} failed to dispatch messages to upstream: {s}", .{ self.name, @errorName(err) }, @src());
                }
            }
        }
    };
}

pub const UpStreamQ = StreamQueue(.UP);
pub const DownStreamQ = StreamQueue(.DOWN);
