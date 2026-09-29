// ============================================================================
// cctrol_api.zig
// ============================================================================
//
// Dosiero generita de ProtobuZig / kgenapi.zig.
//
// Baza proto:
//   cctrol
//
// Generita raw:
//   cctrol.zig
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

const RawFile = @import("cctrol.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Aliaso al la generita raw-nomspaco.
// En la meza fazo gxi montras al la nuna package de la raw-dosiero.
const Raw = RawFile.cctrol;

// Aliaso intence nomita *_impl, kvankam en la meza fazo gxi
// montras al la nuna raw-nomspaco.
//
// Meza fazo:
//   const cctrol_impl = Raw;
//
// Fina fazo:
//   const cctrol_impl = RawFile.<package>_impl;

const cctrol_impl = Raw;

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
pub const TipoPanel = cctrol_impl.TipoPanel;
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
const CCtrolImpl = cctrol_impl.CCtrol;
const EstRemCtrolImpl = cctrol_impl.EstRemCtrol;
const EstMeteoImpl = cctrol_impl.EstMeteo;
const SnrTraficoImpl = cctrol_impl.SnrTrafico;
const PanelInfoVImpl = cctrol_impl.PanelInfoV;
const PanelBaseImpl = cctrol_impl.PanelBase;
const SenialInfoImpl = cctrol_impl.SenialInfo;
const TextoInfoImpl = cctrol_impl.TextoInfo;

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
pub const CCtrol = struct {
    impl: CCtrolImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try CCtrolImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                CCtrolImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn getRemotasCount(self: *const Self) usize {
        return self.impl.remotas.len;
    }

    pub fn getRemotasAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !EstRemCtrol {
        if (index >= self.impl.remotas.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                EstRemCtrolImpl,
                allocator,
                &self.impl.remotas[index],
            ),
        };
    }

    pub fn appendRemotas(self: *Self, allocator: std.mem.Allocator, value: *const EstRemCtrol) !void {
        const tmp_item = try cloneImpl(
            EstRemCtrolImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.remotas.len;
        self.impl.remotas = try allocator.realloc(
            self.impl.remotas,
            old_len + 1,
        );

        self.impl.remotas[old_len] = tmp_item;
    }

    pub fn clearRemotas(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.remotas) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.remotas);
        self.impl.remotas = try allocator.alloc(EstRemCtrolImpl, 0);
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
            .impl = try CCtrolImpl.legiElTeksto(
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
            .impl = try CCtrolImpl.legiElDosiero(
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
            .impl = try CCtrolImpl.deseriigiElBin(
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
            .impl = try CCtrolImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const EstRemCtrol = struct {
    impl: EstRemCtrolImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try EstRemCtrolImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                EstRemCtrolImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn getMeteosCount(self: *const Self) usize {
        return self.impl.meteos.len;
    }

    pub fn getMeteosAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !EstMeteo {
        if (index >= self.impl.meteos.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                EstMeteoImpl,
                allocator,
                &self.impl.meteos[index],
            ),
        };
    }

    pub fn appendMeteos(self: *Self, allocator: std.mem.Allocator, value: *const EstMeteo) !void {
        const tmp_item = try cloneImpl(
            EstMeteoImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.meteos.len;
        self.impl.meteos = try allocator.realloc(
            self.impl.meteos,
            old_len + 1,
        );

        self.impl.meteos[old_len] = tmp_item;
    }

    pub fn clearMeteos(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.meteos) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.meteos);
        self.impl.meteos = try allocator.alloc(EstMeteoImpl, 0);
    }

    pub fn getDatosTrCount(self: *const Self) usize {
        return self.impl.datos_tr.len;
    }

    pub fn getDatosTrAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !SnrTrafico {
        if (index >= self.impl.datos_tr.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                SnrTraficoImpl,
                allocator,
                &self.impl.datos_tr[index],
            ),
        };
    }

    pub fn appendDatosTr(self: *Self, allocator: std.mem.Allocator, value: *const SnrTrafico) !void {
        const tmp_item = try cloneImpl(
            SnrTraficoImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.datos_tr.len;
        self.impl.datos_tr = try allocator.realloc(
            self.impl.datos_tr,
            old_len + 1,
        );

        self.impl.datos_tr[old_len] = tmp_item;
    }

    pub fn clearDatosTr(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.datos_tr) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.datos_tr);
        self.impl.datos_tr = try allocator.alloc(SnrTraficoImpl, 0);
    }

    pub fn getPanelesCount(self: *const Self) usize {
        return self.impl.paneles.len;
    }

    pub fn getPanelesAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !PanelInfoV {
        if (index >= self.impl.paneles.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                PanelInfoVImpl,
                allocator,
                &self.impl.paneles[index],
            ),
        };
    }

    pub fn appendPaneles(self: *Self, allocator: std.mem.Allocator, value: *const PanelInfoV) !void {
        const tmp_item = try cloneImpl(
            PanelInfoVImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.paneles.len;
        self.impl.paneles = try allocator.realloc(
            self.impl.paneles,
            old_len + 1,
        );

        self.impl.paneles[old_len] = tmp_item;
    }

    pub fn clearPaneles(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.paneles) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.paneles);
        self.impl.paneles = try allocator.alloc(PanelInfoVImpl, 0);
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
            .impl = try EstRemCtrolImpl.legiElTeksto(
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
            .impl = try EstRemCtrolImpl.legiElDosiero(
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
            .impl = try EstRemCtrolImpl.deseriigiElBin(
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
            .impl = try EstRemCtrolImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const EstMeteo = struct {
    impl: EstMeteoImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try EstMeteoImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                EstMeteoImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setTemp(self: *Self, value: u32) void {
        self.impl.temp = value;
    }

    pub fn getTemp(self: *const Self) u32 {
        return self.impl.temp;
    }

    pub fn setVViento(self: *Self, value: f32) void {
        self.impl.v_viento = value;
    }

    pub fn getVViento(self: *const Self) f32 {
        return self.impl.v_viento;
    }

    pub fn setDirViento(self: *Self, value: f32) void {
        self.impl.dir_viento = value;
    }

    pub fn getDirViento(self: *const Self) f32 {
        return self.impl.dir_viento;
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
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
            .impl = try EstMeteoImpl.legiElTeksto(
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
            .impl = try EstMeteoImpl.legiElDosiero(
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
            .impl = try EstMeteoImpl.deseriigiElBin(
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
            .impl = try EstMeteoImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const SnrTrafico = struct {
    impl: SnrTraficoImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try SnrTraficoImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                SnrTraficoImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setCarriles(self: *Self, value: u32) void {
        self.impl.carriles = value;
    }

    pub fn getCarriles(self: *const Self) u32 {
        return self.impl.carriles;
    }

    pub fn getVelMediaCount(self: *const Self) usize {
        return self.impl.vel_media.len;
    }

    pub fn getVelMediaAt(self: *const Self, index: usize) !f32 {
        if (index >= self.impl.vel_media.len) {
            return error.IndexOutOfBounds;
        }

        return self.impl.vel_media[index];
    }

    pub fn appendVelMedia(
        self: *Self,
        allocator: std.mem.Allocator,
        value: f32,
    ) !void {
        const old_len = self.impl.vel_media.len;

        self.impl.vel_media = try allocator.realloc(
            self.impl.vel_media,
            old_len + 1,
        );

        self.impl.vel_media[old_len] = value;
    }

    pub fn setVelMedia(
        self: *Self,
        allocator: std.mem.Allocator,
        values: []const f32,
    ) !void {
        const tmp = try allocator.dupe(f32, values);

        allocator.free(self.impl.vel_media);
        self.impl.vel_media = tmp;
    }

    pub fn clearVelMedia(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !void {
        allocator.free(self.impl.vel_media);
        self.impl.vel_media = try allocator.alloc(f32, 0);
    }

    pub fn getVehiculosMinCount(self: *const Self) usize {
        return self.impl.vehiculos_min.len;
    }

    pub fn getVehiculosMinAt(self: *const Self, index: usize) !f32 {
        if (index >= self.impl.vehiculos_min.len) {
            return error.IndexOutOfBounds;
        }

        return self.impl.vehiculos_min[index];
    }

    pub fn appendVehiculosMin(
        self: *Self,
        allocator: std.mem.Allocator,
        value: f32,
    ) !void {
        const old_len = self.impl.vehiculos_min.len;

        self.impl.vehiculos_min = try allocator.realloc(
            self.impl.vehiculos_min,
            old_len + 1,
        );

        self.impl.vehiculos_min[old_len] = value;
    }

    pub fn setVehiculosMin(
        self: *Self,
        allocator: std.mem.Allocator,
        values: []const f32,
    ) !void {
        const tmp = try allocator.dupe(f32, values);

        allocator.free(self.impl.vehiculos_min);
        self.impl.vehiculos_min = tmp;
    }

    pub fn clearVehiculosMin(
        self: *Self,
        allocator: std.mem.Allocator,
    ) !void {
        allocator.free(self.impl.vehiculos_min);
        self.impl.vehiculos_min = try allocator.alloc(f32, 0);
    }

    pub fn setSeccion(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.seccion);
        self.impl.seccion = tmp;
    }

    pub fn getSeccion(self: *const Self) []const u8 {
        return self.impl.seccion;
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
            .impl = try SnrTraficoImpl.legiElTeksto(
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
            .impl = try SnrTraficoImpl.legiElDosiero(
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
            .impl = try SnrTraficoImpl.deseriigiElBin(
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
            .impl = try SnrTraficoImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const PanelInfoV = struct {
    impl: PanelInfoVImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try PanelInfoVImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                PanelInfoVImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn getElementosCount(self: *const Self) usize {
        return self.impl.elementos.len;
    }

    pub fn getElementosAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !PanelBase {
        if (index >= self.impl.elementos.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                PanelBaseImpl,
                allocator,
                &self.impl.elementos[index],
            ),
        };
    }

    pub fn appendElementos(self: *Self, allocator: std.mem.Allocator, value: *const PanelBase) !void {
        const tmp_item = try cloneImpl(
            PanelBaseImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.elementos.len;
        self.impl.elementos = try allocator.realloc(
            self.impl.elementos,
            old_len + 1,
        );

        self.impl.elementos[old_len] = tmp_item;
    }

    pub fn clearElementos(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.elementos) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.elementos);
        self.impl.elementos = try allocator.alloc(PanelBaseImpl, 0);
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
            .impl = try PanelInfoVImpl.legiElTeksto(
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
            .impl = try PanelInfoVImpl.legiElDosiero(
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
            .impl = try PanelInfoVImpl.deseriigiElBin(
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
            .impl = try PanelInfoVImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const PanelBase = struct {
    impl: PanelBaseImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try PanelBaseImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                PanelBaseImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setTipo(self: *Self, value: TipoPanel) void {
        self.impl.tipo = value;
    }

    pub fn getTipo(self: *const Self) TipoPanel {
        return self.impl.tipo;
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn hasDatos(self: *const Self) bool {
        return switch (self.impl.datos) {
            .none => false,
            else => true,
        };
    }

    pub fn clearDatos(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.impl.datos) {
            .none => {},
            .senial => |*value| {
                value.deinit(allocator);
            },
            .texto => |*value| {
                value.deinit(allocator);
            },
        }

        self.impl.datos = .none;
    }

    pub fn setDatosSenial(self: *Self, allocator: std.mem.Allocator, value: *const SenialInfo) !void {
        const tmp = try cloneImpl(
            SenialInfoImpl,
            allocator,
            &value.impl,
        );

        self.clearDatos(allocator);
        self.impl.datos = .{ .senial = tmp };
    }

    pub fn hasDatosSenial(self: *const Self) bool {
        return switch (self.impl.datos) {
            .senial => true,
            else => false,
        };
    }

    pub fn getDatosSenial(self: *const Self, allocator: std.mem.Allocator) !SenialInfo {
        return switch (self.impl.datos) {
            .senial => |*value| .{
                .impl = try cloneImpl(
                    SenialInfoImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
    }

    pub fn setDatosTexto(self: *Self, allocator: std.mem.Allocator, value: *const TextoInfo) !void {
        const tmp = try cloneImpl(
            TextoInfoImpl,
            allocator,
            &value.impl,
        );

        self.clearDatos(allocator);
        self.impl.datos = .{ .texto = tmp };
    }

    pub fn hasDatosTexto(self: *const Self) bool {
        return switch (self.impl.datos) {
            .texto => true,
            else => false,
        };
    }

    pub fn getDatosTexto(self: *const Self, allocator: std.mem.Allocator) !TextoInfo {
        return switch (self.impl.datos) {
            .texto => |*value| .{
                .impl = try cloneImpl(
                    TextoInfoImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
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
            .impl = try PanelBaseImpl.legiElTeksto(
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
            .impl = try PanelBaseImpl.legiElDosiero(
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
            .impl = try PanelBaseImpl.deseriigiElBin(
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
            .impl = try PanelBaseImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const SenialInfo = struct {
    impl: SenialInfoImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try SenialInfoImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                SenialInfoImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn setSenial(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.senial);
        self.impl.senial = tmp;
    }

    pub fn getSenial(self: *const Self) []const u8 {
        return self.impl.senial;
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
            .impl = try SenialInfoImpl.legiElTeksto(
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
            .impl = try SenialInfoImpl.legiElDosiero(
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
            .impl = try SenialInfoImpl.deseriigiElBin(
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
            .impl = try SenialInfoImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const TextoInfo = struct {
    impl: TextoInfoImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try TextoInfoImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                TextoInfoImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setNombre(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.nombre);
        self.impl.nombre = tmp;
    }

    pub fn getNombre(self: *const Self) []const u8 {
        return self.impl.nombre;
    }

    pub fn setTexto(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.texto);
        self.impl.texto = tmp;
    }

    pub fn getTexto(self: *const Self) []const u8 {
        return self.impl.texto;
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
            .impl = try TextoInfoImpl.legiElTeksto(
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
            .impl = try TextoInfoImpl.legiElDosiero(
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
            .impl = try TextoInfoImpl.deseriigiElBin(
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
            .impl = try TextoInfoImpl.deseriigiElDosiero(
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
