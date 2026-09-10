// ============================================================================
// k6b-keymgr - CLI del gestor de claves de K6Bus
// ============================================================================
//
// Dos formas de uso, sobre la misma logica (keymgr.zig):
//
//   1) Subcomandos por FLAGS (scripts/CI):
//
//      k6b-keymgr [--registry RUTA] [--reg-desc TEXTO] <comando> [opciones]
//
//        list                                  tabla de claves del registro
//        create [--days N] [--mode gcm|chacha] [--desc TEXTO]
//        show <key_id>                         detalle (incluye la clave)
//        delete <key_id>
//        help
//
//   2) Modo INTERACTIVO por teclado (sin comando, o con -i/--interactive):
//
//      k6b-keymgr -i            ->  [l]istar [c]rear [m]ostrar [b]orrar [q]salir
//
// Registro por defecto: sec/k6bus.lab.zon.keyreg (formato ZON obligatorio).
// Los registros NO se versionan: sec/ esta en .gitignore.
// ============================================================================
const std = @import("std");

const keymgr = @import("keymgr.zig");

const CliArgs = struct {
    registry: []const u8 = keymgr.RUTA_DEFECTO,
    reg_desc: []const u8 = "k6bus",
    comando: ?[]const u8 = null,
    key_id: ?u32 = null,
    dias: u32 = keymgr.DIAS_DEFECTO,
    modo: keymgr.Modo = .gcm,
    desc: []const u8 = "",
    interactivo: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer {
        const r = gpa.deinit();
        if (r == .leak) std.debug.print("k6b-keymgr: GPA detected leaks\n", .{});
    }
    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var cli = CliArgs{};
    parsear(allocator, argv, &cli) catch |err| {
        std.debug.print("k6b-keymgr: error de uso ({s})\n", .{@errorName(err)});
        ayuda();
        std.process.exit(2);
    };

    ejecutar(allocator, &cli) catch |err| {
        std.debug.print("k6b-keymgr: error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn parsear(allocator: std.mem.Allocator, argv: [][:0]u8, cli: *CliArgs) !void {
    _ = allocator;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--registry") or std.mem.eql(u8, a, "-r")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            cli.registry = argv[i];
        } else if (std.mem.eql(u8, a, "--reg-desc")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            cli.reg_desc = argv[i];
        } else if (std.mem.eql(u8, a, "--interactive") or std.mem.eql(u8, a, "-i")) {
            cli.interactivo = true;
        } else if (std.mem.eql(u8, a, "--days") or std.mem.eql(u8, a, "-d")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            cli.dias = std.fmt.parseInt(u32, argv[i], 10) catch return error.DiasInvalido;
        } else if (std.mem.eql(u8, a, "--mode")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            cli.modo = keymgr.Modo.eliji(argv[i]) orelse return error.ModoInvalido;
        } else if (std.mem.eql(u8, a, "--desc")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            cli.desc = argv[i];
        } else if (std.mem.startsWith(u8, a, "--")) {
            return error.OpcionDesconocida;
        } else if (cli.comando == null) {
            cli.comando = a;
        } else if (cli.key_id == null) {
            cli.key_id = std.fmt.parseInt(u32, a, 10) catch return error.IdInvalido;
        } else {
            return error.ArgumentoDeMas;
        }
    }
}

fn ejecutar(allocator: std.mem.Allocator, cli: *CliArgs) !void {
    const comando = cli.comando orelse "";

    if (cli.interactivo or comando.len == 0) {
        try menu(allocator, cli);
        return;
    }

    var reg = try keymgr.Registro.abrir(allocator, cli.registry, cli.reg_desc);
    defer reg.deinit();

    if (std.mem.eql(u8, comando, "list") or std.mem.eql(u8, comando, "ls")) {
        try listar(allocator, &reg);
    } else if (std.mem.eql(u8, comando, "create")) {
        const desc: ?[]const u8 = if (cli.desc.len > 0) cli.desc else null;
        const id = try reg.crear(cli.dias, cli.modo, desc);
        std.debug.print("clave creada: id={d} modo={s} dias={d}\n", .{ id, @tagName(cli.modo.aCrypto()), cli.dias });
    } else if (std.mem.eql(u8, comando, "show")) {
        const id = cli.key_id orelse return error.FaltaId;
        try mostrar(&reg, id);
    } else if (std.mem.eql(u8, comando, "delete") or std.mem.eql(u8, comando, "rm")) {
        const id = cli.key_id orelse return error.FaltaId;
        try reg.borrar(id);
        std.debug.print("clave borrada: id={d}\n", .{id});
    } else if (std.mem.eql(u8, comando, "help")) {
        ayuda();
    } else {
        std.debug.print("k6b-keymgr: comando desconocido '{s}'\n", .{comando});
        ayuda();
        std.process.exit(2);
    }
}

fn listar(allocator: std.mem.Allocator, reg: *keymgr.Registro) !void {
    const lista = try reg.listar();
    defer allocator.free(lista);

    std.debug.print("registro: {s}  (v{d}, {d} clave(s))\n", .{ reg.ruta, reg.version, lista.len });
    if (lista.len == 0) {
        std.debug.print("  (vacio: crea una con 'create')\n", .{});
        return;
    }

    std.debug.print("  {s:>10}  {s:<22}  {s:<20}  {s:<20}  {s:>5}  {s:<9}  {s}\n", .{
        "ID", "MODO", "CREADA", "CADUCA", "DIAS", "ESTADO", "DESCRIPCION",
    });
    for (lista) |r| {
        const estado: []const u8 = if (r.caducada) "CADUCADA" else if (!r.activa) "FUTURA" else if (r.dias_restantes <= keymgr.AVISO_DIAS) "AVISO" else "OK";
        const signo: []const u8 = if (r.dias_restantes < 0) "-" else "";
        const mag: u64 = @intCast(if (r.dias_restantes < 0) -r.dias_restantes else r.dias_restantes);
        std.debug.print("  {d:>10}  {s:<22}  {s:<20}  {s:<20}  {s}{d:>4}  {s:<9}  {s}\n", .{
            r.key_id,
            @tagName(r.modo),
            r.created_on,
            r.expires_on,
            signo,
            mag,
            estado,
            r.descripcion,
        });
    }
}

