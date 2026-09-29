// ============================================================================
// gtk.zig - FUTURE: GTK face of the key manager (NOT IMPLEMENTED)
// ============================================================================
//
// This file exists to pin down the split of responsibilities: the logic
// lives in keymgr.zig and each face (CLI today, GTK tomorrow) only paints it
// and calls it. It does NOT compile yet: build.zig only compiles the CLI
// (src/keymgr/main.zig), so the core and the CLI still do not depend on GTK.
//
// Planned contract (same API that main.zig uses, no new logic):
//
//   var reg = try keymgr.Registry.open(allocator, path, description);
//   defer reg.deinit();
//
//   // Table: one row per key.
//   const lista = try reg.list();            // []keymgr.Summary
//   defer allocator.free(lista);
//   //   columns: ID | MODO | CREADA | CADUCA | DIAS | ESTADO | DESCRIPCION
//   //   ESTADO: OK / AVISO (<=7 days) / CADUCADA / FUTURA
//
//   // Actions (buttons):
//   const id = try reg.create(days, mode, optional_description);
//   const rec = reg.find(id) orelse ...;     // details (includes key Base64)
//   try reg.remove(id);
//
// Requirements for when it is implemented:
//   - GTK dependency in build.zig, OPTIONAL (e.g. -Dgtk=true), so that
//     `zig build` keeps working without GTK installed;
//   - no changes in keymgr.zig (if something is needed, it is added there
//     and both faces use it);
//   - the binary would be k6b-keymgr-gtk (or the same k6b-keymgr with a
//     `gui` subcommand), to be decided then.
//
// None of this is implemented: it is documentation of the plan.
