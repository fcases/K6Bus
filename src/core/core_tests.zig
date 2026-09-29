// ============================================================================
// core_tests.zig - Core integration tests
// ============================================================================
//
// Ported from the GPA harnesses that were used loose in /tmp, now permanent:
//
//   1) LoadCipher: ZON registry + key_id and its degradations (no registry,
//      nonexistent id, nonexistent file, expired key) -> ALWAYS in the clear
//      with a warning, never a startup failure (Guidelines 8).
// 2) lifecycle: close() of a transport/subscriber SELF-UNREGISTERS;
//      unregisterTransport keeps state; closeTransport extracts and closes
//      (no-op if it was no longer there); start/stop are idempotent.
//
// Conventions:
//   - std.testing.allocator: any leak makes the test fail.
//   - std.testing.tmpDir: nothing is written into the repo.
//   - Test domains are created WITHOUT a default transport and not started
//     (start_at_init = false) so no sockets or network threads are opened.
//
// They run with `zig build test` (aggregated from src/root.zig).
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
// Test utilities
// ----------------------------------------------------------------------------

/// Writes a domain ZON cfg (no default transport, not started) into
/// `dir_abs/nombre`. Returns the path (owned).
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

/// Writes a ZON registry with ONE key and returns its path (owned).
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

/// Is `p` still in the transports registry? (pointer compare, no dereference)
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
    try t.start(); // idempotent
    t.stop();
    t.stop(); // idempotent
    try t.start(); // can be restarted after stop

    t.close(); // destructive + self-unregister
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

    // 1) unregister keeping the transport alive and close it afterwards
    const t1 = try LoopTransport.create(dom, "loop-a", 5);
    try dom.registerTransport(t1.transport());
    try t1.start();
    const p1 = t1.transport().ptr;
    dom.unregisterTransport(t1.transport());
    try testing.expect(!estaRegistrado(dom, p1));
    t1.close();

    // 2) close coordinated by the Domain + no-op if it was no longer there
    const t2 = try LoopTransport.create(dom, "loop-b", 5);
    try dom.registerTransport(t2.transport());
    // Copy of the interface BEFORE closing: after closeTransport the pointer
    // to t2 is already invalid (contract) and cannot be queried again.
    const ifc2 = t2.transport();
    const p2 = ifc2.ptr;
    dom.closeTransport(ifc2);
    try testing.expect(!estaRegistrado(dom, p2));
    dom.closeTransport(ifc2); // no-op (already extracted)
}

// ----------------------------------------------------------------------------
// Subscribers (same contract as the transports)
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

    /// Same contract as the real ones: destructive, self-unregistering close().
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

test "the registry stays ordered by (channel, msgType)" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    const cfg = try escribirCfg(a, dir, "r4.zon.cfg", null, null);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    const s1 = try StubSub.create(dom);
    const s2 = try StubSub.create(dom);
    const s3 = try StubSub.create(dom);
    const s4 = try StubSub.create(dom);

    // Registered deliberately out of order: the registry must keep them sorted
    // by (channel, msgType), which is what makes the indexed dispatch work.
    try dom.registerSubscriber(9, 2, s1.subscriber());
    try dom.registerSubscriber(3, 5, s2.subscriber());
    try dom.registerSubscriber(3, 1, s3.subscriber());
    try dom.registerSubscriber(9, 1, s4.subscriber());

    try testing.expectEqual(@as(usize, 4), dom.registry.items.len);
    const esperado = [_][2]u64{ .{ 3, 1 }, .{ 3, 5 }, .{ 9, 1 }, .{ 9, 2 } };
    for (dom.registry.items, 0..) |entry, i| {
        try testing.expectEqual(esperado[i][0], entry.channel);
        try testing.expectEqual(esperado[i][1], entry.msgType);
    }

    // registryIndex returns the start of the run of matching entries (the first
    // entry >= the key), which is exactly what the dispatch walks.
    try testing.expectEqual(@as(usize, 0), dom.registryIndex(3, 1));
    try testing.expectEqual(@as(usize, 1), dom.registryIndex(3, 5));
    try testing.expectEqual(@as(usize, 2), dom.registryIndex(9, 1));
    try testing.expectEqual(@as(usize, 4), dom.registryIndex(9, 3)); // past the end
    try testing.expectEqual(@as(usize, 2), dom.registryIndex(5, 1)); // gap: next key

    // Remove from the middle: the order must survive (orderedRemove, never
    // swapRemove), and the lookup must still point at the right run.
    dom.unregisterSubscriber(s2.subscriber());
    try testing.expectEqual(@as(usize, 3), dom.registry.items.len);
    try testing.expectEqual(@as(u64, 3), dom.registry.items[0].channel);
    try testing.expectEqual(@as(u64, 1), dom.registry.items[0].msgType);
    try testing.expectEqual(@as(u64, 9), dom.registry.items[1].channel);
    try testing.expectEqual(@as(usize, 1), dom.registryIndex(9, 0));

    // closeSubscriber() removes through takeSubscriber(): the order must
    // survive there too, and the lookup must still point at the right run.
    dom.closeSubscriber(s3.subscriber());
    try testing.expectEqual(@as(usize, 2), dom.registry.items.len);
    try testing.expectEqual(@as(u64, 9), dom.registry.items[0].channel);
    try testing.expectEqual(@as(u64, 1), dom.registry.items[0].msgType);

    s1.close();
    s2.close();
    s4.close();
    try testing.expectEqual(@as(usize, 0), dom.registry.items.len);
}