fn mostrar(reg: *keymgr.Registro, key_id: u32) !void {
    const rec = reg.buscar(key_id) orelse return keymgr.Error.ClaveNoEncontrada;
    const ahora = std.time.timestamp();

    std.debug.print("key_id      : {d}\n", .{rec.key_id});
    std.debug.print("modo        : {s}\n", .{@tagName(rec.mode)});
    std.debug.print("version     : {d}\n", .{rec.version orelse 0});
    std.debug.print("descripcion : {s}\n", .{rec.description orelse ""});
    std.debug.print("created_on  : {s}\n", .{rec.created_on});
    std.debug.print("expires_on  : {s}  ({d} dia(s), {s})\n", .{
        rec.expires_on,
        keymgr.diasHasta(rec.expires_on, ahora),
        if (keymgr.caducada(rec.expires_on, ahora)) "CADUCADA" else "valida",
    });
    std.debug.print("key (Base64): {s}\n", .{rec.key});
}

fn ayuda() void {
    std.debug.print(
        \\k6b-keymgr - gestor de claves de K6Bus
        \\
        \\uso: k6b-keymgr [--registry RUTA] [--reg-desc TEXTO] <comando> [opciones]
        \\     k6b-keymgr -i            (menu interactivo por teclado)
        \\
        \\comandos:
        \\  list                                   claves del registro
        \\  create [--days N] [--mode gcm|chacha] [--desc TEXTO]
        \\  show <key_id>                          detalle (incluye la clave)
        \\  delete <key_id>
        \\  help
        \\
        \\registro por defecto: {s}  (formato ZON)
        \\dias por defecto: {d}   modos: gcm (AES-256-GCM), chacha (ChaCha20-Poly1305)
        \\
    , .{ keymgr.RUTA_DEFECTO, keymgr.DIAS_DEFECTO });
}

// ----------------------------------------------------------------------------
// Menu interactivo
// ----------------------------------------------------------------------------

fn menu(allocator: std.mem.Allocator, cli: *CliArgs) !void {
    var reg = try keymgr.Registro.abrir(allocator, cli.registry, cli.reg_desc);
    defer reg.deinit();

    std.debug.print("k6b-keymgr (interactivo) - registro: {s}\n", .{reg.ruta});

    var linea: [256]u8 = undefined;
    while (true) {
        std.debug.print("\n[l]istar [c]rear [m]ostrar [b]orrar [s]alir > ", .{});
        const entrada = (try leerLinea(&linea)) orelse return;
        const op = if (entrada.len > 0) entrada[0] else ' ';

        switch (op) {
            'l', 'L' => try listar(allocator, &reg),
            'c', 'C' => {
                std.debug.print("dias [enter={d}] > ", .{keymgr.DIAS_DEFECTO});
                const d_txt = (try leerLinea(&linea)) orelse return;
                const dias: u32 = if (d_txt.len == 0) keymgr.DIAS_DEFECTO else (std.fmt.parseInt(u32, d_txt, 10) catch keymgr.DIAS_DEFECTO);

                std.debug.print("modo [gcm|chacha, enter=gcm] > ", .{});
                const m_txt = (try leerLinea(&linea)) orelse return;
                const modo: keymgr.Modo = if (m_txt.len == 0) .gcm else (keymgr.Modo.eliji(m_txt) orelse .gcm);

                std.debug.print("descripcion > ", .{});
                const desc_txt = (try leerLinea(&linea)) orelse return;

                const id = try reg.crear(dias, modo, if (desc_txt.len > 0) desc_txt else null);
                std.debug.print("clave creada: id={d} modo={s} caduca en {d} dia(s)\n", .{ id, @tagName(modo.aCrypto()), dias });
            },
            'm', 'M' => {
                std.debug.print("key_id > ", .{});
                const t = (try leerLinea(&linea)) orelse return;
                const id = std.fmt.parseInt(u32, t, 10) catch {
                    std.debug.print("id invalido\n", .{});
                    continue;
                };
                mostrar(&reg, id) catch |err| std.debug.print("error: {s}\n", .{@errorName(err)});
            },
            'b', 'B' => {
                std.debug.print("key_id > ", .{});
                const t = (try leerLinea(&linea)) orelse return;
                const id = std.fmt.parseInt(u32, t, 10) catch {
                    std.debug.print("id invalido\n", .{});
                    continue;
                };
                reg.borrar(id) catch |err| {
                    std.debug.print("error: {s}\n", .{@errorName(err)});
                    continue;
                };
                std.debug.print("clave borrada: id={d}\n", .{id});
            },
            's', 'S', 'q', 'Q' => return,
            else => std.debug.print("opcion no reconocida\n", .{}),
        }
    }
}

/// Lee una linea de stdin (sin el '\n'). null en EOF.
fn leerLinea(buf: []u8) !?[]const u8 {
    var len: usize = 0;
    while (len < buf.len) {
        var c: [1]u8 = undefined;
        const n = try std.posix.read(0, &c);
        if (n == 0) return if (len == 0) null else buf[0..len];
        if (c[0] == '\n') return std.mem.trim(u8, buf[0..len], " \t\r");
        if (c[0] == '\r') continue;
        buf[len] = c[0];
        len += 1;
    }
    return std.mem.trim(u8, buf[0..len], " \t");
}
