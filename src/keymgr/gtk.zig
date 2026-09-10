// ============================================================================
// gtk.zig - FUTURO: cara GTK del gestor de claves (NO IMPLEMENTADO)
// ============================================================================
//
// Este fichero existe para dejar fijado el reparto de responsabilidades: la
// logica vive en keymgr.zig y cada cara (CLI hoy, GTK manana) solo la pinta y
// la invoca. NO se compila todavia: build.zig solo compila src/keymgr/main.zig,
// asi que el core y la CLI siguen sin depender de GTK.
//
// Contrato previsto (misma API que usa main.zig, sin logica nueva):
//
//   var reg = try keymgr.Registro.abrir(allocator, ruta, descripcion);
//   defer reg.deinit();
//
//   // Tabla: una fila por clave.
//   const lista = try reg.listar();            // []keymgr.Resumen
//   defer allocator.free(lista);
//   //   columnas: ID | MODO | CREADA | CADUCA | DIAS | ESTADO | DESCRIPCION
//   //   ESTADO: OK / AVISO (<=7 dias) / CADUCADA / FUTURA
//
//   // Acciones (botones):
//   const id = try reg.crear(dias, modo, descripcion_opcional);
//   const rec = reg.buscar(id) orelse ...;     // detalle (incluye key Base64)
//   try reg.borrar(id);
//
// Requisitos cuando se implemente:
//   - dependencia GTK en build.zig, OPCIONAL (p. ej. -Dgtk=true), de modo que
//     `zig build` siga funcionando sin GTK instalado;
//   - ningun cambio en keymgr.zig (si hace falta algo, se anade ahi y lo usan
//     las dos caras);
//   - el binario seria k6b-keymgr-gtk (o el mismo k6b-keymgr con subcomando
//     `gui`), a decidir entonces.
//
// Nada de esto esta implementado: es documentacion del plan.
