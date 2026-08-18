// ============================================================================
// Config_api.zig
// ============================================================================
//
// Fichero generado por ProtobuZig / kgenapi.zig.
//
// Proto base:
//   Config
//
// Raw generado:
//   Config.zig
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

const RawFile = @import("Config.zig");

pub const TekstaFormato = RawFile.TekstaFormato;
pub const BinaraFormato = RawFile.BinaraFormato;

// Alias al namespace raw generado.
// En fase intermedia apunta al package actual del fichero raw.
const Raw = RawFile.k6bus.config;

// Alias intencionadamente llamado *_impl aunque en fase intermedia
// apunte al namespace raw actual.
//
// Fase intermedia:
//   const Config_impl = Raw;
//
// Fase final:
//   const Config_impl = RawFile.<package>_impl;

const Config_impl = Raw;

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
pub const BinaryFormat = Config_impl.BinaryFormat;
pub const DispatchMode = Config_impl.DispatchMode;
pub const TransportKind = Config_impl.TransportKind;
pub const Encoding = Config_impl.Encoding;
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
const AppConfigImpl = Config_impl.AppConfig;
const DomainConfigImpl = Config_impl.DomainConfig;
const TransportConfigImpl = Config_impl.TransportConfig;
const MCastConfigImpl = Config_impl.MCastConfig;
const BCastConfigImpl = Config_impl.BCastConfig;
const UDPStarConfigImpl = Config_impl.UDPStarConfig;
const EndPointConfigImpl = Config_impl.EndPointConfig;
const UnixSocketStarConfigImpl = Config_impl.UnixSocketStarConfig;
const CustomTransportConfigImpl = Config_impl.CustomTransportConfig;
const CrossConnectorConfigImpl = Config_impl.CrossConnectorConfig;

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
pub const AppConfig = struct {
    impl: AppConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try AppConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                AppConfigImpl,
                allocator,
                &self.impl,
            ),
        };
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

    pub fn setActivateTrace(self: *Self, value: bool) void {
        self.impl.activate_trace = value;
    }

    pub fn getActivateTrace(self: *const Self) ?bool {
        return self.impl.activate_trace;
    }

    pub fn hasActivateTrace(self: *const Self) bool {
        return self.impl.activate_trace != null;
    }

    pub fn clearActivateTrace(self: *Self) void {
        self.impl.activate_trace = null;
    }

    pub fn setTraceLevel(self: *Self, value: i32) void {
        self.impl.trace_level = value;
    }

    pub fn getTraceLevel(self: *const Self) ?i32 {
        return self.impl.trace_level;
    }

    pub fn hasTraceLevel(self: *const Self) bool {
        return self.impl.trace_level != null;
    }

    pub fn clearTraceLevel(self: *Self) void {
        self.impl.trace_level = null;
    }

    pub fn getDomainsCount(self: *const Self) usize {
        return self.impl.domains.len;
    }

    pub fn getDomainsAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !DomainConfig {
        if (index >= self.impl.domains.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                DomainConfigImpl,
                allocator,
                &self.impl.domains[index],
            ),
        };
    }

    pub fn appendDomains(self: *Self, allocator: std.mem.Allocator, value: *const DomainConfig) !void {
        const tmp_item = try cloneImpl(
            DomainConfigImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.domains.len;
        self.impl.domains = try allocator.realloc(
            self.impl.domains,
            old_len + 1,
        );

        self.impl.domains[old_len] = tmp_item;
    }

    pub fn clearDomains(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.domains) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.domains);
        self.impl.domains = try allocator.alloc(DomainConfigImpl, 0);
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
            .impl = try AppConfigImpl.legiElTeksto(
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
            .impl = try AppConfigImpl.legiElDosiero(
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
            .impl = try AppConfigImpl.deseriigiElBin(
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
            .impl = try AppConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const DomainConfig = struct {
    impl: DomainConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try DomainConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                DomainConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setId(self: *Self, value: u32) void {
        self.impl.id = value;
    }

    pub fn getId(self: *const Self) u32 {
        return self.impl.id;
    }

    pub fn setActivateDefaultTransport(self: *Self, value: bool) void {
        self.impl.activate_default_transport = value;
    }

    pub fn getActivateDefaultTransport(self: *const Self) ?bool {
        return self.impl.activate_default_transport;
    }

    pub fn hasActivateDefaultTransport(self: *const Self) bool {
        return self.impl.activate_default_transport != null;
    }

    pub fn clearActivateDefaultTransport(self: *Self) void {
        self.impl.activate_default_transport = null;
    }

    pub fn setDirectDispatchToSubs(self: *Self, value: bool) void {
        self.impl.direct_dispatch_to_subs = value;
    }

    pub fn getDirectDispatchToSubs(self: *const Self) ?bool {
        return self.impl.direct_dispatch_to_subs;
    }

    pub fn hasDirectDispatchToSubs(self: *const Self) bool {
        return self.impl.direct_dispatch_to_subs != null;
    }

    pub fn clearDirectDispatchToSubs(self: *Self) void {
        self.impl.direct_dispatch_to_subs = null;
    }

    pub fn setBinaryFormat(self: *Self, value: BinaryFormat) void {
        self.impl.binary_format = value;
    }

    pub fn getBinaryFormat(self: *const Self) ?BinaryFormat {
        return self.impl.binary_format;
    }

    pub fn hasBinaryFormat(self: *const Self) bool {
        return self.impl.binary_format != null;
    }

    pub fn clearBinaryFormat(self: *Self) void {
        self.impl.binary_format = null;
    }

    pub fn setStartAtInit(self: *Self, value: bool) void {
        self.impl.start_at_init = value;
    }

    pub fn getStartAtInit(self: *const Self) ?bool {
        return self.impl.start_at_init;
    }

    pub fn hasStartAtInit(self: *const Self) bool {
        return self.impl.start_at_init != null;
    }

    pub fn clearStartAtInit(self: *Self) void {
        self.impl.start_at_init = null;
    }

    pub fn setDispatchMode(self: *Self, value: DispatchMode) void {
        self.impl.dispatch_mode = value;
    }

    pub fn getDispatchMode(self: *const Self) ?DispatchMode {
        return self.impl.dispatch_mode;
    }

    pub fn hasDispatchMode(self: *const Self) bool {
        return self.impl.dispatch_mode != null;
    }

    pub fn clearDispatchMode(self: *Self) void {
        self.impl.dispatch_mode = null;
    }

    pub fn setDispatchBatchTimeMs(self: *Self, value: u32) void {
        self.impl.dispatch_batch_time_ms = value;
    }

    pub fn getDispatchBatchTimeMs(self: *const Self) ?u32 {
        return self.impl.dispatch_batch_time_ms;
    }

    pub fn hasDispatchBatchTimeMs(self: *const Self) bool {
        return self.impl.dispatch_batch_time_ms != null;
    }

    pub fn clearDispatchBatchTimeMs(self: *Self) void {
        self.impl.dispatch_batch_time_ms = null;
    }

    pub fn setKeyFile(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp = try allocator.dupe(u8, value);

        if (self.impl.key_file) |old| {
            allocator.free(old);
        }

        self.impl.key_file = tmp;
    }

    pub fn getKeyFile(self: *const Self) ?[]const u8 {
        return self.impl.key_file;
    }

    pub fn hasKeyFile(self: *const Self) bool {
        return self.impl.key_file != null;
    }

    pub fn clearKeyFile(self: *Self, allocator: std.mem.Allocator) void {
        if (self.impl.key_file) |old| {
            allocator.free(old);
        }

        self.impl.key_file = null;
    }

    pub fn getTransportsCount(self: *const Self) usize {
        return self.impl.transports.len;
    }

    pub fn getTransportsAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !TransportConfig {
        if (index >= self.impl.transports.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                TransportConfigImpl,
                allocator,
                &self.impl.transports[index],
            ),
        };
    }

    pub fn appendTransports(self: *Self, allocator: std.mem.Allocator, value: *const TransportConfig) !void {
        const tmp_item = try cloneImpl(
            TransportConfigImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.transports.len;
        self.impl.transports = try allocator.realloc(
            self.impl.transports,
            old_len + 1,
        );

        self.impl.transports[old_len] = tmp_item;
    }

    pub fn clearTransports(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.transports) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.transports);
        self.impl.transports = try allocator.alloc(TransportConfigImpl, 0);
    }

    pub fn getCrossConnectorsCount(self: *const Self) usize {
        return self.impl.cross_connectors.len;
    }

    pub fn getCrossConnectorsAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !CrossConnectorConfig {
        if (index >= self.impl.cross_connectors.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                CrossConnectorConfigImpl,
                allocator,
                &self.impl.cross_connectors[index],
            ),
        };
    }

    pub fn appendCrossConnectors(self: *Self, allocator: std.mem.Allocator, value: *const CrossConnectorConfig) !void {
        const tmp_item = try cloneImpl(
            CrossConnectorConfigImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.cross_connectors.len;
        self.impl.cross_connectors = try allocator.realloc(
            self.impl.cross_connectors,
            old_len + 1,
        );

        self.impl.cross_connectors[old_len] = tmp_item;
    }

    pub fn clearCrossConnectors(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.cross_connectors) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.cross_connectors);
        self.impl.cross_connectors = try allocator.alloc(CrossConnectorConfigImpl, 0);
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
            .impl = try DomainConfigImpl.legiElTeksto(
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
            .impl = try DomainConfigImpl.legiElDosiero(
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
            .impl = try DomainConfigImpl.deseriigiElBin(
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
            .impl = try DomainConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const TransportConfig = struct {
    impl: TransportConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try TransportConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                TransportConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setKind(self: *Self, value: TransportKind) void {
        self.impl.kind = value;
    }

    pub fn getKind(self: *const Self) TransportKind {
        return self.impl.kind;
    }

    pub fn setEncoding(self: *Self, value: Encoding) void {
        self.impl.encoding = value;
    }

    pub fn getEncoding(self: *const Self) ?Encoding {
        return self.impl.encoding;
    }

    pub fn hasEncoding(self: *const Self) bool {
        return self.impl.encoding != null;
    }

    pub fn clearEncoding(self: *Self) void {
        self.impl.encoding = null;
    }

    pub fn setName(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.name);
        self.impl.name = tmp;
    }

    pub fn getName(self: *const Self) []const u8 {
        return self.impl.name;
    }

    pub fn hasParams(self: *const Self) bool {
        return switch (self.impl.params) {
            .none => false,
            else => true,
        };
    }

    pub fn clearParams(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.impl.params) {
            .none => {},
            .mcast => |*value| {
                value.deinit(allocator);
            },
            .bcast => |*value| {
                value.deinit(allocator);
            },
            .udpstar => |*value| {
                value.deinit(allocator);
            },
            .usoxstar => |*value| {
                value.deinit(allocator);
            },
            .custom => |*value| {
                value.deinit(allocator);
            },
        }

        self.impl.params = .none;
    }

    pub fn setParamsMcast(self: *Self, allocator: std.mem.Allocator, value: *const MCastConfig) !void {
        const tmp = try cloneImpl(
            MCastConfigImpl,
            allocator,
            &value.impl,
        );

        self.clearParams(allocator);
        self.impl.params = .{ .mcast = tmp };
    }

    pub fn hasParamsMcast(self: *const Self) bool {
        return switch (self.impl.params) {
            .mcast => true,
            else => false,
        };
    }

    pub fn getParamsMcast(self: *const Self, allocator: std.mem.Allocator) !MCastConfig {
        return switch (self.impl.params) {
            .mcast => |*value| .{
                .impl = try cloneImpl(
                    MCastConfigImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
    }

    pub fn setParamsBcast(self: *Self, allocator: std.mem.Allocator, value: *const BCastConfig) !void {
        const tmp = try cloneImpl(
            BCastConfigImpl,
            allocator,
            &value.impl,
        );

        self.clearParams(allocator);
        self.impl.params = .{ .bcast = tmp };
    }

    pub fn hasParamsBcast(self: *const Self) bool {
        return switch (self.impl.params) {
            .bcast => true,
            else => false,
        };
    }

    pub fn getParamsBcast(self: *const Self, allocator: std.mem.Allocator) !BCastConfig {
        return switch (self.impl.params) {
            .bcast => |*value| .{
                .impl = try cloneImpl(
                    BCastConfigImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
    }

    pub fn setParamsUdpstar(self: *Self, allocator: std.mem.Allocator, value: *const UDPStarConfig) !void {
        const tmp = try cloneImpl(
            UDPStarConfigImpl,
            allocator,
            &value.impl,
        );

        self.clearParams(allocator);
        self.impl.params = .{ .udpstar = tmp };
    }

    pub fn hasParamsUdpstar(self: *const Self) bool {
        return switch (self.impl.params) {
            .udpstar => true,
            else => false,
        };
    }

    pub fn getParamsUdpstar(self: *const Self, allocator: std.mem.Allocator) !UDPStarConfig {
        return switch (self.impl.params) {
            .udpstar => |*value| .{
                .impl = try cloneImpl(
                    UDPStarConfigImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
    }

    pub fn setParamsUsoxstar(self: *Self, allocator: std.mem.Allocator, value: *const UnixSocketStarConfig) !void {
        const tmp = try cloneImpl(
            UnixSocketStarConfigImpl,
            allocator,
            &value.impl,
        );

        self.clearParams(allocator);
        self.impl.params = .{ .usoxstar = tmp };
    }

    pub fn hasParamsUsoxstar(self: *const Self) bool {
        return switch (self.impl.params) {
            .usoxstar => true,
            else => false,
        };
    }

    pub fn getParamsUsoxstar(self: *const Self, allocator: std.mem.Allocator) !UnixSocketStarConfig {
        return switch (self.impl.params) {
            .usoxstar => |*value| .{
                .impl = try cloneImpl(
                    UnixSocketStarConfigImpl,
                    allocator,
                    value,
                ),
            },
            else => error.WrongOneofField,
        };
    }

    pub fn setParamsCustom(self: *Self, allocator: std.mem.Allocator, value: *const CustomTransportConfig) !void {
        const tmp = try cloneImpl(
            CustomTransportConfigImpl,
            allocator,
            &value.impl,
        );

        self.clearParams(allocator);
        self.impl.params = .{ .custom = tmp };
    }

    pub fn hasParamsCustom(self: *const Self) bool {
        return switch (self.impl.params) {
            .custom => true,
            else => false,
        };
    }

    pub fn getParamsCustom(self: *const Self, allocator: std.mem.Allocator) !CustomTransportConfig {
        return switch (self.impl.params) {
            .custom => |*value| .{
                .impl = try cloneImpl(
                    CustomTransportConfigImpl,
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
            .impl = try TransportConfigImpl.legiElTeksto(
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
            .impl = try TransportConfigImpl.legiElDosiero(
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
            .impl = try TransportConfigImpl.deseriigiElBin(
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
            .impl = try TransportConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const MCastConfig = struct {
    impl: MCastConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try MCastConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                MCastConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setPort(self: *Self, value: i32) void {
        self.impl.port = value;
    }

    pub fn getPort(self: *const Self) i32 {
        return self.impl.port;
    }

    pub fn setTtl(self: *Self, value: i32) void {
        self.impl.ttl = value;
    }

    pub fn getTtl(self: *const Self) ?i32 {
        return self.impl.ttl;
    }

    pub fn hasTtl(self: *const Self) bool {
        return self.impl.ttl != null;
    }

    pub fn clearTtl(self: *Self) void {
        self.impl.ttl = null;
    }

    pub fn setReceiveBuffer(self: *Self, value: i32) void {
        self.impl.receive_buffer = value;
    }

    pub fn getReceiveBuffer(self: *const Self) ?i32 {
        return self.impl.receive_buffer;
    }

    pub fn hasReceiveBuffer(self: *const Self) bool {
        return self.impl.receive_buffer != null;
    }

    pub fn clearReceiveBuffer(self: *Self) void {
        self.impl.receive_buffer = null;
    }

    pub fn setSendBuffer(self: *Self, value: i32) void {
        self.impl.send_buffer = value;
    }

    pub fn getSendBuffer(self: *const Self) ?i32 {
        return self.impl.send_buffer;
    }

    pub fn hasSendBuffer(self: *const Self) bool {
        return self.impl.send_buffer != null;
    }

    pub fn clearSendBuffer(self: *Self) void {
        self.impl.send_buffer = null;
    }

    pub fn setMcastAddress(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.mcast_address);
        self.impl.mcast_address = tmp;
    }

    pub fn getMcastAddress(self: *const Self) []const u8 {
        return self.impl.mcast_address;
    }

    pub fn setLocalAddress(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp = try allocator.dupe(u8, value);

        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = tmp;
    }

    pub fn getLocalAddress(self: *const Self) ?[]const u8 {
        return self.impl.local_address;
    }

    pub fn hasLocalAddress(self: *const Self) bool {
        return self.impl.local_address != null;
    }

    pub fn clearLocalAddress(self: *Self, allocator: std.mem.Allocator) void {
        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = null;
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
            .impl = try MCastConfigImpl.legiElTeksto(
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
            .impl = try MCastConfigImpl.legiElDosiero(
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
            .impl = try MCastConfigImpl.deseriigiElBin(
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
            .impl = try MCastConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const BCastConfig = struct {
    impl: BCastConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try BCastConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                BCastConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setPort(self: *Self, value: i32) void {
        self.impl.port = value;
    }

    pub fn getPort(self: *const Self) i32 {
        return self.impl.port;
    }

    pub fn setReceiveBuffer(self: *Self, value: i32) void {
        self.impl.receive_buffer = value;
    }

    pub fn getReceiveBuffer(self: *const Self) ?i32 {
        return self.impl.receive_buffer;
    }

    pub fn hasReceiveBuffer(self: *const Self) bool {
        return self.impl.receive_buffer != null;
    }

    pub fn clearReceiveBuffer(self: *Self) void {
        self.impl.receive_buffer = null;
    }

    pub fn setSendBuffer(self: *Self, value: i32) void {
        self.impl.send_buffer = value;
    }

    pub fn getSendBuffer(self: *const Self) ?i32 {
        return self.impl.send_buffer;
    }

    pub fn hasSendBuffer(self: *const Self) bool {
        return self.impl.send_buffer != null;
    }

    pub fn clearSendBuffer(self: *Self) void {
        self.impl.send_buffer = null;
    }

    pub fn setBcastAddress(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.bcast_address);
        self.impl.bcast_address = tmp;
    }

    pub fn getBcastAddress(self: *const Self) []const u8 {
        return self.impl.bcast_address;
    }

    pub fn setLocalAddress(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp = try allocator.dupe(u8, value);

        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = tmp;
    }

    pub fn getLocalAddress(self: *const Self) ?[]const u8 {
        return self.impl.local_address;
    }

    pub fn hasLocalAddress(self: *const Self) bool {
        return self.impl.local_address != null;
    }

    pub fn clearLocalAddress(self: *Self, allocator: std.mem.Allocator) void {
        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = null;
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
            .impl = try BCastConfigImpl.legiElTeksto(
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
            .impl = try BCastConfigImpl.legiElDosiero(
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
            .impl = try BCastConfigImpl.deseriigiElBin(
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
            .impl = try BCastConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const UDPStarConfig = struct {
    impl: UDPStarConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try UDPStarConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                UDPStarConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setPort(self: *Self, value: i32) void {
        self.impl.port = value;
    }

    pub fn getPort(self: *const Self) i32 {
        return self.impl.port;
    }

    pub fn setReceiveBuffer(self: *Self, value: i32) void {
        self.impl.receive_buffer = value;
    }

    pub fn getReceiveBuffer(self: *const Self) ?i32 {
        return self.impl.receive_buffer;
    }

    pub fn hasReceiveBuffer(self: *const Self) bool {
        return self.impl.receive_buffer != null;
    }

    pub fn clearReceiveBuffer(self: *Self) void {
        self.impl.receive_buffer = null;
    }

    pub fn setSendBuffer(self: *Self, value: i32) void {
        self.impl.send_buffer = value;
    }

    pub fn getSendBuffer(self: *const Self) ?i32 {
        return self.impl.send_buffer;
    }

    pub fn hasSendBuffer(self: *const Self) bool {
        return self.impl.send_buffer != null;
    }

    pub fn clearSendBuffer(self: *Self) void {
        self.impl.send_buffer = null;
    }

    pub fn setLocalAddress(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp = try allocator.dupe(u8, value);

        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = tmp;
    }

    pub fn getLocalAddress(self: *const Self) ?[]const u8 {
        return self.impl.local_address;
    }

    pub fn hasLocalAddress(self: *const Self) bool {
        return self.impl.local_address != null;
    }

    pub fn clearLocalAddress(self: *Self, allocator: std.mem.Allocator) void {
        if (self.impl.local_address) |old| {
            allocator.free(old);
        }

        self.impl.local_address = null;
    }

    pub fn getEndPointCount(self: *const Self) usize {
        return self.impl.end_point.len;
    }

    pub fn getEndPointAt(self: *const Self, allocator: std.mem.Allocator, index: usize) !EndPointConfig {
        if (index >= self.impl.end_point.len) {
            return error.IndexOutOfBounds;
        }

        return .{
            .impl = try cloneImpl(
                EndPointConfigImpl,
                allocator,
                &self.impl.end_point[index],
            ),
        };
    }

    pub fn appendEndPoint(self: *Self, allocator: std.mem.Allocator, value: *const EndPointConfig) !void {
        const tmp_item = try cloneImpl(
            EndPointConfigImpl,
            allocator,
            &value.impl,
        );
        errdefer tmp_item.deinit(allocator);

        const old_len = self.impl.end_point.len;
        self.impl.end_point = try allocator.realloc(
            self.impl.end_point,
            old_len + 1,
        );

        self.impl.end_point[old_len] = tmp_item;
    }

    pub fn clearEndPoint(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.end_point) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.impl.end_point);
        self.impl.end_point = try allocator.alloc(EndPointConfigImpl, 0);
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
            .impl = try UDPStarConfigImpl.legiElTeksto(
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
            .impl = try UDPStarConfigImpl.legiElDosiero(
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
            .impl = try UDPStarConfigImpl.deseriigiElBin(
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
            .impl = try UDPStarConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const EndPointConfig = struct {
    impl: EndPointConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try EndPointConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                EndPointConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setPort(self: *Self, value: i32) void {
        self.impl.port = value;
    }

    pub fn getPort(self: *const Self) i32 {
        return self.impl.port;
    }

    pub fn setHost(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.host);
        self.impl.host = tmp;
    }

    pub fn getHost(self: *const Self) []const u8 {
        return self.impl.host;
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
            .impl = try EndPointConfigImpl.legiElTeksto(
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
            .impl = try EndPointConfigImpl.legiElDosiero(
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
            .impl = try EndPointConfigImpl.deseriigiElBin(
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
            .impl = try EndPointConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const UnixSocketStarConfig = struct {
    impl: UnixSocketStarConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try UnixSocketStarConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                UnixSocketStarConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setReceiveBuffer(self: *Self, value: i32) void {
        self.impl.receive_buffer = value;
    }

    pub fn getReceiveBuffer(self: *const Self) ?i32 {
        return self.impl.receive_buffer;
    }

    pub fn hasReceiveBuffer(self: *const Self) bool {
        return self.impl.receive_buffer != null;
    }

    pub fn clearReceiveBuffer(self: *Self) void {
        self.impl.receive_buffer = null;
    }

    pub fn setSendBuffer(self: *Self, value: i32) void {
        self.impl.send_buffer = value;
    }

    pub fn getSendBuffer(self: *const Self) ?i32 {
        return self.impl.send_buffer;
    }

    pub fn hasSendBuffer(self: *const Self) bool {
        return self.impl.send_buffer != null;
    }

    pub fn clearSendBuffer(self: *Self) void {
        self.impl.send_buffer = null;
    }

    pub fn setLocalSocketPath(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.local_socket_path);
        self.impl.local_socket_path = tmp;
    }

    pub fn getLocalSocketPath(self: *const Self) []const u8 {
        return self.impl.local_socket_path;
    }

    pub fn getRemoteSocketPathsCount(self: *const Self) usize {
        return self.impl.remote_socket_paths.len;
    }

    pub fn getRemoteSocketPathsAt(self: *const Self, index: usize) ![]const u8 {
        if (index >= self.impl.remote_socket_paths.len) {
            return error.IndexOutOfBounds;
        }

        return self.impl.remote_socket_paths[index];
    }

    pub fn appendRemoteSocketPaths(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp_item = try allocator.dupe(u8, value);
        errdefer allocator.free(tmp_item);

        const old_len = self.impl.remote_socket_paths.len;
        self.impl.remote_socket_paths = try allocator.realloc(
            self.impl.remote_socket_paths,
            old_len + 1,
        );

        self.impl.remote_socket_paths[old_len] = tmp_item;
    }

    pub fn setRemoteSocketPaths(self: *Self, allocator: std.mem.Allocator, values: []const []const u8) !void {
        var tmp_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (tmp_list.items) |item| {
                allocator.free(item);
            }
            tmp_list.deinit(allocator);
        }

        for (values) |value| {
            const tmp_item = try allocator.dupe(u8, value);
            errdefer allocator.free(tmp_item);
            try tmp_list.append(allocator, tmp_item);
        }

        const tmp = try tmp_list.toOwnedSlice(allocator);

        for (self.impl.remote_socket_paths) |item| {
            allocator.free(item);
        }
        allocator.free(self.impl.remote_socket_paths);

        self.impl.remote_socket_paths = tmp;
    }

    pub fn clearRemoteSocketPaths(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.remote_socket_paths) |item| {
            allocator.free(item);
        }
        allocator.free(self.impl.remote_socket_paths);
        self.impl.remote_socket_paths = try allocator.alloc([]const u8, 0);
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
            .impl = try UnixSocketStarConfigImpl.legiElTeksto(
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
            .impl = try UnixSocketStarConfigImpl.legiElDosiero(
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
            .impl = try UnixSocketStarConfigImpl.deseriigiElBin(
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
            .impl = try UnixSocketStarConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const CustomTransportConfig = struct {
    impl: CustomTransportConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try CustomTransportConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                CustomTransportConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn setSubType(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.sub_type);
        self.impl.sub_type = tmp;
    }

    pub fn getSubType(self: *const Self) []const u8 {
        return self.impl.sub_type;
    }

    pub fn setConfig(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.config);
        self.impl.config = tmp;
    }

    pub fn getConfig(self: *const Self) []const u8 {
        return self.impl.config;
    }

    pub fn setPlugInLib(
        self: *Self,
        allocator: std.mem.Allocator,
        value: []const u8,
    ) !void {
        const tmp = try allocator.dupe(u8, value);
        allocator.free(self.impl.plug_in_lib);
        self.impl.plug_in_lib = tmp;
    }

    pub fn getPlugInLib(self: *const Self) []const u8 {
        return self.impl.plug_in_lib;
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
            .impl = try CustomTransportConfigImpl.legiElTeksto(
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
            .impl = try CustomTransportConfigImpl.legiElDosiero(
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
            .impl = try CustomTransportConfigImpl.deseriigiElBin(
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
            .impl = try CustomTransportConfigImpl.deseriigiElDosiero(
                allocator,
                path,
                format,
            ),
        };
    }
};

pub const CrossConnectorConfig = struct {
    impl: CrossConnectorConfigImpl,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try CrossConnectorConfigImpl.initDefault(allocator),
        };
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        self.impl.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return .{
            .impl = try cloneImpl(
                CrossConnectorConfigImpl,
                allocator,
                &self.impl,
            ),
        };
    }

    pub fn getTransportsCount(self: *const Self) usize {
        return self.impl.transports.len;
    }

    pub fn getTransportsAt(self: *const Self, index: usize) ![]const u8 {
        if (index >= self.impl.transports.len) {
            return error.IndexOutOfBounds;
        }

        return self.impl.transports[index];
    }

    pub fn appendTransports(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        const tmp_item = try allocator.dupe(u8, value);
        errdefer allocator.free(tmp_item);

        const old_len = self.impl.transports.len;
        self.impl.transports = try allocator.realloc(
            self.impl.transports,
            old_len + 1,
        );

        self.impl.transports[old_len] = tmp_item;
    }

    pub fn setTransports(self: *Self, allocator: std.mem.Allocator, values: []const []const u8) !void {
        var tmp_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (tmp_list.items) |item| {
                allocator.free(item);
            }
            tmp_list.deinit(allocator);
        }

        for (values) |value| {
            const tmp_item = try allocator.dupe(u8, value);
            errdefer allocator.free(tmp_item);
            try tmp_list.append(allocator, tmp_item);
        }

        const tmp = try tmp_list.toOwnedSlice(allocator);

        for (self.impl.transports) |item| {
            allocator.free(item);
        }
        allocator.free(self.impl.transports);

        self.impl.transports = tmp;
    }

    pub fn clearTransports(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.impl.transports) |item| {
            allocator.free(item);
        }
        allocator.free(self.impl.transports);
        self.impl.transports = try allocator.alloc([]const u8, 0);
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
            .impl = try CrossConnectorConfigImpl.legiElTeksto(
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
            .impl = try CrossConnectorConfigImpl.legiElDosiero(
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
            .impl = try CrossConnectorConfigImpl.deseriigiElBin(
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
            .impl = try CrossConnectorConfigImpl.deseriigiElDosiero(
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
