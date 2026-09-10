const std = @import("std");
const Security = @import("../generated/Security.zig").k6bus.security;

pub const EncryptFn =
    *const fn (
        self: *const Cipher,
        allocator: std.mem.Allocator,
        red_bytes: []const u8,
    ) anyerror![]const u8;

pub const DecryptFn =
    *const fn (
        self: *const Cipher,
        allocator: std.mem.Allocator,
        black_bytes: []const u8,
    ) anyerror![]const u8;

pub const Cipher = struct {
    allocator: std.mem.Allocator,
    mode: Security.CryptoMode,

    key: []u8,

    encrypt_fn: EncryptFn,
    decrypt_fn: DecryptFn,

    const Self = @This();

    // --------------------------------------------------------
    // Public API
    // --------------------------------------------------------
    pub fn createNoCipher(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .mode = .CRYPTO_NONE,

            .key = try allocator.alloc(u8, 0),

            .encrypt_fn = identityEncrypt,
            .decrypt_fn = identityDecrypt,
        };
    }

    pub fn create(allocator: std.mem.Allocator, key_registry: Security.KeyRecord) !Self {
        const key_bytes = try decodeBase64(allocator, key_registry.key);
        errdefer allocator.free(key_bytes);

        var self = Self{
            .allocator = allocator,
            .mode = key_registry.mode,

            .key = key_bytes,

            .encrypt_fn = identityEncrypt,
            .decrypt_fn = identityDecrypt,
        };

        switch (self.mode) {
            .CRYPTO_NONE => {
                self.encrypt_fn = identityEncrypt;
                self.decrypt_fn = identityDecrypt;
            },

            .CRYPTO_AES_256_GCM => {
                if (key_bytes.len != aead_key_len)
                    return error.InvalidKeyLength;
                self.encrypt_fn = aes256GcmEncrypt;
                self.decrypt_fn = aes256GcmDecrypt;
            },

            .CRYPTO_CHACHA20_POLY1305 => {
                if (key_bytes.len != aead_key_len)
                    return error.InvalidKeyLength;
                self.encrypt_fn = chacha20Poly1305Encrypt;
                self.decrypt_fn = chacha20Poly1305Decrypt;
            },

            // Reservado: implementacion propia inyectada (sin dlopen por ahora).
            .CRYPTO_CUSTOM => return error.CustomCipherNotSupported,
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.key);

        self.key = &.{};
    }

    pub fn encrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        return self.encrypt_fn(self, allocator, red_bytes);
    }

    pub fn decrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        return self.decrypt_fn(self, allocator, black_bytes);
    }

    // --------------------------------------------------------
    // Identity
    // --------------------------------------------------------
    fn identityEncrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        _ = self;

        return try allocator.dupe(u8, red_bytes);
    }

    fn identityDecrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        _ = self;

        return try allocator.dupe(u8, black_bytes);
    }

    // --------------------------------------------------------
    // AES-256-GCM
    // --------------------------------------------------------
    fn aes256GcmEncrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        return try aeadEncrypt(std.crypto.aead.aes_gcm.Aes256Gcm, self.key, allocator, red_bytes);
    }

    fn aes256GcmDecrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        return try aeadDecrypt(std.crypto.aead.aes_gcm.Aes256Gcm, self.key, allocator, black_bytes);
    }

    // --------------------------------------------------------
    // CHACHA20-POLY1305
    // --------------------------------------------------------
    fn chacha20Poly1305Encrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        return try aeadEncrypt(std.crypto.aead.chacha_poly.ChaCha20Poly1305, self.key, allocator, red_bytes);
    }

    fn chacha20Poly1305Decrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        return try aeadDecrypt(std.crypto.aead.chacha_poly.ChaCha20Poly1305, self.key, allocator, black_bytes);
    }

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------
    // --------------------------------------------------------
    // AEAD (AES-256-GCM y ChaCha20-Poly1305)
    // --------------------------------------------------------
    // Formato en el wire:
    //     [nonce 12][ciphertext len(red)][tag 16]
    // El nonce es ALEATORIO y UNICO por mensaje (nunca reutilizar
    // nonce+clave con la misma key). El tag autentica el mensaje:
    // datos manipulados o clave incorrecta -> error.AuthenticationFailed.
    // --------------------------------------------------------
    const aead_nonce_len = 12;
    const aead_tag_len = 16;
    const aead_key_len = 32;

    fn aeadEncrypt(
        comptime Aead: type,
        key: []const u8,
        allocator: std.mem.Allocator,
        red_bytes: []const u8,
    ) ![]const u8 {
        const out = try allocator.alloc(
            u8,
            aead_nonce_len + red_bytes.len + aead_tag_len,
        );
        errdefer allocator.free(out);

        var nonce: [aead_nonce_len]u8 = undefined;
        std.crypto.random.bytes(&nonce);
        @memcpy(out[0..aead_nonce_len], &nonce);

        var key_arr: [aead_key_len]u8 = undefined;
        @memcpy(&key_arr, key[0..aead_key_len]);

        var tag: [aead_tag_len]u8 = undefined;
        Aead.encrypt(
            out[aead_nonce_len .. aead_nonce_len + red_bytes.len],
            &tag,
            red_bytes,
            "",
            nonce,
            key_arr,
        );
        @memcpy(out[aead_nonce_len + red_bytes.len ..], &tag);

        return out;
    }

    fn aeadDecrypt(
        comptime Aead: type,
        key: []const u8,
        allocator: std.mem.Allocator,
        black_bytes: []const u8,
    ) ![]const u8 {
        if (black_bytes.len < aead_nonce_len + aead_tag_len)
            return error.InvalidCiphertext;

        const ct = black_bytes[aead_nonce_len .. black_bytes.len - aead_tag_len];

        var nonce: [aead_nonce_len]u8 = undefined;
        @memcpy(&nonce, black_bytes[0..aead_nonce_len]);

        var tag: [aead_tag_len]u8 = undefined;
        @memcpy(&tag, black_bytes[black_bytes.len - aead_tag_len ..]);

        var key_arr: [aead_key_len]u8 = undefined;
        @memcpy(&key_arr, key[0..aead_key_len]);

        const out = try allocator.alloc(u8, ct.len);
        errdefer allocator.free(out);

        // Si la autenticacion falla, el errdefer libera out al propagar.
        Aead.decrypt(out, ct, tag, "", nonce, key_arr) catch
            return error.AuthenticationFailed;

        return out;
    }

    fn decodeBase64(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        const dec = std.base64.standard.Decoder;
        const out_len = try dec.calcSizeForSlice(text);
        const out = try allocator.alloc(u8, out_len);
        try dec.decode(out, text);

        return out;
    }
};

