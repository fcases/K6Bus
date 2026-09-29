const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // For now we keep Debug fixed.
    // If you want to go back to the configurable mode:
    // const optimize = b.standardOptimizeOption(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    // ------------------------------------------------------------
    // k6bus dependency/module
    // ------------------------------------------------------------
    // This build.zig lives in examples/demo1.
    // Therefore the K6Bus repo root is two levels up:
    //      examples/demo1/build.zig
    //      ../../src/root.zig
    // In the future, with build.zig.zon, this could be changed to:
    // b.dependency("k6bus", .{}).module("k6bus")
    const k6bus_mod = b.createModule(.{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ------------------------------------------------------------
    // demo1 executable
    // ------------------------------------------------------------
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    demo_mod.addImport("k6bus", k6bus_mod);

    const demo = b.addExecutable(.{
        .name = "k6bus_demo1",
        .root_module = demo_mod,
        .use_llvm = true,
    });

    b.installArtifact(demo);

    // ------------------------------------------------------------
    // Run
    // ------------------------------------------------------------
    const run_demo = b.addRunArtifact(demo);

    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const run_step = b.step("run", "Run demo1");
    run_step.dependOn(&run_demo.step);

    // ------------------------------------------------------------
    // Check
    // ------------------------------------------------------------
    const check_step = b.step("check", "Build demo1 without running");
    check_step.dependOn(&demo.step);

    // ------------------------------------------------------------
    // Generate demo1 runtime
    // This step generates/copies the demo-specific runtime.
    // It does not generate the K6Bus core protos.
    // Expected structure:
    // examples/demo1/
    //   protos/
    //     Estacion.proto
    //   src/
    //     main.zig
    //     runtime/
    //       encdec.zig                 (copied from src/generated)
    //       generic_pubsub.zig         (copied from src/core)
    //       safe_pubsub.zig            (copied from src/core)
    //       Estacion.zig               (protobuzig)
    //       Estacion_api.zig           (protobuzig)
    //       Estacion_pubsub.zig        (k6b-genpubsub, raw)
    //       Estacion_safe_pubsub.zig   (k6b-genpubsub, safe)
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
        "Generate demo1 runtime files from Estacion.proto",
    );

    // Create src/runtime if it does not exist.
    const mkdir_runtime = b.addSystemCommand(&.{
        "mkdir",
        "-p",
        "src/runtime",
    });
    gen_step.dependOn(&mkdir_runtime.step);

    // Copy encdec.zig from the core/template.
    const copy_encdec = b.addSystemCommand(&.{
        "cp",
        "../../src/generated/encdec.zig",
        "src/runtime/encdec.zig",
    });
    copy_encdec.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_encdec.step);

    // Copy generic_pubsub.zig from the core/template.
    const copy_generic_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/generic_pubsub.zig",
        "src/runtime/generic_pubsub.zig",
    });
    copy_generic_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_generic_pubsub.step);

    // Copy safe_pubsub.zig from the core/template.
    const copy_safe_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/safe_pubsub.zig",
        "src/runtime/safe_pubsub.zig",
    });
    copy_safe_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_safe_pubsub.step);

    // Generate Estacion.zig and Estacion_api.zig with ProtobuZig.
    const gen_estacion = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "Estacion.proto",
    });
    gen_estacion.step.dependOn(&mkdir_runtime.step);
    gen_estacion.step.dependOn(&copy_encdec.step);
    gen_step.dependOn(&gen_estacion.step);

    // Generate Estacion_pubsub.zig + Estacion_safe_pubsub.zig (k6b-genpubsub).
    const gen_estacion_pubsub = b.addSystemCommand(&.{
        genpubsub_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "Estacion.proto",
    });
    gen_estacion_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_estacion_pubsub.step.dependOn(&copy_generic_pubsub.step);
    gen_estacion_pubsub.step.dependOn(&copy_safe_pubsub.step);
    gen_estacion_pubsub.step.dependOn(&gen_estacion.step);
    gen_step.dependOn(&gen_estacion_pubsub.step);
}