/// Hand-writes a ZON cfg with ONE UDPSTAR transport (literal text, not
/// relying on the generated oneof API). It does not start the domain: only
/// the sockets are created. `con_defecto` also adds the default MCast or not.
fn escribirCfgUdpstar(
    a: std.mem.Allocator,
    dir_abs: []const u8,
    nombre: []const u8,
    local_address: []const u8,
    con_defecto: bool,
    send_buffer: u32,
    receive_buffer: u32,
) ![]const u8 {
    const texto = try std.fmt.allocPrint(a,
        \\.{{
        \\    .version = 1,
        \\    .activate_trace = false,
        \\    .trace_level = 0,
        \\    .domains = .{{
        \\        .{{
        \\            .id = 77,
        \\            .activate_default_transport = {s},
        \\            .direct_dispatch_to_subs = false,
        \\            .key_registry_file = null,
        \\            .key_id = null,
        \\            .binary_format = .BF_PROTOBUF,
        \\            .start_at_init = false,
        \\            .dispatch_mode = .IMMEDIATE,
        \\            .dispatch_batch_time_ms = 0,
        \\            .transports = .{{
        \\                .{{
        \\                    .name = "udpstar-test",
        \\                    .kind = .UDPSTAR,
        \\                    .params = .{{
        \\                        .udpstar = .{{
        \\                            .local_address = "{s}",
        \\                            .port = 40071,
        \\                            .end_points = .{{
        \\                                .{{ .host = "127.0.0.1", .port = 40072 }},
        \\                            }},
        \\                            .send_buffer = {d},
        \\                            .receive_buffer = {d},
        \\                        }},
        \\                    }},
        \\                }},
        \\            }},
        \\            .cross_connectors = .{{}},
        \\        }},
        \\    }},
        \\}}
        \\
    , .{
        if (con_defecto) "true" else "false",
        local_address,
        send_buffer,
        receive_buffer,
    });
    defer a.free(texto);

    const path = try std.fs.path.join(a, &.{ dir_abs, nombre });
    errdefer a.free(path);
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = texto });
    return path;
}

test "un buffer de socket absurdo no impide crear el dominio (aviso y se sigue)" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    // 134217727 = 128 MB - 1: an absurd value ON PURPOSE. On FreeBSD it made
    // setsockopt fail with ENOBUFS (error.SystemResources) and took the
    // startup down; on Linux the kernel silently trims it. The real cfg
    // default is 2097152 (2 MiB).
    const cfg = try escribirCfgUdpstar(a, dir, "buf.zon.cfg", "Any", false, 134217727, 134217727);
    defer a.free(cfg);

    var dom = try Domain.createFromFileEx(a, 77, cfg, null, null);
    defer dom.close();

    try testing.expectEqual(@as(usize, 1), dom.transports.items.len);
}

test "un fallo al crear un transporte no filtra lo ya creado" {
    const a = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(dir);

    // invalid local_address: it fails INSIDE createEx, when the domain
    // already has queues, logger, the registered default MCast and the
    // lists. std.testing.allocator turns any leak into a test failure.
    const cfg = try escribirCfgUdpstar(a, dir, "malo.zon.cfg", "999.999.999.999", true, 1 * 1024 * 1024, 1 * 1024 * 1024);
    defer a.free(cfg);

    if (Domain.createFromFileEx(a, 77, cfg, null, null)) |dom| {
        dom.close();
        return error.DeberiaHaberFallado;
    } else |err| {
        // The exact error comes from std: parseIp4 returns error.Overflow for
        // an octet > 255 (error.InvalidCharacter for garbage, InvalidEnd if
        // there are extra octets). What matters here is that creation fails
        // WITHOUT leaking what was already created, and std.testing.allocator
        // verifies that when the test finishes.
        try testing.expectEqual(error.Overflow, err);
    }
}
