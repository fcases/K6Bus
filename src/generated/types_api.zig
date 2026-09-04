// ============================================================================
// types_api.zig
// ============================================================================
//
// Fichero generado por ProtobuZig / kgenapi.zig.
//
// Proto base:
//   types
//
// Raw generado:
//   types.zig
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

const RawFile = @import("types.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Alias al namespace raw generado.
// En fase intermedia apunta al package actual del fichero raw.
const Raw = RawFile.k6bus;

// Alias intencionadamente llamado *_impl aunque en fase intermedia
// apunte al namespace raw actual.
//
// Fase intermedia:
//   const types_impl = Raw;
//
// Fase final:
//   const types_impl = RawFile.<package>_impl;

const types_impl = Raw;

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
const MsgImpl = types_impl.Msg;
const PacketImpl = types_impl.Packet;

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
pub const Msg = struct {
    impl: MsgImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try MsgImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                MsgImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setMsgType(self: *Self, value: u64) void {
        self.impl.msgType = value;
    }

    pub fn getMsgType(self: *const Self) u64 {
        return self.impl.msgType;
    }

    pub fn getChannelsCount(self: *const Self) usize {
        return self.impl.channels.len;
    }

    pub fn getChannelsAt(self: *const Self, index: usize) !u64 {
        if (index >= self.impl.channels.len) {
            return error.IndexOutOfBounds;
        }

        return self.impl.channels[index];
    }

    pub fn appendChannels(
        self: *Self,
        allocator: std.mem.Allocator,
        value: u64,
    ) !void {
        const old_len = self.impl.channels.len;

        self.impl.channels = try allocator.realloc(
            self.impl.channels,
            old_len + 1,
        );

        self.impl.channels[old_len] = value;
    }

    pub fn setChannels(
        self: *Self,
        allocator: std.mem.Allocator,
        values: []const u64,
    ) !void {
        const tmp = try allocator.dupe(u64, values);

        allocator.free(self.impl.channels);
        self.impl.channels = tmp;
    }

    pub fn clearChannels(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !void {
        allocator.free(self.impl.channels);
        self.impl.channels = try allocator.alloc(u64, 0);
    }

    pub fn setPayLoad(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.payLoad);
        self.impl.payLoad = tmp;
    }

    pub fn getPayLoad(self: *const Self) []const u8 {
        return self.impl.payLoad;
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
            .impl = try MsgImpl.legiElTeksto(
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
            .impl = try MsgImpl.legiElDosiero(
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
            .impl = try MsgImpl.deseriigiElBin(
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
            .impl = try MsgImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const Packet = struct {
    impl: PacketImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try PacketImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                PacketImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setOutOfBand(self: *Self, value: u64) void {
        self.impl.OutOfBand = value;
    }

    pub fn getOutOfBand(self: *const Self) ?u64 {
        return self.impl.OutOfBand;
    }

    pub fn hasOutOfBand(self: *const Self) bool {
        return self.impl.OutOfBand != null;
    }

    pub fn clearOutOfBand(self: *Self) void {
        self.impl.OutOfBand = null;
    }

    pub fn getMessagesCount(self: *const Self) usize {
        return self.impl.messages.len;
    }

    pub fn getMessagesAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !Msg {
        if (index >= self.impl.messages.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                MsgImpl,
                allocator,
                &self.impl.messages[index],
            ),
        };
    }

    pub fn appendMessages(self: *Self, allocator: std.mem.Allocator, value: *const Msg) !void {
        const tmp_item = try cloneImpl(
            MsgImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.messages.len;
        self.impl.messages = try allocator.realloc(
            self.impl.messages,
            old_len + 1,
        );

        self.impl.messages[old_len] = tmp_item;
    }

    pub fn clearMessages(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.messages) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.messages);
        self.impl.messages = try allocator.alloc(MsgImpl, 0);
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
            .impl = try PacketImpl.legiElTeksto(
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
            .impl = try PacketImpl.legiElDosiero(
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
            .impl = try PacketImpl.deseriigiElBin(
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
            .impl = try PacketImpl.deseriigiElDosiero(
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
