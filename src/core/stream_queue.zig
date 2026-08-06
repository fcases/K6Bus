// ============================================================================
// StreamQueue
// ============================================================================
//
// Cola de distribución principal de Domain.
//
// StreamQueue desacopla productores y consumidores de mensajes,
// proporcionando un punto central de encaminamiento dentro del
// dominio K6Bus.
//
// Existen dos instancias:
//
//   StreamQueueDOWN
//       Recibe mensajes generados localmente y los distribuye
//       hacia los transportes registrados.
//
//   StreamQueueUP
//       Recibe mensajes procedentes de los transportes y los
//       distribuye hacia los subscribers registrados.
//
// Responsabilidades:
//
//   - almacenar temporalmente listas de Msg
//   - procesar mensajes mediante QueueMgr
//   - desacoplar productores y consumidores
//   - distribuir mensajes a transportes o subscribers
//   - aplicar políticas de DispatchMode
//
// StreamQueue no realiza:
//
//   - serialización/deserialización
//   - cifrado/descifrado
//   - codificación/decodificación
//   - operaciones de red
//
// Dichas funciones pertenecen a PacketProcessor y a los
// transportes concretos.
//
// Arquitectura:
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
//           Transportes              Subscribers
//
// ============================================================================
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
    name: []const u8,
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
        self.name = if (mode == .UP) try domain.allocator.dupe(u8, "StreamQueueUP") else try domain.allocator.dupe(u8, "StreamQueueDOWN");
        self.mode = mode;

        self.dispatch_fn =
            if (mode == .UP) dispatchToSubscribers else dispatchToTransports;

        self.qm = try QueueMgr.create(domain, self.name, batch_mode, batch_wait_ms, self, self.dispatch_fn);

        logger = &domain.logger;
        logger.info("{s} initialized", .{self.qm.name}, @src());
    }

    fn deinit(self: *Self) void {
        self.domain.allocator.free(self.name);
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
        const aux_name = try self.domain.allocator.dupe(u8, self.qm.name);
        defer self.domain.allocator.free(aux_name);

        self.qm.close();
        self.deinit();

        logger.info("{s} closed", .{self.aux_name}, @src());
    }

    pub fn enqueue(self: *StreamQueue, msg: Msg) !void {
        self.qm.enqueue(msg) catch {
            logger.err("{s} failed to enqueue message", .{self.qm.name}, @src());
            return error.EnqueueFailed;
        };
    }

    pub fn enqueueMany(self: *StreamQueue, msgs: []const Msg) !void {
        self.qm.enqueueMany(msgs) catch {
            logger.err("{s} failed to enqueue messages", .{self.qm.name}, @src());
            return error.EnqueueFailed;
        };
    }

    pub fn dispatchToSubscribersDirect(self: *StreamQueue, msg_list: []const Msg) void {
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
                logger.warning("{s} failed to clone messages for transport {s}", .{ self.qm.name, transport.getName() }, @src());
                continue;
            };

            transport.enqueueMany(clonList) catch {
                Utils.freeClonedMsgSlice(self.domain.allocator, clonList);
                logger.warning("{s} failed to enqueue messages for transport {s}", .{ self.name, transport.getName() }, @src());
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
        self.domain.upstream.enqueueMany(clonList2) catch {
            Utils.freeClonedMsgSlice(self.domain.allocator, clonList2);
            logger.warning("{s} failed to dispatch messages to upstream", .{self.qm.name}, @src());
        };
        self.domain.allocator.free(clonList2);
        logger.info("{s} dispatched messages to upstream {s}", .{ self.qm.name, self.domain.upstream.qm.name }, @src());

        Utils.freeMsgsFromSlice(self.domain.allocator, @constCast(msg_list));
    }
};
