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
    // Este build.zig vive en examples/demo1.
    // Por tanto, la raiz del repo K6Bus queda dos niveles arriba.
    //
    // examples/demo1/build.zig
    // ../../src/root.zig
    //
    // Para una futura version con build.zig.zon, esto podria cambiarse
    // por b.dependency("k6bus", .{}).module("k6bus").
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
    // Generate demo1 proto
    // ------------------------------------------------------------
    // Este step genera el codigo de la demo, no los protos core de K6Bus.
    // Los protos core se generan desde el build.zig raiz con:
    //   zig build gen
    //
    // Estructura esperada:
    //   examples/demo1/proto/Estacion.proto
    //   examples/demo1/src/runtime/Estacion.zig
    //   examples/demo1/src/runtime/encdec.zig
    const protobuzig_path =
        b.option([]const u8, "protobuzig", "Path to protobuzig binary") orelse
        if (target.result.os.tag == .windows)
            "../../tools/protobuzig.exe"
        else
            "../../tools/protobuzig";

    const gen_step = b.step("gen", "Generate demo1 Zig files from proto using protobuzig");

    const gen_estacion = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/runtime",
        "Estacion.proto",
    });
    gen_step.dependOn(&gen_estacion.step);
}
