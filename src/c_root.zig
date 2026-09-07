// ============================================================================
// c_root.zig
// ============================================================================
//
// Raiz del modulo compilado para libk6bus.a (la libreria con la C ABI).
//
// Fuerza el analisis de exports_c.zig (prototipo de la C ABI) para que sus
// `export fn`:
//   - entren como simbolos en libk6bus.a;
//   - alimenten el header C generado (-femit-h -> k6bus.h).
//
// exports_c.zig es un prototipo experimental (Directrices seccion 8): la C
// ABI definitiva se disenara de cabo a rabo tras estabilizar la v1 Zig.
// ============================================================================

const exports_c = @import("core/exports_c.zig");

comptime {
    // Fuerza el analisis de las funciones exportadas (el analisis en Zig es
    // perezoso: sin estas referencias, las `export fn` no entrarian en la lib
    // ni en el header).
    _ = exports_c.k6b_domain_create;
    _ = exports_c.k6b_domain_close;
    _ = exports_c.k6b_domain_send_raw;
}
