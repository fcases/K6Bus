// ============================================================================
// demo3_matrix - Validacion E2E del transporte Matrix de K6Bus.
//
// Dos procesos (roles a/b), cada uno con un Domain id 77 y su transporte
// Matrix ("matrixA" / "matrixB"). Ambos transportes usan EL MISMO usuario de
// Matrix y la misma sala: dos "devices" del mismo usuario en la misma sala.
//
// Nota: src/runtime/ es una COPIA local del runtime Estacion de
// examples/demo1 (misma proto => mismo msgType). Si se regenera el runtime de
// demo1, recopiar estos ficheros para mantenerlos en sync.
//
// Flujo de validacion (A publica N, B los recibe por Matrix):
//   1. Arrancar B primero: fija su next_batch base (el backlog historico de
//      la sala NO se procesa; solo llega lo publicado en vivo).
//   2. A publica N -> subA los recibe en local; matrixA los envia a la sala.
//   3. B recibe los N via /sync de matrixB.
//   4. subA debe quedar en EXACTAMENTE N: si el eco propio de matrixA llegase
//      a reinyectarse (dedup por unsigned.transaction_id roto) seria 2N.
//
// Uso:
//   (terminal 1) zig build run -- b <usuario> <password> [room] [N]
//   (terminal 2) zig build run -- a <usuario> <password> [room] [N]
//
// Cada rol espera a que SU sync inicial (baseline) termine antes de
// suscribir/publicar: los eventos anteriores al baseline se descartan por
// diseno (solo se procesa lo que llega en vivo).
//
//   room: '#alias:servidor' o '!roomid:servidor' (default #lasala:matrix.org)
//
// La password se pasa por argumento: nunca queda en el repo.
// ============================================================================
const std = @import("std");
const k6bus = @import("k6bus");

const ApiFile = @import("runtime/Estacion_api.zig");
const Estacion = ApiFile.Estacion;

const PubSub = @import("runtime/Estacion_safe_pubsub.zig");
const Estacion_Publisher = PubSub.Estacion_Publisher;
const Estacion_Subscriber = PubSub.Estacion_Subscriber;

const DOMAIN_ID: u32 = 77;
const CHANNEL = "estacion_channel";

var received = std.atomic.Value(usize).init(0);

const Role = enum { a, b };

pub fn main() !void {
    realMain() catch |e| {
        std.debug.print("[demo3_matrix] FATAL: {s}\n", .{@errorName(e)});
        if (@errorReturnTrace()) |t| std.debug.dumpStackTrace(t.*);
        std.process.exit(1);
    };
}

fn realMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("[demo3_matrix] GPA detected leaks\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("uso: k6bus_demo3_matrix <a|b> <usuario> <password> [room] [N]\n", .{});
        std.process.exit(2);
    }
    const role: Role = if (std.ascii.eqlIgnoreCase(args[1], "a")) .a else if (std.ascii.eqlIgnoreCase(args[1], "b")) .b else {
        std.debug.print("rol invalido: '{s}' (usa 'a' o 'b')\n", .{args[1]});
        std.process.exit(2);
    };
    const user = args[2];
    const password = args[3];
    const room: []const u8 = if (args.len > 4 and args[4].len > 0) args[4] else "#lasala:matrix.org";
    const count: usize = if (args.len > 5) std.fmt.parseInt(usize, args[5], 10) catch 3 else 3;

    std.debug.print("== demo3_matrix rol={s}: transporte Matrix E2E ==\n", .{@tagName(role)});
    std.debug.print("  usuario: {s}  sala: {s}  N={d}\n", .{ user, room, count });

    // ------------------------------------------------------------------
    // Dominio (config: k6bus.App.pb.cfg del cwd, sin transporte default)
    // ------------------------------------------------------------------
    var dom = try k6bus.Domain.createEx(allocator, DOMAIN_ID, null, null);
    defer dom.close();

    // ------------------------------------------------------------------
    // Transporte Matrix (programatico: credenciales por argumento)
    // ------------------------------------------------------------------
    const mcfg = k6bus.Config.MatrixTransportConfig{
        .server = "https://matrix.org",
        .user = user,
        .password = password,
        .room = room,
        .proxy = null,
    };

    const transport_name: []const u8 = switch (role) {
        .a => "matrixA",
        .b => "matrixB",
    };

    const mt = try k6bus.MatrixTransport.create(dom, transport_name, mcfg);
    try dom.registerTransport(mt.transport());
    try mt.start();

    std.debug.print("  transporte {s} arrancado; esperando login+sync inicial...\n", .{transport_name});

    // El sync inicial (baseline) tarda ~10 s: se espera de forma determinista
    // (deadline 60 s). Publicar ANTES del baseline del receptor haria que sus
    // eventos se descartasen (semantica "solo lo vivo").
    const t_sync = std.time.milliTimestamp();
    while (!mt.isInitialSyncDone()) {
        if (std.time.milliTimestamp() - t_sync > 60_000) {
            std.debug.print("[FAIL] timeout esperando el sync inicial\n", .{});
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }
    std.debug.print("  sync inicial listo en {d} ms\n", .{std.time.milliTimestamp() - t_sync});

    // ------------------------------------------------------------------
    // Subscriber (ambos roles) y Publisher (solo rol a)
    // ------------------------------------------------------------------
    const sub = try Estacion_Subscriber.create(dom, CHANNEL, callback);
    defer dom.closeSubscriber(sub.subscriber());

    var publ: ?Estacion_Publisher = null;
    if (role == .a) {
        publ = try Estacion_Publisher.create(dom);
    }

    std.debug.print("  subscriber listo (canal '{s}')\n", .{CHANNEL});

    switch (role) {
        .a => try roleA(allocator, &publ.?, count),
        .b => try roleB(count),
    }
}

