// ============================================================================
// k6b-keymgr - K6Bus key manager CLI
// ============================================================================
//
// Two ways of using it, over the same logic (keymgr.zig):
//
//   1) Subcommands through FLAGS (scripts/CI):
//
//      k6b-keymgr [--registry RUTA] [--reg-desc TEXTO] <comando> [opciones]
//
//        list                                  table of keys in the registry
//        create [--days N] [--mode gcm|chacha] [--desc TEXTO]
//        show <key_id>                         details (includes the key)
//        delete <key_id>
//        help
//
//   2) INTERACTIVE keyboard mode (no command, or with -i/--interactive):
//
//      k6b-keymgr -i            ->  [l]istar [c]rear [m]ostrar [b]orrar [q]salir
//
// Default registry: sec/k6bus.lab.zon.keyreg (ZON format required).
// Registries are NOT versioned: sec/ is in .gitignore.
// ============================================================================
const std = @import("std");

const keymgr = @import("keymgr.zig");

const CliArgs = struct {
    registry: []const u8 = keymgr.DEFAULT_PATH,
    reg_desc: []const u8 = "k6bus",
    command: ?[]const u8 = null,
    key_id: ?u32 = null,
    days: u32 = keymgr.DEFAULT_DAYS,
    mode: keymgr.Mode = .gcm,
    desc: []const u8 = "",
    interactive: bool = false,
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
    parseArgs(allocator, argv, &cli) catch |err| {
        std.debug.print("k6b-keymgr: error de uso ({s})\n", .{@errorName(err)});
        usage();
        std.process.exit(2);
    };

    run(allocator, &cli) catch |err| {
        std.debug.print("k6b-keymgr: error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn parseArgs(allocator: std.mem.Allocator, argv: [][:0]u8, cli: *CliArgs) !void {
    _ = allocator;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--registry") or std.mem.eql(u8, a, "-r")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            cli.registry = argv[i];
        } else if (std.mem.eql(u8, a, "--reg-desc")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            cli.reg_desc = argv[i];
        } else if (std.mem.eql(u8, a, "--interactive") or std.mem.eql(u8, a, "-i")) {
            cli.interactive = true;
        } else if (std.mem.eql(u8, a, "--days") or std.mem.eql(u8, a, "-d")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            cli.days = std.fmt.parseInt(u32, argv[i], 10) catch return error.InvalidDays;
        } else if (std.mem.eql(u8, a, "--mode")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            cli.mode = keymgr.Mode.fromName(argv[i]) orelse return error.InvalidMode;
        } else if (std.mem.eql(u8, a, "--desc")) {
            i += 1;
            if (i >= argv.len) return error.MissingValue;
            cli.desc = argv[i];
        } else if (std.mem.startsWith(u8, a, "--")) {
            return error.UnknownOption;
        } else if (cli.command == null) {
            cli.command = a;
        } else if (cli.key_id == null) {
            cli.key_id = std.fmt.parseInt(u32, a, 10) catch return error.InvalidId;
        } else {
            return error.TooManyArguments;
        }
    }
}

fn run(allocator: std.mem.Allocator, cli: *CliArgs) !void {
    const command = cli.command orelse "";

    if (cli.interactive or command.len == 0) {
        try interactiveMenu(allocator, cli);
        return;
    }

    var reg = try keymgr.Registry.open(allocator, cli.registry, cli.reg_desc);
    defer reg.deinit();

    if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "ls")) {
        try list(allocator, &reg);
    } else if (std.mem.eql(u8, command, "create")) {
        const desc: ?[]const u8 = if (cli.desc.len > 0) cli.desc else null;
        const id = try reg.create(cli.days, cli.mode, desc);
        std.debug.print("clave creada: id={d} modo={s} dias={d}\n", .{ id, @tagName(cli.mode.toCrypto()), cli.days });
    } else if (std.mem.eql(u8, command, "show")) {
        const id = cli.key_id orelse return error.MissingId;
        try show(&reg, id);
    } else if (std.mem.eql(u8, command, "delete") or std.mem.eql(u8, command, "rm")) {
        const id = cli.key_id orelse return error.MissingId;
        try reg.remove(id);
        std.debug.print("clave borrada: id={d}\n", .{id});
    } else if (std.mem.eql(u8, command, "help")) {
        usage();
    } else {
        std.debug.print("k6b-keymgr: comando desconocido '{s}'\n", .{command});
        usage();
        std.process.exit(2);
    }
}

