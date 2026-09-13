const std = @import("std");

// main.zig: codigo de USUARIO.
//
// Ejemplo generado por protobuzig --ws. Modificalo libremente para
// poner la logica de tu problema: crear mensajes, rellenar campos,
// escribir a fichero, cambiar de formato, etc.
//
// Lo generado vive en src/runtime:
//
//     Bon.zig       implementacion RAW (uso interno; no la importes)
//     Bon_api.zig   API SEGURA sobre el raw: usa ESTA
//     encdec.zig         soporte de serializacion
//
//     const Base = @import("runtime/Bon_api.zig");
//
const Base = @import("runtime/Bon_api.zig");
const Ejemplo = Base.Cia;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    // 1) Crea un objeto del mensaje del contrato.
    var msg = try Ejemplo.initDefault(a);
    defer msg.deinit(a);

    // Muestra en el primer campo ("name") usando la API segura: quita
    // esto y pon tu logica.
    try msg.setName(a, "valor de ejemplo");


    // 2) Escribelo a fichero como Protobuf Text y leelo de vuelta.
    try msg.writeToFile(a, "demo.txt", .TF_PROTOBUF);
    var desde_texto = try Ejemplo.readFromFile(a, "demo.txt", .TF_PROTOBUF);
    defer desde_texto.deinit(a);

    // 3) Cambia de formato: binario Protocol Buffers, y leelo de vuelta.
    try msg.serializeToFile(a, "demo.pb", .BF_PROTOBUF);
    var desde_binario = try Ejemplo.deserializeFromFile(a, "demo.pb", .BF_PROTOBUF);
    defer desde_binario.deinit(a);

    // 4) Muestra el contenido por consola.
    const texto = try msg.writeToText(a, .TF_PROTOBUF);
    defer a.free(texto);
    std.debug.print("{s}\n", .{texto});

    std.debug.print("Demo ok: revisa demo.txt y demo.pb en el directorio actual.\n", .{});
}
