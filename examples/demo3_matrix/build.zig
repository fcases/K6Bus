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
}