fn list(allocator: std.mem.Allocator, reg: *keymgr.Registry) !void {
    const summaries = try reg.list();
    defer allocator.free(summaries);

    std.debug.print("registro: {s}  (v{d}, {d} clave(s))\n", .{ reg.path, reg.version, summaries.len });
    if (summaries.len == 0) {
        std.debug.print("  (vacio: crea una con 'create')\n", .{});
        return;
    }

    std.debug.print("  {s:>10}  {s:<22}  {s:<20}  {s:<20}  {s:>5}  {s:<9}  {s}\n", .{
        "ID", "MODO", "CREADA", "CADUCA", "DIAS", "ESTADO", "DESCRIPCION",
    });
    for (summaries) |r| {
        const state: []const u8 = if (r.expired) "CADUCADA" else if (!r.active) "FUTURA" else if (r.days_left <= keymgr.WARN_DAYS) "AVISO" else "OK";
        const sign: []const u8 = if (r.days_left < 0) "-" else "";
        const magnitude: u64 = @intCast(if (r.days_left < 0) -r.days_left else r.days_left);
        std.debug.print("  {d:>10}  {s:<22}  {s:<20}  {s:<20}  {s}{d:>4}  {s:<9}  {s}\n", .{
            r.key_id,
            @tagName(r.mode),
            r.created_on,
            r.expires_on,
            sign,
            magnitude,
            state,
            r.description,
        });
    }
}

fn show(reg: *keymgr.Registry, key_id: u32) !void {
    const rec = reg.find(key_id) orelse return keymgr.Error.KeyNotFound;
    const now = std.time.timestamp();

    std.debug.print("key_id      : {d}\n", .{rec.key_id});
    std.debug.print("modo        : {s}\n", .{@tagName(rec.mode)});
    std.debug.print("version     : {d}\n", .{rec.version orelse 0});
    std.debug.print("descripcion : {s}\n", .{rec.description orelse ""});
    std.debug.print("created_on  : {s}\n", .{rec.created_on});
    std.debug.print("expires_on  : {s}  ({d} dia(s), {s})\n", .{
        rec.expires_on,
        keymgr.daysUntil(rec.expires_on, now),
        if (keymgr.expired(rec.expires_on, now)) "CADUCADA" else "valida",
    });
    std.debug.print("key (Base64): {s}\n", .{rec.key});
}

fn usage() void {
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
    , .{ keymgr.DEFAULT_PATH, keymgr.DEFAULT_DAYS });
}

// ----------------------------------------------------------------------------
// Interactive menu
// ----------------------------------------------------------------------------

fn interactiveMenu(allocator: std.mem.Allocator, cli: *CliArgs) !void {
    var reg = try keymgr.Registry.open(allocator, cli.registry, cli.reg_desc);
    defer reg.deinit();

    std.debug.print("k6b-keymgr (interactivo) - registro: {s}\n", .{reg.path});

    var line: [256]u8 = undefined;
    while (true) {
        std.debug.print("\n[l]istar [c]rear [m]ostrar [b]orrar [s]alir > ", .{});
        const input = (try readLine(&line)) orelse return;
        const op = if (input.len > 0) input[0] else ' ';

        switch (op) {
            'l', 'L' => try list(allocator, &reg),
            'c', 'C' => {
                std.debug.print("dias [enter={d}] > ", .{keymgr.DEFAULT_DAYS});
                const days_text = (try readLine(&line)) orelse return;
                const days: u32 = if (days_text.len == 0) keymgr.DEFAULT_DAYS else (std.fmt.parseInt(u32, days_text, 10) catch keymgr.DEFAULT_DAYS);

                std.debug.print("modo [gcm|chacha, enter=gcm] > ", .{});
                const mode_text = (try readLine(&line)) orelse return;
                const mode: keymgr.Mode = if (mode_text.len == 0) .gcm else (keymgr.Mode.fromName(mode_text) orelse .gcm);

                std.debug.print("descripcion > ", .{});
                const desc_text = (try readLine(&line)) orelse return;

                const id = try reg.create(days, mode, if (desc_text.len > 0) desc_text else null);
                std.debug.print("clave creada: id={d} modo={s} caduca en {d} dia(s)\n", .{ id, @tagName(mode.toCrypto()), days });
            },
            'm', 'M' => {
                std.debug.print("key_id > ", .{});
                const t = (try readLine(&line)) orelse return;
                const id = std.fmt.parseInt(u32, t, 10) catch {
                    std.debug.print("id invalido\n", .{});
                    continue;
                };
                show(&reg, id) catch |err| std.debug.print("error: {s}\n", .{@errorName(err)});
            },
            'b', 'B' => {
                std.debug.print("key_id > ", .{});
                const t = (try readLine(&line)) orelse return;
                const id = std.fmt.parseInt(u32, t, 10) catch {
                    std.debug.print("id invalido\n", .{});
                    continue;
                };
                reg.remove(id) catch |err| {
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

/// Reads one line from stdin (without the '\n'). null at EOF.
fn readLine(buf: []u8) !?[]const u8 {
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
