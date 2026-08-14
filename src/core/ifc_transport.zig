// ============================================================================
// ifc_transport.zig
//
// Interface between Domain and Transports.
//
// Domain only knows:
//
//      start()
//      stop()
//      close()
//      enqueue()
//      crossConnect()
//
// Everything else belongs to the concrete transport.
//
// ============================================================================

const std = @import("std");

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

// ============================================================================
// INTERFACE
// ============================================================================
pub const ifcTransport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const Self = @This();

    // ========================================================================
    // VTABLE
    // ========================================================================
    pub const VTable = struct {
        start: *const fn (*anyopaque,) anyerror!void,
        stop: *const fn (*anyopaque) void,
        close: *const fn (*anyopaque) void,
        enqueue: *const fn (*anyopaque, Msg) anyerror!void,
        enqueueMany: *const fn (*anyopaque, []const Msg) anyerror!void,
        crossConnect: *const fn (*anyopaque, ifcTransport) anyerror!void,
        getName: *const fn (*anyopaque) []const u8,
    };

    // ========================================================================
    // PUBLIC API
    // ========================================================================
    pub fn start(self: Self) !void {
        try self.vtable.start(self.ptr);
    }

    pub fn stop(self: Self) void {
        self.vtable.stop(self.ptr);
    }

    pub fn close(self: Self) void {
        self.vtable.close(self.ptr);
    }

    pub fn enqueue(self: Self, msg: Msg) !void {
        try self.vtable.enqueue(self.ptr, msg);
    }

    pub fn enqueueMany(self: Self, msg_list: []const Msg) !void {
        try self.vtable.enqueueMany(self.ptr, msg_list);
    }

    pub fn crossConnect(self: Self, other: ifcTransport) !void {
        try self.vtable.crossConnect(self.ptr, other);
    }

    pub fn getName(self: Self) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    // ========================================================================
    // AUTOMATIC VTABLE GENERATION
    // ========================================================================
    pub fn init(impl: anytype) ifcTransport {
        const Impl = @TypeOf(impl.*);

        const gen = struct {
            fn start(ptr: *anyopaque) !void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                try Impl.start(self);
            }

            fn stop(ptr: *anyopaque) void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                Impl.stop(self);
            }

            fn close(ptr: *anyopaque) void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                Impl.close(self);
            }

            fn enqueue(ptr: *anyopaque, msg: Msg) !void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                try Impl.enqueue(self, msg);
            }

            fn enqueueMany(ptr: *anyopaque, msg_list: []const Msg) !void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                try Impl.enqueueMany(self, msg_list);
            }
            
            fn crossConnect(ptr: *anyopaque, other: ifcTransport) !void {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                try Impl.crossConnect(self, other);
            }

            fn getName(ptr: *anyopaque) []const u8 {
                const self: *Impl = @ptrCast(@alignCast(ptr));

                return Impl.getName(self);
            }
        };

        return .{
            .ptr = impl,
            .vtable = &.{
                .getName = gen.getName,
                .start = gen.start,
                .stop = gen.stop,
                .close = gen.close,
                .enqueue = gen.enqueue,
                .enqueueMany = gen.enqueueMany,
                .crossConnect = gen.crossConnect,
            },
        };
    }
};
