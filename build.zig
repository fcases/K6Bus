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

    // Modulo de la libreria instalada: API publica de root.zig + C ABI.
    // c_root.zig re-exporta root.zig y fuerza el analisis de las `export fn`
    // de exports_c.zig para que entren en libk6bus.a y en el header (-femit-h).
    // link_libc: exports_c usa std.heap.c_allocator.
    const k6bus_c_mod = b.createModule(.{
        .root_source_file = b.path("src/c_root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // ------------------------------------------------------------
    // libk6bus.a
    // ------------------------------------------------------------
    const k6bus_lib = b.addLibrary(.{
        .name = "k6bus",
        .linkage = .static,
        .root_module = k6bus_c_mod,
        .use_llvm = true,
    });
    // b.installArtifact(k6bus_lib);
    // k6bus_lib.step solo compila.
    // install_k6bus.step compila e instala en zig-out/lib.
    const install_k6bus = b.addInstallArtifact(k6bus_lib, .{});
    b.getInstallStep().dependOn(&install_k6bus.step);

    // Header C instalado en el MISMO directorio que libk6bus.a
    // (zig-out/lib/k6bus.h). Es espejo MANUAL de src/core/exports_c.zig:
    // -femit-h NO genera header en zig 0.15.2 (verificado 2026-09-04), aunque
    // los simbolos exportados si entran en el .a (via c_root.zig).
    const install_k6bus_h = b.addInstallFileWithDir(
        b.path("src/core/k6bus.h"),
        .lib,
        "k6bus.h",
    );
    b.getInstallStep().dependOn(&install_k6bus_h.step);

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
    // k6b-keymgr tool (gestor de claves; la logica vive en src/keymgr)
    // ------------------------------------------------------------
    const keymgr_mod = b.createModule(.{
        .root_source_file = b.path("src/keymgr/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    keymgr_mod.addImport("k6bus", k6bus_mod);

    const keymgr_exe = b.addExecutable(.{
        .name = "k6b-keymgr",
        .root_module = keymgr_mod,
        .use_llvm = true,
    });
    const install_keymgr = b.addInstallArtifact(keymgr_exe, .{});
    b.getInstallStep().dependOn(&install_keymgr.step);

    const build_keymgr_step = b.step(
        "build_keymgr",
        "Build and install k6b-keymgr tool",
    );
    build_keymgr_step.dependOn(&install_keymgr.step);

    // ------------------------------------------------------------
    // k6b-genws tool (crea un ws de protobuzig ya listo para K6Bus)
    // ------------------------------------------------------------
    const genws_mod = b.createModule(.{
        .root_source_file = b.path("src/genws/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const genws_exe = b.addExecutable(.{
        .name = "k6b-genws",
        .root_module = genws_mod,
        .use_llvm = true,
    });
    const install_genws = b.addInstallArtifact(genws_exe, .{});
    b.getInstallStep().dependOn(&install_genws.step);

    const build_genws_step = b.step(
        "build_genws",
        "Build and install k6b-genws tool",
    );
    build_genws_step.dependOn(&install_genws.step);

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
    //   zig build run_demo2 -- cctrol --config_file cfg/k6bus.Demo2.pb.cfg
    //   zig build run_demo2 -- remotas --config_file cfg/k6bus.Demo2.pb.cfg
    // ------------------------------------------------------------
    const demo1_run = b.addSystemCommand(&.{
        zig_exe,
        "build",
        "run",
    });
    demo1_run.setCwd(b.path("examples/demo1"));

    if (b.args) |args| {
        demo1_run.addArg("--");
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
        demo2_run.addArg("--");
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
    // demo3_matrix (transporte Matrix E2E)
    //   zig build run_demo3_matrix -- <usuario> <password> [room] [N] [M]
    // ------------------------------------------------------------
    const demo3_run = b.addSystemCommand(&.{
        zig_exe,
        "build",
        "run",
    });
    demo3_run.setCwd(b.path("examples/demo3_matrix"));

    if (b.args) |args| {
        demo3_run.addArg("--");
        demo3_run.addArgs(args);
    }

    const run_demo3_step = b.step(
        "run_demo3_matrix",
        "Run examples/demo3_matrix (transporte Matrix E2E; necesita usuario/password)",
    );
    run_demo3_step.dependOn(&demo3_run.step);

    const demo3_build = b.addSystemCommand(&.{
        zig_exe,
        "build",
    });
    demo3_build.setCwd(b.path("examples/demo3_matrix"));

    const build_demo3_step = b.step(
        "build_demo3_matrix",
        "Build examples/demo3_matrix using its own build.zig",
    );
    build_demo3_step.dependOn(&demo3_build.step);

    // ------------------------------------------------------------
    // Build todo todito todo sin ejecutar
    // ------------------------------------------------------------
    const check_all_step = b.step(
        "check_all",
        "Build k6bus core, genpubsub and demo workspaces",
    );
    // check_all_step.dependOn(&k6bus_lib.step);
    check_all_step.dependOn(&install_k6bus.step);
    check_all_step.dependOn(&demo1_build.step);
    check_all_step.dependOn(&demo2_build.step);
    check_all_step.dependOn(&demo3_build.step);
    check_all_step.dependOn(&install_genpubsub.step);
    check_all_step.dependOn(&install_keymgr.step);
    check_all_step.dependOn(&install_genws.step);

    // ------------------------------------------------------------
    // Generate core protos
    // K6Bus/protos contiene solo los protos core:
    //   Config.proto
    //   types.proto (Msg + Packet)
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

    const gen_types = b.addSystemCommand(&.{
        protobuzig_path,
        "--proto_dir",
        "protos",
        "--output_dir",
        "src/generated",
        "types.proto",
    });
    gen_step.dependOn(&gen_types.step);

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

    // ------------------------------------------------------------
    // Regeneracion automatica (R3, 2026-09-10)
    //   zig build regen_all    -> regenera core + runtime de los 3 demos
    //   zig build regen_check  -> regen_all + compila + FALLA si hay diff
    //
    // Los generados estan COMMITEADOS: el check detecta DRIFT (contenido
    // distinto de lo preparado/commiteado, o ficheros generados nuevos sin
    // trackear). Uso: antes de commitear, `zig build regen_check`.
    // ------------------------------------------------------------
    const regen_core = b.addSystemCommand(&.{ zig_exe, "build", "gen" });

    const regen_demo1 = b.addSystemCommand(&.{ zig_exe, "build", "gen" });
    regen_demo1.setCwd(b.path("examples/demo1"));
    regen_demo1.step.dependOn(&install_genpubsub.step);

    const regen_demo2 = b.addSystemCommand(&.{ zig_exe, "build", "gen" });
    regen_demo2.setCwd(b.path("examples/demo2"));
    regen_demo2.step.dependOn(&install_genpubsub.step);

    const regen_demo3 = b.addSystemCommand(&.{ zig_exe, "build", "gen" });
    regen_demo3.setCwd(b.path("examples/demo3_matrix"));
    regen_demo3.step.dependOn(&install_genpubsub.step);

    const regen_all_step = b.step(
        "regen_all",
        "Regenerate core + demo runtimes (protobuzig + k6b-genpubsub)",
    );
    regen_all_step.dependOn(&regen_core.step);
    regen_all_step.dependOn(&regen_demo1.step);
    regen_all_step.dependOn(&regen_demo2.step);
    regen_all_step.dependOn(&regen_demo3.step);

    // Compilar DESPUES de regenerar (mismo orden que el flujo manual).
    const compile_tras_regen = b.addSystemCommand(&.{ zig_exe, "build", "check_all" });
    compile_tras_regen.step.dependOn(&regen_core.step);
    compile_tras_regen.step.dependOn(&regen_demo1.step);
    compile_tras_regen.step.dependOn(&regen_demo2.step);
    compile_tras_regen.step.dependOn(&regen_demo3.step);

    // Fallo si lo regenerado no coincide con lo commiteado/preparado.
    const diff_generados = b.addSystemCommand(&.{
        "bash",
        "-c",
        \\set -u
        \\rutas="src/generated examples/demo1/src/runtime examples/demo2/src/runtime examples/demo3_matrix/src/runtime"
        \\if ! git diff --quiet -- $rutas; then
        \\  echo "R3: DIFF en ficheros generados (regenera y commitea):"
        \\  git --no-pager diff --stat -- $rutas
        \\  exit 1
        \\fi
        \\sin_trackear=$(git ls-files -o --exclude-standard -- $rutas)
        \\if [ -n "$sin_trackear" ]; then
        \\  echo "R3: ficheros generados SIN TRACKEAR (git add pendiente):"
        \\  echo "$sin_trackear"
        \\  exit 1
        \\fi
        \\echo "R3 OK: lo regenerado coincide con lo commiteado/preparado."
        ,
    });
    diff_generados.step.dependOn(&compile_tras_regen.step);

    const regen_check_step = b.step(
        "regen_check",
        "Regenerate + build + fail if generated files differ (R3)",
    );
    regen_check_step.dependOn(&diff_generados.step);

}
