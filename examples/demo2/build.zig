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
    // This build.zig lives in examples/demo2.
    // Therefore the K6Bus repo root is two levels up:
    //      examples/demo2/build.zig
    //      ../../src/root.zig
    // In the future, with build.zig.zon, this could be changed to:
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
    // Usage from examples/demo2:
    //   zig build run -- cctrol --config_file cfg/k6bus.Demo2.pb.cfg
    //   zig build run -- remotas --config_file cfg/k6bus.Demo2.pb.cfg
    // Usage from the root build:
    //   zig build run_demo2 -- cctrol --config_file cfg/k6bus.Demo2.pb.cfg
    //   zig build run_demo2 -- remotas --config_file cfg/k6bus.Demo2.pb.cfg
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
    // This step generates/copies the demo-specific runtime.
    // It does not generate the K6Bus core protos.
    // Expected structure:
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

    // Copy generic_pubsub.zig from the core/template.
    const copy_safe_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/safe_pubsub.zig",
        "src/runtime/safe_pubsub.zig",
    });
    copy_safe_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_safe_pubsub.step);

    // Generate cctrol.zig with ProtobuZig.
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

    // Generate cctrol_pubsub.zig with k6b-genpubsub.
    // Adjust these flags if the real k6b-genpubsub CLI changes in the end.
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
    gen_cctrol_pubsub.step.dependOn(&copy_safe_pubsub.step);
    gen_cctrol_pubsub.step.dependOn(&gen_cctrol.step);
    gen_step.dependOn(&gen_cctrol_pubsub.step);
}
