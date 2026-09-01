const std = @import("std");
const dbg = std.debug;
const all = std.mem;
const equal = std.mem.eql;
const  io = std.Io;

const encdec = @import("encdec.zig");
const EncodeBuffer = encdec.EncodeBuffer;
const DecodeBuffer = encdec.DecodeBuffer;

//const TokenIterType = std.mem.TokenIterator(u8, .any);
const TokenIterType = CustomTokenizer;

pub const k6bus = struct {

    pub const config = struct {


pub const BinaryFormat = enum(u64) {
   BF_PROTOBUF = 0,
   BF_OMG_CDR = 1,
   BF_ASN1_BER = 2,
   BF_ASN1_DER = 3,
};

pub const DispatchMode = enum(u64) {
   IMMEDIATE = 0,
   BATCH = 1,
};

pub const TransportKind = enum(u64) {
   LOOP = 0,
   MCAST = 1,
   BCAST = 2,
   UDPSTAR = 3,
   USOXSTAR = 4,
   CUSTOM = 100,
};

pub const Encoding = enum(u64) {
   RAW = 0,
   BASE64 = 1,
};

pub const AppConfig = struct {
    version: ?u32 = 1 ,
    activate_trace: ?bool = false ,
    trace_level: ?i32 = 0 ,
    domains: []DomainConfig,

    pub fn initDefault(allocator: all.Allocator) !AppConfig {
        return AppConfig {
            .version = 1,
            .activate_trace = false,
            .trace_level = 0,
            .domains = try allocator.alloc(DomainConfig, 0),
        };
    }

    pub fn deinit(self: *const AppConfig, allocator: all.Allocator) void {
        for (self.domains) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.domains);
    }

    pub fn skribiAlTeksto(self: *AppConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, AppConfig, @as(*AppConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *AppConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, AppConfig, @as(*AppConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !AppConfig {
        return try legiTiponElTeksto(allocator, AppConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !AppConfig {
        return try legiTiponElDosiero(allocator, AppConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const AppConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.version ) |val|  
            try bufro.print(allocator,"{s}version: {any}\n",.{ ind, val });
        if( self.activate_trace ) |val|  
            try bufro.print(allocator,"{s}activate_trace: {any}\n",.{ ind, val });
        if( self.trace_level ) |val|  
            try bufro.print(allocator,"{s}trace_level: {any}\n",.{ ind, val });
        for(self.domains) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const domains_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(domains_text);

            try bufro.print(allocator, "{s}domains {{\n{s}{s}}}\n", .{ ind, domains_text, ind });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !AppConfig {
        var mia_Mesagho = try AppConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var domains_list: std.ArrayList(DomainConfig) = .empty;
        errdefer {
            for (domains_list.items) |*item| {
                item.deinit(allocator);
            }
            domains_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "version" ) ) {
                mia_Mesagho.version =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "activate_trace" ) ) {
                mia_Mesagho.activate_trace =  if( equal(u8, val,"true") ) true else false;
                continue;
            }
            if( equal(u8, tok, "trace_level" ) ) {
                mia_Mesagho.trace_level =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "domains" ) ) {
                const sub_msg = try DomainConfig.legiElProtobufTeksto(allocator, it); 
                domains_list.append(allocator, sub_msg) catch |err| {
                    sub_msg.deinit(allocator);
                    return err;
                };
                continue;
            }
        }
        for (mia_Mesagho.domains) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.domains);
        mia_Mesagho.domains = try domains_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const AppConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, AppConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const AppConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, AppConfig, @as(*AppConfig, self), path, b_formato);
    }

    fn seriigi(self: *const AppConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        var domains_i: usize = self.domains.len;
        while (domains_i > 0) {
            domains_i -= 1;
            const item = self.domains[domains_i];
            const domains_longa = try item.seriigi( allocator, buffer );
            tuta_longo += domains_longa;
            tuta_longo += try buffer.encodeVarint(domains_longa);
            tuta_longo += try buffer.encodeVarint(34);
        }  // 11  rept - no def - varlong

        if( self.trace_level ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(24);
        }   //1 opt - no def - no varlong

        if( self.activate_trace ) |val| {
            tuta_longo += try buffer.encodeBool( val );
            tuta_longo += try buffer.encodeVarint(16);
        }   //1 opt - no def - no varlong

        if( self.version ) |val| {
            tuta_longo += try buffer.encodeUint32( val );
            tuta_longo += try buffer.encodeVarint(8);
        }   //1 opt - no def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !AppConfig {
        return try deseriigiTiponElBin(allocator, AppConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !AppConfig {
        return try deseriigiTiponElDosiero(allocator, AppConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !AppConfig {
        var mia_Mesagho = try AppConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var domains_list: std.ArrayList(DomainConfig) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 0 ) 
                mia_Mesagho.version = try buffer.decodeUint32()
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.activate_trace = try buffer.decodeBool()
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.trace_level = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 2 ) 
            { 
                try domains_list.append( 
                    allocator, 
                    try DomainConfig.deseriigi(allocator, buffer, try buffer.decodeVarint() )
                );
            }
        }

        const tmp_domains = try domains_list.toOwnedSlice(allocator);
        for (mia_Mesagho.domains) |*item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.domains);
        mia_Mesagho.domains = tmp_domains;

        return mia_Mesagho;
    }
};    // AppConfig

pub const DomainConfig = struct {
    id: u32,
    activate_default_transport: ?bool = true ,
    direct_dispatch_to_subs: ?bool = false ,
    key_file: ?[]const u8 = null,
    binary_format: ?BinaryFormat = .BF_PROTOBUF ,
    start_at_init: ?bool = true ,
    dispatch_mode: ?DispatchMode = .IMMEDIATE ,
    dispatch_batch_time_ms: ?u32 = 0 ,
    transports: []TransportConfig,
    cross_connectors: []CrossConnectorConfig,

    pub fn initDefault(allocator: all.Allocator) !DomainConfig {
        return DomainConfig {
            .id = 0,
            .activate_default_transport = true,
            .direct_dispatch_to_subs = false,
            .key_file = null,
            .binary_format = .BF_PROTOBUF,
            .start_at_init = true,
            .dispatch_mode = .IMMEDIATE,
            .dispatch_batch_time_ms = 0,
            .transports = try allocator.alloc(TransportConfig, 0),
            .cross_connectors = try allocator.alloc(CrossConnectorConfig, 0),
        };
    }

    pub fn deinit(self: *const DomainConfig, allocator: all.Allocator) void {
        if( self.key_file ) |f| {
            allocator.free(f);
        }
        for (self.transports) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.transports);
        for (self.cross_connectors) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.cross_connectors);
    }

    pub fn skribiAlTeksto(self: *DomainConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, DomainConfig, @as(*DomainConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *DomainConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, DomainConfig, @as(*DomainConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !DomainConfig {
        return try legiTiponElTeksto(allocator, DomainConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !DomainConfig {
        return try legiTiponElDosiero(allocator, DomainConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const DomainConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}id: {any}\n",.{ind, self.id });
        if( self.activate_default_transport ) |val|  
            try bufro.print(allocator,"{s}activate_default_transport: {any}\n",.{ ind, val });
        if( self.direct_dispatch_to_subs ) |val|  
            try bufro.print(allocator,"{s}direct_dispatch_to_subs: {any}\n",.{ ind, val });
        if( self.key_file ) |val|  
            try bufro.print(allocator,"{s}key_file: \"{s}\"\n",.{ ind, val });
        if( self.binary_format ) |val|  
            try bufro.print(allocator, "{s}binary_format: {s}\n", .{ ind, @tagName(val) });
        if( self.start_at_init ) |val|  
            try bufro.print(allocator,"{s}start_at_init: {any}\n",.{ ind, val });
        if( self.dispatch_mode ) |val|  
            try bufro.print(allocator, "{s}dispatch_mode: {s}\n", .{ ind, @tagName(val) });
        if( self.dispatch_batch_time_ms ) |val|  
            try bufro.print(allocator,"{s}dispatch_batch_time_ms: {any}\n",.{ ind, val });
        for(self.transports) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const transports_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(transports_text);

            try bufro.print(allocator, "{s}transports {{\n{s}{s}}}\n", .{ ind, transports_text, ind });
        }
        for(self.cross_connectors) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const cross_connectors_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(cross_connectors_text);

            try bufro.print(allocator, "{s}cross_connectors {{\n{s}{s}}}\n", .{ ind, cross_connectors_text, ind });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !DomainConfig {
        var mia_Mesagho = try DomainConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var transports_list: std.ArrayList(TransportConfig) = .empty;
        errdefer {
            for (transports_list.items) |*item| {
                item.deinit(allocator);
            }
            transports_list.deinit(allocator);
        }
        var cross_connectors_list: std.ArrayList(CrossConnectorConfig) = .empty;
        errdefer {
            for (cross_connectors_list.items) |*item| {
                item.deinit(allocator);
            }
            cross_connectors_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "id" ) ) {
                mia_Mesagho.id =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "activate_default_transport" ) ) {
                mia_Mesagho.activate_default_transport =  if( equal(u8, val,"true") ) true else false;
                continue;
            }
            if( equal(u8, tok, "direct_dispatch_to_subs" ) ) {
                mia_Mesagho.direct_dispatch_to_subs =  if( equal(u8, val,"true") ) true else false;
                continue;
            }
            if( equal(u8, tok, "key_file" ) ) {
                const tmp_key_file = try unescapePbTextToken(allocator, val);
                if (mia_Mesagho.key_file) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.key_file = tmp_key_file;
                continue;
            }
            if( equal(u8, tok, "binary_format" ) ) {
                mia_Mesagho.binary_format = parseEnumValue(BinaryFormat, val) catch (std.meta.intToEnum(BinaryFormat, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "start_at_init" ) ) {
                mia_Mesagho.start_at_init =  if( equal(u8, val,"true") ) true else false;
                continue;
            }
            if( equal(u8, tok, "dispatch_mode" ) ) {
                mia_Mesagho.dispatch_mode = parseEnumValue(DispatchMode, val) catch (std.meta.intToEnum(DispatchMode, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "dispatch_batch_time_ms" ) ) {
                mia_Mesagho.dispatch_batch_time_ms =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "transports" ) ) {
                const sub_msg = try TransportConfig.legiElProtobufTeksto(allocator, it); 
                transports_list.append(allocator, sub_msg) catch |err| {
                    sub_msg.deinit(allocator);
                    return err;
                };
                continue;
            }
            if( equal(u8, tok, "cross_connectors" ) ) {
                const sub_msg = try CrossConnectorConfig.legiElProtobufTeksto(allocator, it); 
                cross_connectors_list.append(allocator, sub_msg) catch |err| {
                    sub_msg.deinit(allocator);
                    return err;
                };
                continue;
            }
        }
        for (mia_Mesagho.transports) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.transports);
        mia_Mesagho.transports = try transports_list.toOwnedSlice(allocator); 
        for (mia_Mesagho.cross_connectors) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.cross_connectors);
        mia_Mesagho.cross_connectors = try cross_connectors_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const DomainConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, DomainConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const DomainConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, DomainConfig, @as(*DomainConfig, self), path, b_formato);
    }

    fn seriigi(self: *const DomainConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        var cross_connectors_i: usize = self.cross_connectors.len;
        while (cross_connectors_i > 0) {
            cross_connectors_i -= 1;
            const item = self.cross_connectors[cross_connectors_i];
            const cross_connectors_longa = try item.seriigi( allocator, buffer );
            tuta_longo += cross_connectors_longa;
            tuta_longo += try buffer.encodeVarint(cross_connectors_longa);
            tuta_longo += try buffer.encodeVarint(82);
        }  // 11  rept - no def - varlong

        var transports_i: usize = self.transports.len;
        while (transports_i > 0) {
            transports_i -= 1;
            const item = self.transports[transports_i];
            const transports_longa = try item.seriigi( allocator, buffer );
            tuta_longo += transports_longa;
            tuta_longo += try buffer.encodeVarint(transports_longa);
            tuta_longo += try buffer.encodeVarint(74);
        }  // 11  rept - no def - varlong

        if( self.dispatch_batch_time_ms ) |val| {
            tuta_longo += try buffer.encodeUint32( val );
            tuta_longo += try buffer.encodeVarint(64);
        }   //1 opt - no def - no varlong

        if( self.dispatch_mode ) |val| {
            tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
            tuta_longo += try buffer.encodeVarint(56);
        }   //1 opt - no def - no varlong

        if( self.start_at_init ) |val| {
            tuta_longo += try buffer.encodeBool( val );
            tuta_longo += try buffer.encodeVarint(48);
        }   //1 opt - no def - no varlong

        if( self.binary_format ) |val| {
            tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
            tuta_longo += try buffer.encodeVarint(40);
        }   //1 opt - no def - no varlong

        if ( self.key_file ) |val| {
            const st_longa = try buffer.encodeString( val );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(34);
        }  //3  opt - no def - varlong

        if( self.direct_dispatch_to_subs ) |val| {
            tuta_longo += try buffer.encodeBool( val );
            tuta_longo += try buffer.encodeVarint(24);
        }   //1 opt - no def - no varlong

        if( self.activate_default_transport ) |val| {
            tuta_longo += try buffer.encodeBool( val );
            tuta_longo += try buffer.encodeVarint(16);
        }   //1 opt - no def - no varlong

        tuta_longo += try buffer.encodeUint32( self.id );
        tuta_longo += try buffer.encodeVarint(8);
        //5 req - no def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !DomainConfig {
        return try deseriigiTiponElBin(allocator, DomainConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !DomainConfig {
        return try deseriigiTiponElDosiero(allocator, DomainConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !DomainConfig {
        var mia_Mesagho = try DomainConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var transports_list: std.ArrayList(TransportConfig) = .empty; 
        var cross_connectors_list: std.ArrayList(CrossConnectorConfig) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 0 ) 
                mia_Mesagho.id = try buffer.decodeUint32()
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.activate_default_transport = try buffer.decodeBool()
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.direct_dispatch_to_subs = try buffer.decodeBool()
            else if ( field_number == 4 and wire_type == 2 ) 
            {
                const tmp_key_file = try buffer.decodeString(  try buffer.decodeVarint() );
                if (mia_Mesagho.key_file) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.key_file = tmp_key_file;
            }
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.binary_format = try std.meta.intToEnum(BinaryFormat, try buffer.decodeVarint() ) 
            else if ( field_number == 6 and wire_type == 0 ) 
                mia_Mesagho.start_at_init = try buffer.decodeBool()
            else if ( field_number == 7 and wire_type == 0 ) 
                mia_Mesagho.dispatch_mode = try std.meta.intToEnum(DispatchMode, try buffer.decodeVarint() ) 
            else if ( field_number == 8 and wire_type == 0 ) 
                mia_Mesagho.dispatch_batch_time_ms = try buffer.decodeUint32()
            else if ( field_number == 9 and wire_type == 2 ) 
            { 
                try transports_list.append( 
                    allocator, 
                    try TransportConfig.deseriigi(allocator, buffer, try buffer.decodeVarint() )
                );
            }
            else if ( field_number == 10 and wire_type == 2 ) 
            { 
                try cross_connectors_list.append( 
                    allocator, 
                    try CrossConnectorConfig.deseriigi(allocator, buffer, try buffer.decodeVarint() )
                );
            }
        }

        const tmp_transports = try transports_list.toOwnedSlice(allocator);
        for (mia_Mesagho.transports) |*item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.transports);
        mia_Mesagho.transports = tmp_transports;
        const tmp_cross_connectors = try cross_connectors_list.toOwnedSlice(allocator);
        for (mia_Mesagho.cross_connectors) |*item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.cross_connectors);
        mia_Mesagho.cross_connectors = tmp_cross_connectors;

        return mia_Mesagho;
    }
};    // DomainConfig

