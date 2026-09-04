// ============================================================================
// ifc_subscriber.zig
//
// Interface between Domain and Subscribers.
//
// Domain only knows:
//
//      start()
//      stop()
//      close()
//      enqueue()
//
// Everything else belongs to the concrete subscriber.
//
// ============================================================================

const std = @import("std");

const Msg = @import("../generated/types.zig").k6bus.Msg;

// ============================================================================
// INTERFACE
// ============================================================================
pub const ifcSubscriber = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const Self = @This();

    // ========================================================================
    // VTABLE
    // ========================================================================
    pub const VTable = struct {
        start: *const fn (
            *anyopaque,
        ) anyerror!void,
        stop: *const fn (*anyopaque) void,
        close: *const fn (*anyopaque) void,
        enqueue: *const fn (*anyopaque, Msg) anyerror!void,
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

    // ========================================================================
    // AUTOMATIC VTABLE GENERATION
    // ========================================================================
    pub fn init(impl: anytype) ifcSubscriber {
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
        };

        return .{
            .ptr = impl,
            .vtable = &.{
                .start = gen.start,
                .stop = gen.stop,
                .close = gen.close,
                .enqueue = gen.enqueue,
            },
        };
    }
};
