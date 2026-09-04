// ============================================================================
// Security_api.zig
// ============================================================================
//
// Fichero generado por ProtobuZig / kgenapi.zig.
//
// Proto base:
//   Security
//
// Raw generado:
//   Security.zig
//
// Este fichero contiene wrappers/API segura sobre el raw generado.
//
// Fase intermedia:
//   - el fichero raw mantiene los tipos actuales.
//   - este fichero genera wrappers seguros encima.
//
// Fase final posible:
//   - el fichero raw pasara a *_impl.zig.
//   - este fichero o su equivalente pasara a ser la API publica principal.
//
// No editar a mano salvo para depuracion.
// ============================================================================

const std = @import("std");

const RawFile = @import("Security.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Alias al namespace raw generado.
// En fase intermedia apunta al package actual del fichero raw.
const Raw = RawFile.k6bus.security;

// Alias intencionadamente llamado *_impl aunque en fase intermedia
// apunte al namespace raw actual.
//
// Fase intermedia:
//   const Security_impl = Raw;
//
// Fase final:
//   const Security_impl = RawFile.<package>_impl;

const Security_impl = Raw;

// ============================================================================
// ALIASES PUBLICOS A ENUMS RAW / IMPL
// ============================================================================
//
// Los enums no necesitan wrapper. Se reexportan desde el namespace raw/impl.
//
// En fase intermedia:
//   pub const TipoPanel = cctrol_impl.TipoPanel;
//
// En fase final:
//   pub const TipoPanel = cctrol_impl.TipoPanel;
//
pub const CryptoMode = Security_impl.CryptoMode;
// ============================================================================
// API SEGURA
// ============================================================================
//
// Objetivo:
//
//   - ocultar el acceso directo a campos owned siempre que sea posible.
//   - exponer setters/builders/getters controlados.
//   - ofrecer nombres publicos en ingles para operaciones generales:
//       serializeToBin
//       deserializeFromBin
//       writeToText
//       readFromText
//
// Reglas previstas:
//
//   - append de repeated message hace copia profunda.
//   - no se expone appendOwned como API publica inicial.
//   - getXAt(index) devuelve copia owned.
//   - el usuario debe llamar deinit() sobre copias devueltas.
//   - no se exponen slices repeated internos como API principal.
//

// ============================================================================
// ALIASES INTERNOS A TIPOS RAW / IMPL
// ============================================================================
//
// Estos aliases permiten que el cuerpo de los wrappers no dependa de si
// estamos en fase intermedia o fase final.
//
// Fase intermedia:
//   EstMeteoImpl = cctrol_impl.EstMeteo
//
// Fase final:
//   EstMeteoImpl = cctrol_impl.EstMeteo_impl
//
const KeyRecordImpl = Security_impl.KeyRecord;

// ============================================================================
// HELPERS PRIVADOS DE COPIA PROFUNDA
// ============================================================================
//
// cloneImpl() realiza una copia profunda usando el camino binario generado.
//
// Estrategia inicial:
//
//   clone = seriigiAlBin(.BF_PROTOBUF) + deseriigiElBin(.BF_PROTOBUF)
//
// Esta version prioriza simplicidad y seguridad de ownership.
// Si seriigi/deseriigi tiene un bug, debe corregirse en ProtobuZig,
// porque afecta tambien al uso normal de mensajes en K6Bus.
//

fn cloneImpl(comptime T: type, allocator: std.mem.Allocator, src: *const T) !T {
    const bytes = try src.seriigiAlBin(allocator, .BF_PROTOBUF);
    defer allocator.free(bytes);

    return try T.deseriigiElBin(allocator, bytes, .BF_PROTOBUF);
}

// ============================================================================
// WRAPPERS PUBLICOS
// ============================================================================
//
// De momento cada wrapper solo contiene:
//
//   impl: TipoImpl
//
// En los siguientes pasos se generaran:
//
//   - initDefault()
//   - deinit()
//   - serializeToBin()
//   - deserializeFromBin()
//   - writeToText()
//   - readFromText()
//   - setters/getters/builders seguros
//
pub const KeyRecord = struct {
    impl: KeyRecordImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try KeyRecordImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                KeyRecordImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setMode(self: *Self, value: CryptoMode) void {
        self.impl.mode = value;
    }

    pub fn getMode(self: *const Self) CryptoMode {
        return self.impl.mode;
    }

    pub fn setKeyId(self: *Self, value: u32) void {
        self.impl.key_id = value;
    }

    pub fn getKeyId(self: *const Self) u32 {
        return self.impl.key_id;
    }

    pub fn setVersion(self: *Self, value: u32) void {
        self.impl.version = value;
    }

    pub fn getVersion(self: *const Self) ?u32 {
        return self.impl.version;
    }

    pub fn hasVersion(self: *const Self) bool {
        return self.impl.version != null;
    }

    pub fn clearVersion(self: *Self) void {
        self.impl.version = null;
    }

    pub fn setKey(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.key);
        self.impl.key = tmp;
    }

    pub fn getKey(self: *const Self) []const u8 {
        return self.impl.key;
    }

    pub fn setDescription(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp = try allocator.dupe(u8, value);

        if (self.impl.description) |old| {
            allocator.free(old);
        }

        self.impl.description = tmp;
    }

    pub fn getDescription(self: *const Self) ?[]const u8 {
        return self.impl.description;
    }

    pub fn hasDescription(self: *const Self) bool {
        return self.impl.description != null;
    }

    pub fn clearDescription(self: *Self, allocator: std.mem.Allocator) void {
        if (self.impl.description) |old| {
            allocator.free(old);
        }

        self.impl.description = null;
    }

    pub fn writeToText(
        self: *Self,
        allocator: std.mem.Allocator,
        format: TekstaFormato,
    ) ![]const u8 {
        return try self.impl.skribiAlTeksto(
            allocator,
            format,
        );
    }

    pub fn writeToFile(
        self: *Self,
        allocator: std.mem.Allocator,
        path: []const u8,
        format: TekstaFormato,
    ) !void {
        try self.impl.skribiAlDosiero(
            allocator,
            path,
            format,
        );
    }

    pub fn readFromText(
        allocator: std.mem.Allocator,
        input: []const u8,
        format: TekstaFormato,
    ) !Self {
        return .{
            .impl = try KeyRecordImpl.legiElTeksto(
                allocator,
                input,
                format,
            ),
        };
    }

    pub fn readFromFile(
        allocator: std.mem.Allocator,
        path: []const u8,
        format: TekstaFormato,
    ) !Self {
        return .{
            .impl = try KeyRecordImpl.legiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }

    pub fn serializeToBin(
        self: *const Self,
        allocator: std.mem.Allocator,
        format: BinaraFormato,
    ) ![]const u8 {
        return try self.impl.seriigiAlBin(
            allocator,
            format,
        );
    }

    pub fn serializeToFile(
        self: *const Self,
        allocator: std.mem.Allocator,
        path: []const u8,
        format: BinaraFormato,
    ) !void {
        try self.impl.seriigiAlDosiero(
            allocator,
            path,
            format,
        );
    }

    pub fn deserializeFromBin(
        allocator: std.mem.Allocator,
        input: []const u8,
        format: BinaraFormato,
    ) !Self {
        return .{
            .impl = try KeyRecordImpl.deseriigiElBin(
                allocator,
                input,
                format,
            ),
        };
    }

    pub fn deserializeFromFile(
        allocator: std.mem.Allocator,
        path: [:0]const u8,
        format: BinaraFormato,
    ) !Self {
        return .{
            .impl = try KeyRecordImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

// ============================================================================
// FIN API SEGURA
// ============================================================================