pub const TransportConfig = struct {
    pub const Params = union(enum) {
        none: void,
        loop: LoopTransportConfig,
        mcast: MCastConfig,
        bcast: BCastConfig,
        udpstar: UDPStarConfig,
        usoxstar: UnixSocketStarConfig,
        custom: CustomTransportConfig,
    };

    name: []const u8,
    kind: TransportKind = .MCAST ,
    encoding: ?Encoding = .RAW ,
    params: Params,

    pub fn initDefault(allocator: all.Allocator) !TransportConfig {
        return TransportConfig {
            .name = try allocator.dupe(u8, ""),
            .kind = .MCAST,
            .encoding = .RAW,
            .params = .{ .none = {} },
        };
    }

    fn deinitParams(self: *const TransportConfig, allocator: all.Allocator) void {
        switch (self.params) {
            .none => {},
            .loop => |*v| v.deinit(allocator),
            .mcast => |*v| v.deinit(allocator),
            .bcast => |*v| v.deinit(allocator),
            .udpstar => |*v| v.deinit(allocator),
            .usoxstar => |*v| v.deinit(allocator),
            .custom => |*v| v.deinit(allocator),
        }
    }

    pub fn deinit(self: *const TransportConfig, allocator: all.Allocator) void {
        allocator.free(self.name);
        self.deinitParams(allocator);
    }

    pub fn skribiAlTeksto(self: *TransportConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, TransportConfig, @as(*TransportConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *TransportConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, TransportConfig, @as(*TransportConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !TransportConfig {
        return try legiTiponElTeksto(allocator, TransportConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !TransportConfig {
        return try legiTiponElDosiero(allocator, TransportConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const TransportConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}name: \"{s}\"\n",.{ind, self.name });
        try bufro.print(allocator, "{s}kind: {s}\n", .{ ind, @tagName(self.kind) });
        if( self.encoding ) |val|  
            try bufro.print(allocator, "{s}encoding: {s}\n", .{ ind, @tagName(val) });
        switch (self.params) {
            .none => {},
            .loop => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const loop_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(loop_text);

                try bufro.print(allocator, "{s}loop {{\n{s}{s}}}\n", .{ ind, loop_text, ind });
            },
            .mcast => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const mcast_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(mcast_text);

                try bufro.print(allocator, "{s}mcast {{\n{s}{s}}}\n", .{ ind, mcast_text, ind });
            },
            .bcast => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const bcast_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(bcast_text);

                try bufro.print(allocator, "{s}bcast {{\n{s}{s}}}\n", .{ ind, bcast_text, ind });
            },
            .udpstar => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const udpstar_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(udpstar_text);

                try bufro.print(allocator, "{s}udpstar {{\n{s}{s}}}\n", .{ ind, udpstar_text, ind });
            },
            .usoxstar => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const usoxstar_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(usoxstar_text);

                try bufro.print(allocator, "{s}usoxstar {{\n{s}{s}}}\n", .{ ind, usoxstar_text, ind });
            },
            .custom => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const custom_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(custom_text);

                try bufro.print(allocator, "{s}custom {{\n{s}{s}}}\n", .{ ind, custom_text, ind });
            },
        }


        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !TransportConfig {
        var mia_Mesagho = try TransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "name" ) ) {
                const tmp_name = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.name);
                mia_Mesagho.name = tmp_name;
                continue;
            }
            if( equal(u8, tok, "kind" ) ) {
                mia_Mesagho.kind = parseEnumValue(TransportKind, val) catch (std.meta.intToEnum(TransportKind, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "encoding" ) ) {
                mia_Mesagho.encoding = parseEnumValue(Encoding, val) catch (std.meta.intToEnum(Encoding, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "loop" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_loop_val = try LoopTransportConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .loop = params_loop_val };
                continue;
            }
            if( equal(u8, tok, "mcast" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_mcast_val = try MCastConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .mcast = params_mcast_val };
                continue;
            }
            if( equal(u8, tok, "bcast" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_bcast_val = try BCastConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .bcast = params_bcast_val };
                continue;
            }
            if( equal(u8, tok, "udpstar" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_udpstar_val = try UDPStarConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .udpstar = params_udpstar_val };
                continue;
            }
            if( equal(u8, tok, "usoxstar" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_usoxstar_val = try UnixSocketStarConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .usoxstar = params_usoxstar_val };
                continue;
            }
            if( equal(u8, tok, "custom" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const params_custom_val = try CustomTransportConfig.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .custom = params_custom_val };
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const TransportConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, TransportConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const TransportConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, TransportConfig, @as(*TransportConfig, self), path, b_formato);
    }

    fn seriigi(self: *const TransportConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        switch (self.params) {
            .none => {},
            .loop => |val| {
                const params_loop_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_loop_longa;
                tuta_longo += try buffer.encodeVarint(params_loop_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 10) << 3) | 2);
            },
            .mcast => |val| {
                const params_mcast_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_mcast_longa;
                tuta_longo += try buffer.encodeVarint(params_mcast_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 11) << 3) | 2);
            },
            .bcast => |val| {
                const params_bcast_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_bcast_longa;
                tuta_longo += try buffer.encodeVarint(params_bcast_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 12) << 3) | 2);
            },
            .udpstar => |val| {
                const params_udpstar_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_udpstar_longa;
                tuta_longo += try buffer.encodeVarint(params_udpstar_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 13) << 3) | 2);
            },
            .usoxstar => |val| {
                const params_usoxstar_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_usoxstar_longa;
                tuta_longo += try buffer.encodeVarint(params_usoxstar_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 14) << 3) | 2);
            },
            .custom => |val| {
                const params_custom_longa = try val.seriigi(allocator, buffer);
                tuta_longo += params_custom_longa;
                tuta_longo += try buffer.encodeVarint(params_custom_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 100) << 3) | 2);
            },
        }

        if( self.encoding ) |val| {
            tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
            tuta_longo += try buffer.encodeVarint(24);
        }   //1 opt - no def - no varlong

        if( self.kind != .MCAST )  {
            tuta_longo += try buffer.encodeVarint( @intFromEnum(self.kind) );
            tuta_longo += try buffer.encodeVarint(16);
        }  //6  req - def - no varlong

        const name_longa = try buffer.encodeString( self.name );
        tuta_longo += name_longa;
        tuta_longo += try buffer.encodeVarint(name_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !TransportConfig {
        return try deseriigiTiponElBin(allocator, TransportConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !TransportConfig {
        return try deseriigiTiponElDosiero(allocator, TransportConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !TransportConfig {
        var mia_Mesagho = try TransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 10 and wire_type == 2 )
            {
                const params_loop_val = try LoopTransportConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .loop = params_loop_val };
            }
            else if ( field_number == 11 and wire_type == 2 )
            {
                const params_mcast_val = try MCastConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .mcast = params_mcast_val };
            }
            else if ( field_number == 12 and wire_type == 2 )
            {
                const params_bcast_val = try BCastConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .bcast = params_bcast_val };
            }
            else if ( field_number == 13 and wire_type == 2 )
            {
                const params_udpstar_val = try UDPStarConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .udpstar = params_udpstar_val };
            }
            else if ( field_number == 14 and wire_type == 2 )
            {
                const params_usoxstar_val = try UnixSocketStarConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .usoxstar = params_usoxstar_val };
            }
            else if ( field_number == 100 and wire_type == 2 )
            {
                const params_custom_val = try CustomTransportConfig.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitParams(allocator);
                mia_Mesagho.params = .{ .custom = params_custom_val };
            }
            else if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_name = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.name);
                mia_Mesagho.name = tmp_name;
            }
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.kind = try std.meta.intToEnum(TransportKind, try buffer.decodeVarint() ) 
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.encoding = try std.meta.intToEnum(Encoding, try buffer.decodeVarint() ) ;
        }


        return mia_Mesagho;
    }
};    // TransportConfig

