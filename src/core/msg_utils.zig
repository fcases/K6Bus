// msg_utils.zig
//
// Utilidades de ownership para k6bus.msg.Msg.
//
// Responsabilidades:
//
// - Clonado profundo de Msg.
// - Liberación de memoria dinámica de Msg.
// - Mantener toda la lógica de ownership de Msg en un único lugar.
//
// Nota:
// El propio Msg se pasa por valor.
// Estas funciones sólo gestionan la memoria dinámica
// asociada a sus slices.
//

const std = @import("std");
const all = std.mem;

// const Msg = @import("msg.zig").Msg;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

/// Crea una copia profunda de un mensaje.
///
/// Se duplican:
/// - channels
/// - payLoad
///
/// Se copian por valor:
/// - msgType
pub fn cloneMsg(allocator: all.Allocator, src: *const Msg) !Msg {
    const cloned_channels =
        try allocator.dupe(u64, src.channels);

    errdefer allocator.free(cloned_channels);

    const cloned_payload =
        try allocator.dupe(u8, src.payLoad);

    errdefer allocator.free(cloned_payload);

    return Msg{
        .channels = cloned_channels,
        .msgType = src.msgType,
        .payLoad = cloned_payload,
    };
}

/// Libera la memoria dinámica asociada a un Msg.
///
/// No libera el propio Msg.
///
/// Uso típico:
///
/// var msg: Msg = ...;
/// msg_utils.free(allocator, &msg);
///
pub fn freeMsg(allocator: all.Allocator, msg: *Msg) void {
    allocator.free(msg.channels);
    allocator.free(msg.payLoad);

    msg.channels = &.{};
    msg.payLoad = &.{};
}

/// Libera todos los mensajes de una lista.
///
/// No destruye el ArrayList.
/// Sólo libera los recursos internos de cada Msg.
pub fn freeMsgsFromSlice(allocator: all.Allocator, msgs: []Msg) void {
    for (msgs) |*msg| {
        freeMsg(allocator, msg);
    }
}

/// Clona una lista completa de mensajes.
///
/// Cada Msg resultante es propietario de sus
/// propios canales y payload.
pub fn cloneMsgSlice(allocator: all.Allocator, msgs: []const Msg) ![]Msg {
    const result =
        try allocator.alloc(Msg, msgs.len);

    var cloned_count: usize = 0;
    errdefer {
        freeMsgsFromSlice(allocator, result[0..cloned_count]);
        allocator.free(result);
    }

    for (msgs, 0..) |msg, i| {
        result[i] = try cloneMsg(allocator, &msg);
        cloned_count += 1;
    }

    return result;
}

/// Libera una lista creada mediante cloneMsgSlice().
///
/// Libera:
/// - payloads
/// - channels
/// - array de Msg
pub fn freeClonedMsgSlice(allocator: all.Allocator, msgs: []Msg) void {
    freeMsgsFromSlice(allocator, msgs);

    allocator.free(msgs);
}
