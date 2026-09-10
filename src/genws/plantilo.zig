// ============================================================================
// plantilo.zig - Plantilla del build.zig "sabor K6Bus" que k6b-genws machaca
// ============================================================================
//
// protobuzig --ws genera un build.zig solo-Zig (sin k6bus, sin pub/sub). Este
// tool lo SUSTITUYE por el suyo: mismo exe + pasos check/run/test, mas
//   - el modulo "k6bus" (lo necesitan los X_pubsub.zig generados),
//   - un paso `gen` que regenera con protobuzig + k6b-genpubsub y recopia el
//     soporte (encdec/generic/safe pubsub) desde el core de K6Bus,
//   - un paso `kbusdemo` opcional (si existe src/main_k6bus.zig).
//
// Los tokens %%X%% se sustituyen con std.mem.replaceOwned (sin fmt, para no
// tener que escapar las llaves del Zig generado).
// ============================================================================
const std = @import("std");

pub const PLANTILO_BUILD =
    \\const std = @import("std");
    \\
    \\// ---------------------------------------------------------------------------
    \\// build.zig generado por k6b-genws (K6Bus) sobre el workspace de protobuzig.
    \\//
    \\//   zig build            compila el demo (src/main.zig)
    \\//   zig build run        ejecuta el demo
    \\//   zig build test       tests del contrato (src/tests.zig)
    \\//   zig build check      compila sin ejecutar
    \\//   zig build gen        regenera runtime/ (protobuzig + k6b-genpubsub)
    \\//
    \\// El modulo `k6bus` (para los X_pubsub.zig) apunta al K6Bus que genero este
    \\// workspace: %%K6BUS%%. Se puede sobreescribir con -Dk6bus=<ruta>.
    \\// ---------------------------------------------------------------------------
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize: std.builtin.OptimizeMode = .Debug;
    \\
    \\    const k6bus_dir = b.option([]const u8, "k6bus", "Ruta al repo de K6Bus") orelse "%%K6BUS%%";
    \\
    \\    const k6bus_mod = b.createModule(.{
    \\        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ k6bus_dir, "src", "root.zig" }) },
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    // ------------------------------------------------------------
    \\    // Demo (src/main.zig)
    \\    // ------------------------------------------------------------
    \\    const demo_mod = b.createModule(.{
    \\        .root_source_file = b.path("src/main.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\    demo_mod.addImport("k6bus", k6bus_mod);
    \\
    \\    const demo = b.addExecutable(.{
    \\        .name = "%%WS%%",
    \\        .root_module = demo_mod,
    \\        .use_llvm = true,
    \\    });
    \\    b.installArtifact(demo);
    \\
    \\    const run_demo = b.addRunArtifact(demo);
    \\    if (b.args) |args| run_demo.addArgs(args);
    \\    const run_step = b.step("run", "Run the demo");
    \\    run_step.dependOn(&run_demo.step);
    \\
    \\    // ------------------------------------------------------------
    \\    // Tests (src/tests.zig): round-trip por mensaje externo
    \\    // ------------------------------------------------------------
    \\    const tests_mod = b.createModule(.{
    \\        .root_source_file = b.path("src/tests.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\    tests_mod.addImport("k6bus", k6bus_mod);
    \\
    \\    const tests = b.addTest(.{ .root_module = tests_mod });
    \\    const run_tests = b.addRunArtifact(tests);
    \\    const test_step = b.step("test", "Run the contract tests");
    \\    test_step.dependOn(&run_tests.step);
    \\
    \\    // ------------------------------------------------------------
    \\    // Check: compila demo + tests sin ejecutar
    \\    // ------------------------------------------------------------
    \\    const check_step = b.step("check", "Build demo and tests without running");
    \\    check_step.dependOn(&demo.step);
    \\    check_step.dependOn(&tests.step);
    \\
    \\    // ------------------------------------------------------------
    \\    // gen: regenera src/runtime/ y el soporte de pub/sub
    \\    // ------------------------------------------------------------
    \\    const protobuzig_path = b.option([]const u8, "protobuzig", "Ruta a protobuzig") orelse "%%PROTOBUZIG%%";
    \\    const genpubsub_path = b.option([]const u8, "genpubsub", "Ruta a k6b-genpubsub") orelse "%%GENPUBSUB%%";
    \\
    \\    const gen_step = b.step("gen", "Regenerate src/runtime (protobuzig + k6b-genpubsub)");
    \\
    \\    const mkdir_runtime = b.addSystemCommand(&.{ "mkdir", "-p", "src/runtime" });
    \\    gen_step.dependOn(&mkdir_runtime.step);
    \\
    \\    const copy_encdec = b.addSystemCommand(&.{
    \\        "cp",
    \\        b.pathJoin(&.{ k6bus_dir, "src", "generated", "encdec.zig" }),
    \\        "src/runtime/encdec.zig",
    \\    });
    \\    copy_encdec.step.dependOn(&mkdir_runtime.step);
    \\    gen_step.dependOn(&copy_encdec.step);
    \\
    \\    const copy_generic = b.addSystemCommand(&.{
    \\        "cp",
    \\        b.pathJoin(&.{ k6bus_dir, "src", "core", "generic_pubsub.zig" }),
    \\        "src/runtime/generic_pubsub.zig",
    \\    });
    \\    copy_generic.step.dependOn(&mkdir_runtime.step);
    \\    gen_step.dependOn(&copy_generic.step);
    \\
    \\    const copy_safe = b.addSystemCommand(&.{
    \\        "cp",
    \\        b.pathJoin(&.{ k6bus_dir, "src", "core", "safe_pubsub.zig" }),
    \\        "src/runtime/safe_pubsub.zig",
    \\    });
    \\    copy_safe.step.dependOn(&mkdir_runtime.step);
    \\    gen_step.dependOn(&copy_safe.step);
    \\
    \\    const gen_proto = b.addSystemCommand(&.{
    \\        protobuzig_path,
    \\        "--proto_dir",
    \\        "protos",
    \\        "--output_dir",
    \\        "src/runtime",
    \\        "%%PROTO%%",
    \\    });
    \\    gen_proto.step.dependOn(&mkdir_runtime.step);
    \\    gen_proto.step.dependOn(&copy_encdec.step);
    \\    gen_step.dependOn(&gen_proto.step);
    \\
    \\    const gen_pubsub = b.addSystemCommand(&.{
    \\        genpubsub_path,
    \\        "--proto_dir",
    \\        "protos",
    \\        "--output_dir",
    \\        "src/runtime",
    \\        "%%PROTO%%",
    \\    });
    \\    gen_pubsub.step.dependOn(&copy_generic.step);
    \\    gen_pubsub.step.dependOn(&copy_safe.step);
    \\    gen_pubsub.step.dependOn(&gen_proto.step);
    \\    gen_step.dependOn(&gen_pubsub.step);
    \\}
    \\
;

/// Sintetiza el contenido del build.zig con los tokens sustituidos.
pub fn buildZig(
    allocator: std.mem.Allocator,
    ws_nomo: []const u8,
    k6bus_dir: []const u8,
    protobuzig_path: []const u8,
    genpubsub_path: []const u8,
    proto_nomo: []const u8,
) ![]u8 {
    const pares = [_][2][]const u8{
        .{ "%%WS%%", ws_nomo },
        .{ "%%K6BUS%%", k6bus_dir },
        .{ "%%PROTOBUZIG%%", protobuzig_path },
        .{ "%%GENPUBSUB%%", genpubsub_path },
        .{ "%%PROTO%%", proto_nomo },
    };

    var out = try allocator.dupe(u8, PLANTILO_BUILD);
    for (pares) |p| {
        const nuevo = try std.mem.replaceOwned(u8, allocator, out, p[0], p[1]);
        allocator.free(out);
        out = nuevo;
    }
    return out;
}
