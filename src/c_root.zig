// ============================================================================
// c_root.zig
// ============================================================================
//
// Root of the module compiled into libk6bus.a (the library with the C ABI).
//
// It forces the analysis of exports_c.zig (prototype of the C ABI) so that
// its `export fn`:
//   - enter as symbols in libk6bus.a;
//   - feed the generated C header (-femit-h -> k6bus.h).
//
// exports_c.zig is an experimental prototype (Guidelines section 8): the
// definitive C ABI will be designed from scratch after stabilizing Zig v1.
// ============================================================================

const exports_c = @import("core/exports_c.zig");

comptime {
    // Forces the analysis of the exported functions (analysis in Zig is
    // lazy: without these references, the `export fn` would not enter the lib
    // nor the header).
    _ = exports_c.k6b_domain_create;
    _ = exports_c.k6b_domain_close;
    _ = exports_c.k6b_domain_send_raw;
}
