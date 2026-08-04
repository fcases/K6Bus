const std = @import("std");

// ============================================================================
// INTERFACE
// ============================================================================

const ifcTransport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        start: *const fn (*anyopaque) void,
        stop: *const fn (*anyopaque) void,
        close: *const fn (*anyopaque) void,
    };

    pub fn start(self: ifcTransport) void {
        self.vtable.start(self.ptr);
    }

    pub fn stop(self: ifcTransport) void {
        self.vtable.stop(self.ptr);
    }

    pub fn close(self: ifcTransport) void {
        self.vtable.close(self.ptr);
    }

    pub fn init(impl: anytype) ifcTransport {
        const Impl = @TypeOf(impl.*);

        const gen = struct {
            fn start(ptr: *anyopaque) void {
                const self: *Impl = @ptrCast(@alignCast(ptr));
                Transport(Impl).start(self);
            }

            fn stop(ptr: *anyopaque) void {
                const self: *Impl = @ptrCast(@alignCast(ptr));
                Transport(Impl).stop(self);
            }

            fn close(ptr: *anyopaque) void {
                const self: *Impl = @ptrCast(@alignCast(ptr));
                Transport(Impl).close(self);
            }
        };

        return .{
            .ptr = impl,
            .vtable = &.{
                .start = gen.start,
                .stop = gen.stop,
                .close = gen.close,
            },
        };
    }
};

// ============================================================================
// COMMON TRANSPORT BEHAVIOUR (CRTP STYLE)
// ============================================================================
fn Transport(comptime Self: type) type {
    return struct {
        pub fn start(self: *Self) void {
            base_start(self);
            if (@hasDecl(Self, "onStart")) self.onStart();
        }

        pub fn stop(self: *Self) void {
            if (@hasDecl(Self, "onStop")) self.onStop();
            base_stop(self);
        }

        pub fn close(self: *Self) void {
            if (@hasDecl(Self, "onClose")) self.onClose();
            base_close(self);
        }

        fn base_start(self: *Self) void {
            _ = self;
            std.debug.print("[Transport] start common\n",.{});
        }

        fn base_stop(self: *Self) void {
            _ = self;
            std.debug.print("[Transport] stop common\n",.{});
        }

        fn base_close(self: *Self) void {
            _ = self;
            std.debug.print("[Transport] close common\n",.{});
        }
    };
}

// ============================================================================
// MCAST
// ============================================================================

const aMCastTransport = struct {
    group: []const u8,
    port: u16,

    pub fn onStart(self: *aMCastTransport) void {
        std.debug.print(
            "[MCast] joining {s}:{d}\n",
            .{
                self.group,
                self.port,
            },
        );
    }

    pub fn onStop(self: *aMCastTransport) void {
        _ = self;
        std.debug.print(
            "[MCast] stopping\n",
            .{},
        );
    }

    pub fn onClose(self: *aMCastTransport) void {
        _ = self;

        std.debug.print(
            "[MCast] closing sockets\n",
            .{},
        );
    }
};

// ============================================================================
// BCAST
// ============================================================================

const aBCastTransport = struct {
    addr: []const u8,
    port: u16,

    pub fn onStart(self: *aBCastTransport) void {
        std.debug.print(
            "[BCast] start {s}:{d}\n",
            .{
                self.addr,
                self.port,
            },
        );
    }

    pub fn onStop(self: *aBCastTransport) void {
        _ = self;
        std.debug.print(
            "[BCast] stop\n",
            .{},
        );
    }

    pub fn onClose(self: *aBCastTransport) void {
        _ = self;

        std.debug.print(
            "[BCast] close\n",
            .{},
        );
    }
};

// ============================================================================
// MAIN
// ============================================================================

pub fn main() void {
    var mcast = aMCastTransport{
        .group = "239.255.0.11",
        .port = 40069,
    };

    var bcast = aBCastTransport{
        .addr = "192.168.2.255",
        .port = 40069,
    };

    const lista = [_]ifcTransport{
        ifcTransport.init(&mcast),
        ifcTransport.init(&bcast),
    };

    for (lista) |t| {
        t.start();
    }

    std.debug.print("\n", .{});

    for (lista) |t| {
        t.stop();
    }

    std.debug.print("\n", .{});

    for (lista) |t| {
        t.close();
    }
}