fn roleA(allocator: std.mem.Allocator, publ: *Estacion_Publisher, count: usize) !void {
    var est = try Estacion.initDefault(allocator);
    defer est.deinit(allocator);
    try est.setName(allocator, "Estacion A");
    try est.setUbicacion(allocator, "Origen Matrix A");

    var i: usize = 0;
    while (i < count) : (i += 1) {
        est.setTemperatura(@as(f32, @floatFromInt(i)) + 20.0);
        _ = try publ.publish(CHANNEL, &est);
    }
    std.debug.print("  A publico {d} mensajes; esperando entrega local ({d})...\n", .{ count, count });

    // Entrega local inmediata al subscriber del propio dominio.
    const t0 = std.time.milliTimestamp();
    while (received.load(.monotonic) < count) {
        if (std.time.milliTimestamp() - t0 > 30_000) {
            std.debug.print("  [FAIL] timeout entrega local (recibidos {d} de {d})\n", .{ received.load(.monotonic), count });
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }

    // Ventana extra: si el eco propio llegase a reinyectarse via matrixA,
    // received subiria por encima de count (dedup roto).
    std.Thread.sleep(8 * std.time.ns_per_s);
    const total = received.load(.monotonic);
    std.debug.print("== Resultado rol a ==\n", .{});
    std.debug.print("  subA = {d}  esperado = {d}\n", .{ total, count });
    if (total == count) {
        std.debug.print("VEREDICTO A: OK - entrega local sin duplicados (el eco propio de matrixA se descarto)\n", .{});
    } else {
        std.debug.print("VEREDICTO A: FAIL - subA={d} esperado={d} (dedup roto o perdidas)\n", .{ total, count });
        std.process.exit(4);
    }
}

fn roleB(count: usize) !void {
    std.debug.print("  B esperando {d} mensajes de A via Matrix (deadline 90 s)...\n", .{count});

    const t0 = std.time.milliTimestamp();
    while (received.load(.monotonic) < count) {
        if (std.time.milliTimestamp() - t0 > 90_000) {
            std.debug.print("  [FAIL] timeout esperando mensajes via Matrix (recibidos {d} de {d})\n", .{ received.load(.monotonic), count });
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }

    std.Thread.sleep(2 * std.time.ns_per_s);
    const total = received.load(.monotonic);
    std.debug.print("== Resultado rol b ==\n", .{});
    std.debug.print("  subB = {d}  esperado = {d}\n", .{ total, count });
    if (total == count) {
        std.debug.print("VEREDICTO B: OK - {d} mensajes recibidos por Matrix desde el device del mismo usuario\n", .{count});
    } else {
        std.debug.print("VEREDICTO B: FAIL - subB={d} esperado={d}\n", .{ total, count });
        std.process.exit(4);
    }
}

fn callback(
    _: std.mem.Allocator,
    channel_name: []const u8,
    estacion: *const Estacion,
) void {
    _ = channel_name;
    _ = estacion;
    _ = received.fetchAdd(1, .monotonic) + 1;
}
