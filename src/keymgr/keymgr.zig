// ============================================================================
// keymgr.zig - Logica del gestor de claves de K6Bus ("la chicha")
// ============================================================================
//
// Sin CLI ni interfaz: solo el registro y las operaciones. Lo consumen:
//   - src/keymgr/main.zig  (CLI: flags + menu interactivo por teclado)
//   - src/keymgr/gtk.zig   (FUTURO: misma API, otra cara)
//
// MODELO (decision 2026-09-10): UN FICHERO DE REGISTRO por entorno, formato
// ZON unicamente, con N KeyRecord dentro (Security.proto -> KeyRegistry):
//
//     sec/k6bus.lab.zon.keyreg      sec/k6bus.prod.zon.keyreg
//
// El dominio elige registro + clave con DomainConfig.key_registry_file +
// key_id. Sin key_id (o si no existe, o si la clave caduco) el core arranca
// SIN CIFRAR y avisa por el logger (Directrices 8).
//
// key_id: identificador "poco probable en otra maquina": hash de
// [IP local + PID + 16 bytes aleatorios], truncado a u32 y nunca 0, con
// comprobacion de no-repeticion dentro del registro.
//
// Escritura atomica: se escribe a <ruta>.tmp y se renombra sobre el registro.
// ============================================================================
const std = @import("std");
const builtin = @import("builtin");

const k6bus = @import("k6bus");
const KeyRecord = k6bus.Security.KeyRecord;
const KeyRegistry = k6bus.Security.KeyRegistry;
const CryptoMode = k6bus.Security.CryptoMode;

pub const RUTA_DEFECTO = "sec/k6bus.lab.zon.keyreg";
pub const SUFIJO_REGISTRO = ".zon.keyreg";
pub const DIAS_DEFECTO: u32 = 90;
/// AES-256-GCM y ChaCha20-Poly1305 usan clave de 32 bytes.
pub const CLAVE_LEN: usize = 32;
/// Aviso cuando quedan estos dias o menos.
pub const AVISO_DIAS: i64 = 7;

pub const Error = error{
    ClaveNoEncontrada,
    RegistroInvalido,
    ModoNoSoportado,
    DiasInvalidos,
};

pub const Modo = enum {
    gcm,
    chacha,

    pub fn aCrypto(self: Modo) CryptoMode {
        return switch (self) {
            .gcm => .CRYPTO_AES_256_GCM,
            .chacha => .CRYPTO_CHACHA20_POLY1305,
        };
    }

    pub fn eliji(nomo: []const u8) ?Modo {
        if (std.ascii.eqlIgnoreCase(nomo, "gcm")) return .gcm;
        if (std.ascii.eqlIgnoreCase(nomo, "aes")) return .gcm;
        if (std.ascii.eqlIgnoreCase(nomo, "aes256gcm")) return .gcm;
        if (std.ascii.eqlIgnoreCase(nomo, "chacha")) return .chacha;
        if (std.ascii.eqlIgnoreCase(nomo, "chacha20poly1305")) return .chacha;
        return null;
    }
};

/// Resumen de una clave para listar (campos PRESTADOS del registro).
pub const Resumen = struct {
    key_id: u32,
    modo: CryptoMode,
    descripcion: []const u8,
    created_on: []const u8,
    expires_on: []const u8,
    dias_restantes: i64,
    caducada: bool,
    /// Ya se puede usar (dentro de ventana).
    activa: bool,
};

