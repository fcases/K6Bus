const std = @import("std");
const t = std.testing;

// tests.zig: un test round-trip (Protobuf Text + binario) por cada
// mensaje EXTERNO del contrato (2); los anidados no se testean
// aqui. Generado por protobuzig --ws: si anades mensajes al .proto,
// regenera el workspace.

// API segura generada (Bon_api.zig), no el raw. Los wrappers viven
// en el nivel superior del fichero (sin el paquete del proto) y el
// namespace lleva el nombre del CONTRATO (el del fichero .proto).
const Bon = @import("runtime/Bon_api.zig");

fn ronda(comptime T: type) !void {
    const a = t.allocator;

    var msg = try T.initDefault(a);
    defer msg.deinit(a);

    // Protobuf Text: escribir y releer.
    const teksto = try msg.writeToText(a, .TF_PROTOBUF);
    defer a.free(teksto);
    var reteksto = try T.readFromText(a, teksto, .TF_PROTOBUF);
    defer reteksto.deinit(a);

    // Binario Protocol Buffers: escribir y releer.
    const binara = try msg.serializeToBin(a, .BF_PROTOBUF);
    defer a.free(binara);
    var rebinara = try T.deserializeFromBin(a, binara, .BF_PROTOBUF);
    defer rebinara.deinit(a);
}

test "Cia: round-trip texto + binario" {
    try ronda(Bon.Cia);
}

test "Bon: round-trip texto + binario" {
    try ronda(Bon.Bon);
}
