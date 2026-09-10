const std = @import("std");

// ---------------------------------------------------------------------------
// demo3_matrix: validacion E2E del transporte Matrix.
//
// Reutiliza el runtime Estacion de examples/demo1 (misma proto en ambos
// dominios => mismo msgType, ya que msgType = hash(domain.id + typeName)).
//
// Estructura:
//   Domain A (id 77) + transporte Matrix "matrixA"
//   Domain B (id 77) + transporte Matrix "matrixB"
//   Ambos transportes usan EL MISMO usuario de Matrix y la misma sala.
//
// Flujo:
//   1) A publica N mensajes  -> subA los recibe en local; subB los recibe
//      via Matrix (device B del mismo usuario).
//   2) B publica M mensajes  -> subB local; subA via Matrix.
//   3) Verificacion: subA == subB == N + M (sin duplicados: el eco propio
//      de cada transporte se descarta por unsigned.transaction_id).
//
// Uso:
//   zig build run -- <usuario> <password> [room] [N] [M]
//   room por defecto: #lasala:matrix.org
// ---------------------------------------------------------------------------
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    const k6bus_mod = b.createModule(.{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("k6bus", k6bus_mod);

    const demo = b.addExecutable(.{
        .name = "k6bus_demo3_matrix",
        .root_module = demo_mod,
        .use_llvm = true,
    });
    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| run_demo.addArgs(args);

    const run_step = b.step("run", "Run demo3_matrix");
    run_step.dependOn(&run_demo.step);

    const check_step = b.step("check", "Build demo3_matrix without running");
    check_step.dependOn(&demo.step);

    // ------------------------------------------------------------
    // Generate runtime (R3): mismo patron que demo1/demo2.
    // Estructura: protos/Estacion.proto -> src/runtime/
    //   encdec.zig, generic_pubsub.zig, safe_pubsub.zig (copiados del core)
    //   Estacion.zig + Estacion_api.zig                (protobuzig)
    //   Estacion_pubsub.zig + Estacion_safe_pubsub.zig (k6b-genpubsub)
    // Antes NO existia: el runtime era una copia manual de demo1.
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

    const gen_step = b.step("gen", "Generate demo3_matrix runtime from Estacion.proto");

    const mkdir_runtime = b.addSystemCommand(&.{ "mkdir", "-p", "src/runtime" });
    gen_step.dependOn(&mkdir_runtime.step);

    const copy_encdec = b.addSystemCommand(&.{
        "cp",
        "../../src/generated/encdec.zig",
        "src/runtime/encdec.zig",
    });
    copy_encdec.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_encdec.step);

    const copy_generic_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/generic_pubsub.zig",
        "src/runtime/generic_pubsub.zig",
    });
    copy_generic_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_generic_pubsub.step);

    const copy_safe_pubsub = b.addSystemCommand(&.{
        "cp",
        "../../src/core/safe_pubsub.zig",
        "src/runtime/safe_pubsub.zig",
    });
    copy_safe_pubsub.step.dependOn(&mkdir_runtime.step);
    gen_step.dependOn(&copy_safe_pubsub.step);

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
