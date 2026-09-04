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
