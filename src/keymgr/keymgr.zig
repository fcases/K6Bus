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

pub const DEFAULT_PATH = "sec/k6bus.lab.zon.keyreg";
pub const REGISTRY_SUFFIX = ".zon.keyreg";
pub const DEFAULT_DAYS: u32 = 90;
/// AES-256-GCM y ChaCha20-Poly1305 usan clave de 32 bytes.
pub const KEY_LEN: usize = 32;
/// Aviso cuando quedan estos dias o menos.
pub const WARN_DAYS: i64 = 7;

pub const Error = error{
    KeyNotFound,
    InvalidRegistry,
    ModeNotSupported,
    InvalidDays,
};

pub const Mode = enum {
    gcm,
    chacha,

    pub fn toCrypto(self: Mode) CryptoMode {
        return switch (self) {
            .gcm => .CRYPTO_AES_256_GCM,
            .chacha => .CRYPTO_CHACHA20_POLY1305,
        };
    }

    pub fn fromName(name: []const u8) ?Mode {
        if (std.ascii.eqlIgnoreCase(name, "gcm")) return .gcm;
        if (std.ascii.eqlIgnoreCase(name, "aes")) return .gcm;
        if (std.ascii.eqlIgnoreCase(name, "aes256gcm")) return .gcm;
        if (std.ascii.eqlIgnoreCase(name, "chacha")) return .chacha;
        if (std.ascii.eqlIgnoreCase(name, "chacha20poly1305")) return .chacha;
        return null;
    }
};

/// Resumen de una clave para listar (campos PRESTADOS del registro).
pub const Summary = struct {
    key_id: u32,
    mode: CryptoMode,
    description: []const u8,
    created_on: []const u8,
    expires_on: []const u8,
    days_left: i64,
    expired: bool,
    /// Ya se puede usar (dentro de ventana).
    active: bool,
};

