const std = @import("std");

const k6bus = @import("k6bus");
const app = @import("generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var dom = k6bus.Domain.create(allocator);

    const Estacion = app.Estacion.demo1.Estacion;
    const SubscriberEstacion = app.SubscriberEstacion;

    var sub = SubscriberEst.create("micanal");

    std.debug.print("Sistema listo", .{});
}
