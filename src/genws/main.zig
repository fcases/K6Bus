// ============================================================================
// k6b-genws - Creates a COMPLETE ProtobuZig workspace for K6Bus
// ============================================================================
//
//   k6b-genws --dir my_dir xxx.proto
//
// What it does, in this order:
//   1) calls protobuzig with --ws <dir>         -> Zig-only ws (protobuzig)
//   2) copies the core pub/sub support          -> src/runtime/
//      (generic_pubsub.zig + safe_pubsub.zig; encdec.zig comes from protobuzig)
//   3) calls k6b-genpubsub on the proto         -> X_pubsub.zig + X_safe_pubsub.zig
//   4) REPLACES the ws build.zig with its own: `k6bus` module + steps
//      check/run/test/gen (plantilo.zig)
//
// The resulting ws compiles and runs with:  cd my_dir && zig build run
//
// Paths: by default inferred from the executable itself (zig-out/bin/k6b-genws
// -> K6Bus root). They can be overridden:
//   --k6bus <dir>      K6Bus root (k6bus module + support to copy)
//   --protobuzig <f>   proto generator binary
//   --genpubsub <f>    k6b-genpubsub binary
//   --proto_dir <dir>  .proto directory (by default: the argument one or ".")
//
// The ws is NOT versioned in K6Bus: it is user working material.
// ============================================================================
const std = @import("std");

const plantilo = @import("plantilo.zig");

const Uzo = struct {
    dir: ?[]const u8 = null,
    proto_dir: []const u8 = ".",
    proto: ?[]const u8 = null,
    k6bus: ?[]const u8 = null,
    protobuzig: ?[]const u8 = null,
    genpubsub: ?[]const u8 = null,
    verboso: bool = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer {
        const r = gpa.deinit();
        if (r == .leak) std.debug.print("k6b-genws: GPA detected leaks\n", .{});
    }
    const a = gpa.allocator();

    const argv = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, argv);

    var uzo = Uzo{};
    parsear(argv, &uzo) catch |err| {
        std.debug.print("k6b-genws: error de uso ({s})\n", .{@errorName(err)});
        ayuda();
        std.process.exit(2);
    };

    if (uzo.dir == null or uzo.proto == null) {
        ayuda();
        std.process.exit(2);
    }

    // K6Bus root: by default, two levels above the executable
    // (zig-out/bin/k6b-genws -> <K6BUS>). If the exe is somewhere else,
    // --k6bus is mandatory.
    const k6bus_dir = if (uzo.k6bus) |k|
        try a.dupe(u8, k)
    else blk: {
        const exe_dir = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(exe_dir);
        const bin = std.fs.path.dirname(exe_dir) orelse return error.K6BusNoLocalizado;
        const raiz = std.fs.path.dirname(bin) orelse return error.K6BusNoLocalizado;
        break :blk try a.dupe(u8, raiz);
    };
    defer a.free(k6bus_dir);

    const exe_ext: []const u8 = if (@import("builtin").os.tag == .windows) ".exe" else "";

    const protobuzig_nomo = try std.fmt.allocPrint(a, "protobuzig{s}", .{exe_ext});
    defer a.free(protobuzig_nomo);
    const genpubsub_nomo = try std.fmt.allocPrint(a, "k6b-genpubsub{s}", .{exe_ext});
    defer a.free(genpubsub_nomo);

    const protobuzig_path = if (uzo.protobuzig) |p|
        try a.dupe(u8, p)
    else
        try std.fs.path.join(a, &.{ k6bus_dir, "tools", protobuzig_nomo });
    defer a.free(protobuzig_path);

    const genpubsub_path = if (uzo.genpubsub) |p|
        try a.dupe(u8, p)
    else
        try std.fs.path.join(a, &.{ k6bus_dir, "zig-out", "bin", genpubsub_nomo });
    defer a.free(genpubsub_path);

    // Absolute ws path (so it does not depend on the cwd) and its base name.
    const ws_abs = try std.fs.cwd().realpathAlloc(a, ".");
    defer a.free(ws_abs);
    const ws_dir = try std.fs.path.resolve(a, &.{ ws_abs, uzo.dir.? });
    defer a.free(ws_dir);
    const ws_nomo = std.fs.path.basename(ws_dir);

    std.debug.print("k6b-genws: ws={s}\n  k6bus={s}\n  protobuzig={s}\n  genpubsub={s}\n", .{
        ws_dir, k6bus_dir, protobuzig_path, genpubsub_path,
    });

    // ---------------------------------------------------------------
    // 1) protobuzig --ws <dir> --proto_dir <dir> <proto>
    // ---------------------------------------------------------------
    const proto_dir_abs = try std.fs.path.resolve(a, &.{ ws_abs, uzo.proto_dir });
    defer a.free(proto_dir_abs);

    try paso("1/4 protobuzig --ws", &.{
        protobuzig_path, "--ws", ws_dir, "--proto_dir", proto_dir_abs, uzo.proto.?,
    });

    // ---------------------------------------------------------------
    // 2) pub/sub support into the ws src/runtime
    // ---------------------------------------------------------------
    const runtime_dir = try std.fs.path.join(a, &.{ ws_dir, "src", "runtime" });
    defer a.free(runtime_dir);

    try copiar(a, k6bus_dir, "src/core/generic_pubsub.zig", runtime_dir, "generic_pubsub.zig");
    try copiar(a, k6bus_dir, "src/core/safe_pubsub.zig", runtime_dir, "safe_pubsub.zig");
    std.debug.print("2/4 copiado soporte de pub/sub -> src/runtime/\n", .{});

    // ---------------------------------------------------------------
    // 3) k6b-genpubsub (reads the proto from <ws>/protos)
    // ---------------------------------------------------------------
    const ws_protos = try std.fs.path.join(a, &.{ ws_dir, "protos" });
    defer a.free(ws_protos);

    try paso("3/4 k6b-genpubsub", &.{
        genpubsub_path,
        "--proto_dir",
        ws_protos,
        "--output_dir",
        runtime_dir,
        uzo.proto.?,
    });

    // ---------------------------------------------------------------
    // 4) overwrite build.zig with the "K6Bus flavor"
    // ---------------------------------------------------------------
    const contenido = try plantilo.buildZig(a, ws_nomo, k6bus_dir, protobuzig_path, genpubsub_path, uzo.proto.?);
    defer a.free(contenido);

    const build_path = try std.fs.path.join(a, &.{ ws_dir, "build.zig" });
    defer a.free(build_path);

    {
        var f = try std.fs.cwd().createFile(build_path, .{ .truncate = true });
        defer f.close();
        try f.writeAll(contenido);
    }
    std.debug.print("4/4 build.zig reescrito (modulo k6bus + pasos check/run/test/gen)\n", .{});

    std.debug.print("\nworkspace listo:\n  cd {s} && zig build run\n", .{ws_dir});
}

