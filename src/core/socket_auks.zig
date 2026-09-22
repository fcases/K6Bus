// ============================================================================
// socket_auks.zig - Auxiliares de socket compartidos por los transportes
// ============================================================================
const std = @import("std");

const Logger = @import("logger.zig").Logger;

/// Pide un tamano de buffer de socket (SO_RCVBUF / SO_SNDBUF).
///
/// Los tamanos de buffer son un CONSEJO de rendimiento, no un requisito de
/// correctitud, y cada sistema los limita a su manera:
///   - Linux recorta en silencio al valor de net.core.rmem_max / wmem_max.
///   - FreeBSD devuelve ENOBUFS si se pide mas de kern.ipc.maxsockbuf
///     (2 MB por defecto).
/// Tratar ese rechazo como error fatal tumbaba el arranque del dominio en
/// FreeBSD (F10, 2026-09-15): se pedia 134217727 (128 MB) y el setsockopt
/// fallaba -> error.SystemResources. Ahora se avisa y se sigue: el socket se
/// queda con el valor por defecto del sistema, que es lo unico que puede dar.
///
/// Ademas se lee de vuelta el valor concedido: si el sistema recorto la peticion
/// sin quejarse (caso de Linux) se avisa, para que nadie crea que tiene 128 MB
/// de buffer cuando tiene 200 KB.
pub fn agorduBufon(
    logilo: *Logger,
    transporto: []const u8,
    sock: std.posix.socket_t,
    opcio: u32,
    kio: []const u8,
    petita: u32,
) void {
    var valoro = petita;

    std.posix.setsockopt(
        sock,
        std.posix.SOL.SOCKET,
        opcio,
        std.mem.asBytes(&valoro),
    ) catch |err| {
        logilo.warning(
            "{s}: {s} = {d} bytes rechazado por el sistema ({s}): se usa el valor por defecto",
            .{ transporto, kio, petita, @errorName(err) },
            @src(),
        );
        return;
    };

    var efektiva: c_int = 0;
    std.posix.getsockopt(
        sock,
        std.posix.SOL.SOCKET,
        opcio,
        std.mem.asBytes(&efektiva),
    ) catch return;

    if (efektiva <= 0) return;

    const concedida: u32 = @intCast(efektiva);
    if (concedida >= petita) return;

    logilo.warning(
        "{s}: {s} pedidos {d} bytes, el sistema concede {d} (limites del SO: kern.ipc.maxsockbuf en BSD, net.core.rmem_max / wmem_max en Linux)",
        .{ transporto, kio, petita, concedida },
        @src(),
    );
}
