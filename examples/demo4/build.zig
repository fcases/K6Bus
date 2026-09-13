const std = @import("std");

// ---------------------------------------------------------------------------
// build.zig generado por k6b-genws (K6Bus) sobre el workspace de protobuzig.
//
//   zig build            compila el demo (src/main.zig)
//   zig build run        ejecuta el demo
//   zig build test       tests del contrato (src/tests.zig)
//   zig build check      compila sin ejecutar
//   zig build gen        regenera runtime/ (protobuzig + k6b-genpubsub)
//
// El modulo `k6bus` (para los X_pubsub.zig) apunta al K6Bus que genero este
// workspace: /home/chuco/MyProgs/ZIG/06_k6bus/K6Bus. Se puede sobreescribir con -Dk6bus=<ruta>.
// ---------------------------------------------------------------------------
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    const k6bus_dir = b.option([]const u8, "k6bus", "Ruta al repo de K6Bus") orelse "/home/chuco/MyProgs/ZIG/06_k6bus/K6Bus";

    const k6bus_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ k6bus_dir, "src", "root.zig" }) },
        .target = target,
        .optimize = optimize,
    });

    // ------------------------------------------------------------
    // Demo (src/main.zig)
    // ------------------------------------------------------------
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("k6bus", k6bus_mod);

    const demo = b.addExecutable(.{
        .name = "demo4",
        .root_module = demo_mod,
        .use_llvm = true,
    });
    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| run_demo.addArgs(args);
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_demo.step);

    // ------------------------------------------------------------
    // Tests (src/tests.zig): round-trip por mensaje externo
    // ------------------------------------------------------------
    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_mod.addImport("k6bus", k6bus_mod);

    const tests = b.addTest(.{ .root_module = tests_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the contract tests");
    test_step.dependOn(&run_tests.step);

    // ------------------------------------------------------------
    // Check: compila demo + tests sin ejecutar
    // ------------------------------------------------------------
    const check_step = b.step("check", "Build demo and tests without running");
    check_step.dependOn(&demo.step);
    check_step.dependOn(&tests.step);

    // ------------------------------------------------------------
    // gen: regenera src/runtime/ y el soporte de pub/sub
    // ------------------------------------------------------------
    const protobuzig_path = b.option([]const u8, "protobuzig", "Ruta a protobuzig") orelse "/home/chuco/MyProgs/ZIG/06_k6bus/K6Bus/tools/protobuzig";
    const genpubsub_path = b.option([]const u8, "genpubsub", "Ruta a k6b-genpubsub") orelse "/home/chuco/MyProgs/ZIG/06_k6bus/K6Bus/zig-out/bin/k6b-genpubsub";

    const gen_step = b.step("gen", "Regenerate src/runtime (protobuzig + k6b-genpubsub)");

    const mkdir_runtime = b.addSystemCommand(&.{ "mkdir", "-p", "src/runtime" });
    gen_step.dependOn(&mkdir_runtime.step);

    const copy_encdec = b.addSystemCommand(&.{
        "cp",
        b.pathJoin(&.{ k6bus_dir, "src", "generated", "encdec.zig" }),
        "src/runtime/encdec.zig",
    });
    copy_encdec.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_encdec.step);

    const copy_generic = b.addSystemCommand(&.{
        "cp",
        b.pathJoin(&.{ k6bus_dir, "src", "core", "generic_pubsub.zig" }),
        "src/runtime/generic_pubsub.zig",
    });
    copy_generic.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_generic.step);

    const copy_safe = b.addSystemCommand(&.{
        "cp",
        b.pathJoin(&.{ k6bus_dir, "src", "core", "safe_pubsub.zig" }),
        "src/runtime/safe_pubsub.zig",
    });
    copy_safe.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_safe.step);

    const gen_proto = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "Bon.proto",
    });
    gen_proto.step.dependOn(&mkdir_runtime.step);
    gen_proto.step.dependOn(&copy_encdec.step);
    gen_step.dependOn(&gen_proto.step);

    const gen_pubsub = b.addSystemCommand(&.{
        genpubsub_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "Bon.proto",
    });
    gen_pubsub.step.dependOn(&copy_generic.step);
    gen_pubsub.step.dependOn(&copy_safe.step);
    gen_pubsub.step.dependOn(&gen_proto.step);
    gen_step.dependOn(&gen_pubsub.step);
}
