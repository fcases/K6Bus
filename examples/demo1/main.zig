const std = @import("std");

const k6bus = @import("k6bus");

const app = @import("generated/root.zig");
const Estacion = app.Estacion;
const SubscriberEstacion = app.EstacionSubscriber;
const PublisherEstacion = app.EstacionPublisher;

var logger: *k6bus.Logger = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var dom = try k6bus.Domain.create(allocator, 77);

    logger = &dom.logger;

    var publ = PublisherEstacion.create(dom) catch return dom.logger.err("Error creando publisher", .{}, @src());
    const subs = SubscriberEstacion.create(dom, "estacion_channel", mia_callback) catch return dom.logger.err("Error creando subscriber", .{}, @src());
    _ = subs;

    var miEst = Estacion{
        .name = "Estacion 1",
        .ubicacion = "Ubicacion 1",
        .temperatura = 20.1,
    };

    const ser1 = miEst.seriigiAlBin(allocator, app.EstacionFile.BinaraFormato.BF_BINPB2TEKSTO_HEX) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n", .{ser1});
    defer allocator.free(ser1);

    _ = publ.publish("estacion_channel", &miEst) catch {
        dom.logger.err("Error publicando estacion", .{}, @src());
        return;
    };

    std.Thread.sleep(3_000_000_000);
    dom.close();

    return;
}

pub fn mia_callback(channel_name: []const u8, estacion: *const Estacion) void {
    logger.info("\nmia_callback channel={s} Estacion={{\n\t.name={s}\n\t.ubicacion={s}\n\t.temperatura={d}\n}}\n", .{ channel_name, estacion.name, estacion.ubicacion, estacion.temperatura }, @src());
}
