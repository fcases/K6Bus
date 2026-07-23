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
    iv: []u8,

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
            .iv = try allocator.alloc(u8, 0),

            .encrypt_fn = identityEncrypt,
            .decrypt_fn = identityDecrypt,
        };
    }

    pub fn create(allocator: std.mem.Allocator, key_registry: Security.KeyRegistry) !Self {
        const key_bytes = try decodeBase64(allocator, key_registry.Key);
        errdefer allocator.free(key_bytes);

        const iv_bytes = if (key_registry.iv) |iv_b64|
            try decodeBase64(allocator, iv_b64)
        else
            try allocator.alloc(u8, 0);

        var self = Self{
            .allocator = allocator,
            .mode = key_registry.mode orelse .CRYPTO_AES_256_GCM,

            .key = key_bytes,
            .iv = iv_bytes,

            .encrypt_fn = identityEncrypt,
            .decrypt_fn = identityDecrypt,
        };

        switch (self.mode) {
            .CRYPTO_NONE => {
                self.encrypt_fn = identityEncrypt;
                self.decrypt_fn = identityDecrypt;
            },

            .CRYPTO_AES_256_GCM => {
                self.encrypt_fn = aes256GcmEncrypt;
                self.decrypt_fn = aes256GcmDecrypt;
            },

            .CRYPTO_CHACHA20_POLY1305 => {
                self.encrypt_fn = chacha20Poly1305Encrypt;
                self.decrypt_fn = chacha20Poly1305Decrypt;
            },

            .CRYPTO_AES_256_CBC => {
                self.encrypt_fn = aes256CbcEncrypt;
                self.decrypt_fn = aes256CbcDecrypt;
            },
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.key);
        self.allocator.free(self.iv);

        self.key = &.{};
        self.iv = &.{};
    }

    pub fn encrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        return self.encrypt_fn(self, allocator, red_bytes);
    }

    pub fn decrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        return self.decrypt_fn(
            self,
            allocator,
            black_bytes,
        );
    }

    // --------------------------------------------------------
    // Identity
    // --------------------------------------------------------
    fn identityEncrypt(self: *const Self, allocator: std.mem.Allocator, red_bytes: []const u8) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            red_bytes,
        );
    }

    fn identityDecrypt(self: *const Self, allocator: std.mem.Allocator, black_bytes: []const u8) ![]const u8 {
        _ = self;

        return try allocator.dupe(u8, black_bytes);
    }

    // --------------------------------------------------------
    // AES-256-GCM
    // --------------------------------------------------------
    //
    // TODO:
    // Implementación real.
    //
    // De momento funciona como pass-through
    // para permitir cerrar la arquitectura.
    //
    // Sustituir por std.crypto.aead.aes_gcm
    // cuando se integre definitivamente.
    //
    // --------------------------------------------------------

    fn aes256GcmEncrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        red_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            red_bytes,
        );
    }

    fn aes256GcmDecrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        black_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            black_bytes,
        );
    }

    // --------------------------------------------------------
    // CHACHA20-POLY1305
    // --------------------------------------------------------
    //
    // TODO:
    // Implementación real.
    //
    // --------------------------------------------------------

    fn chacha20Poly1305Encrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        red_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            red_bytes,
        );
    }

    fn chacha20Poly1305Decrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        black_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            black_bytes,
        );
    }

    // --------------------------------------------------------
    // AES-256-CBC
    // --------------------------------------------------------
    //
    // TODO:
    // Implementación real.
    //
    // --------------------------------------------------------

    fn aes256CbcEncrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        red_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            red_bytes,
        );
    }

    fn aes256CbcDecrypt(
        self: *const Self,
        allocator: std.mem.Allocator,
        black_bytes: []const u8,
    ) ![]const u8 {
        _ = self;

        return try allocator.dupe(
            u8,
            black_bytes,
        );
    }

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    fn decodeBase64(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        const dec = std.base64.standard.Decoder;
        const out_len = try dec.calcSizeForSlice(text);
        const out = try allocator.alloc(u8, out_len);
        try dec.decode(out, text);

        return out;
    }
};
