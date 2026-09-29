// ============================================================================
// types_api.zig
// ============================================================================
//
// Dosiero generita de ProtobuZig / kgenapi.zig.
//
// Baza proto:
//   types
//
// Generita raw:
//   types.zig
//
// Cxi tiu dosiero enhavas wrapper-ojn (sekura API) super la raw.
//
// Meza fazo:
//   - la raw-dosiero konservas la nunajn tipojn.
//   - cxi tiu dosiero generas sekurajn wrapper-ojn supre.
//
// Ebla fina fazo:
//   - la raw-dosiero pasos al *_impl.zig.
//   - cxi tiu dosiero aux gia ekvivalento farigxos cefa publika API.
//
// Ne redaktu mane krom por sencimigado.
// ============================================================================

const std = @import("std");

const RawFile = @import("types.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Aliaso al la generita raw-nomspaco.
// En la meza fazo gxi montras al la nuna package de la raw-dosiero.
const Raw = RawFile.k6bus;

// Aliaso intence nomita *_impl, kvankam en la meza fazo gxi
// montras al la nuna raw-nomspaco.
//
// Meza fazo:
//   const types_impl = Raw;
//
// Fina fazo:
//   const types_impl = RawFile.<package>_impl;

const types_impl = Raw;

// ============================================================================
// SEKURA API
// ============================================================================
//
// Celo:
//
//   - kasxi la rektan aliron al owned-kampoj kiam eble.
//   - montri kontrolitajn setter-ojn/builder-ojn/getter-ojn.
//   - proponi publikajn nomojn en la angla por generalaj operacioj:
//       serializeToBin
//       deserializeFromBin
//       writeToText
//       readFromText
//
// Antauxviditaj reguloj:
//
//   - append de repeated message faras profundan kopion.
//   - appendOwned ne estas montrata kiel komenca publika API.
//   - getXAt(index) redonas owned-kopion.
//   - la uzanto devas voki deinit() sur redonitajn kopiojn.
//   - internaj repeated slices ne estas montrataj kiel cefa API.
//

// ============================================================================
// INTERNAJ ALIASOJ AL RAW / IMPL-TIPOJ
// ============================================================================
//
// Cxi tiuj aliasoj ebligas, ke la korpo de la wrapper-oj ne dependu
// de tio, cxu ni estas en la meza aux fina fazo.
//
// Meza fazo:
//   EstMeteoImpl = cctrol_impl.EstMeteo
//
// Fina fazo:
//   EstMeteoImpl = cctrol_impl.EstMeteo_impl
//
const MsgImpl = types_impl.Msg;
const PacketImpl = types_impl.Packet;

// ============================================================================
// PRIVATAJ HELPILOJ DE PROFUNDA KOPIO
// ============================================================================
//
// cloneImpl() faras profundan kopion per la generita binara vojo.
//
// Komenca strategio:
//
//   clone = seriigiAlBin(.BF_PROTOBUF) + deseriigiElBin(.BF_PROTOBUF)
//
// Cxi tiu versio prioritatas simplecon kaj sekurecon de ownership.
// Se seriigi/deseriigi havas cimon, gxi riparigxu en ProtobuZig,
// cxar gxi trafas ankaux la normalan uzon de mesagxoj en K6Bus.
//

fn cloneImpl(comptime T: type, allocator: std.mem.Allocator, src: *const T) !T {
    const bytes = try src.seriigiAlBin(allocator, .BF_PROTOBUF);
    defer allocator.free(bytes);

    return try T.deseriigiElBin(allocator, bytes, .BF_PROTOBUF);
}

// ============================================================================
// PUBLIKAJ WRAPPER-OJ
// ============================================================================
//
// Provizore cxiu wrapper enhavas nur:
//
//   impl: TipoImpl
//
// En la sekvaj pasxoj generigxos:
//
//   - initDefault()
//   - deinit()
//   - serializeToBin()
//   - deserializeFromBin()
//   - writeToText()
//   - readFromText()
//   - sekuraj setter-oj/getter-oj/builder-oj
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
// FINO DE LA SEKURA API
// ============================================================================
