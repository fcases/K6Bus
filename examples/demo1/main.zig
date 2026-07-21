const std = @import("std");

const k6bus = @import("k6bus");

const app = @import("generated/root.zig");
const Estacion = app.Estacion.demo1.Estacion;
const SubscriberEstacion = app.SubscriberEstacion;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var dom = try k6bus.Domain.create(allocator, 77);

    const publ = app.EstacionPublisher.create(&dom) catch return dom.logger.err("Error creando publisher", .{}, @src());

    const subs = app.EstacionSubscriber.create(&dom, "estacion_channel") catch return dom.logger.err("Error creando subscriber", .{}, @src());

    _ = subs;

    const miEst = Estacion{
        .id = 1,
        .nombre = "Estacion 1",
        .ubicacion = "Ubicacion 1",
    };
    publ.publish("estacion_channel", &miEst) catch return dom.logger.err("Error publicando estacion", .{}, @src());

    std.Thread.sleep(5_000_000_000);
    dom.close() catch return dom.logger.err("Error cerrando dominio", .{}, @src());
    dom.logger.info("Demo finalizado", .{}, @src());

    return;
}
