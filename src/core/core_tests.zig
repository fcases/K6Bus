// ============================================================================
// core_tests.zig - Tests de integracion del core (R1, 2026-09-10)
// ============================================================================
//
// Portados de los harness GPA que se usaban sueltos en /tmp, ahora permanentes:
//
//   1) LoadCipher: registro ZON + key_id y sus degradaciones (sin registro,
//      id inexistente, fichero inexistente, clave caducada) -> SIEMPRE en
//      claro con aviso, nunca fallo de arranque (Directrices 8).
//   2) Ciclo de vida D1: close() de un transporte/subscriber se
//      AUTO-DESREGISTRA; unregisterTransport mantiene estado; closeTransport
//      extrae y cierra (no-op si ya no estaba); start/stop son idempotentes.
//
// Convenciones:
//   - std.testing.allocator: cualquier fuga hace fallar el test.
//   - std.testing.tmpDir: nada se escribe en el repo.
//   - Los dominios de test se crean SIN transporte por defecto y sin arrancar
//     (start_at_init = false) para no abrir sockets ni hilos de red.
//
// Se ejecutan con `zig build test` (agregados desde src/root.zig).
// ============================================================================
const std = @import("std");
const testing = std.testing;

const Domain = @import("domain.zig").Domain;
const LoopTransport = @import("loop_transport.zig").LoopTransport;
const ifcSubscriber = @import("ifc_subscriber.zig").ifcSubscriber;

const Config = @import("../generated/Config.zig").k6bus.config;
const Security = @import("../generated/Security.zig").k6bus.security;
const Msg = @import("../generated/types.zig").k6bus.Msg;

// ----------------------------------------------------------------------------
// Utilidades de test
// ----------------------------------------------------------------------------

/// Escribe un cfg ZON de un dominio (sin transporte por defecto, sin arrancar)
/// en `dir_abs/nombre`. Devuelve la ruta (owned).
fn escribirCfg(
    a: std.mem.Allocator,
    dir_abs: []const u8,
    nombre: []const u8,
    reg_file: ?[]const u8,
    key_id: ?u32,
) ![]const u8 {
    var app = try Config.AppConfig.initDefault(a);
    defer app.deinit(a);

    a.free(app.domains);
    app.domains = try a.alloc(Config.DomainConfig, 1);
    app.domains[0] = try Config.DomainConfig.initDefault(a);

    app.domains[0].id = 77;
    app.domains[0].activate_default_transport = false;
    app.domains[0].start_at_init = false;
    if (reg_file) |r| app.domains[0].key_registry_file = try a.dupe(u8, r);
    app.domains[0].key_id = key_id;

    const path = try std.fs.path.join(a, &.{ dir_abs, nombre });
    errdefer a.free(path);
    try app.skribiAlDosiero(a, path, .TF_ZIG_ZON);
    return path;
}

/// Escribe un registro ZON con UNA clave y devuelve su ruta (owned).
fn escribirRegistro(
    a: std.mem.Allocator,
    dir_abs: []const u8,
    nombre: []const u8,
    modo: Security.CryptoMode,
    key_b64: []const u8,
    expires_on: []const u8,
    key_id: u32,
) ![]const u8 {
    var reg = try Security.KeyRegistry.initDefault(a);
    defer reg.deinit(a);

    a.free(reg.description);
    reg.description = try a.dupe(u8, "registro de test");
    reg.version = 1;

    a.free(reg.keys);
    reg.keys = try a.alloc(Security.KeyRecord, 1);
    reg.keys[0] = try Security.KeyRecord.initDefault(a);
    const rec = &reg.keys[0];

    a.free(rec.key);
    rec.key = try a.dupe(u8, key_b64);
    a.free(rec.created_on);
    rec.created_on = try a.dupe(u8, "2026-01-01T00:00:00Z");
    a.free(rec.expires_on);
    rec.expires_on = try a.dupe(u8, expires_on);
    rec.mode = modo;
    rec.key_id = key_id;

    const path = try std.fs.path.join(a, &.{ dir_abs, nombre });
    errdefer a.free(path);
    try reg.skribiAlDosiero(a, path, .TF_ZIG_ZON);
    return path;
}

fn claveAleatoriaBase64(a: std.mem.Allocator) ![]u8 {
    var bruto: [32]u8 = undefined;
    std.crypto.random.bytes(&bruto);
    const b64 = std.base64.standard;
    const out = try a.alloc(u8, b64.Encoder.calcSize(bruto.len));
    _ = b64.Encoder.encode(out, &bruto);
    return out;
}

/// ¿Sigue `p` en el registro de transportes? (compara punteros, no desreferencia)
fn estaRegistrado(dom: *Domain, p: *anyopaque) bool {
    for (dom.transports.items) |tr| {
        if (tr.ptr == p) return true;
    }
    return false;
}

fn estaRegistradoSub(dom: *Domain, p: *anyopaque) bool {
    for (dom.registry.items) |reg| {
        if (reg.subscriber.ptr == p) return true;
    }
    return false;
}

// ----------------------------------------------------------------------------
// LoadCipher
// ----------------------------------------------------------------------------

test "LoadCipher: sin key_registry_file arranca en claro" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "sin_clave.zon.cfg", null, null);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_NONE, dom.cipher.mode);
}