pub const LoopTransportConfig = struct {
    delay_ms: ?u32 = 200 ,

    pub fn initDefault(allocator: all.Allocator) !LoopTransportConfig {
        _ = allocator;
        return LoopTransportConfig {
            .delay_ms = 200,
        };
    }

    pub fn deinit(self: *const LoopTransportConfig, allocator: all.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn skribiAlTeksto(self: *LoopTransportConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, LoopTransportConfig, @as(*LoopTransportConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *LoopTransportConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, LoopTransportConfig, @as(*LoopTransportConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !LoopTransportConfig {
        return try legiTiponElTeksto(allocator, LoopTransportConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !LoopTransportConfig {
        return try legiTiponElDosiero(allocator, LoopTransportConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const LoopTransportConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.delay_ms ) |val|  
            try bufro.print(allocator,"{s}delay_ms: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !LoopTransportConfig {
        var mia_Mesagho = try LoopTransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "delay_ms" ) ) {
                mia_Mesagho.delay_ms =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const LoopTransportConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, LoopTransportConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const LoopTransportConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, LoopTransportConfig, @as(*LoopTransportConfig, self), path, b_formato);
    }

    fn seriigi(self: *const LoopTransportConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        if( self.delay_ms ) |val| {
            tuta_longo += try buffer.encodeUint32( val );
            tuta_longo += try buffer.encodeVarint(8);
        }   //1 opt - no def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !LoopTransportConfig {
        return try deseriigiTiponElBin(allocator, LoopTransportConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !LoopTransportConfig {
        return try deseriigiTiponElDosiero(allocator, LoopTransportConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !LoopTransportConfig {
        var mia_Mesagho = try LoopTransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 0 ) 
                mia_Mesagho.delay_ms = try buffer.decodeUint32();
        }


        return mia_Mesagho;
    }
};    // LoopTransportConfig

pub const MCastConfig = struct {
    local_address: ?[]const u8 = null,
    mcast_address: []const u8,
    port: i32 = 40069 ,
    ttl: ?i32 = 1 ,
    receive_buffer: ?i32 = 134217727 ,
    send_buffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !MCastConfig {
        return MCastConfig {
            .local_address = try allocator.dupe(u8, "Any"),
            .mcast_address = try allocator.dupe(u8, "239.255.0.1"),
            .port = 40069,
            .ttl = 1,
            .receive_buffer = 134217727,
            .send_buffer = 134217727,
        };
    }

    pub fn deinit(self: *const MCastConfig, allocator: all.Allocator) void {
        if( self.local_address ) |f| {
            allocator.free(f);
        }
        allocator.free(self.mcast_address);
    }

    pub fn skribiAlTeksto(self: *MCastConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, MCastConfig, @as(*MCastConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *MCastConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, MCastConfig, @as(*MCastConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !MCastConfig {
        return try legiTiponElTeksto(allocator, MCastConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !MCastConfig {
        return try legiTiponElDosiero(allocator, MCastConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const MCastConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.local_address ) |val|  
            try bufro.print(allocator,"{s}local_address: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}mcast_address: \"{s}\"\n",.{ind, self.mcast_address });
        try bufro.print(allocator,"{s}port: {any}\n",.{ind, self.port });
        if( self.ttl ) |val|  
            try bufro.print(allocator,"{s}ttl: {any}\n",.{ ind, val });
        if( self.receive_buffer ) |val|  
            try bufro.print(allocator,"{s}receive_buffer: {any}\n",.{ ind, val });
        if( self.send_buffer ) |val|  
            try bufro.print(allocator,"{s}send_buffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !MCastConfig {
        var mia_Mesagho = try MCastConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "local_address" ) ) {
                const tmp_local_address = try unescapePbTextToken(allocator, val);
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
                continue;
            }
            if( equal(u8, tok, "mcast_address" ) ) {
                const tmp_mcast_address = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.mcast_address);
                mia_Mesagho.mcast_address = tmp_mcast_address;
                continue;
            }
            if( equal(u8, tok, "port" ) ) {
                mia_Mesagho.port =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "ttl" ) ) {
                mia_Mesagho.ttl =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "receive_buffer" ) ) {
                mia_Mesagho.receive_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "send_buffer" ) ) {
                mia_Mesagho.send_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const MCastConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, MCastConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const MCastConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, MCastConfig, @as(*MCastConfig, self), path, b_formato);
    }

    fn seriigi(self: *const MCastConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        if( self.send_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(48);
        }   //1 opt - no def - no varlong

        if( self.receive_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(40);
        }   //1 opt - no def - no varlong

        if( self.ttl ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(32);
        }   //1 opt - no def - no varlong

        if( self.port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.port );
            tuta_longo += try buffer.encodeVarint(24);
        }  //6  req - def - no varlong

        if ( ! equal(u8, self.mcast_address, "239.255.0.1") ) {
            const st_longa = try buffer.encodeString( self.mcast_address );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(18);
        }  //8 req - def - varlong

        if ( self.local_address ) |val| {
            const st_longa = try buffer.encodeString( val );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  //3  opt - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !MCastConfig {
        return try deseriigiTiponElBin(allocator, MCastConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !MCastConfig {
        return try deseriigiTiponElDosiero(allocator, MCastConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !MCastConfig {
        var mia_Mesagho = try MCastConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_local_address = try buffer.decodeString(  try buffer.decodeVarint() );
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
            }
            else if ( field_number == 2 and wire_type == 2 ) 
            {
                const tmp_mcast_address = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.mcast_address);
                mia_Mesagho.mcast_address = tmp_mcast_address;
            }
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.port = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.ttl = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.receive_buffer = try buffer.decodeInt32()
            else if ( field_number == 6 and wire_type == 0 ) 
                mia_Mesagho.send_buffer = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};    // MCastConfig

pub const BCastConfig = struct {
    local_address: ?[]const u8 = null,
    bcast_address: []const u8,
    port: i32 = 40069 ,
    receive_buffer: ?i32 = 134217727 ,
    send_buffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !BCastConfig {
        return BCastConfig {
            .local_address = try allocator.dupe(u8, "Any"),
            .bcast_address = try allocator.dupe(u8, ""),
            .port = 40069,
            .receive_buffer = 134217727,
            .send_buffer = 134217727,
        };
    }

    pub fn deinit(self: *const BCastConfig, allocator: all.Allocator) void {
        if( self.local_address ) |f| {
            allocator.free(f);
        }
        allocator.free(self.bcast_address);
    }

    pub fn skribiAlTeksto(self: *BCastConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, BCastConfig, @as(*BCastConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *BCastConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, BCastConfig, @as(*BCastConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !BCastConfig {
        return try legiTiponElTeksto(allocator, BCastConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !BCastConfig {
        return try legiTiponElDosiero(allocator, BCastConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const BCastConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.local_address ) |val|  
            try bufro.print(allocator,"{s}local_address: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}bcast_address: \"{s}\"\n",.{ind, self.bcast_address });
        try bufro.print(allocator,"{s}port: {any}\n",.{ind, self.port });
        if( self.receive_buffer ) |val|  
            try bufro.print(allocator,"{s}receive_buffer: {any}\n",.{ ind, val });
        if( self.send_buffer ) |val|  
            try bufro.print(allocator,"{s}send_buffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !BCastConfig {
        var mia_Mesagho = try BCastConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "local_address" ) ) {
                const tmp_local_address = try unescapePbTextToken(allocator, val);
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
                continue;
            }
            if( equal(u8, tok, "bcast_address" ) ) {
                const tmp_bcast_address = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.bcast_address);
                mia_Mesagho.bcast_address = tmp_bcast_address;
                continue;
            }
            if( equal(u8, tok, "port" ) ) {
                mia_Mesagho.port =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "receive_buffer" ) ) {
                mia_Mesagho.receive_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "send_buffer" ) ) {
                mia_Mesagho.send_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const BCastConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, BCastConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const BCastConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, BCastConfig, @as(*BCastConfig, self), path, b_formato);
    }

    fn seriigi(self: *const BCastConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        if( self.send_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(40);
        }   //1 opt - no def - no varlong

        if( self.receive_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(32);
        }   //1 opt - no def - no varlong

        if( self.port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.port );
            tuta_longo += try buffer.encodeVarint(24);
        }  //6  req - def - no varlong

        const bcast_address_longa = try buffer.encodeString( self.bcast_address );
        tuta_longo += bcast_address_longa;
        tuta_longo += try buffer.encodeVarint(bcast_address_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        if ( self.local_address ) |val| {
            const st_longa = try buffer.encodeString( val );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  //3  opt - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !BCastConfig {
        return try deseriigiTiponElBin(allocator, BCastConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !BCastConfig {
        return try deseriigiTiponElDosiero(allocator, BCastConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !BCastConfig {
        var mia_Mesagho = try BCastConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_local_address = try buffer.decodeString(  try buffer.decodeVarint() );
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
            }
            else if ( field_number == 2 and wire_type == 2 ) 
            {
                const tmp_bcast_address = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.bcast_address);
                mia_Mesagho.bcast_address = tmp_bcast_address;
            }
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.port = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.receive_buffer = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.send_buffer = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};    // BCastConfig

pub const UDPStarConfig = struct {
    local_address: ?[]const u8 = null,
    port: i32,
    end_point: []EndPointConfig,
    receive_buffer: ?i32 = 134217727 ,
    send_buffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !UDPStarConfig {
        return UDPStarConfig {
            .local_address = try allocator.dupe(u8, "Any"),
            .port = 0,
            .end_point = try allocator.alloc(EndPointConfig, 0),
            .receive_buffer = 134217727,
            .send_buffer = 134217727,
        };
    }

    pub fn deinit(self: *const UDPStarConfig, allocator: all.Allocator) void {
        if( self.local_address ) |f| {
            allocator.free(f);
        }
        for (self.end_point) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.end_point);
    }

    pub fn skribiAlTeksto(self: *UDPStarConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, UDPStarConfig, @as(*UDPStarConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *UDPStarConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, UDPStarConfig, @as(*UDPStarConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !UDPStarConfig {
        return try legiTiponElTeksto(allocator, UDPStarConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !UDPStarConfig {
        return try legiTiponElDosiero(allocator, UDPStarConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const UDPStarConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.local_address ) |val|  
            try bufro.print(allocator,"{s}local_address: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}port: {any}\n",.{ind, self.port });
        for(self.end_point) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const end_point_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(end_point_text);

            try bufro.print(allocator, "{s}end_point {{\n{s}{s}}}\n", .{ ind, end_point_text, ind });
        }
        if( self.receive_buffer ) |val|  
            try bufro.print(allocator,"{s}receive_buffer: {any}\n",.{ ind, val });
        if( self.send_buffer ) |val|  
            try bufro.print(allocator,"{s}send_buffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !UDPStarConfig {
        var mia_Mesagho = try UDPStarConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end_point_list: std.ArrayList(EndPointConfig) = .empty;
        errdefer {
            for (end_point_list.items) |*item| {
                item.deinit(allocator);
            }
            end_point_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "local_address" ) ) {
                const tmp_local_address = try unescapePbTextToken(allocator, val);
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
                continue;
            }
            if( equal(u8, tok, "port" ) ) {
                mia_Mesagho.port =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "end_point" ) ) {
                const sub_msg = try EndPointConfig.legiElProtobufTeksto(allocator, it); 
                end_point_list.append(allocator, sub_msg) catch |err| {
                    sub_msg.deinit(allocator);
                    return err;
                };
                continue;
            }
            if( equal(u8, tok, "receive_buffer" ) ) {
                mia_Mesagho.receive_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "send_buffer" ) ) {
                mia_Mesagho.send_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
        }
        for (mia_Mesagho.end_point) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.end_point);
        mia_Mesagho.end_point = try end_point_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const UDPStarConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, UDPStarConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const UDPStarConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, UDPStarConfig, @as(*UDPStarConfig, self), path, b_formato);
    }

    fn seriigi(self: *const UDPStarConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        if( self.send_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(40);
        }   //1 opt - no def - no varlong

        if( self.receive_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(32);
        }   //1 opt - no def - no varlong

        var end_point_i: usize = self.end_point.len;
        while (end_point_i > 0) {
            end_point_i -= 1;
            const item = self.end_point[end_point_i];
            const end_point_longa = try item.seriigi( allocator, buffer );
            tuta_longo += end_point_longa;
            tuta_longo += try buffer.encodeVarint(end_point_longa);
            tuta_longo += try buffer.encodeVarint(26);
        }  // 11  rept - no def - varlong

        tuta_longo += try buffer.encodeInt32( self.port );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        if ( self.local_address ) |val| {
            const st_longa = try buffer.encodeString( val );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  //3  opt - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !UDPStarConfig {
        return try deseriigiTiponElBin(allocator, UDPStarConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !UDPStarConfig {
        return try deseriigiTiponElDosiero(allocator, UDPStarConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !UDPStarConfig {
        var mia_Mesagho = try UDPStarConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var end_point_list: std.ArrayList(EndPointConfig) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_local_address = try buffer.decodeString(  try buffer.decodeVarint() );
                if (mia_Mesagho.local_address) |old| {
                    allocator.free(old);
                }
                mia_Mesagho.local_address = tmp_local_address;
            }
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.port = try buffer.decodeInt32()
            else if ( field_number == 3 and wire_type == 2 ) 
            { 
                try end_point_list.append( 
                    allocator, 
                    try EndPointConfig.deseriigi(allocator, buffer, try buffer.decodeVarint() )
                );
            }
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.receive_buffer = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.send_buffer = try buffer.decodeInt32();
        }

        const tmp_end_point = try end_point_list.toOwnedSlice(allocator);
        for (mia_Mesagho.end_point) |*item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.end_point);
        mia_Mesagho.end_point = tmp_end_point;

        return mia_Mesagho;
    }
};    // UDPStarConfig

pub const EndPointConfig = struct {
    host: []const u8,
    port: i32 = 40069 ,

    pub fn initDefault(allocator: all.Allocator) !EndPointConfig {
        return EndPointConfig {
            .host = try allocator.dupe(u8, ""),
            .port = 40069,
        };
    }

    pub fn deinit(self: *const EndPointConfig, allocator: all.Allocator) void {
        allocator.free(self.host);
    }

    pub fn skribiAlTeksto(self: *EndPointConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, EndPointConfig, @as(*EndPointConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *EndPointConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, EndPointConfig, @as(*EndPointConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !EndPointConfig {
        return try legiTiponElTeksto(allocator, EndPointConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !EndPointConfig {
        return try legiTiponElDosiero(allocator, EndPointConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const EndPointConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}host: \"{s}\"\n",.{ind, self.host });
        try bufro.print(allocator,"{s}port: {any}\n",.{ind, self.port });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !EndPointConfig {
        var mia_Mesagho = try EndPointConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "host" ) ) {
                const tmp_host = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.host);
                mia_Mesagho.host = tmp_host;
                continue;
            }
            if( equal(u8, tok, "port" ) ) {
                mia_Mesagho.port =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const EndPointConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, EndPointConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const EndPointConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, EndPointConfig, @as(*EndPointConfig, self), path, b_formato);
    }

    fn seriigi(self: *const EndPointConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        if( self.port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.port );
            tuta_longo += try buffer.encodeVarint(16);
        }  //6  req - def - no varlong

        const host_longa = try buffer.encodeString( self.host );
        tuta_longo += host_longa;
        tuta_longo += try buffer.encodeVarint(host_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !EndPointConfig {
        return try deseriigiTiponElBin(allocator, EndPointConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !EndPointConfig {
        return try deseriigiTiponElDosiero(allocator, EndPointConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !EndPointConfig {
        var mia_Mesagho = try EndPointConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_host = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.host);
                mia_Mesagho.host = tmp_host;
            }
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.port = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};    // EndPointConfig

pub const UnixSocketStarConfig = struct {
    local_socket_path: []const u8,
    remote_socket_paths: [][]const u8,
    receive_buffer: ?i32 = 134217727 ,
    send_buffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !UnixSocketStarConfig {
        return UnixSocketStarConfig {
            .local_socket_path = try allocator.dupe(u8, ""),
            .remote_socket_paths = try allocator.alloc([]const u8, 0),
            .receive_buffer = 134217727,
            .send_buffer = 134217727,
        };
    }

    pub fn deinit(self: *const UnixSocketStarConfig, allocator: all.Allocator) void {
        allocator.free(self.local_socket_path);
        for (self.remote_socket_paths) |item| {
            allocator.free(item);
        }
        allocator.free(self.remote_socket_paths);
    }

    pub fn skribiAlTeksto(self: *UnixSocketStarConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, UnixSocketStarConfig, @as(*UnixSocketStarConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *UnixSocketStarConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, UnixSocketStarConfig, @as(*UnixSocketStarConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !UnixSocketStarConfig {
        return try legiTiponElTeksto(allocator, UnixSocketStarConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !UnixSocketStarConfig {
        return try legiTiponElDosiero(allocator, UnixSocketStarConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const UnixSocketStarConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}local_socket_path: \"{s}\"\n",.{ind, self.local_socket_path });
        for(self.remote_socket_paths) |obj| {
            try bufro.print(allocator,"{s}remote_socket_paths: \"{s}\"\n",.{ind, obj });
        }
        if( self.receive_buffer ) |val|  
            try bufro.print(allocator,"{s}receive_buffer: {any}\n",.{ ind, val });
        if( self.send_buffer ) |val|  
            try bufro.print(allocator,"{s}send_buffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !UnixSocketStarConfig {
        var mia_Mesagho = try UnixSocketStarConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var remote_socket_paths_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (remote_socket_paths_list.items) |item| {
                allocator.free(item);
            }
            remote_socket_paths_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "local_socket_path" ) ) {
                const tmp_local_socket_path = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.local_socket_path);
                mia_Mesagho.local_socket_path = tmp_local_socket_path;
                continue;
            }
            if( equal(u8, tok, "remote_socket_paths" ) ) {
                const tmp_item = try unescapePbTextToken(
                    allocator,
                    val,
                );
                remote_socket_paths_list.append(allocator, tmp_item) catch |err| {
                    allocator.free(tmp_item);
                    return err;
                };
                continue;
            }
            if( equal(u8, tok, "receive_buffer" ) ) {
                mia_Mesagho.receive_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "send_buffer" ) ) {
                mia_Mesagho.send_buffer =  std.fmt.parseInt(i32,val,10) catch 0;
                continue;
            }
        }
        for (mia_Mesagho.remote_socket_paths) |item| {
            allocator.free(item);
        }
        allocator.free(mia_Mesagho.remote_socket_paths);
        mia_Mesagho.remote_socket_paths = try remote_socket_paths_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const UnixSocketStarConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, UnixSocketStarConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const UnixSocketStarConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, UnixSocketStarConfig, @as(*UnixSocketStarConfig, self), path, b_formato);
    }

    fn seriigi(self: *const UnixSocketStarConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        if( self.send_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(32);
        }   //1 opt - no def - no varlong

        if( self.receive_buffer ) |val| {
            tuta_longo += try buffer.encodeInt32( val );
            tuta_longo += try buffer.encodeVarint(24);
        }   //1 opt - no def - no varlong

        var remote_socket_paths_i: usize = self.remote_socket_paths.len;
        while (remote_socket_paths_i > 0) {
            remote_socket_paths_i -= 1;
            const item = self.remote_socket_paths[remote_socket_paths_i];
            const remote_socket_paths_longa = try buffer.encodeString( item );
            tuta_longo += remote_socket_paths_longa;
            tuta_longo += try buffer.encodeVarint(remote_socket_paths_longa);
            tuta_longo += try buffer.encodeVarint(18);
        }  // 11  rept - no def - varlong

        const local_socket_path_longa = try buffer.encodeString( self.local_socket_path );
        tuta_longo += local_socket_path_longa;
        tuta_longo += try buffer.encodeVarint(local_socket_path_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !UnixSocketStarConfig {
        return try deseriigiTiponElBin(allocator, UnixSocketStarConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !UnixSocketStarConfig {
        return try deseriigiTiponElDosiero(allocator, UnixSocketStarConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !UnixSocketStarConfig {
        var mia_Mesagho = try UnixSocketStarConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var remote_socket_paths_list: std.ArrayList([]const u8) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_local_socket_path = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.local_socket_path);
                mia_Mesagho.local_socket_path = tmp_local_socket_path;
            }
            else if ( field_number == 2 and wire_type == 2 ) 
            { 
                try remote_socket_paths_list.append( 
                    allocator, 
                    try buffer.decodeString(  try buffer.decodeVarint() )
                );
            }
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.receive_buffer = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.send_buffer = try buffer.decodeInt32();
        }

        const tmp_remote_socket_paths = try remote_socket_paths_list.toOwnedSlice(allocator);
        for (mia_Mesagho.remote_socket_paths) |item| {
            allocator.free(item);
        }
        allocator.free(mia_Mesagho.remote_socket_paths);
        mia_Mesagho.remote_socket_paths = tmp_remote_socket_paths;

        return mia_Mesagho;
    }
};    // UnixSocketStarConfig

pub const CustomTransportConfig = struct {
    sub_type: []const u8,
    config: []const u8,
    plug_in_lib: []const u8,

    pub fn initDefault(allocator: all.Allocator) !CustomTransportConfig {
        return CustomTransportConfig {
            .sub_type = try allocator.dupe(u8, ""),
            .config = try allocator.dupe(u8, ""),
            .plug_in_lib = try allocator.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *const CustomTransportConfig, allocator: all.Allocator) void {
        allocator.free(self.sub_type);
        allocator.free(self.config);
        allocator.free(self.plug_in_lib);
    }

    pub fn skribiAlTeksto(self: *CustomTransportConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *CustomTransportConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !CustomTransportConfig {
        return try legiTiponElTeksto(allocator, CustomTransportConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !CustomTransportConfig {
        return try legiTiponElDosiero(allocator, CustomTransportConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const CustomTransportConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}sub_type: \"{s}\"\n",.{ind, self.sub_type });
        try bufro.print(allocator,"{s}config: {any}\n",.{ind, self.config });
        try bufro.print(allocator,"{s}plug_in_lib: \"{s}\"\n",.{ind, self.plug_in_lib });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !CustomTransportConfig {
        var mia_Mesagho = try CustomTransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "sub_type" ) ) {
                const tmp_sub_type = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.sub_type);
                mia_Mesagho.sub_type = tmp_sub_type;
                continue;
            }
            if( equal(u8, tok, "config" ) ) {
                const tmp_config = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.config);
                mia_Mesagho.config = tmp_config;
                continue;
            }
            if( equal(u8, tok, "plug_in_lib" ) ) {
                const tmp_plug_in_lib = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.plug_in_lib);
                mia_Mesagho.plug_in_lib = tmp_plug_in_lib;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const CustomTransportConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, CustomTransportConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const CustomTransportConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), path, b_formato);
    }

    fn seriigi(self: *const CustomTransportConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        const plug_in_lib_longa = try buffer.encodeString( self.plug_in_lib );
        tuta_longo += plug_in_lib_longa;
        tuta_longo += try buffer.encodeVarint(plug_in_lib_longa);
        tuta_longo += try buffer.encodeVarint(242);
        //7  req - no def - varlong

        const config_longa = try buffer.encodeBytes( self.config );
        tuta_longo += config_longa;
        tuta_longo += try buffer.encodeVarint(config_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        const sub_type_longa = try buffer.encodeString( self.sub_type );
        tuta_longo += sub_type_longa;
        tuta_longo += try buffer.encodeVarint(sub_type_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !CustomTransportConfig {
        return try deseriigiTiponElBin(allocator, CustomTransportConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !CustomTransportConfig {
        return try deseriigiTiponElDosiero(allocator, CustomTransportConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !CustomTransportConfig {
        var mia_Mesagho = try CustomTransportConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            {
                const tmp_sub_type = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.sub_type);
                mia_Mesagho.sub_type = tmp_sub_type;
            }
            else if ( field_number == 2 and wire_type == 2 ) 
            {
                const tmp_config = try buffer.decodeBytes(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.config);
                mia_Mesagho.config = tmp_config;
            }
            else if ( field_number == 30 and wire_type == 2 ) 
            {
                const tmp_plug_in_lib = try buffer.decodeString(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.plug_in_lib);
                mia_Mesagho.plug_in_lib = tmp_plug_in_lib;
            }
        }


        return mia_Mesagho;
    }
};    // CustomTransportConfig

pub const CrossConnectorConfig = struct {
    transports: [][]const u8,

    pub fn initDefault(allocator: all.Allocator) !CrossConnectorConfig {
        return CrossConnectorConfig {
            .transports = try allocator.alloc([]const u8, 0),
        };
    }

    pub fn deinit(self: *const CrossConnectorConfig, allocator: all.Allocator) void {
        for (self.transports) |item| {
            allocator.free(item);
        }
        allocator.free(self.transports);
    }

    pub fn skribiAlTeksto(self: *CrossConnectorConfig, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, CrossConnectorConfig, @as(*CrossConnectorConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *CrossConnectorConfig, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, CrossConnectorConfig, @as(*CrossConnectorConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !CrossConnectorConfig {
        return try legiTiponElTeksto(allocator, CrossConnectorConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !CrossConnectorConfig {
        return try legiTiponElDosiero(allocator, CrossConnectorConfig, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const CrossConnectorConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        for(self.transports) |obj| {
            try bufro.print(allocator,"{s}transports: \"{s}\"\n",.{ind, obj });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !CrossConnectorConfig {
        var mia_Mesagho = try CrossConnectorConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var transports_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (transports_list.items) |item| {
                allocator.free(item);
            }
            transports_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "transports" ) ) {
                const tmp_item = try unescapePbTextToken(
                    allocator,
                    val,
                );
                transports_list.append(allocator, tmp_item) catch |err| {
                    allocator.free(tmp_item);
                    return err;
                };
                continue;
            }
        }
        for (mia_Mesagho.transports) |item| {
            allocator.free(item);
        }
        allocator.free(mia_Mesagho.transports);
        mia_Mesagho.transports = try transports_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const CrossConnectorConfig, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, CrossConnectorConfig, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const CrossConnectorConfig, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, CrossConnectorConfig, @as(*CrossConnectorConfig, self), path, b_formato);
    }

    fn seriigi(self: *const CrossConnectorConfig, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        var transports_i: usize = self.transports.len;
        while (transports_i > 0) {
            transports_i -= 1;
            const item = self.transports[transports_i];
            const transports_longa = try buffer.encodeString( item );
            tuta_longo += transports_longa;
            tuta_longo += try buffer.encodeVarint(transports_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  // 11  rept - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !CrossConnectorConfig {
        return try deseriigiTiponElBin(allocator, CrossConnectorConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !CrossConnectorConfig {
        return try deseriigiTiponElDosiero(allocator, CrossConnectorConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !CrossConnectorConfig {
        var mia_Mesagho = try CrossConnectorConfig.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var transports_list: std.ArrayList([]const u8) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            { 
                try transports_list.append( 
                    allocator, 
                    try buffer.decodeString(  try buffer.decodeVarint() )
                );
            }
        }

        const tmp_transports = try transports_list.toOwnedSlice(allocator);
        for (mia_Mesagho.transports) |item| {
            allocator.free(item);
        }
        allocator.free(mia_Mesagho.transports);
        mia_Mesagho.transports = tmp_transports;

        return mia_Mesagho;
    }
};    // CrossConnectorConfig

    };   // config
};   // k6bus

//////////////////////////////////////////////
/// //////////////////////////////////////////
/// //////////////////////////////////////////
//////////////////////////////////////////////

//////////////////////////////////////////////
/// Seriigi Binaran Tipon
/// //////////////////////////////////////////

pub const BinaraFormato = enum(u32) {
    BF_PROTOBUF = 0,
    BF_OMG_CDR = 1,
    BF_ASN1_BER = 2,
    BF_ASN1_DER = 3,
    BF_BASE64 = 10,
    BF_BINPB2TEKSTO_HEX = 11,
    BF_BINPB2TEKSTO_DEC = 12,
};

fn seriigiTipon(allocator: all.Allocator, comptime T: type, value: * const T) ![]const u8 {
    var mia_enc = try EncodeBuffer.init(allocator, 48 * 1024);
    defer mia_enc.deinit();

    const longo = try value.seriigi(allocator, &mia_enc);
    const bytes = try allocator.alloc(u8, longo);
    std.mem.copyForwards(u8, bytes, mia_enc.data());
    return bytes;
}

fn seriigiTiponAlBin(allocator: all.Allocator, comptime T: type, value: * const T, b_formato: BinaraFormato) ![]const u8 {
    var parsed: []const u8 = undefined;
    switch (b_formato) {
        .BF_PROTOBUF => {
            parsed = try seriigiTipon(allocator, T, value);
        },
        .BF_BASE64 => {
            const binaraj_bitoj = try seriigiTipon(allocator, T, value);
            defer allocator.free(binaraj_bitoj);

            const enc=std.base64.standard.Encoder;
            const base64_longo = enc.calcSize(binaraj_bitoj.len);
            const base64_bitoj = try allocator.alloc(u8, base64_longo);
            parsed = enc.encode(base64_bitoj, binaraj_bitoj);
        },
        .BF_BINPB2TEKSTO_HEX => {
            const binaraj_bitoj = try seriigiTipon(allocator, T, value);
            defer allocator.free(binaraj_bitoj);

            var bin2teksto_bitoj:std.ArrayList(u8)= .empty;
            const hex = "0123456789ABCDEF";
            try bin2teksto_bitoj.print(allocator,"{{ ", .{});
            for (binaraj_bitoj, 0..) |val, i| {
                const hi: u8 = @intCast((val >> 4) & 0xF);
                const lo: u8 = @intCast(val & 0xF);
                try bin2teksto_bitoj.print(allocator,"0x{c}{c}{s} ", .{ hex[hi], hex[lo], if (i!=binaraj_bitoj.len-1) "," else ""});

                if ((i + 1) % 20 == 0) try bin2teksto_bitoj.print(allocator,"\n", .{});
            }
            try bin2teksto_bitoj.print(allocator,"}}", .{});
            parsed = try bin2teksto_bitoj.toOwnedSlice(allocator);
        },
        .BF_BINPB2TEKSTO_DEC => {
            const binaraj_bitoj = try seriigiTipon(allocator, T, value);
            defer allocator.free(binaraj_bitoj);

            var bin2teksto_bitoj:std.ArrayList(u8)= .empty;
            bin2teksto_bitoj.print(allocator,"{any}",.{binaraj_bitoj}) catch |err| {
                std.debug.print("eraro dum bin2teksto: {}\n", .{err});
                return err;
            };
            parsed = try bin2teksto_bitoj.toOwnedSlice(allocator);
        },    
        else => {
            return error.UnsupportedFormat;
        },
    }

    return parsed;
}

fn seriigiTiponAlDosiero(allocator: all.Allocator, comptime T: type, value: * const T, b_formato: BinaraFormato, path: []const u8) !void {
    const teksto = try seriigiTiponAlBin(allocator, T, value, b_formato);
    defer allocator.free(teksto);

    var dosiero = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer dosiero.close();
    try dosiero.writeAll(teksto);
}

//////////////////////////////////////////////
//// Deseriigi Binaran Tipon
//////////////////////////////////////////////

fn deseriigiTipon(allocator: all.Allocator, comptime T: type, input: []const u8) !T {
    var mia_dec = DecodeBuffer.init(allocator, input, 0, -1);
    defer mia_dec.deinit();

    const obj = try T.deseriigi(allocator, &mia_dec, null);
    return obj;
}

fn deseriigiTiponElBin(allocator: all.Allocator, comptime T: type, input: []const u8, b_formato: BinaraFormato) !T {
    var parsed: []const u8 = undefined;
    var parsed_owned: ?[]u8 = null;
    defer {
        if (parsed_owned) |buf| {
            allocator.free(buf);
        }
    }

    switch (b_formato) {
        .BF_PROTOBUF => {
            parsed = input;
        },
        .BF_BASE64 => {
            const dec=std.base64.standard.Decoder;
            const base64_decoded_longo = try dec.calcSizeForSlice(input);
            const base64_decoded = try allocator.alloc(u8, base64_decoded_longo);

            parsed_owned = base64_decoded;

            dec.decode(base64_decoded,input) catch |err| {
                std.debug.print("eraro dum deseriigo: {}\n", .{err});
                return err;
            };
            parsed = base64_decoded;
        },
        .BF_BINPB2TEKSTO_HEX, .BF_BINPB2TEKSTO_DEC => {
            var it = std.mem.tokenizeAny(u8, input, "{}, \n\r\t");
            var bytes: std.ArrayList(u8) = .empty;
            while (it.next()) |tok| {
                const val = std.fmt.parseUnsigned(u8, tok, 0) catch |err| {
                    std.debug.print("eraro dum parseInt dec: {}\n", .{err});
                    return err;
                };
                bytes.append(allocator, val) catch |err| {
                    std.debug.print("eraro dum append dec: {}\n", .{err});
                    return err;
                };
            }
            parsed = try bytes.toOwnedSlice(allocator);
        },
        else => {
            return error.UnsupportedFormat;
        },
    }

    return deseriigiTipon(allocator, T, parsed);
}

fn deseriigiTiponElDosiero(allocator: all.Allocator, comptime T: type, path: []const u8, b_formato: BinaraFormato) !T {
    var dosiero = try std.fs.cwd().openFile(path, .{});
    defer dosiero.close();

    const dosiera_long = try dosiero.getEndPos();
    var enhavo = allocator.alloc(u8, dosiera_long + 1) catch return error.OutOfMemory;
    defer allocator.free(enhavo);

    _ = try dosiero.readAll(enhavo[0..dosiera_long]);
    enhavo[dosiera_long] = 0;

    return deseriigiTiponElBin(allocator, T, enhavo[0..dosiera_long :0], b_formato);
}

//////////////////////////////////////////////
/// //////////////////////////////////////////
/// //////////////////////////////////////////
//////////////////////////////////////////////

const zon = std.zon;

fn parseEnumValue(comptime E: type, tok: []const u8) !E {
    if (std.meta.stringToEnum(E, tok)) |v| return v;
    const n = try std.fmt.parseInt(u64, tok, 10);
    return try std.meta.intToEnum(E, n);
}

fn legiSubProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) ![]const u8 {
    var bufro: std.ArrayList(u8) = .empty;
    var depth: usize = 1;

    while (it.next()) |tok| {
        if (equal(u8, tok, "{")) {
            depth += 1;
            try bufro.print(allocator, "{ ", .{});
            continue;
        }

        if (equal(u8, tok, "}")) {
            depth -= 1;
            if (depth == 0) break;
            try bufro.print(allocator, "} ", .{});
            continue;
        }

        try bufro.print(allocator, "{s} ", .{tok});
    }

    if (depth != 0) return error.InvalidFormat;
    return try bufro.toOwnedSlice(allocator);
}

pub const TekstaFormato = enum(u32) {
    TF_ZIG_ZON,
    TF_PROTOBUF,
    TF_JSON,
    TF_ASN1,
};

//////////////////////////////////////////////
//// Skribi Tipon Al Teksto
//////////////////////////////////////////////

pub fn skribiTiponAlTeksto(allocator: all.Allocator, comptime T: type, value: *T, t_formato: TekstaFormato) ![]const u8 {
    var skribila_asignilo = std.Io.Writer.Allocating.init(allocator);

    const self = @as(T, value.*);
    var bytes: []const u8 = undefined;
    switch (t_formato) {
        .TF_ZIG_ZON => {
            zon.stringify.serialize(self, .{}, &skribila_asignilo.writer) catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
                return err;
            };
            bytes = skribila_asignilo.toOwnedSlice() catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
               return err;
            };
        },
        .TF_JSON => {
            std.json.fmt(self, .{ .whitespace = .indent_3 }).format(&skribila_asignilo.writer) catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
                return err;
            };
            bytes = skribila_asignilo.toOwnedSlice() catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
               return err;
            };
        },
        .TF_PROTOBUF => {
            bytes = self.skribiAlProtobufTeksto(allocator, "") catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
                return err;
            };
        },
        else => {
            return error.UnsupportedFormat;
        },
    }

    return bytes;
}

fn skribiTiponAlDosiero(allocator: all.Allocator, comptime T: type, value: *T, path: []const u8, t_formato: TekstaFormato) !void {
    const teksto = try skribiTiponAlTeksto(allocator, T, value, t_formato);
    defer allocator.free(teksto);

    var dosiero = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer dosiero.close();
    try dosiero.writeAll(teksto);
}

//////////////////////////////////////////////
//// Legi Tipon El Teksto
//////////////////////////////////////////////

pub fn legiTiponElTeksto(allocator: all.Allocator, comptime T: type, input: []const u8, t_formato: TekstaFormato) !T {
    var parsed: T = undefined;
    switch (t_formato) {
        .TF_ZIG_ZON => {
            const zon_input = try allocator.dupeZ(u8, input);
            defer allocator.free(zon_input);
            parsed = zon.parse.fromSlice(T, allocator, zon_input, null, .{}) catch |err| {
                std.debug.print("eraro dun deseriigo: {}\n", .{err});
                return err;
            };
        },
        .TF_JSON => {
            parsed = std.json.parseFromSliceLeaky(T, allocator, input, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch |err| {
                std.debug.print("eraro dun deseriigo: {}\n", .{err});
                return err;
            };
        },
        .TF_PROTOBUF => {
//            var it: TokenIterType = std.mem.tokenizeAny(u8, input, ":\", \n\r\t");
            var it: TokenIterType = TokenIterType.init( input);
            parsed = T.legiElProtobufTeksto(allocator, &it) catch |err| {
                std.debug.print("eraro dun deseriigo: {}\n", .{err});
                return err;
            };
            _=it.peek();
        },
        else => {
            return error.UnsupportedFormat;
        },
    }

    return parsed;
}

pub fn legiTiponElDosiero(allocator: all.Allocator, comptime T: type, path: []const u8, t_formato: TekstaFormato) !T {
    var dosiero = try std.fs.cwd().openFile(path, .{});
    defer dosiero.close();

    const dosiera_long = try dosiero.getEndPos();
    var enhavo = allocator.alloc(u8, dosiera_long + 1) catch return error.OutOfMemory;
    defer allocator.free(enhavo);

    _ = try dosiero.readAll(enhavo[0..dosiera_long]);
    enhavo[dosiera_long] = 0;

    return legiTiponElTeksto(allocator, T, enhavo[0..dosiera_long :0], t_formato);
}

/// Tokenizador sencillo para Protobuf Text.
/// - Devuelve slices prestados del buffer original.
/// - Los literales entre comillas se devuelven sin las comillas.
/// - No interpreta todavia escapes como \\n, \\x01 o \\001.
/// - Reconoce { } < > [ ] como tokens independientes.
/// - Ignora espacios, :, ',', ';' y comentarios iniciados por #.
pub const CustomTokenizer = struct {
    buffer: []const u8,
    index: usize,
    const Self = @This();

    pub fn init(buffer: []const u8) Self {
        return .{ .buffer = buffer, .index = 0, };
    }

    pub fn peek(self: Self) ?[]const u8 {
        var copy = self;
        return copy.next();
    }

    /// El slice devuelto apunta directamente al buffer original.
    pub fn next(self: *Self) ?[]const u8 {
        self.skipIgnored();
        if (self.index >= self.buffer.len) { return null; }

        const current = self.buffer[self.index];
        if (current == '"' or current == '\'') { return self.readQuotedToken(); }
        if (isStructuralToken(current)) {
            const start = self.index;
            self.index += 1;
            return self.buffer[start..self.index];
        }
        return self.readBareToken();
    }

    fn skipIgnored(self: *Self) void {
        while (self.index < self.buffer.len) {
            const current = self.buffer[self.index];

            if (isDelimiter(current)) {
                self.index += 1;
                continue;
            }
            if (current == '#') {
                self.skipComment();
                continue;
            }
            break;
        }
    }
    fn skipComment(self: *Self) void {
        while (
            self.index < self.buffer.len and
            self.buffer[self.index] != '\n'
        ) {  self.index += 1; }
    }

    fn readQuotedToken(self: *Self) ?[]const u8 {
        const quote = self.buffer[self.index];

        self.index += 1;
        const content_start = self.index;

        while (self.index < self.buffer.len) {
            const current = self.buffer[self.index];

            if (current == '\\') {
                self.index += 1;
                if (self.index < self.buffer.len) { self.index += 1; }
                continue;
            }
            if (current == quote) {
                const content_end = self.index;
                self.index += 1;
                return self.buffer[content_start..content_end];
            }
            if (current == '\n' or current == '\r') { return null; }
            self.index += 1;
        }
        return null;
    }

    fn readBareToken(self: *Self) ?[]const u8 {
        const start = self.index;

        while (self.index < self.buffer.len) {
            const current = self.buffer[self.index];

            if (
                isDelimiter(current) or
                isStructuralToken(current) or
                current == '"' or
                current == '\'' or
                current == '#'
            ) { break; }
            self.index += 1;
        }
        if (self.index == start) { return null; }

        return self.buffer[start..self.index];
    }

    fn isDelimiter(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r', ':', ',', ';' => true,
            else => false,
        };
    }

    fn isStructuralToken(c: u8) bool {
        return switch (c) {
            '{', '}', '<', '>', '[', ']' => true,
            else => false,
        };
    }
};

fn unescapePbTextToken(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    var index: usize = 0;
    while (index < input.len) {
        const current = input[index];
        if (current != '\\') {
            try result.append(allocator, current);
            index += 1;
            continue;
        }
        index += 1;
        if (index >= input.len) {
            return error.InvalidPbTextEscape;
        }
        const escaped = input[index];
        index += 1;
        switch (escaped) {
            'a' => try result.append(allocator, 0x07),
            'b' => try result.append(allocator, 0x08),
            'f' => try result.append(allocator, 0x0c),
            'n' => try result.append(allocator, '\n'),
            'r' => try result.append(allocator, '\r'),
            't' => try result.append(allocator, '\t'),
            'v' => try result.append(allocator, 0x0b),
            '\\' => try result.append(allocator, '\\'),
            '\'' => try result.append(allocator, '\''),
            '"' => try result.append(allocator, '"'),
            '0'...'7' => {
                var value: u16 = escaped - '0';
                var digits: usize = 1;
                while (
                    digits < 3 and
                    index < input.len and
                    input[index] >= '0' and
                    input[index] <= '7'
                ) {
                    value = value * 8 + input[index] - '0';
                    index += 1;
                    digits += 1;
                }
                if (value > 255) { return error.InvalidPbTextEscape; }
                try result.append(allocator, @intCast(value));
            },
            'x', 'X' => {
                var value: u16 = 0;
                var digits: usize = 0;
                while (digits < 2 and index < input.len) {
                    const digit = hexDigitValue(input[index]) orelse break;
                    value = value * 16 + digit;
                    index += 1;
                    digits += 1;
                }
                if (digits == 0) { return error.InvalidPbTextEscape; }
                try result.append(allocator, @intCast(value));
            },
            else => return error.InvalidPbTextEscape,
        }
    }
    return try result.toOwnedSlice(allocator);

}

fn hexDigitValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0', 
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

