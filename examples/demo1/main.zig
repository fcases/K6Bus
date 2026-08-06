const std = @import("std");

const k6bus = @import("k6bus");

const app = @import("generated/root.zig");
const Estacion = app.Estacion;
const SubscriberEstacion = app.EstacionSubscriber;
const PublisherEstacion = app.EstacionPublisher;

const DispatchMode = k6bus.Config.DispatchMode;

var logger: *k6bus.Logger = undefined;

var published_count: u32 = 0;
var count1: std.atomic.Value(u32) = .init(0);
var count2: std.atomic.Value(u32) = .init(0);
var count3: std.atomic.Value(u32) = .init(0);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // var dom = try k6bus.Domain.create(allocator, 77);
    var dom = try k6bus.Domain.createEx(allocator, 77, .BATCH, 300);

    logger = &dom.logger;

    var publ = PublisherEstacion.create(dom) catch return dom.logger.err("Error creando publisher", .{}, @src());
    // const subs = SubscriberEstacion.create(dom, "estacion_channel", mia_callback) catch return dom.logger.err("Error creando subscriber", .{}, @src());
    const subs1 = try SubscriberEstacion.create(dom, "estacion_channel", callback_1);
    const subs2 = try SubscriberEstacion.create(dom, "estacion_channel", callback_2);
    // const subs3 = try SubscriberEstacion.create(dom, "estacion_channel", callback_3);
    _ = subs1; // avoid unused variable warning
    _ = subs2; // avoid unused variable warning
    // _ = subs3; // avoid unused variable warning

    var miEst = Estacion{
        .name = "Estacion 1",
        .ubicacion = "Ubicacion 1",
        .temperatura = 20.1,
    };

    // const ser1 = miEst.seriigiAlBin(allocator, app.EstacionFile.BinaraFormato.BF_BINPB2TEKSTO_HEX) catch return dom.logger.err("Error serializando estacion", .{}, @src());
    // std.debug.print("{s}\n", .{ser1});
    // defer allocator.free(ser1);

    const N: usize = 10;
    while (true) {
        std.debug.print("\n[a] publicar {d} mensajes | [q] salir > ", .{N});

        const key = readKey() catch |err| {
            std.debug.print("Error leyendo tecla: {}\n", .{err});
            continue;
        };

        switch (key) {
            'q', 'Q' => {
                std.debug.print("Saliendo del bucle...\n", .{});
                break;
            },

            'a', 'A' => {
                std.debug.print("Publicando {d} mensajes...\n", .{N});

                // const t0 = std.time.milliTimestamp();
                // for (0..10000) |_| {
                for (0..N) |_| {
                    miEst.temperatura += 0.05;
                    published_count += 1;
                    // std.debug.print("sent count: {d}\n", .{published_count});

                    _ = publ.publish("estacion_channel", &miEst) catch {
                        dom.logger.err("Error publicando estacion", .{}, @src());
                        return;
                    };
                }
                // std.debug.print("publish done: {} ms\n", .{std.time.milliTimestamp() - t0});
            },

            else => {
                std.debug.print("Tecla no reconocida: '{c}'. Usa 'a' o 'q'.\n", .{key});
            },
        }
    }

    // logger.info("Received callbacks={d}", .{received_count}, @src());
    dom.close();
    // std.debug.print("all received : {} ms\n", .{std.time.milliTimestamp() - t0});

    return;
}

// pub fn mia_callback(channel_name: []const u8, estacion: *const Estacion) void {
//     received_count += 1;
//     std.debug.print("received count: {d}\n", .{received_count});

//     logger.info(
//         \\\tmia_callback count={d} channel={s} Estacion={{
//         \\\t\t .name={s}
//         \\t\t .ubicacion={s}
//         \\t\t .temperatura={d}
//         \\t}}
//     ,
//         .{
//             received_count,
//             channel_name,
//             estacion.name,
//             estacion.ubicacion,
//             estacion.temperatura,
//         },
//         @src(),
//     );
// }

fn callback_1(channel_name: []const u8, estacion: *const Estacion) void {
    _ = channel_name;
    _ = estacion;

    const n = count1.fetchAdd(1, .monotonic) + 1;

    // if (n % 5000 == 0) std.debug.print("SUB1 received={d}\n", .{n});
    std.debug.print("SUB1 received={d}\n", .{n});
}

fn callback_2(channel_name: []const u8, estacion: *const Estacion) void {
    _ = channel_name;
    _ = estacion;

    const n = count2.fetchAdd(1, .monotonic) + 1;

    // if (n % 5000 == 0) std.debug.print("SUB2 received={d}\n", .{n});
    std.debug.print("SUB2 received={d}\n", .{n});
}

// fn callback_3(channel_name: []const u8, estacion: *const Estacion) void {
//     _ = channel_name;
//     _ = estacion;

//     const n = count3.fetchAdd(1, .monotonic) + 1;

//     // if (n % 5000 == 0) std.debug.print("SUB3 received={d}\n", .{n});
//     std.debug.print("SUB3 received={d}\n", .{n});
// }

fn readKey() !u8 {
    var buf: [64]u8 = undefined;

    // stdin = fd 0
    const stdin_fd: std.posix.fd_t = 0;

    const n = try std.posix.read(stdin_fd, buf[0..]);

    if (n == 0) return 'q';

    for (buf[0..n]) |c| {
        switch (c) {
            '\n', '\r', ' ', '\t' => continue,
            else => return c,
        }
    }

    return 0;
}
