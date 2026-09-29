// ============================================================================
// Security_api.zig
// ============================================================================
//
// Dosiero generita de ProtobuZig / kgenapi.zig.
//
// Baza proto:
//   Security
//
// Generita raw:
//   Security.zig
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

const RawFile = @import("Security.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Aliaso al la generita raw-nomspaco.
// En la meza fazo gxi montras al la nuna package de la raw-dosiero.
const Raw = RawFile.k6bus.security;

// Aliaso intence nomita *_impl, kvankam en la meza fazo gxi
// montras al la nuna raw-nomspaco.
//
// Meza fazo:
//   const Security_impl = Raw;
//
// Fina fazo:
//   const Security_impl = RawFile.<package>_impl;

const Security_impl = Raw;

// ============================================================================
// PUBLIKAJ ALIASOJ AL RAW / IMPL-ENUMOJ
// ============================================================================
//
// Enum-oj ne bezonas wrapper-on. Ili reeksportigxas el raw/impl.
//
// En la meza fazo:
//   pub const TipoPanel = cctrol_impl.TipoPanel;
//
// En la fina fazo:
//   pub const TipoPanel = cctrol_impl.TipoPanel;
//
pub const CryptoMode = Security_impl.CryptoMode;
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
const KeyRecordImpl = Security_impl.KeyRecord;
const KeyRegistryImpl = Security_impl.KeyRegistry;

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

    pub fn setCreatedOn(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.created_on);
        self.impl.created_on = tmp;
    }

    pub fn getCreatedOn(self: *const Self) []const u8 {
        return self.impl.created_on;
    }

    pub fn setExpiresOn(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.expires_on);
        self.impl.expires_on = tmp;
    }

    pub fn getExpiresOn(self: *const Self) []const u8 {
        return self.impl.expires_on;
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

pub const KeyRegistry = struct {
    impl: KeyRegistryImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try KeyRegistryImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                KeyRegistryImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setVersion(self: *Self, value: u32) void {
        self.impl.version = value;
    }

    pub fn getVersion(self: *const Self) u32 {
        return self.impl.version;
    }

    pub fn setDescription(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.description);
        self.impl.description = tmp;
    }

    pub fn getDescription(self: *const Self) []const u8 {
        return self.impl.description;
    }

    pub fn getKeysCount(self: *const Self) usize {
        return self.impl.keys.len;
    }

    pub fn getKeysAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !KeyRecord {
        if (index >= self.impl.keys.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                KeyRecordImpl,
                allocator,
                &self.impl.keys[index],
            ),
        };
    }

    pub fn appendKeys(self: *Self, allocator: std.mem.Allocator, value: *const KeyRecord) !void {
        const tmp_item = try cloneImpl(
            KeyRecordImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.keys.len;
        self.impl.keys = try allocator.realloc(
            self.impl.keys,
            old_len + 1,
        );

        self.impl.keys[old_len] = tmp_item;
    }

    pub fn clearKeys(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.keys) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.keys);
        self.impl.keys = try allocator.alloc(KeyRecordImpl, 0);
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
            .impl = try KeyRegistryImpl.legiElTeksto(
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
            .impl = try KeyRegistryImpl.legiElDosiero(
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
            .impl = try KeyRegistryImpl.deseriigiElBin(
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
            .impl = try KeyRegistryImpl.deseriigiElDosiero(
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