// ============================================================================
// TESTS (R2, 2026-09-10): permanentes y con std.testing.allocator (si algo
// fuga, el test falla). Cubren: identidad sin cifrado, round-trip de los dos
// AEAD, tamper de un byte, clave incorrecta, longitudes invalidas y modos no
// soportados. Se ejecutan con `zig build test`.
// ============================================================================
const testing = std.testing;

/// KeyRecord de prueba con la clave dada (Base64) y ventana amplia.
fn registroDePrueba(allocator: std.mem.Allocator, modo: Security.CryptoMode, key_b64: []const u8) !Security.KeyRecord {
    var rec = try Security.KeyRecord.initDefault(allocator);
    errdefer rec.deinit(allocator);

    allocator.free(rec.key);
    rec.key = try allocator.dupe(u8, key_b64);

    allocator.free(rec.created_on);
    rec.created_on = try allocator.dupe(u8, "2026-01-01T00:00:00Z");

    allocator.free(rec.expires_on);
    rec.expires_on = try allocator.dupe(u8, "2036-01-01T00:00:00Z");

    rec.mode = modo;
    rec.key_id = 1;
    return rec;
}

/// Clave aleatoria de aead_key_len bytes, en Base64 (owned).
fn claveAleatoriaBase64(allocator: std.mem.Allocator, len: usize) ![]u8 {
    const bruto = try allocator.alloc(u8, len);
    defer allocator.free(bruto);
    std.crypto.random.bytes(bruto);

    const b64 = std.base64.standard;
    const out = try allocator.alloc(u8, b64.Encoder.calcSize(len));
    _ = b64.Encoder.encode(out, bruto);
    return out;
}

test "cipher: sin cifrado es identidad y devuelve copia" {
    const a = testing.allocator;

    var c = try Cipher.createNoCipher(a);
    defer c.deinit();

    try testing.expectEqual(Security.CryptoMode.CRYPTO_NONE, c.mode);

    const claro = "hola k6bus";
    const negro = try c.encrypt(a, claro);
    defer a.free(negro);

    try testing.expectEqualStrings(claro, negro);
    try testing.expect(negro.ptr != claro.ptr); // copia, no alias

    const vuelta = try c.decrypt(a, negro);
    defer a.free(vuelta);
    try testing.expectEqualStrings(claro, vuelta);
}

test "cipher: AES-256-GCM round-trip" {
    const a = testing.allocator;

    const key_b64 = try claveAleatoriaBase64(a, 32);
    defer a.free(key_b64);

    var rec = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key_b64);
    defer rec.deinit(a);

    var c = try Cipher.create(a, rec);
    defer c.deinit();
    try testing.expectEqual(Security.CryptoMode.CRYPTO_AES_256_GCM, c.mode);

    const claro = "paquete k6bus de prueba";
    const negro = try c.encrypt(a, claro);
    defer a.free(negro);

    // [nonce 12][ct][tag 16]
    try testing.expectEqual(claro.len + 12 + 16, negro.len);
    try testing.expect(!std.mem.eql(u8, claro, negro));

    const vuelta = try c.decrypt(a, negro);
    defer a.free(vuelta);
    try testing.expectEqualStrings(claro, vuelta);
}