fn parsear(argv: [][:0]u8, uzo: *Uzo) !void {
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const x = argv[i];
        if (std.mem.eql(u8, x, "--dir") or std.mem.eql(u8, x, "-d")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            uzo.dir = argv[i];
        } else if (std.mem.eql(u8, x, "--proto_dir")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            uzo.proto_dir = argv[i];
        } else if (std.mem.eql(u8, x, "--k6bus")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            uzo.k6bus = argv[i];
        } else if (std.mem.eql(u8, x, "--protobuzig")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            uzo.protobuzig = argv[i];
        } else if (std.mem.eql(u8, x, "--genpubsub")) {
            i += 1;
            if (i >= argv.len) return error.FaltaValor;
            uzo.genpubsub = argv[i];
        } else if (std.mem.eql(u8, x, "--quiet") or std.mem.eql(u8, x, "-q")) {
            uzo.verboso = false;
        } else if (std.mem.eql(u8, x, "--help") or std.mem.eql(u8, x, "-h")) {
            ayuda();
            std.process.exit(0);
        } else if (std.mem.startsWith(u8, x, "-")) {
            return error.OpcionDesconocida;
        } else if (uzo.proto == null) {
            // accepts "X.proto" or "path/to/X.proto" (then sets proto_dir)
            if (std.fs.path.dirname(x)) |d| {
                uzo.proto_dir = d;
                uzo.proto = std.fs.path.basename(x);
            } else {
                uzo.proto = x;
            }
        } else {
            return error.ArgumentoDeMas;
        }
    }
}

fn ayuda() void {
    std.debug.print(
        \\k6b-genws - crea un workspace de ProtobuZig completo para K6Bus
        \\
        \\uso: k6b-genws --dir <dir> [--proto_dir <dir>] <proto.proto>
        \\
        \\  1) protobuzig --ws <dir> --proto_dir <dir> <proto>
        \\  2) copia generic_pubsub.zig + safe_pubsub.zig a <dir>/src/runtime
        \\  3) k6b-genpubsub -> X_pubsub.zig + X_safe_pubsub.zig
        \\  4) reescribe <dir>/build.zig (modulo k6bus + pasos check/run/test/gen)
        \\
        \\opciones: --k6bus <dir>  --protobuzig <f>  --genpubsub <f>  --quiet
        \\despues:  cd <dir> && zig build run
        \\
    , .{});
}

/// Runs a command; on failure it prints its output and aborts.
fn paso(etiqueta: []const u8, argv: []const []const u8) !void {
    const a = std.heap.page_allocator;

    const res = std.process.Child.run(.{
        .allocator = a,
        .argv = argv,
        .max_output_bytes = 8 * 1024 * 1024,
    }) catch |err| {
        std.debug.print("{s}: no se pudo ejecutar '{s}': {s}\n", .{ etiqueta, argv[0], @errorName(err) });
        return err;
    };
    defer a.free(res.stdout);
    defer a.free(res.stderr);

    switch (res.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("{s}: FALLO (exit {d})\n{s}{s}\n", .{ etiqueta, code, res.stdout, res.stderr });
            return error.PasoFallido;
        },
        else => {
            std.debug.print("{s}: terminado de forma anormal\n{s}{s}\n", .{ etiqueta, res.stdout, res.stderr });
            return error.PasoFallido;
        },
    }

    std.debug.print("{s}: OK\n", .{etiqueta});
}

/// Copies <k6bus>/<rel> to <dst_dir>/<dst_nomo>.
fn copiar(
    a: std.mem.Allocator,
    k6bus_dir: []const u8,
    rel: []const u8,
    dst_dir: []const u8,
    dst_nomo: []const u8,
) !void {
    const src = try std.fs.path.join(a, &.{ k6bus_dir, rel });
    defer a.free(src);

    var dir = try std.fs.cwd().openDir(dst_dir, .{});
    defer dir.close();

    try std.fs.cwd().copyFile(src, dir, dst_nomo, .{});
    std.debug.print("     copiado {s} -> {s}\n", .{ rel, dst_nomo });
}
