// ============================================================================
// socket_auks.zig - Socket helpers shared by the transports
// ============================================================================
const std = @import("std");

const Logger = @import("logger.zig").Logger;

/// Requests a socket buffer size (SO_RCVBUF / SO_SNDBUF).
///
/// Buffer sizes are a performance HINT, not a correctness requirement,
/// and every system limits them in its own way:
///   - Linux silently trims them to net.core.rmem_max / wmem_max.
///   - FreeBSD returns ENOBUFS if more than kern.ipc.maxsockbuf is
///     requested (2 MB by default).
/// Treating that rejection as a fatal error killed domain startup on
/// FreeBSD (F10, 2026-09-15): 134217727 (128 MB) was requested and the
/// setsockopt failed -> error.SystemResources. Now it warns and goes on:
/// the socket keeps the system default, the only value it can give.
///
/// The granted value is also read back: if the system trimmed the request
/// without complaining (Linux case) it warns, so nobody believes it has 128
/// MB of buffer when it really has 200 KB.
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