/// Registro de claves abierto (fichero + contenido en memoria).
pub const Registro = struct {
    allocator: std.mem.Allocator,
    ruta: []const u8, // owned
    description: []const u8, // owned
    version: u32,
    keys: std.ArrayList(KeyRecord), // owned (records y sus strings)
    creado_ahora: bool,

    const Self = @This();

    /// Abre el registro; si no existe lo crea vacio (con esa descripcion).
    pub fn abrir(allocator: std.mem.Allocator, ruta: []const u8, descripcion_nueva: []const u8) !Self {
        if (!std.mem.endsWith(u8, ruta, SUFIJO_REGISTRO)) {
            return Error.RegistroInvalido;
        }

        const ruta_owned = try allocator.dupe(u8, ruta);
        // OJO: el errdefer de self.deinit() ya libera ruta_owned (no anadir otro).

        // Asegura el directorio del registro (p.ej. sec/).
        if (std.fs.path.dirname(ruta_owned)) |dir| {
            if (dir.len > 0) try std.fs.cwd().makePath(dir);
        }

        var self = Self{
            .allocator = allocator,
            .ruta = ruta_owned,
            .description = &.{},
            .version = 1,
            .keys = .empty,
            .creado_ahora = false,
        };
        errdefer self.deinit();

        if (std.fs.cwd().access(ruta_owned, .{})) |_| {
            try self.cargarDeDisco();
        } else |_| {
            self.description = try allocator.dupe(u8, descripcion_nueva);
            self.creado_ahora = true;
            try self.guardar();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.ruta);
        if (self.description.len > 0) self.allocator.free(self.description);
        for (self.keys.items) |*rec| rec.deinit(self.allocator);
        self.keys.deinit(self.allocator);
    }

    /// Lee el registro ZON del disco y MUEVE sus records a nuestra lista.
    fn cargarDeDisco(self: *Self) !void {
        const reg = try KeyRegistry.legiElDosiero(self.allocator, self.ruta, .TF_ZIG_ZON);

        // Posesion: nos quedamos con los records y con la description como
        // propios; liberamos los CONTENEDORES del registro leido sin llamar a
        // su deinit (evita doble free de los records ya movidos).
        self.description = try self.allocator.dupe(u8, reg.description);
        self.version = reg.version;

        for (reg.keys) |rec| {
            try self.keys.append(self.allocator, rec);
        }

        if (reg.keys.len > 0) self.allocator.free(reg.keys);
        if (reg.description.len > 0) self.allocator.free(reg.description);
    }

    /// Escribe el registro completo de forma atomica (tmp + rename).
    pub fn guardar(self: *Self) !void {
        const tmp = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.ruta});
        defer self.allocator.free(tmp);

        // Vista prestada: NO se libera (los records son de la lista).
        var vista = KeyRegistry{
            .version = self.version,
            .description = self.description,
            .keys = self.keys.items,
        };
        try vista.skribiAlDosiero(self.allocator, tmp, .TF_ZIG_ZON);

        try std.fs.cwd().rename(tmp, self.ruta);
    }

    /// Resumen de todas las claves (ordenado por key_id). Caller libera el slice.
    pub fn listar(self: *const Self) ![]Resumen {
        const out = try self.allocator.alloc(Resumen, self.keys.items.len);
        errdefer self.allocator.free(out);

        const ahora = std.time.timestamp();
        for (self.keys.items, 0..) |rec, i| {
            out[i] = .{
                .key_id = rec.key_id,
                .modo = rec.mode,
                .descripcion = rec.description orelse "",
                .created_on = rec.created_on,
                .expires_on = rec.expires_on,
                .dias_restantes = diasHasta(rec.expires_on, ahora),
                .caducada = caducada(rec.expires_on, ahora),
                .activa = activa(rec, ahora),
            };
        }
        std.mem.sort(Resumen, out, {}, porId);
        return out;
    }

    fn porId(_: void, a: Resumen, b: Resumen) bool {
        return a.key_id < b.key_id;
    }

    pub fn buscar(self: *Self, key_id: u32) ?*KeyRecord {
        for (self.keys.items) |*rec| {
            if (rec.key_id == key_id) return rec;
        }
        return null;
    }

    /// Crea una clave nueva (32 bytes aleatorios en Base64) con ventana
    /// [ahora, ahora + dias]. Devuelve su key_id.
    pub fn crear(self: *Self, dias: u32, modo: Modo, descripcion: ?[]const u8) !u32 {
        if (dias == 0) return Error.DiasInvalidos;

        var bruto: [CLAVE_LEN]u8 = undefined;
        std.crypto.random.bytes(&bruto);
        defer {
            @memset(bruto[0..], 0);
            std.mem.doNotOptimizeAway(&bruto);
        }

        const b64 = std.base64.standard;
        const clave_b64 = try self.allocator.alloc(u8, b64.Encoder.calcSize(CLAVE_LEN));
        defer self.allocator.free(clave_b64);
        _ = b64.Encoder.encode(clave_b64, &bruto);

        const ahora = std.time.timestamp();
        const creada = try formatearIso(self.allocator, ahora);
        defer self.allocator.free(creada);
        const expira = try formatearIso(self.allocator, ahora + @as(i64, dias) * 24 * 60 * 60);
        defer self.allocator.free(expira);

        var rec = try KeyRecord.initDefault(self.allocator);
        errdefer rec.deinit(self.allocator);

        self.allocator.free(rec.key);
        rec.key = try self.allocator.dupe(u8, clave_b64);
        self.allocator.free(rec.created_on);
        rec.created_on = try self.allocator.dupe(u8, creada);
        self.allocator.free(rec.expires_on);
        rec.expires_on = try self.allocator.dupe(u8, expira);
        rec.mode = modo.aCrypto();
        rec.key_id = self.nuevoId();
        if (descripcion) |d| {
            if (rec.description) |old| self.allocator.free(old);
            rec.description = try self.allocator.dupe(u8, d);
        }

        try self.keys.append(self.allocator, rec);
        try self.guardar();

        return rec.key_id;
    }

    /// Borra una clave del registro (y del disco).
    pub fn borrar(self: *Self, key_id: u32) !void {
        for (self.keys.items, 0..) |*rec, i| {
            if (rec.key_id != key_id) continue;

            const quitada = self.keys.orderedRemove(i);
            quitada.deinit(self.allocator);
            try self.guardar();
            return;
        }
        return Error.ClaveNoEncontrada;
    }

    /// key_id "poco probable en otra maquina": hash(IP + PID + 16B aleatorios).
    fn nuevoId(self: *Self) u32 {
        var intento: usize = 0;
        while (intento < 8) : (intento += 1) {
            var ale: [16]u8 = undefined;
            std.crypto.random.bytes(&ale);

            var h = std.hash.XxHash3.init(0);

            var ip_buf: [16]u8 = undefined;
            if (ipLocal(&ip_buf)) |ip| h.update(ip);

            var pid_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &pid_buf, @intCast(getPid()), .little);
            h.update(&pid_buf);

            h.update(&ale);

            const truncado: u32 = @truncate(h.final());
            const id = if (truncado == 0) 1 else truncado;

            if (self.buscar(id) == null) return id;
        }
        // Colision repetida (improbable): desviar para no repetir id.
        return (self.nuevoIdSimple() | 1);
    }

    fn nuevoIdSimple(self: *Self) u32 {
        var max: u32 = 0;
        for (self.keys.items) |rec| {
            if (rec.key_id > max) max = rec.key_id;
        }
        return max +% 1;
    }
};

