const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    // ------------------------------------------------------------
    // k6bus module
    // ------------------------------------------------------------
    const k6bus_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    // ------------------------------------------------------------
    // libk6bus.a
    // ------------------------------------------------------------
    const k6bus_lib = b.addLibrary(.{
        .name = "k6bus",
        .linkage = .static,
        .root_module = k6bus_mod,
        .use_llvm = true,
    });

    b.installArtifact(k6bus_lib);

    // ------------------------------------------------------------
    // demo1 executable
    // ------------------------------------------------------------
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/demo1/main.zig"),
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

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const run_step = b.step("run", "Run demo1");
    run_step.dependOn(&run_demo.step);

    // ------------------------------------------------------------
    // Tests core
    // ------------------------------------------------------------
    const core_tests = b.addTest(.{
        .root_module = k6bus_mod,
    });

    const run_core_tests = b.addRunArtifact(core_tests);

    const test_step = b.step("test", "Run k6bus tests");
    test_step.dependOn(&run_core_tests.step);

    // ------------------------------------------------------------
    // Check
    // ------------------------------------------------------------
    const check_step = b.step("check", "Build k6bus and demo1 without running");
    check_step.dependOn(&k6bus_lib.step);
    check_step.dependOn(&demo.step);

    // ------------------------------------------------------------
    // Generate core protos
    // Ajustar comandos si la CLI real de protobuzig difiere.
    // ------------------------------------------------------------
    const protobuzig_path =
        b.option([]const u8, "protobuzig", "Path to protobuzig binary") orelse
        if (target.result.os.tag == .windows)
            "tools/protobuzig.exe"
        else
            "tools/protobuzig";

    const gen_step = b.step("gen", "Generate Zig files from protos using protobuzig");

    const gen_msg = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos/k6bus",
        "--output_dir",
        "src/generated",
        "Msg.proto",
    });
    gen_step.dependOn(&gen_msg.step);

    const gen_packet = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos/k6bus",
        "--output_dir",
        "src/generated",
        "Packet.proto",
    });
    gen_step.dependOn(&gen_packet.step);

    const gen_config = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos/k6bus",
        "--output_dir",
        "src/generated",
        "Config.proto",
    });
    gen_step.dependOn(&gen_config.step);

    const gen_security = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos/k6bus",
        "--output_dir",
        "src/generated",
        "Security.proto",
    });
    gen_step.dependOn(&gen_security.step);

    // ------------------------------------------------------------
    // Generate demo1 proto
    // ------------------------------------------------------------
    const gen_estacion = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos/demo1",
        "--output_dir",
        "examples/demo1/generated",
        "Estacion.proto",
    });
    gen_step.dependOn(&gen_estacion.step);
}
