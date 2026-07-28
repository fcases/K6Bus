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

    const ser2 = miEst.seriigiAlBin(allocator, app.EstacionFile.BinaraFormato.BF_BINPB2TEKSTO_DEC) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n", .{ser2});
    defer allocator.free(ser2);

    const ser3 = miEst.seriigiAlBin(allocator, app.EstacionFile.BinaraFormato.BF_PROTOBUF) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{any}\n", .{ser3});
    defer allocator.free(ser3);

    const ser4 = miEst.seriigiAlBin(allocator, app.EstacionFile.BinaraFormato.BF_BASE64) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n\n", .{ser4});
    defer allocator.free(ser4);

    const tex1 = miEst.skribiAlTeksto(allocator, .TF_PROTOBUF) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n", .{tex1});
    defer allocator.free(tex1);

    const tex2 = miEst.skribiAlTeksto(allocator, .TF_ZIG_ZON) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n", .{tex2});
    defer allocator.free(tex2);

    const tex3 = miEst.skribiAlTeksto(allocator, .TF_JSON) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    std.debug.print("{s}\n\n", .{tex3});
    defer allocator.free(tex3);

    std.debug.print("mia_callback channel={s} Estacion={{\n\t.name={s}\n\t.ubicacion={s}\n\t.temperatura={d}\n}}\n", .{ "estacion_channel", miEst.name, miEst.ubicacion, miEst.temperatura });

    _ = publ.publish("estacion_channel", &miEst) catch {
        dom.logger.err("Error publicando estacion", .{}, @src());
        return;
    };

    std.Thread.sleep(15_000_000_000);
    dom.close();
    dom.logger.info("Demo finalizado", .{}, @src());

    return;
}

pub fn mia_callback(channel_name: []const u8, estacion: *const Estacion) void {
    logger.info("mia_callback channel={s} Estacion={{\n\t.name={s}\n\t.ubicacion={s}\n\t.temperatura={d}\n}}\n", .{ channel_name, estacion.name, estacion.ubicacion, estacion.temperatura }, @src());
    std.debug.print("mia_callback channel={s} Estacion={{\n\t.name={s}\n\t.ubicacion={s}\n\t.temperatura={d:.17}\n}}\n", .{ channel_name, estacion.name, estacion.ubicacion, estacion.temperatura });
}
