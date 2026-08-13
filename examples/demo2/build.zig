const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // De momento mantenemos Debug fijo.
    // Si quieres volver al modo configurable:
    // const optimize = b.standardOptimizeOption(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    // ------------------------------------------------------------
    // k6bus dependency/module
    // ------------------------------------------------------------
    // Este build.zig vive en examples/demo2.
    // Por tanto, la raiz del repo K6Bus queda dos niveles arriba:
    //      examples/demo2/build.zig
    //      ../../src/root.zig
    // En el futuro, con build.zig.zon, esto podria cambiarse por:
    // b.dependency("k6bus", .{}).module("k6bus")
    const k6bus_mod = b.createModule(.{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ------------------------------------------------------------
    // demo2 executable
    // ------------------------------------------------------------
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("k6bus", k6bus_mod);

    const demo = b.addExecutable(.{
        .name = "k6bus_demo2",
        .root_module = demo_mod,
        .use_llvm = true,
    });
    b.installArtifact(demo);

    // ------------------------------------------------------------
    // Run
    // Uso desde examples/demo2:
    //   zig build run -- cctrol --config_file config/cctrol.zon
    //   zig build run -- remotas --config_file config/remotas.zon
    // Uso desde el build raiz:
    //   zig build run_demo2 -- cctrol --config_file config/cctrol.zon
    //   zig build run_demo2 -- remotas --config_file config/remotas.zon
    // ------------------------------------------------------------
    const run_demo = b.addRunArtifact(demo);

    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const run_step = b.step("run", "Run demo2");
    run_step.dependOn(&run_demo.step);

    // ------------------------------------------------------------
    // Check
    // ------------------------------------------------------------
    const check_step = b.step("check", "Build demo2 without running");
    check_step.dependOn(&demo.step);

    // ------------------------------------------------------------
    // Generate demo2 runtime
    // Este step genera/copia el runtime especifico de la demo.
    // No genera los protos core de K6Bus.
    // Estructura esperada:
    // examples/demo2/
    //   proto/
    //     cctrol.proto
    //   src/
    //     main.zig
    //     runtime/
    //       encdec.zig
    //       generic_pubsub.zig
    //       cctrol.zig
    //       cctrol_pubsub.zig
    // ------------------------------------------------------------
    const protobuzig_path =
        b.option([]const u8, "protobuzig", "Path to protobuzig binary") orelse
        if (target.result.os.tag == .windows)
            "../../tools/protobuzig.exe"
        else
            "../../tools/protobuzig";

    const genpubsub_path =
        b.option([]const u8, "genpubsub", "Path to k6b-genpubsub binary") orelse
        if (target.result.os.tag == .windows)
            "../../zig-out/bin/k6b-genpubsub.exe"
        else
            "../../zig-out/bin/k6b-genpubsub";

    const gen_step = b.step(
        "gen",
        "Generate demo2 runtime files from cctrol.proto",
    );

    // Crear src/runtime si no existe.
    const mkdir_runtime = b.addSystemCommand(&.{
        "mkdir",
        "-p",
        "src/runtime",
    });
    gen_step.dependOn(&mkdir_runtime.step);

    // Copiar encdec.zig desde el core/template.
    const copy_encdec = b.addSystemCommand(&.{
        "cp",
        "../../src/generated/encdec.zig",
        "src/runtime/encdec.zig",
    });
    copy_encdec.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_encdec.step);

    // Copiar generic_pubsub.zig desde el core/template.
    const copy_generic_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/generic_pubsub.zig",
        "src/runtime/generic_pubsub.zig",
    });
    copy_generic_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_generic_pubsub.step);

    // Generar cctrol.zig con ProtobuZig.
    const gen_cctrol = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "cctrol.proto",
    });
    gen_cctrol.step.dependOn(&mkdir_runtime.step);
    gen_cctrol.step.dependOn(&copy_encdec.step);
    gen_step.dependOn(&gen_cctrol.step);

    // Generar cctrol_pubsub.zig con k6b-genpubsub.
    // Ajustar estos flags si finalmente la CLI real de k6b-genpubsub cambia.
    const gen_cctrol_pubsub = b.addSystemCommand(&.{
        genpubsub_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "cctrol.proto",
    });
    gen_cctrol_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_cctrol_pubsub.step.dependOn(&copy_generic_pubsub.step);
    gen_cctrol_pubsub.step.dependOn(&gen_cctrol.step);
    gen_step.dependOn(&gen_cctrol_pubsub.step);
}