/// Registro de claves abierto (fichero + contenido en memoria).
pub const Registry = struct {
    allocator: std.mem.Allocator,
    path: []const u8, // owned
    description: []const u8, // owned
    version: u32,
    keys: std.ArrayList(KeyRecord), // owned (records y sus strings)
    created_now: bool,

    const Self = @This();

    /// Abre el registro; si no existe lo crea vacio (con esa descripcion).
    pub fn open(allocator: std.mem.Allocator, path: []const u8, descripcion_nueva: []const u8) !Self {
        if (!std.mem.endsWith(u8, path, REGISTRY_SUFFIX)) {
            return Error.InvalidRegistry;
        }

        const path_owned = try allocator.dupe(u8, path);
        // OJO: el errdefer de self.deinit() ya libera path_owned (no anadir otro).

        // Asegura el directorio del registro (p.ej. sec/).
        if (std.fs.path.dirname(path_owned)) |dir| {
            if (dir.len > 0) try std.fs.cwd().makePath(dir);
        }

        var self = Self{
            .allocator = allocator,
            .path = path_owned,
            .description = &.{},
            .version = 1,
            .keys = .empty,
            .created_now = false,
        };
        errdefer self.deinit();

        if (std.fs.cwd().access(path_owned, .{})) |_| {
            try self.loadFromDisk();
        } else |_| {
            self.description = try allocator.dupe(u8, descripcion_nueva);
            self.created_now = true;
            try self.save();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
        if (self.description.len > 0) self.allocator.free(self.description);
        for (self.keys.items) |*rec| rec.deinit(self.allocator);
        self.keys.deinit(self.allocator);
    }

    /// Lee el registro ZON del disco y MUEVE sus records a nuestra lista.
    fn loadFromDisk(self: *Self) !void {
        const reg = try KeyRegistry.legiElDosiero(self.allocator, self.path, .TF_ZIG_ZON);

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
    pub fn save(self: *Self) !void {
        const tmp = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.path});
        defer self.allocator.free(tmp);

        // Vista prestada: NO se libera (los records son de la lista).
        var view = KeyRegistry{
            .version = self.version,
            .description = self.description,
            .keys = self.keys.items,
        };
        try view.skribiAlDosiero(self.allocator, tmp, .TF_ZIG_ZON);

        try std.fs.cwd().rename(tmp, self.path);
    }

    /// Resumen de todas las claves (ordenado por key_id). Caller libera el slice.
    pub fn list(self: *const Self) ![]Summary {
        const out = try self.allocator.alloc(Summary, self.keys.items.len);
        errdefer self.allocator.free(out);

        const now = std.time.timestamp();
        for (self.keys.items, 0..) |rec, i| {
            out[i] = .{
                .key_id = rec.key_id,
                .mode = rec.mode,
                .description = rec.description orelse "",
                .created_on = rec.created_on,
                .expires_on = rec.expires_on,
                .days_left = daysUntil(rec.expires_on, now),
                .expired = expired(rec.expires_on, now),
                .active = active(rec, now),
            };
        }
        std.mem.sort(Summary, out, {}, byId);
        return out;
    }

    fn byId(_: void, a: Summary, b: Summary) bool {
        return a.key_id < b.key_id;
    }

    pub fn find(self: *Self, key_id: u32) ?*KeyRecord {
        for (self.keys.items) |*rec| {
            if (rec.key_id == key_id) return rec;
        }
        return null;
    }

    /// Crea una clave nueva (32 bytes aleatorios en Base64) con ventana
    /// [now, now + days]. Devuelve su key_id.
    pub fn create(self: *Self, days: u32, mode: Mode, description: ?[]const u8) !u32 {
        if (days == 0) return Error.InvalidDays;

        var raw: [KEY_LEN]u8 = undefined;
        std.crypto.random.bytes(&raw);
        defer {
            @memset(raw[0..], 0);
            std.mem.doNotOptimizeAway(&raw);
        }

        const b64 = std.base64.standard;
        const key_b64 = try self.allocator.alloc(u8, b64.Encoder.calcSize(KEY_LEN));
        defer self.allocator.free(key_b64);
        _ = b64.Encoder.encode(key_b64, &raw);

        const now = std.time.timestamp();
        const created = try formatIso(self.allocator, now);
        defer self.allocator.free(created);
        const expires_at = try formatIso(self.allocator, now + @as(i64, days) * 24 * 60 * 60);
        defer self.allocator.free(expires_at);

        var rec = try KeyRecord.initDefault(self.allocator);
        errdefer rec.deinit(self.allocator);

        self.allocator.free(rec.key);
        rec.key = try self.allocator.dupe(u8, key_b64);
        self.allocator.free(rec.created_on);
        rec.created_on = try self.allocator.dupe(u8, created);
        self.allocator.free(rec.expires_on);
        rec.expires_on = try self.allocator.dupe(u8, expires_at);
        rec.mode = mode.toCrypto();
        rec.key_id = self.newId();
        if (description) |d| {
            if (rec.description) |old| self.allocator.free(old);
            rec.description = try self.allocator.dupe(u8, d);
        }

        try self.keys.append(self.allocator, rec);
        try self.save();

        return rec.key_id;
    }

    /// Borra una clave del registro (y del disco).
    pub fn remove(self: *Self, key_id: u32) !void {
        for (self.keys.items, 0..) |*rec, i| {
            if (rec.key_id != key_id) continue;

            const removed = self.keys.orderedRemove(i);
            removed.deinit(self.allocator);
            try self.save();
            return;
        }
        return Error.KeyNotFound;
    }

    /// key_id "poco probable en otra maquina": hash(IP + PID + 16B aleatorios).
    fn newId(self: *Self) u32 {
        var attempt: usize = 0;
        while (attempt < 8) : (attempt += 1) {
            var random_bytes: [16]u8 = undefined;
            std.crypto.random.bytes(&random_bytes);

            var h = std.hash.XxHash3.init(0);

            var ip_buf: [16]u8 = undefined;
            if (localIp(&ip_buf)) |ip| h.update(ip);

            var pid_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &pid_buf, @intCast(getPid()), .little);
            h.update(&pid_buf);

            h.update(&random_bytes);

            const truncated: u32 = @truncate(h.final());
            const id = if (truncated == 0) 1 else truncated;

            if (self.find(id) == null) return id;
        }
        // Colision repetida (improbable): desviar para no repetir id.
        return (self.newSequentialId() | 1);
    }

    fn newSequentialId(self: *Self) u32 {
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
fn localIp(buf: *[16]u8) ?[]const u8 {
    const sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch return null;
    defer std.posix.close(sock);

    var destination: std.posix.sockaddr.in = .{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, 53),
        .addr = std.mem.nativeToBig(u32, 0x08080808), // 8.8.8.8 (no se envia nada)
    };

    std.posix.connect(sock, @ptrCast(&destination), @sizeOf(std.posix.sockaddr.in)) catch return null;

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

pub fn formatIso(allocator: std.mem.Allocator, secs: i64) ![]const u8 {
    const epoch = std.time.epoch;
    const es = epoch.EpochSeconds{ .secs = @intCast(secs) };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
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
pub fn parseIso(iso: []const u8) ?i64 {
    if (iso.len != 20) return null;
    if (iso[4] != '-' or iso[7] != '-' or iso[10] != 'T' or iso[13] != ':' or iso[16] != ':' or iso[19] != 'Z') return null;

    const year = std.fmt.parseInt(u16, iso[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, iso[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, iso[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, iso[11..13], 10) catch return null;
    const min = std.fmt.parseInt(u8, iso[14..16], 10) catch return null;
    const sec = std.fmt.parseInt(u8, iso[17..19], 10) catch return null;
    if (month < 1 or month > 12 or day < 1 or day > 31) return null;
    if (hour > 23 or min > 59 or sec > 60) return null;

    const days_in_month = [12]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var days: i64 = 0;
    var y: u16 = 1970;
    while (y < year) : (y += 1) days += if (isLeapYear(y)) 366 else 365;
    var m: u8 = 1;
    while (m < month) : (m += 1) {
        days += days_in_month[m - 1];
        if (m == 2 and isLeapYear(year)) days += 1;
    }
    days += @as(i64, day) - 1;
    return days * 24 * 60 * 60 + @as(i64, hour) * 3600 + @as(i64, min) * 60 + sec;
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// La clave ya no es valida (paso expires_on).
pub fn expired(expires_on: []const u8, now: i64) bool {
    const t = parseIso(expires_on) orelse return false;
    return now >= t;
}

/// Dias que faltan (negativo si ya paso).
pub fn daysUntil(expires_on: []const u8, now: i64) i64 {
    const t = parseIso(expires_on) orelse return 0;
    return @divFloor(t - now, 24 * 60 * 60);
}

/// Dentro de la ventana [created_on, expires_on).
pub fn active(rec: KeyRecord, now: i64) bool {
    const start = parseIso(rec.created_on) orelse return false;
    const end = parseIso(rec.expires_on) orelse return false;
    return now >= start and now < end;
}