test "LoadCipher: registro + key_id correctos -> cifrado activo y round-trip" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const key_b64 = try claveAleatoriaBase64(a);
    defer a.free(key_b64);

    const reg = try escribirRegistro(a, dir, "lab.zon.keyreg", .CRYPTO_AES_256_GCM, key_b64, "2036-01-01T00:00:00Z", 4242);
    defer a.free(reg);

    const cfg = try escribirCfg(a, dir, "con_clave.zon.cfg", reg, 4242);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_AES_256_GCM, dom.cipher.mode);

    const claro = "paquete de integracion";
    const negro = try dom.cipher.encrypt(a, claro);
    defer a.free(negro);
    const vuelta = try dom.cipher.decrypt(a, negro);
    defer a.free(vuelta);
    try testing.expectEqualStrings(claro, vuelta);
    try testing.expect(!std.mem.eql(u8, claro, negro));
}

test "LoadCipher: key_id inexistente -> en claro" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const key_b64 = try claveAleatoriaBase64(a);
    defer a.free(key_b64);

    const reg = try escribirRegistro(a, dir, "lab2.zon.keyreg", .CRYPTO_AES_256_GCM, key_b64, "2036-01-01T00:00:00Z", 4242);
    defer a.free(reg);

    const cfg = try escribirCfg(a, dir, "id_malo.zon.cfg", reg, 9999);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_NONE, dom.cipher.mode);
}

test "LoadCipher: clave caducada -> en claro" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const key_b64 = try claveAleatoriaBase64(a);
    defer a.free(key_b64);

    const reg = try escribirRegistro(a, dir, "caducada.zon.keyreg", .CRYPTO_AES_256_GCM, key_b64, "2020-02-01T00:00:00Z", 7);
    defer a.free(reg);

    const cfg = try escribirCfg(a, dir, "caducada.zon.cfg", reg, 7);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_NONE, dom.cipher.mode);
}

test "LoadCipher: fichero de registro inexistente -> en claro" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "no_fichero.zon.cfg", "no_existe.zon.keyreg", 1);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_NONE, dom.cipher.mode);
}

// ----------------------------------------------------------------------------
// Ciclo de vida D1
// ----------------------------------------------------------------------------

test "transporte: close() se autodesregistra y start/stop son idempotentes" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "d1.zon.cfg", null, null);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    const t = try LoopTransport.create(dom, "loop-test", 5);
    try dom.registerTransport(t.transport());
    try testing.expectEqual(@as(usize, 1), dom.transports.items.len);

    const p = t.transport().ptr;

    try t.start();
    try t.start(); // idempotente
    t.stop();
    t.stop(); // idempotente
    try t.start(); // se puede rearrancar tras stop

    t.close(); // destructivo + autodesregistro
    try testing.expect(!estaRegistrado(dom, p));
    try testing.expectEqual(@as(usize, 0), dom.transports.items.len);
}

test "transporte: unregisterTransport mantiene estado; closeTransport extrae y cierra" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "d1b.zon.cfg", null, null);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    // 1) desregistrar manteniendo el transporte vivo y cerrarlo despues
    const t1 = try LoopTransport.create(dom, "loop-a", 5);
    try dom.registerTransport(t1.transport());
    try t1.start();
    const p1 = t1.transport().ptr;
    dom.unregisterTransport(t1.transport());
    try testing.expect(!estaRegistrado(dom, p1));
    t1.close();

    // 2) cierre coordinado por el Domain + no-op si ya no estaba
    const t2 = try LoopTransport.create(dom, "loop-b", 5);
    try dom.registerTransport(t2.transport());
    // Copia de la interfaz ANTES de cerrar: tras closeTransport el puntero a
    // t2 ya es invalido (contrato D1) y no se puede volver a consultar.
    const ifc2 = t2.transport();
    const p2 = ifc2.ptr;
    dom.closeTransport(ifc2);
    try testing.expect(!estaRegistrado(dom, p2));
    dom.closeTransport(ifc2); // no-op (ya extraido)
}

// ----------------------------------------------------------------------------
// Subscribers (mismo contrato que los transportes)
// ----------------------------------------------------------------------------

const StubSub = struct {
    domain: *Domain,
    ifc: ifcSubscriber,

    fn create(dom: *Domain) !*StubSub {
        const self = try dom.allocator.create(StubSub);
        self.* = .{ .domain = dom, .ifc = undefined };
        self.ifc = ifcSubscriber.init(self);
        return self;
    }

    pub fn subscriber(self: *StubSub) ifcSubscriber {
        return self.ifc;
    }

    pub fn start(self: *StubSub) !void {
        _ = self;
    }

    pub fn stop(self: *StubSub) void {
        _ = self;
    }

    /// Mismo contrato que los reales: close() destructivo y autodesregistrante.
    pub fn close(self: *StubSub) void {
        self.domain.unregisterSubscriber(self.subscriber());
        self.domain.allocator.destroy(self);
    }

    pub fn enqueue(self: *StubSub, msg: Msg) !void {
        _ = self;
        _ = msg;
    }
};

test "subscriber: close() se autodesregistra" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "sub.zon.cfg", null, null);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    const s = try StubSub.create(dom);
    try dom.registerSubscriber(7, 11, s.subscriber());
    try testing.expectEqual(@as(usize, 1), dom.registry.items.len);

    const p = s.subscriber().ptr;
    s.close();
    try testing.expect(!estaRegistradoSub(dom, p));
    try testing.expectEqual(@as(usize, 0), dom.registry.items.len);
}
