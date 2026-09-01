const std = @import("std");

const k6bus = @import("k6bus");

const ApiFile = @import("runtime/Estacion_api.zig");
const Estacion = ApiFile.Estacion;

const PubSub = @import("runtime/Estacion_safe_pubsub.zig");
const Estacion_Publisher = PubSub.Estacion_Publisher;
const Estacion_Subscriber = PubSub.Estacion_Subscriber;

var count1: std.atomic.Value(u32) = .init(0);
var count2: std.atomic.Value(u32) = .init(0);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("GPA detected leaks\n", .{});
        }
    }

    const allocator = gpa.allocator();

    // var dom = try k6bus.Domain.create(allocator, 77);
    var dom = try k6bus.Domain.createEx(allocator, 77, .BATCH, 300);
    defer dom.close();

    var publ = try Estacion_Publisher.create(dom);

    // Nuevo contrato: la baja de los subscribers la coordina el Domain.
    const subs1 = try Estacion_Subscriber.create(dom, "estacion_channel", callback_1);
    defer dom.closeSubscriber(subs1.interface());

    const subs2 = try Estacion_Subscriber.create(dom, "estacion_channel", callback_2);
    defer dom.closeSubscriber(subs2.interface());

    // Mensaje construido con la API segura.
    var miEst = try Estacion.initDefault(allocator);
    defer miEst.deinit(allocator);
    try miEst.setName(allocator, "Estacion 1");
    try miEst.setUbicacion(allocator, "Ubicacion 1");
    miEst.setTemperatura(20.1);

    const N: usize = 10;
    const transporte0 = dom.transports.items[0];

    while (true) {
        std.debug.print(
            "\n[a] publicar {d} mensajes | [s] parar Transporte 0 | [r] arrancar Transporte 0 | [x] cerrar Transporte 0 | [q] salir > ",
            .{N},
        );

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

                for (0..N) |_| {
                    miEst.setTemperatura(miEst.getTemperatura() + 0.05);

                    _ = publ.publish("estacion_channel", &miEst) catch {
                        dom.logger.err("Error publicando estacion", .{}, @src());
                        return;
                    };
                }
            },

            's', 'S' => {
                std.debug.print("Parando Transporte 0...\n", .{});
                transporte0.stop();
            },

            'r', 'R' => {
                std.debug.print("Arrancando Transporte 0...\n", .{});
                transporte0.start() catch |err| {
                    std.debug.print(
                        "Error arrancando Transporte 0: {s}\n",
                        .{@errorName(err)},
                    );
                };
            },

            'x', 'X' => {
                std.debug.print("Cerrando definitivamente Transporte 0...\n", .{});
                dom.closeTransport(transporte0);

                // Desde este punto, transporte0 contiene un ptr inválido.
                // Hay que salir del bucle y no volver a utilizarlo.
                break;
            },

            else => {
                std.debug.print(
                    "Tecla no reconocida: '{c}'. Usa 'a', 's', 'r', 'x' o 'q'.\n",
                    .{key},
                );
            },
        }
    }

    return;
}

fn callback_1(
    _: std.mem.Allocator,
    channel_name: []const u8,
    estacion: *const Estacion,
) void {
    _ = channel_name;
    _ = estacion;

    const n = count1.fetchAdd(1, .monotonic) + 1;

    // if (n % 5000 == 0) std.debug.print("SUB1 received={d}\n", .{n});
    std.debug.print("SUB1 received={d}\n", .{n});
}

fn callback_2(
    _: std.mem.Allocator,
    channel_name: []const u8,
    estacion: *const Estacion,
) void {
    _ = channel_name;
    _ = estacion;

    const n = count2.fetchAdd(1, .monotonic) + 1;

    // if (n % 5000 == 0) std.debug.print("SUB2 received={d}\n", .{n});
    std.debug.print("SUB2 received={d}\n", .{n});
}

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