test "cipher: AES-256-GCM detecta un byte manipulado (ct y tag)" {
    const a = testing.allocator;

    const key_b64 = try claveAleatoriaBase64(a, 32);
    defer a.free(key_b64);
    var rec = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key_b64);
    defer rec.deinit(a);

    var c = try Cipher.create(a, rec);
    defer c.deinit();

    const claro = "mensaje integro";
    const original = try c.encrypt(a, claro);
    defer a.free(original);

    // 1) un byte en medio del ciphertext
    {
        const roto = try a.dupe(u8, original);
        defer a.free(roto);
        const pos = 12 + 3; // dentro del ct
        roto[pos] ^= 0x01;
        try testing.expectError(error.AuthenticationFailed, c.decrypt(a, roto));
    }

    // 2) un byte del tag
    {
        const roto = try a.dupe(u8, original);
        defer a.free(roto);
        roto[roto.len - 1] ^= 0x01;
        try testing.expectError(error.AuthenticationFailed, c.decrypt(a, roto));
    }

    // 3) un byte del nonce
    {
        const roto = try a.dupe(u8, original);
        defer a.free(roto);
        roto[0] ^= 0x01;
        try testing.expectError(error.AuthenticationFailed, c.decrypt(a, roto));
    }
}

test "cipher: AES-256-GCM falla con clave incorrecta" {
    const a = testing.allocator;

    const key1 = try claveAleatoriaBase64(a, 32);
    defer a.free(key1);
    const key2 = try claveAleatoriaBase64(a, 32);
    defer a.free(key2);

    var rec1 = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key1);
    defer rec1.deinit(a);
    var rec2 = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key2);
    defer rec2.deinit(a);

    var c1 = try Cipher.create(a, rec1);
    defer c1.deinit();
    var c2 = try Cipher.create(a, rec2);
    defer c2.deinit();

    const negro = try c1.encrypt(a, "secreto");
    defer a.free(negro);

    // la clave correcta descifra...
    const ok = try c1.decrypt(a, negro);
    defer a.free(ok);
    try testing.expectEqualStrings("secreto", ok);

    // ...y la incorrecta no.
    try testing.expectError(error.AuthenticationFailed, c2.decrypt(a, negro));
}

test "cipher: ChaCha20-Poly1305 round-trip y tamper" {
    const a = testing.allocator;

    const key_b64 = try claveAleatoriaBase64(a, 32);
    defer a.free(key_b64);
    var rec = try registroDePrueba(a, .CRYPTO_CHACHA20_POLY1305, key_b64);
    defer rec.deinit(a);

    var c = try Cipher.create(a, rec);
    defer c.deinit();
    try testing.expectEqual(Security.CryptoMode.CRYPTO_CHACHA20_POLY1305, c.mode);

    const claro = "otro paquete k6bus";
    const negro = try c.encrypt(a, claro);
    defer a.free(negro);
    try testing.expectEqual(claro.len + 12 + 16, negro.len);

    const vuelta = try c.decrypt(a, negro);
    defer a.free(vuelta);
    try testing.expectEqualStrings(claro, vuelta);

    const roto = try a.dupe(u8, negro);
    defer a.free(roto);
    roto[13] ^= 0x80;
    try testing.expectError(error.AuthenticationFailed, c.decrypt(a, roto));
}

test "cipher: clave con longitud invalida" {
    const a = testing.allocator;

    const key16 = try claveAleatoriaBase64(a, 16);
    defer a.free(key16);

    var rec = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key16);
    defer rec.deinit(a);

    try testing.expectError(error.InvalidKeyLength, Cipher.create(a, rec));
}

test "cipher: modo CUSTOM no soportado y ciphertext corto" {
    const a = testing.allocator;

    const key_b64 = try claveAleatoriaBase64(a, 32);
    defer a.free(key_b64);

    var rec_custom = try registroDePrueba(a, .CRYPTO_CUSTOM, key_b64);
    defer rec_custom.deinit(a);
    try testing.expectError(error.CustomCipherNotSupported, Cipher.create(a, rec_custom));

    var rec = try registroDePrueba(a, .CRYPTO_AES_256_GCM, key_b64);
    defer rec.deinit(a);
    var c = try Cipher.create(a, rec);
    defer c.deinit();

    // menos de nonce+tag bytes no puede ser un ciphertext valido
    try testing.expectError(error.InvalidCiphertext, c.decrypt(a, "corto"));
}
