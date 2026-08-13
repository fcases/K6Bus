const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const zig_exe = b.graph.zig_exe;

    // const optimize = b.standardOptimizeOption(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    // ------------------------------------------------------------
    // k6bus module
    // ------------------------------------------------------------
    const k6bus_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    // k6b-genpubsub tool
    // ------------------------------------------------------------
    const genpubsub_mod = b.createModule(.{
        .root_source_file = b.path("src/genpubsub/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const genpubsub_exe = b.addExecutable(.{
        .name = "k6b-genpubsub",
        .root_module = genpubsub_mod,
        .use_llvm = true,
    });
    const install_genpubsub = b.addInstallArtifact(genpubsub_exe, .{});
    b.getInstallStep().dependOn(&install_genpubsub.step);

    const build_genpubsub_step = b.step(
        "build_genpubsub",
        "Build and install k6b-genpubsub tool",
    );
    build_genpubsub_step.dependOn(&install_genpubsub.step);

    // ------------------------------------------------------------
    // Tests core
    // ------------------------------------------------------------
    const core_tests = b.addTest(.{
        .root_module = k6bus_mod,
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const test_step = b.step("test", "Run k6bus core tests");
    test_step.dependOn(&run_core_tests.step);

    // ------------------------------------------------------------
    // Check core
    // ------------------------------------------------------------
    const check_step = b.step("check", "Build k6bus core without running demos");
    check_step.dependOn(&k6bus_lib.step);

    // ------------------------------------------------------------
    // Demo workspaces
    // Cada demo tiene su propio build.zig.
    // Uso:
    //   zig build run_demo1
    //   zig build run_demo2
    // Alias:
    //   zig build demo1
    //   zig build demo2
    // Pasar argumentos a la demo:
    //   zig build run_demo2 --cctrol --config_file config/cctrol.zon
    //   zig build run_demo2 --remotas --config_file config/remotas.zon
    // ------------------------------------------------------------
    const demo1_run = b.addSystemCommand(&.{
        zig_exe,
        "build",
        "run",
    });
    demo1_run.setCwd(b.path("examples/demo1"));

    if (b.args) |args| {
        demo1_run.addArgs(args);
    }

    const run_demo1_step = b.step(
        "run_demo1",
        "Run examples/demo1 using its own build.zig",
    );
    run_demo1_step.dependOn(&demo1_run.step); // zig build run_demo1 llama a demo1_run osea a zig build run del directorio examples/demo1

    const demo2_run = b.addSystemCommand(&.{
        zig_exe,
        "build",
        "run",
    });
    demo2_run.setCwd(b.path("examples/demo2"));

    if (b.args) |args| {
        demo2_run.addArgs(args);
    }

    const run_demo2_step = b.step(
        "run_demo2",
        "Run examples/demo2 using its own build.zig",
    );
    run_demo2_step.dependOn(&demo2_run.step); // zig build run_demo2 llama a demo2_run osea a zig build run del directorio examples/demo2

    // ------------------------------------------------------------
    // Build demo workspaces without running
    //
    // Uso:
    //   zig build build_demo1
    //   zig build build_demo2
    //   zig build check_all
    // ------------------------------------------------------------
    const demo1_build = b.addSystemCommand(&.{
        zig_exe,
        "build",
    });
    demo1_build.setCwd(b.path("examples/demo1"));

    const build_demo1_step = b.step(
        "build_demo1",
        "Build examples/demo1 using its own build.zig",
    );
    build_demo1_step.dependOn(&demo1_build.step); // zig build build_demo1 llama a demo1_build osea a zig build del directorio examples/demo1

    const demo2_build = b.addSystemCommand(&.{
        zig_exe,
        "build",
    });
    demo2_build.setCwd(b.path("examples/demo2"));

    const build_demo2_step = b.step(
        "build_demo2",
        "Build examples/demo2 using its own build.zig",
    );
    build_demo2_step.dependOn(&demo2_build.step); // zig build build_demo2 llama a demo2_build osea a zig build del directorio examples/demo2

    // ------------------------------------------------------------
    // Build todo todito todo sin ejecutar
    // ------------------------------------------------------------
    const check_all_step = b.step(
        "check_all",
        "Build k6bus core, genpubsub and demo workspaces",
    );
    check_all_step.dependOn(&k6bus_lib.step);
    check_all_step.dependOn(&demo1_build.step);
    check_all_step.dependOn(&demo2_build.step);
    check_all_step.dependOn(&install_genpubsub.step);

    // ------------------------------------------------------------
    // Generate core protos
    // K6Bus/protos contiene solo los protos core:
    //   Config.proto
    //   Msg.proto
    //   Packet.proto
    //   Security.proto
    // ------------------------------------------------------------
    const protobuzig_path =
        b.option([]const u8, "protobuzig", "Path to protobuzig binary") orelse
        if (target.result.os.tag == .windows)
            "tools/protobuzig.exe"
        else
            "tools/protobuzig";

    const gen_step = b.step(
        "gen",
        "Generate Zig files from K6Bus core protos using protobuzig",
    );

    const gen_msg = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/generated",
        "Msg.proto",
    });
    gen_step.dependOn(&gen_msg.step);

    const gen_packet = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/generated",
        "Packet.proto",
    });
    gen_step.dependOn(&gen_packet.step);

    const gen_config = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/generated",
        "Config.proto",
    });
    gen_step.dependOn(&gen_config.step);

    const gen_security = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/generated",
        "Security.proto",
    });
    gen_step.dependOn(&gen_security.step);
}
