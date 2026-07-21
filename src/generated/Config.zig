const std = @import("std");
const dbg = std.debug;
const all = std.mem;
const equal = std.mem.eql;
const  io = std.Io;
const encdec = @import("../encdec.zig");
const EncodeBuffer = encdec.EncodeBuffer;
const DecodeBuffer = encdec.DecodeBuffer;


pub const k6bus = struct {

    pub const config = struct {


pub const BinaryFormatDef = enum(u64) {
   BIN_PROTOBUF = 0,
   BIN_CDR = 1,
   BIN_ASN1_BER = 2,
   BIN_ASN1_DER = 3,
};

pub const DispatchModeDef = enum(u64) {
   IMMEDIATE = 0,
   BATCH = 1,
};

pub const TransportKind = enum(u64) {
   MCAST = 0,
   BCAST = 1,
   UDPSTAR = 2,
   USOXSTAR = 3,
   CUSTOM = 100,
};

pub const EncodingDef = enum(u64) {
   RAW = 0,
   BASE64 = 1,
};

pub const AppConfig = struct {
    version: ?u32 = 1 ,
    ActivateTrace: ?bool = false ,
    TraceLevel: ?i32 = 0 ,
    Domains: []DomainCfg,

    pub fn initDefault(allocator: all.Allocator) !AppConfig {
        const self = try allocator.create(AppConfig);
        self.* = AppConfig{
            .version = 1,
            .ActivateTrace = false,
            .TraceLevel = 0,
            .Domains = try allocator.alloc(DomainCfg, 0),
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *AppConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, AppConfig, @as(*AppConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *AppConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, AppConfig, @as(*AppConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !AppConfig {
        return try encdec.legiTiponElTeksto(allocator, AppConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !AppConfig {
        return try encdec.legiTiponElDosiero(allocator, AppConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const AppConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        if( self.version ) |val|  
            try bufro.print(allocator,"{s}version: {any}\n",.{ ind, val });
        if( self.ActivateTrace ) |val|  
            try bufro.print(allocator,"{s}ActivateTrace: {any}\n",.{ ind, val });
        if( self.TraceLevel ) |val|  
            try bufro.print(allocator,"{s}TraceLevel: {any}\n",.{ ind, val });
        for(self.Domains) |obj| 
            try bufro.print(allocator, "{s}Domains {{\n{s}{s}}}\n", .{ind, try obj.skribiAlProtobufTeksto(allocator,indent),ind });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *AppConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, AppConfig, @as(*AppConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *AppConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, AppConfig, @as(*AppConfig, self), path, b_formato);
    }

    fn seriigi(self: *const AppConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        for (self.Domains) |item| {
            const Domains_longa = try item.seriigi( buffer );
            tuta_longo += Domains_longa;
            tuta_longo += try buffer.encodeVarint(Domains_longa);
            tuta_longo += try buffer.encodeVarint(34);
        }  // 11  rept - no def - varlong 

        if( self.TraceLevel ) |val| {
            if( val != 0 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(24);
            }
        }  //2 opt - def - no varlong

        if( self.ActivateTrace ) |val| {
            if( val != false )  {
                tuta_longo += try buffer.encodeBool( val );
                tuta_longo += try buffer.encodeVarint(16);
            }
        }  //2 opt - def - no varlong

        if( self.version ) |val| {
            if( val != 1 )  {
                tuta_longo += try buffer.encodeUint32( val );
                tuta_longo += try buffer.encodeVarint(8);
            }
        }  //2 opt - def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !AppConfig {
        return try deseriigiTiponElBin(allocator, AppConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !AppConfig {
        return try deseriigiTiponElDosiero(allocator, AppConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !AppConfig {
        var mia_Mesagho= try AppConfig.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var Domains_list: std.ArrayList(DomainCfg) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 0 ) 
                mia_Mesagho.version = try buffer.decodeUint32()
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.ActivateTrace = try buffer.decodeBool()
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.TraceLevel = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 2 ) 
                { try Domains_list.append( allocator, try DomainCfg.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.Domains = try Domains_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};

pub const DomainCfg = struct {
    Id: i32,
    ActivateDefaultTransport: ?bool = true ,
    DirectDispatchToSubs: ?bool = false ,
    KeyFile: ?[]const u8 = null,
    BinaryFormat: ?BinaryFormatDef = .BIN_PROTOBUF ,
    StartAtInit: ?bool = true ,
    DispatchMode: ?DispatchModeDef = .IMMEDIATE ,
    DispatchBatchTimeMs: ?i32 = 0 ,
    Transports: []TransportDef,
    CrossConnectors: []CrossConnectorDef,

    pub fn initDefault(allocator: all.Allocator) !DomainCfg {
        const self = try allocator.create(DomainCfg);
        self.* = DomainCfg{
            .Id = 0,
            .ActivateDefaultTransport = true,
            .DirectDispatchToSubs = false,
            .KeyFile = null,
            .BinaryFormat = .BIN_PROTOBUF,
            .StartAtInit = true,
            .DispatchMode = .IMMEDIATE,
            .DispatchBatchTimeMs = 0,
            .Transports = try allocator.alloc(TransportDef, 0),
            .CrossConnectors = try allocator.alloc(CrossConnectorDef, 0),
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *DomainCfg, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, DomainCfg, @as(*DomainCfg, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *DomainCfg, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, DomainCfg, @as(*DomainCfg, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !DomainCfg {
        return try encdec.legiTiponElTeksto(allocator, DomainCfg, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !DomainCfg {
        return try encdec.legiTiponElDosiero(allocator, DomainCfg, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const DomainCfg, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        try bufro.print(allocator,"{s}Id: {any}\n",.{ind, self.Id });
        if( self.ActivateDefaultTransport ) |val|  
            try bufro.print(allocator,"{s}ActivateDefaultTransport: {any}\n",.{ ind, val });
        if( self.DirectDispatchToSubs ) |val|  
            try bufro.print(allocator,"{s}DirectDispatchToSubs: {any}\n",.{ ind, val });
        if( self.KeyFile ) |val|  
            try bufro.print(allocator,"{s}KeyFile: \"{s}\"\n",.{ ind, val });
        if( self.BinaryFormat ) |val|  
            try bufro.print(allocator,"{s}BinaryFormat: {any}\n",.{ ind, val });
        if( self.StartAtInit ) |val|  
            try bufro.print(allocator,"{s}StartAtInit: {any}\n",.{ ind, val });
        if( self.DispatchMode ) |val|  
            try bufro.print(allocator,"{s}DispatchMode: {any}\n",.{ ind, val });
        if( self.DispatchBatchTimeMs ) |val|  
            try bufro.print(allocator,"{s}DispatchBatchTimeMs: {any}\n",.{ ind, val });
        for(self.Transports) |obj| 
            try bufro.print(allocator, "{s}Transports {{\n{s}{s}}}\n", .{ind, try obj.skribiAlProtobufTeksto(allocator,indent),ind });
        for(self.CrossConnectors) |obj| 
            try bufro.print(allocator, "{s}CrossConnectors {{\n{s}{s}}}\n", .{ind, try obj.skribiAlProtobufTeksto(allocator,indent),ind });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *DomainCfg, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, DomainCfg, @as(*DomainCfg,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *DomainCfg, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, DomainCfg, @as(*DomainCfg, self), path, b_formato);
    }

    fn seriigi(self: *const DomainCfg, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        for (self.CrossConnectors) |item| {
            const CrossConnectors_longa = try item.seriigi( buffer );
            tuta_longo += CrossConnectors_longa;
            tuta_longo += try buffer.encodeVarint(CrossConnectors_longa);
            tuta_longo += try buffer.encodeVarint(82);
        }  // 11  rept - no def - varlong 

        for (self.Transports) |item| {
            const Transports_longa = try item.seriigi( buffer );
            tuta_longo += Transports_longa;
            tuta_longo += try buffer.encodeVarint(Transports_longa);
            tuta_longo += try buffer.encodeVarint(74);
        }  // 11  rept - no def - varlong 

        if( self.DispatchBatchTimeMs ) |val| {
            if( val != 0 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(64);
            }
        }  //2 opt - def - no varlong

        if( self.DispatchMode ) |val| {
            if( val != .IMMEDIATE )  {
                tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
                tuta_longo += try buffer.encodeVarint(56);
            }
        }  //2 opt - def - no varlong

        if( self.StartAtInit ) |val| {
            if( val != true )  {
                tuta_longo += try buffer.encodeBool( val );
                tuta_longo += try buffer.encodeVarint(48);
            }
        }  //2 opt - def - no varlong

        if( self.BinaryFormat ) |val| {
            if( val != .BIN_PROTOBUF )  {
                tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
                tuta_longo += try buffer.encodeVarint(40);
            }
        }  //2 opt - def - no varlong

        if ( self.KeyFile ) |val| {
            const st_longa = try buffer.encodeString( val );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(34);
        }  //3  opt - no def - varlong

        if( self.DirectDispatchToSubs ) |val| {
            if( val != false )  {
                tuta_longo += try buffer.encodeBool( val );
                tuta_longo += try buffer.encodeVarint(24);
            }
        }  //2 opt - def - no varlong

        if( self.ActivateDefaultTransport ) |val| {
            if( val != true )  {
                tuta_longo += try buffer.encodeBool( val );
                tuta_longo += try buffer.encodeVarint(16);
            }
        }  //2 opt - def - no varlong

        tuta_longo += try buffer.encodeInt32( self.Id );
        tuta_longo += try buffer.encodeVarint(8);
        //5 req - no def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !DomainCfg {
        return try deseriigiTiponElBin(allocator, DomainCfg, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !DomainCfg {
        return try deseriigiTiponElDosiero(allocator, DomainCfg, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !DomainCfg {
        var mia_Mesagho= try DomainCfg.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var Transports_list: std.ArrayList(TransportDef) = .empty; 
        var CrossConnectors_list: std.ArrayList(CrossConnectorDef) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 0 ) 
                mia_Mesagho.Id = try buffer.decodeInt32()
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.ActivateDefaultTransport = try buffer.decodeBool()
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.DirectDispatchToSubs = try buffer.decodeBool()
            else if ( field_number == 4 and wire_type == 2 ) 
                mia_Mesagho.KeyFile = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.BinaryFormat = try std.meta.intToEnum(BinaryFormatDef, try buffer.decodeVarint() ) 
            else if ( field_number == 6 and wire_type == 0 ) 
                mia_Mesagho.StartAtInit = try buffer.decodeBool()
            else if ( field_number == 7 and wire_type == 0 ) 
                mia_Mesagho.DispatchMode = try std.meta.intToEnum(DispatchModeDef, try buffer.decodeVarint() ) 
            else if ( field_number == 8 and wire_type == 0 ) 
                mia_Mesagho.DispatchBatchTimeMs = try buffer.decodeInt32()
            else if ( field_number == 9 and wire_type == 2 ) 
                { try Transports_list.append( allocator, try TransportDef.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
            else if ( field_number == 10 and wire_type == 2 ) 
                { try CrossConnectors_list.append( allocator, try CrossConnectorDef.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.Transports = try Transports_list.toOwnedSlice(allocator); 
        mia_Mesagho.CrossConnectors = try CrossConnectors_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};

pub const TransportDef = struct {
    Name: []const u8,
    Kind: TransportKind,
    ReceiveOwnMsgs: ?bool = false ,
    Encoding: ?EncodingDef = .RAW ,
    mcast: ?MCastDefConfig = null,

    pub fn initDefault(allocator: all.Allocator) !TransportDef {
        const self = try allocator.create(TransportDef);
        self.* = TransportDef{
            .Name = "", 
            .Kind = undefined, 
            .ReceiveOwnMsgs = false,
            .Encoding = .RAW,
            .mcast = null,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *TransportDef, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, TransportDef, @as(*TransportDef, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *TransportDef, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, TransportDef, @as(*TransportDef, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !TransportDef {
        return try encdec.legiTiponElTeksto(allocator, TransportDef, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !TransportDef {
        return try encdec.legiTiponElDosiero(allocator, TransportDef, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const TransportDef, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        try bufro.print(allocator,"{s}Name: \"{s}\"\n",.{ind, self.Name });
        try bufro.print(allocator,"{s}Kind: {any}\n",.{ind, self.Kind });
        if( self.ReceiveOwnMsgs ) |val|  
            try bufro.print(allocator,"{s}ReceiveOwnMsgs: {any}\n",.{ ind, val });
        if( self.Encoding ) |val|  
            try bufro.print(allocator,"{s}Encoding: {any}\n",.{ ind, val });
        if( self.mcast ) |val|  
            try bufro.print(allocator, "{s}mcast {{\n{s}{s}}}\n", .{ind, try val.skribiAlProtobufTeksto(allocator,indent),ind });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *TransportDef, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, TransportDef, @as(*TransportDef,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *TransportDef, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, TransportDef, @as(*TransportDef, self), path, b_formato);
    }

    fn seriigi(self: *const TransportDef, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if ( self.mcast ) |val| {
            const st_longa = try val.seriigi( buffer );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(82);
        }  //3  opt - no def - varlong

        if( self.Encoding ) |val| {
            if( val != .RAW )  {
                tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
                tuta_longo += try buffer.encodeVarint(32);
            }
        }  //2 opt - def - no varlong

        if( self.ReceiveOwnMsgs ) |val| {
            if( val != false )  {
                tuta_longo += try buffer.encodeBool( val );
                tuta_longo += try buffer.encodeVarint(24);
            }
        }  //2 opt - def - no varlong

        tuta_longo += try buffer.encodeVarint( @intFromEnum(self.Kind) );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        const Name_longa = try buffer.encodeString( self.Name );
        tuta_longo += Name_longa;
        tuta_longo += try buffer.encodeVarint(Name_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !TransportDef {
        return try deseriigiTiponElBin(allocator, TransportDef, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !TransportDef {
        return try deseriigiTiponElDosiero(allocator, TransportDef, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !TransportDef {
        var mia_Mesagho= try TransportDef.initDefault(allocator);

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
                mia_Mesagho.Name = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.Kind = try std.meta.intToEnum(TransportKind, try buffer.decodeVarint() ) 
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.ReceiveOwnMsgs = try buffer.decodeBool()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.Encoding = try std.meta.intToEnum(EncodingDef, try buffer.decodeVarint() ) 
            else if ( field_number == 10 and wire_type == 2 ) 
                mia_Mesagho.mcast = try MCastDefConfig.deseriigi(allocator, buffer, try buffer.decodeVarint() );
        }


        return mia_Mesagho;
    }
};

pub const MCastDefConfig = struct {
    LocalAddress: ?[]const u8 = "Any" ,
    MCastAddress: []const u8 = "239.255.0.1" ,
    Port: i32 = 40069 ,
    TTL: ?i32 = 1 ,
    ReceiveBuffer: ?i32 = 134217727 ,
    SendBuffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !MCastDefConfig {
        const self = try allocator.create(MCastDefConfig);
        self.* = MCastDefConfig{
            .LocalAddress = "Any",
            .MCastAddress = "239.255.0.1",
            .Port = 40069,
            .TTL = 1,
            .ReceiveBuffer = 134217727,
            .SendBuffer = 134217727,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *MCastDefConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, MCastDefConfig, @as(*MCastDefConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *MCastDefConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, MCastDefConfig, @as(*MCastDefConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !MCastDefConfig {
        return try encdec.legiTiponElTeksto(allocator, MCastDefConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !MCastDefConfig {
        return try encdec.legiTiponElDosiero(allocator, MCastDefConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const MCastDefConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        if( self.LocalAddress ) |val|  
            try bufro.print(allocator,"{s}LocalAddress: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}MCastAddress: \"{s}\"\n",.{ind, self.MCastAddress });
        try bufro.print(allocator,"{s}Port: {any}\n",.{ind, self.Port });
        if( self.TTL ) |val|  
            try bufro.print(allocator,"{s}TTL: {any}\n",.{ ind, val });
        if( self.ReceiveBuffer ) |val|  
            try bufro.print(allocator,"{s}ReceiveBuffer: {any}\n",.{ ind, val });
        if( self.SendBuffer ) |val|  
            try bufro.print(allocator,"{s}SendBuffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *MCastDefConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, MCastDefConfig, @as(*MCastDefConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *MCastDefConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, MCastDefConfig, @as(*MCastDefConfig, self), path, b_formato);
    }

    fn seriigi(self: *const MCastDefConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if( self.SendBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(48);
            }
        }  //2 opt - def - no varlong

        if( self.ReceiveBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(40);
            }
        }  //2 opt - def - no varlong

        if( self.TTL ) |val| {
            if( val != 1 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(32);
            }
        }  //2 opt - def - no varlong

        if( self.Port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.Port );
            tuta_longo += try buffer.encodeVarint(24);
        }  //6  req - def - no varlong

        if ( ! equal(u8, self.MCastAddress, "239.255.0.1") ) {
            const st_longa = try buffer.encodeString( self.MCastAddress );
            tuta_longo += st_longa;
            tuta_longo += try buffer.encodeVarint(st_longa);
            tuta_longo += try buffer.encodeVarint(18);
        }  //8 req - def - varlong

        if ( self.LocalAddress ) |val| {
            if ( ! equal(u8, val, "Any") ) {
                const st_longa = try buffer.encodeString( val );
                tuta_longo += st_longa;
                tuta_longo += try buffer.encodeVarint(st_longa);
                tuta_longo += try buffer.encodeVarint(10);
            }  
        }  //4  opt - def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !MCastDefConfig {
        return try deseriigiTiponElBin(allocator, MCastDefConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !MCastDefConfig {
        return try deseriigiTiponElDosiero(allocator, MCastDefConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !MCastDefConfig {
        var mia_Mesagho= try MCastDefConfig.initDefault(allocator);

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
                mia_Mesagho.LocalAddress = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.MCastAddress = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.Port = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.TTL = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.ReceiveBuffer = try buffer.decodeInt32()
            else if ( field_number == 6 and wire_type == 0 ) 
                mia_Mesagho.SendBuffer = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};

pub const BCastDefConfig = struct {
    LocalAddress: ?[]const u8 = "Any" ,
    BCastAddress: []const u8,
    Port: i32 = 40069 ,
    ReceiveBuffer: ?i32 = 134217727 ,
    SendBuffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !BCastDefConfig {
        const self = try allocator.create(BCastDefConfig);
        self.* = BCastDefConfig{
            .LocalAddress = "Any",
            .BCastAddress = "", 
            .Port = 40069,
            .ReceiveBuffer = 134217727,
            .SendBuffer = 134217727,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *BCastDefConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, BCastDefConfig, @as(*BCastDefConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *BCastDefConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, BCastDefConfig, @as(*BCastDefConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !BCastDefConfig {
        return try encdec.legiTiponElTeksto(allocator, BCastDefConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !BCastDefConfig {
        return try encdec.legiTiponElDosiero(allocator, BCastDefConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const BCastDefConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        if( self.LocalAddress ) |val|  
            try bufro.print(allocator,"{s}LocalAddress: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}BCastAddress: \"{s}\"\n",.{ind, self.BCastAddress });
        try bufro.print(allocator,"{s}Port: {any}\n",.{ind, self.Port });
        if( self.ReceiveBuffer ) |val|  
            try bufro.print(allocator,"{s}ReceiveBuffer: {any}\n",.{ ind, val });
        if( self.SendBuffer ) |val|  
            try bufro.print(allocator,"{s}SendBuffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *BCastDefConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, BCastDefConfig, @as(*BCastDefConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *BCastDefConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, BCastDefConfig, @as(*BCastDefConfig, self), path, b_formato);
    }

    fn seriigi(self: *const BCastDefConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if( self.SendBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(40);
            }
        }  //2 opt - def - no varlong

        if( self.ReceiveBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(32);
            }
        }  //2 opt - def - no varlong

        if( self.Port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.Port );
            tuta_longo += try buffer.encodeVarint(24);
        }  //6  req - def - no varlong

        const BCastAddress_longa = try buffer.encodeString( self.BCastAddress );
        tuta_longo += BCastAddress_longa;
        tuta_longo += try buffer.encodeVarint(BCastAddress_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        if ( self.LocalAddress ) |val| {
            if ( ! equal(u8, val, "Any") ) {
                const st_longa = try buffer.encodeString( val );
                tuta_longo += st_longa;
                tuta_longo += try buffer.encodeVarint(st_longa);
                tuta_longo += try buffer.encodeVarint(10);
            }  
        }  //4  opt - def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !BCastDefConfig {
        return try deseriigiTiponElBin(allocator, BCastDefConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !BCastDefConfig {
        return try deseriigiTiponElDosiero(allocator, BCastDefConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !BCastDefConfig {
        var mia_Mesagho= try BCastDefConfig.initDefault(allocator);

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
                mia_Mesagho.LocalAddress = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.BCastAddress = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.Port = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.ReceiveBuffer = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.SendBuffer = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};

pub const UDPStarDefConfig = struct {
    LocalAddress: ?[]const u8 = "Any" ,
    Port: i32,
    EndPoint: []EndPointDef,
    ReceiveBuffer: ?i32 = 134217727 ,
    SendBuffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !UDPStarDefConfig {
        const self = try allocator.create(UDPStarDefConfig);
        self.* = UDPStarDefConfig{
            .LocalAddress = "Any",
            .Port = 0,
            .EndPoint = try allocator.alloc(EndPointDef, 0),
            .ReceiveBuffer = 134217727,
            .SendBuffer = 134217727,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *UDPStarDefConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, UDPStarDefConfig, @as(*UDPStarDefConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *UDPStarDefConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, UDPStarDefConfig, @as(*UDPStarDefConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !UDPStarDefConfig {
        return try encdec.legiTiponElTeksto(allocator, UDPStarDefConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !UDPStarDefConfig {
        return try encdec.legiTiponElDosiero(allocator, UDPStarDefConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const UDPStarDefConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        if( self.LocalAddress ) |val|  
            try bufro.print(allocator,"{s}LocalAddress: \"{s}\"\n",.{ ind, val });
        try bufro.print(allocator,"{s}Port: {any}\n",.{ind, self.Port });
        for(self.EndPoint) |obj| 
            try bufro.print(allocator, "{s}EndPoint {{\n{s}{s}}}\n", .{ind, try obj.skribiAlProtobufTeksto(allocator,indent),ind });
        if( self.ReceiveBuffer ) |val|  
            try bufro.print(allocator,"{s}ReceiveBuffer: {any}\n",.{ ind, val });
        if( self.SendBuffer ) |val|  
            try bufro.print(allocator,"{s}SendBuffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *UDPStarDefConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, UDPStarDefConfig, @as(*UDPStarDefConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *UDPStarDefConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, UDPStarDefConfig, @as(*UDPStarDefConfig, self), path, b_formato);
    }

    fn seriigi(self: *const UDPStarDefConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if( self.SendBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(40);
            }
        }  //2 opt - def - no varlong

        if( self.ReceiveBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(32);
            }
        }  //2 opt - def - no varlong

        for (self.EndPoint) |item| {
            const EndPoint_longa = try item.seriigi( buffer );
            tuta_longo += EndPoint_longa;
            tuta_longo += try buffer.encodeVarint(EndPoint_longa);
            tuta_longo += try buffer.encodeVarint(26);
        }  // 11  rept - no def - varlong 

        tuta_longo += try buffer.encodeInt32( self.Port );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        if ( self.LocalAddress ) |val| {
            if ( ! equal(u8, val, "Any") ) {
                const st_longa = try buffer.encodeString( val );
                tuta_longo += st_longa;
                tuta_longo += try buffer.encodeVarint(st_longa);
                tuta_longo += try buffer.encodeVarint(10);
            }  
        }  //4  opt - def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !UDPStarDefConfig {
        return try deseriigiTiponElBin(allocator, UDPStarDefConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !UDPStarDefConfig {
        return try deseriigiTiponElDosiero(allocator, UDPStarDefConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !UDPStarDefConfig {
        var mia_Mesagho= try UDPStarDefConfig.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var EndPoint_list: std.ArrayList(EndPointDef) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.LocalAddress = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.Port = try buffer.decodeInt32()
            else if ( field_number == 3 and wire_type == 2 ) 
                { try EndPoint_list.append( allocator, try EndPointDef.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.ReceiveBuffer = try buffer.decodeInt32()
            else if ( field_number == 5 and wire_type == 0 ) 
                mia_Mesagho.SendBuffer = try buffer.decodeInt32();
        }

        mia_Mesagho.EndPoint = try EndPoint_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};

pub const EndPointDef = struct {
    Host: []const u8,
    Port: i32 = 40069 ,

    pub fn initDefault(allocator: all.Allocator) !EndPointDef {
        const self = try allocator.create(EndPointDef);
        self.* = EndPointDef{
            .Host = "", 
            .Port = 40069,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *EndPointDef, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, EndPointDef, @as(*EndPointDef, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *EndPointDef, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, EndPointDef, @as(*EndPointDef, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !EndPointDef {
        return try encdec.legiTiponElTeksto(allocator, EndPointDef, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !EndPointDef {
        return try encdec.legiTiponElDosiero(allocator, EndPointDef, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const EndPointDef, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        try bufro.print(allocator,"{s}Host: \"{s}\"\n",.{ind, self.Host });
        try bufro.print(allocator,"{s}Port: {any}\n",.{ind, self.Port });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *EndPointDef, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, EndPointDef, @as(*EndPointDef,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *EndPointDef, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, EndPointDef, @as(*EndPointDef, self), path, b_formato);
    }

    fn seriigi(self: *const EndPointDef, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if( self.Port != 40069 )  {
            tuta_longo += try buffer.encodeInt32( self.Port );
            tuta_longo += try buffer.encodeVarint(16);
        }  //6  req - def - no varlong

        const Host_longa = try buffer.encodeString( self.Host );
        tuta_longo += Host_longa;
        tuta_longo += try buffer.encodeVarint(Host_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !EndPointDef {
        return try deseriigiTiponElBin(allocator, EndPointDef, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !EndPointDef {
        return try deseriigiTiponElDosiero(allocator, EndPointDef, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !EndPointDef {
        var mia_Mesagho= try EndPointDef.initDefault(allocator);

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
                mia_Mesagho.Host = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.Port = try buffer.decodeInt32();
        }


        return mia_Mesagho;
    }
};

pub const UnixSocketStarDefConfig = struct {
    LocalSocketPath: []const u8,
    RemoteSocketPaths: [][]const u8,
    ReceiveBuffer: ?i32 = 134217727 ,
    SendBuffer: ?i32 = 134217727 ,

    pub fn initDefault(allocator: all.Allocator) !UnixSocketStarDefConfig {
        const self = try allocator.create(UnixSocketStarDefConfig);
        self.* = UnixSocketStarDefConfig{
            .LocalSocketPath = "", 
            .RemoteSocketPaths = try allocator.alloc([]const u8, 0),
            .ReceiveBuffer = 134217727,
            .SendBuffer = 134217727,
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *UnixSocketStarDefConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, UnixSocketStarDefConfig, @as(*UnixSocketStarDefConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *UnixSocketStarDefConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, UnixSocketStarDefConfig, @as(*UnixSocketStarDefConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !UnixSocketStarDefConfig {
        return try encdec.legiTiponElTeksto(allocator, UnixSocketStarDefConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !UnixSocketStarDefConfig {
        return try encdec.legiTiponElDosiero(allocator, UnixSocketStarDefConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const UnixSocketStarDefConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        try bufro.print(allocator,"{s}LocalSocketPath: \"{s}\"\n",.{ind, self.LocalSocketPath });
        for(self.RemoteSocketPaths) |obj| 
            try bufro.print(allocator,"{s}RemoteSocketPaths: \"{s}\"\n",.{ind, obj });
        if( self.ReceiveBuffer ) |val|  
            try bufro.print(allocator,"{s}ReceiveBuffer: {any}\n",.{ ind, val });
        if( self.SendBuffer ) |val|  
            try bufro.print(allocator,"{s}SendBuffer: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *UnixSocketStarDefConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, UnixSocketStarDefConfig, @as(*UnixSocketStarDefConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *UnixSocketStarDefConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, UnixSocketStarDefConfig, @as(*UnixSocketStarDefConfig, self), path, b_formato);
    }

    fn seriigi(self: *const UnixSocketStarDefConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        if( self.SendBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(32);
            }
        }  //2 opt - def - no varlong

        if( self.ReceiveBuffer ) |val| {
            if( val != 134217727 )  {
                tuta_longo += try buffer.encodeInt32( val );
                tuta_longo += try buffer.encodeVarint(24);
            }
        }  //2 opt - def - no varlong

        for (self.RemoteSocketPaths) |item| {
            const RemoteSocketPaths_longa = try buffer.encodeString( item );
            tuta_longo += RemoteSocketPaths_longa;
            tuta_longo += try buffer.encodeVarint(RemoteSocketPaths_longa);
            tuta_longo += try buffer.encodeVarint(18);
        }  // 11  rept - no def - varlong 

        const LocalSocketPath_longa = try buffer.encodeString( self.LocalSocketPath );
        tuta_longo += LocalSocketPath_longa;
        tuta_longo += try buffer.encodeVarint(LocalSocketPath_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !UnixSocketStarDefConfig {
        return try deseriigiTiponElBin(allocator, UnixSocketStarDefConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !UnixSocketStarDefConfig {
        return try deseriigiTiponElDosiero(allocator, UnixSocketStarDefConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !UnixSocketStarDefConfig {
        var mia_Mesagho= try UnixSocketStarDefConfig.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var RemoteSocketPaths_list: std.ArrayList([]const u8) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.LocalSocketPath = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                { try RemoteSocketPaths_list.append( allocator, try buffer.decodeString(  try buffer.decodeVarint() ) ); }
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.ReceiveBuffer = try buffer.decodeInt32()
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.SendBuffer = try buffer.decodeInt32();
        }

        mia_Mesagho.RemoteSocketPaths = try RemoteSocketPaths_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};

pub const CustomTransportConfig = struct {
    SubType: []const u8,
    Config: []const u8,
    PlugInLib: []const u8,

    pub fn initDefault(allocator: all.Allocator) !CustomTransportConfig {
        const self = try allocator.create(CustomTransportConfig);
        self.* = CustomTransportConfig{
            .SubType = "", 
            .Config = undefined, 
            .PlugInLib = "", 
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *CustomTransportConfig, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *CustomTransportConfig, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !CustomTransportConfig {
        return try encdec.legiTiponElTeksto(allocator, CustomTransportConfig, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !CustomTransportConfig {
        return try encdec.legiTiponElDosiero(allocator, CustomTransportConfig, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const CustomTransportConfig, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        try bufro.print(allocator,"{s}SubType: \"{s}\"\n",.{ind, self.SubType });
        try bufro.print(allocator,"{s}Config: {any}\n",.{ind, self.Config });
        try bufro.print(allocator,"{s}PlugInLib: \"{s}\"\n",.{ind, self.PlugInLib });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *CustomTransportConfig, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, CustomTransportConfig, @as(*CustomTransportConfig,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *CustomTransportConfig, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, CustomTransportConfig, @as(*CustomTransportConfig, self), path, b_formato);
    }

    fn seriigi(self: *const CustomTransportConfig, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        const PlugInLib_longa = try buffer.encodeString( self.PlugInLib );
        tuta_longo += PlugInLib_longa;
        tuta_longo += try buffer.encodeVarint(PlugInLib_longa);
        tuta_longo += try buffer.encodeVarint(242);
        //7  req - no def - varlong

        const Config_longa = try buffer.encodeBytes( self.Config );
        tuta_longo += Config_longa;
        tuta_longo += try buffer.encodeVarint(Config_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        const SubType_longa = try buffer.encodeString( self.SubType );
        tuta_longo += SubType_longa;
        tuta_longo += try buffer.encodeVarint(SubType_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !CustomTransportConfig {
        return try deseriigiTiponElBin(allocator, CustomTransportConfig, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !CustomTransportConfig {
        return try deseriigiTiponElDosiero(allocator, CustomTransportConfig, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !CustomTransportConfig {
        var mia_Mesagho= try CustomTransportConfig.initDefault(allocator);

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
                mia_Mesagho.SubType = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.Config = try buffer.decodeBytes(  try buffer.decodeVarint() )
            else if ( field_number == 30 and wire_type == 2 ) 
                mia_Mesagho.PlugInLib = try buffer.decodeString(  try buffer.decodeVarint() );
        }


        return mia_Mesagho;
    }
};

pub const CrossConnectorDef = struct {
    Transports: [][]const u8,

    pub fn initDefault(allocator: all.Allocator) !CrossConnectorDef {
        const self = try allocator.create(CrossConnectorDef);
        self.* = CrossConnectorDef{
            .Transports = try allocator.alloc([]const u8, 0),
        };
        return self.*;
    }

    pub fn skribiAlTeksto(self: *CrossConnectorDef, allocator: all.Allocator, t_formato: encdec.TekstaFormato) ![]const u8 {
        return try encdec.skribiTiponAlTeksto(allocator, CrossConnectorDef, @as(*CrossConnectorDef, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *CrossConnectorDef, allocator: all.Allocator, path: []const u8, t_formato: encdec.TekstaFormato) !void {
        try encdec.skribiTiponAlDosiero(allocator, CrossConnectorDef, @as(*CrossConnectorDef, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: [:0]const u8, t_formato: encdec.TekstaFormato) !CrossConnectorDef {
        return try encdec.legiTiponElTeksto(allocator, CrossConnectorDef, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: [:0]const u8, t_formato: encdec.TekstaFormato) !CrossConnectorDef {
        return try encdec.legiTiponElDosiero(allocator, CrossConnectorDef, path, t_formato);
    }

    pub fn skribiAlProtobufTeksto(self: *const CrossConnectorDef, allocator: all.Allocator,ind: []const u8) ![]const u8 {
       const indent = std.mem.concatWithSentinel(std.heap.page_allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
       var bufro:std.ArrayList(u8)= .empty;
       if( equal(u8,indent,"") ) { {} } 

        for(self.Transports) |obj| 
            try bufro.print(allocator,"{s}Transports: \"{s}\"\n",.{ind, obj });

        return bufro.toOwnedSlice(allocator);
    }

    pub fn seriigiAlBin(self: *CrossConnectorDef, allocator: all.Allocator, b_formato: encdec.BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, CrossConnectorDef, @as(*CrossConnectorDef,self), b_formato);
    }

    pub fn seriigiAlDosiero(self: *CrossConnectorDef, allocator: all.Allocator, path: []const u8, b_formato: encdec.BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, CrossConnectorDef, @as(*CrossConnectorDef, self), path, b_formato);
    }

    fn seriigi(self: *const CrossConnectorDef, buffer: *EncodeBuffer) !usize {
        var tuta_longo: usize = 0;
 
        for (self.Transports) |item| {
            const Transports_longa = try buffer.encodeString( item );
            tuta_longo += Transports_longa;
            tuta_longo += try buffer.encodeVarint(Transports_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  // 11  rept - no def - varlong 

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: encdec.BinaraFormato) !CrossConnectorDef {
        return try deseriigiTiponElBin(allocator, CrossConnectorDef, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: encdec.BinaraFormato) !CrossConnectorDef {
        return try deseriigiTiponElDosiero(allocator, CrossConnectorDef, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !CrossConnectorDef {
        var mia_Mesagho= try CrossConnectorDef.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var Transports_list: std.ArrayList([]const u8) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                { try Transports_list.append( allocator, try buffer.decodeString(  try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.Transports = try Transports_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};

    };   // config
};   // k6bus

//////////////////////////////////////////////
/// //////////////////////////////////////////
/// //////////////////////////////////////////
//////////////////////////////////////////////

//////////////////////////////////////////////
/// Seriigi Binaran Tipon
/// //////////////////////////////////////////

fn seriigiTipon(allocator: all.Allocator, comptime T: type, value: *T) ![]const u8 {
    var mia_enc = try EncodeBuffer.init(allocator, 48 * 1024);
    defer mia_enc.deinit();

    const longo = try value.seriigi(&mia_enc);
    const bytes = try allocator.alloc(u8, longo);
    std.mem.copyForwards(u8, bytes, mia_enc.data());
    return bytes;
}

fn seriigiTiponAlBin(allocator: all.Allocator, comptime T: type, value: *T, b_formato: encdec.BinaraFormato) ![]const u8 {
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
        .BF_BIN2TEKSTO => {
            const binaraj_bitoj = try seriigiTipon(allocator, T, value);
            defer allocator.free(binaraj_bitoj);

            var bin2teksto_bitoj:std.ArrayList(u8)= .empty;
            const hex = "0123456789ABCDEF";
            for (binaraj_bitoj, 0..) |val, i| {
                const hi: u8 = @intCast((val >> 4) & 0xF);
                const lo: u8 = @intCast(val & 0xF);
                try bin2teksto_bitoj.print(allocator,"0x{c}{c} ", .{ hex[hi], hex[lo] });

                if ((i + 1) % 20 == 0) try bin2teksto_bitoj.print(allocator,"\n", .{});
            }
            parsed = try bin2teksto_bitoj.toOwnedSlice(allocator);
        },
        else => {
            return error.UnsupportedFormat;
        },
    }

    return parsed;
}

fn seriigiTiponAlDosiero(allocator: all.Allocator, comptime T: type, value: *T, b_formato: encdec.BinaraFormato, path: []const u8) !void {
    const teksto = try seriigiTiponAlBin(allocator, T, value, b_formato);

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

fn deseriigiTiponElBin(allocator: all.Allocator, comptime T: type, input: []const u8, b_formato: encdec.BinaraFormato) !T {
    var parsed: []const u8 = undefined;
    switch (b_formato) {
        .BF_PROTOBUF => {
            parsed = input;
        },
        .BF_BASE64 => {
            const dec=std.base64.standard.Decoder;
            const base64_decoded_longo = try dec.calcSizeForSlice(input);
            const base64_decoded = try allocator.alloc(u8, base64_decoded_longo);

            dec.decode(base64_decoded,input) catch |err| {
                std.debug.print("eraro dum deseriigo: {}\n", .{err});
                return err;
            };
            parsed = base64_decoded;
        },
        .BF_BIN2TEKSTO => {
            return error.UnsupportedFormat;
        },
        else => {
            return error.UnsupportedFormat;
        },
    }

    return deseriigiTipon(allocator, T, parsed);
}

fn deseriigiTiponElDosiero(allocator: all.Allocator, comptime T: type, path: []const u8, b_formato: encdec.BinaraFormato) !T {
    var dosiero = try std.fs.cwd().openFile(path, .{});
    defer dosiero.close();

    const dosiera_long = try dosiero.getEndPos();
    var enhavo = allocator.alloc(u8, dosiera_long + 1) catch return error.OutOfMemory;
    defer allocator.free(enhavo);

    _ = try dosiero.readAll(enhavo[0..dosiera_long]);
    enhavo[dosiera_long] = 0;

    return deseriigiTiponElBin(allocator, T, enhavo[0..dosiera_long :0], b_formato);
}