// ----------------------------------------------------------------------------
// Identidad de maquina
// ----------------------------------------------------------------------------

/// IP local (IPv4) via socket UDP conectado sin enviar nada. null si no se pudo.
fn ipLocal(buf: *[16]u8) ?[]const u8 {
    const sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch return null;
    defer std.posix.close(sock);

    var destino: std.posix.sockaddr.in = .{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, 53),
        .addr = std.mem.nativeToBig(u32, 0x08080808), // 8.8.8.8 (no se envia nada)
    };

    std.posix.connect(sock, @ptrCast(&destino), @sizeOf(std.posix.sockaddr.in)) catch return null;

    var local: std.posix.sockaddr.in = undefined;
    var len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    std.posix.getsockname(sock, @ptrCast(&local), &len) catch return null;

    const bytes: [4]u8 = @bitCast(local.addr);
    const txt = std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch return null;
    return txt;
}

fn getPid() u32 {
    // TODO(BSD/Windows): igual que en udp_transport.zig.
    if (builtin.os.tag == .windows or builtin.os.tag == .freebsd or builtin.os.tag == .openbsd or builtin.os.tag == .netbsd)
        return 0;
    return @intCast(std.os.linux.getpid());
}

// ----------------------------------------------------------------------------
// Tiempo: ISO 8601 UTC ("YYYY-MM-DDTHH:MM:SSZ"), orden lexicografico
// ----------------------------------------------------------------------------

pub fn formatearIso(allocator: std.mem.Allocator, segs: i64) ![]const u8 {
    const epoch = std.time.epoch;
    const es = epoch.EpochSeconds{ .secs = @intCast(segs) };
    const dia = es.getEpochDay();
    const yd = dia.calculateYearDay();
    const md = yd.calculateMonthDay();
    const tod = es.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        @intFromEnum(md.month),
        md.day_index + 1,
        tod.getHoursIntoDay(),
        tod.getMinutesIntoHour(),
        tod.getSecondsIntoMinute(),
    });
}

/// "YYYY-MM-DDTHH:MM:SSZ" -> epoch UTC (null si no encaja).
pub fn parsearIso(iso: []const u8) ?i64 {
    if (iso.len != 20) return null;
    if (iso[4] != '-' or iso[7] != '-' or iso[10] != 'T' or iso[13] != ':' or iso[16] != ':' or iso[19] != 'Z') return null;

    const year = std.fmt.parseInt(u16, iso[0..4], 10) catch return null;
    const mes = std.fmt.parseInt(u8, iso[5..7], 10) catch return null;
    const dia = std.fmt.parseInt(u8, iso[8..10], 10) catch return null;
    const hora = std.fmt.parseInt(u8, iso[11..13], 10) catch return null;
    const min = std.fmt.parseInt(u8, iso[14..16], 10) catch return null;
    const seg = std.fmt.parseInt(u8, iso[17..19], 10) catch return null;
    if (mes < 1 or mes > 12 or dia < 1 or dia > 31) return null;
    if (hora > 23 or min > 59 or seg > 60) return null;

    const dias_mes = [12]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var dias: i64 = 0;
    var y: u16 = 1970;
    while (y < year) : (y += 1) dias += if (bisiesto(y)) 366 else 365;
    var m: u8 = 1;
    while (m < mes) : (m += 1) {
        dias += dias_mes[m - 1];
        if (m == 2 and bisiesto(year)) dias += 1;
    }
    dias += @as(i64, dia) - 1;
    return dias * 24 * 60 * 60 + @as(i64, hora) * 3600 + @as(i64, min) * 60 + seg;
}

fn bisiesto(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// La clave ya no es valida (paso expires_on).
pub fn caducada(expires_on: []const u8, ahora: i64) bool {
    const t = parsearIso(expires_on) orelse return false;
    return ahora >= t;
}

/// Dias que faltan (negativo si ya paso).
pub fn diasHasta(expires_on: []const u8, ahora: i64) i64 {
    const t = parsearIso(expires_on) orelse return 0;
    return @divFloor(t - ahora, 24 * 60 * 60);
}

/// Dentro de la ventana [created_on, expires_on).
pub fn activa(rec: KeyRecord, ahora: i64) bool {
    const ini = parsearIso(rec.created_on) orelse return false;
    const fin = parsearIso(rec.expires_on) orelse return false;
    return ahora >= ini and ahora < fin;
}
