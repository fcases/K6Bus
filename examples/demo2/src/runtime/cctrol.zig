const std = @import("std");
const dbg = std.debug;
const all = std.mem;
const equal = std.mem.eql;
const  io = std.Io;

const encdec = @import("encdec.zig");
const EncodeBuffer = encdec.EncodeBuffer;
const DecodeBuffer = encdec.DecodeBuffer;

const TokenIterType = std.mem.TokenIterator(u8, .any);

pub const cctrol = struct {


pub const TipoPanel = enum(u64) {
   SENIAL = 0,
   TEXTO = 1,
};

pub const CCtrol = struct {
    nombre: []const u8,
    remotas: []EstRemCtrol,

    pub fn initDefault(allocator: all.Allocator) !CCtrol {
        return CCtrol {
            .nombre = try allocator.dupe(u8, ""),
            .remotas = try allocator.alloc(EstRemCtrol, 0),
        };
    }

    pub fn deinit(self: *const CCtrol, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        for (self.remotas) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.remotas);
    }

    pub fn setNombre(
        self: *CCtrol,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *CCtrol, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, CCtrol, @as(*CCtrol, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *CCtrol, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, CCtrol, @as(*CCtrol, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !CCtrol {
        return try legiTiponElTeksto(allocator, CCtrol, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !CCtrol {
        return try legiTiponElDosiero(allocator, CCtrol, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const CCtrol, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        for(self.remotas) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const remotas_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(remotas_text);

            try bufro.print(allocator, "{s}remotas {{\n{s}{s}}}\n", .{ ind, remotas_text, ind });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !CCtrol {
        var mia_Mesagho= try CCtrol.initDefault(allocator); 

        var remotas_list: std.ArrayList(EstRemCtrol) = .empty; 
        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "remotas" ) ) { 
                const sub_msg = try EstRemCtrol.legiElProtobufTeksto(allocator, it); 
                try remotas_list.append(allocator, sub_msg); 
                continue;
            }
        }
        for (mia_Mesagho.remotas) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.remotas);
        mia_Mesagho.remotas = try remotas_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const CCtrol, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, CCtrol, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const CCtrol, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, CCtrol, @as(*CCtrol, self), path, b_formato);
    }

    fn seriigi(self: *const CCtrol, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
    for (self.remotas) |item| {
        const remotas_longa = try item.seriigi( allocator, buffer );
        tuta_longo += remotas_longa;
        tuta_longo += try buffer.encodeVarint(remotas_longa);
        tuta_longo += try buffer.encodeVarint(18);
    }  // 11  rept - no def - varlong 

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !CCtrol {
        return try deseriigiTiponElBin(allocator, CCtrol, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !CCtrol {
        return try deseriigiTiponElDosiero(allocator, CCtrol, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !CCtrol {
        var mia_Mesagho= try CCtrol.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var remotas_list: std.ArrayList(EstRemCtrol) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                { try remotas_list.append( allocator, try EstRemCtrol.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.remotas = try remotas_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};    // CCtrol

pub const EstRemCtrol = struct {
    nombre: []const u8,
    meteos: []EstMeteo,
    datos_tr: []SnrTrafico,
    paneles: []PanelInfoV,

    pub fn initDefault(allocator: all.Allocator) !EstRemCtrol {
        return EstRemCtrol {
            .nombre = try allocator.dupe(u8, ""),
            .meteos = try allocator.alloc(EstMeteo, 0),
            .datos_tr = try allocator.alloc(SnrTrafico, 0),
            .paneles = try allocator.alloc(PanelInfoV, 0),
        };
    }

    pub fn deinit(self: *const EstRemCtrol, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        for (self.meteos) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.meteos);
        for (self.datos_tr) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.datos_tr);
        for (self.paneles) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.paneles);
    }

    pub fn setNombre(
        self: *EstRemCtrol,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *EstRemCtrol, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, EstRemCtrol, @as(*EstRemCtrol, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *EstRemCtrol, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, EstRemCtrol, @as(*EstRemCtrol, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !EstRemCtrol {
        return try legiTiponElTeksto(allocator, EstRemCtrol, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !EstRemCtrol {
        return try legiTiponElDosiero(allocator, EstRemCtrol, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const EstRemCtrol, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        for(self.meteos) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const meteos_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(meteos_text);

            try bufro.print(allocator, "{s}meteos {{\n{s}{s}}}\n", .{ ind, meteos_text, ind });
        }
        for(self.datos_tr) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const datos_tr_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(datos_tr_text);

            try bufro.print(allocator, "{s}datos_tr {{\n{s}{s}}}\n", .{ ind, datos_tr_text, ind });
        }
        for(self.paneles) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const paneles_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(paneles_text);

            try bufro.print(allocator, "{s}paneles {{\n{s}{s}}}\n", .{ ind, paneles_text, ind });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !EstRemCtrol {
        var mia_Mesagho= try EstRemCtrol.initDefault(allocator); 

        var meteos_list: std.ArrayList(EstMeteo) = .empty;         var datos_tr_list: std.ArrayList(SnrTrafico) = .empty;         var paneles_list: std.ArrayList(PanelInfoV) = .empty; 
        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "meteos" ) ) { 
                const sub_msg = try EstMeteo.legiElProtobufTeksto(allocator, it); 
                try meteos_list.append(allocator, sub_msg); 
                continue;
            }
            if( equal(u8, tok, "datos_tr" ) ) { 
                const sub_msg = try SnrTrafico.legiElProtobufTeksto(allocator, it); 
                try datos_tr_list.append(allocator, sub_msg); 
                continue;
            }
            if( equal(u8, tok, "paneles" ) ) { 
                const sub_msg = try PanelInfoV.legiElProtobufTeksto(allocator, it); 
                try paneles_list.append(allocator, sub_msg); 
                continue;
            }
        }
        for (mia_Mesagho.meteos) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.meteos);
        mia_Mesagho.meteos = try meteos_list.toOwnedSlice(allocator); 
        for (mia_Mesagho.datos_tr) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.datos_tr);
        mia_Mesagho.datos_tr = try datos_tr_list.toOwnedSlice(allocator); 
        for (mia_Mesagho.paneles) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.paneles);
        mia_Mesagho.paneles = try paneles_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const EstRemCtrol, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, EstRemCtrol, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const EstRemCtrol, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, EstRemCtrol, @as(*EstRemCtrol, self), path, b_formato);
    }

    fn seriigi(self: *const EstRemCtrol, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
    for (self.paneles) |item| {
        const paneles_longa = try item.seriigi( allocator, buffer );
        tuta_longo += paneles_longa;
        tuta_longo += try buffer.encodeVarint(paneles_longa);
        tuta_longo += try buffer.encodeVarint(34);
    }  // 11  rept - no def - varlong 

    for (self.datos_tr) |item| {
        const datos_tr_longa = try item.seriigi( allocator, buffer );
        tuta_longo += datos_tr_longa;
        tuta_longo += try buffer.encodeVarint(datos_tr_longa);
        tuta_longo += try buffer.encodeVarint(26);
    }  // 11  rept - no def - varlong 

    for (self.meteos) |item| {
        const meteos_longa = try item.seriigi( allocator, buffer );
        tuta_longo += meteos_longa;
        tuta_longo += try buffer.encodeVarint(meteos_longa);
        tuta_longo += try buffer.encodeVarint(18);
    }  // 11  rept - no def - varlong 

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !EstRemCtrol {
        return try deseriigiTiponElBin(allocator, EstRemCtrol, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !EstRemCtrol {
        return try deseriigiTiponElDosiero(allocator, EstRemCtrol, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !EstRemCtrol {
        var mia_Mesagho= try EstRemCtrol.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var meteos_list: std.ArrayList(EstMeteo) = .empty; 
        var datos_tr_list: std.ArrayList(SnrTrafico) = .empty; 
        var paneles_list: std.ArrayList(PanelInfoV) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                { try meteos_list.append( allocator, try EstMeteo.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
            else if ( field_number == 3 and wire_type == 2 ) 
                { try datos_tr_list.append( allocator, try SnrTrafico.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
            else if ( field_number == 4 and wire_type == 2 ) 
                { try paneles_list.append( allocator, try PanelInfoV.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.meteos = try meteos_list.toOwnedSlice(allocator); 
        mia_Mesagho.datos_tr = try datos_tr_list.toOwnedSlice(allocator); 
        mia_Mesagho.paneles = try paneles_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};    // EstRemCtrol

pub const EstMeteo = struct {
    nombre: []const u8,
    temp: u32,
    v_viento: f32,
    dir_viento: f32,

    pub fn initDefault(allocator: all.Allocator) !EstMeteo {
        return EstMeteo {
            .nombre = try allocator.dupe(u8, ""),
            .temp = 0,
            .v_viento = 0,
            .dir_viento = 0,
        };
    }

    pub fn deinit(self: *const EstMeteo, allocator: all.Allocator) void {
        allocator.free(self.nombre);
    }

    pub fn setNombre(
        self: *EstMeteo,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *EstMeteo, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, EstMeteo, @as(*EstMeteo, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *EstMeteo, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, EstMeteo, @as(*EstMeteo, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !EstMeteo {
        return try legiTiponElTeksto(allocator, EstMeteo, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !EstMeteo {
        return try legiTiponElDosiero(allocator, EstMeteo, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const EstMeteo, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        try bufro.print(allocator,"{s}temp: {any}\n",.{ind, self.temp });
        try bufro.print(allocator,"{s}v_viento: {any}\n",.{ind, self.v_viento });
        try bufro.print(allocator,"{s}dir_viento: {any}\n",.{ind, self.dir_viento });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !EstMeteo {
        var mia_Mesagho= try EstMeteo.initDefault(allocator); 


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "temp" ) ) { 
                mia_Mesagho.temp =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "v_viento" ) ) { 
                mia_Mesagho.v_viento =  std.fmt.parseFloat(f32,val) catch 0.0;
                continue;
            }
            if( equal(u8, tok, "dir_viento" ) ) { 
                mia_Mesagho.dir_viento =  std.fmt.parseFloat(f32,val) catch 0.0;
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const EstMeteo, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, EstMeteo, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const EstMeteo, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, EstMeteo, @as(*EstMeteo, self), path, b_formato);
    }

    fn seriigi(self: *const EstMeteo, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        tuta_longo += try buffer.encodeFloat( self.dir_viento );
        tuta_longo += try buffer.encodeVarint(37);
        //5 req - no def - no varlong

        tuta_longo += try buffer.encodeFloat( self.v_viento );
        tuta_longo += try buffer.encodeVarint(29);
        //5 req - no def - no varlong

        tuta_longo += try buffer.encodeUint32( self.temp );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !EstMeteo {
        return try deseriigiTiponElBin(allocator, EstMeteo, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !EstMeteo {
        return try deseriigiTiponElDosiero(allocator, EstMeteo, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !EstMeteo {
        var mia_Mesagho= try EstMeteo.initDefault(allocator);

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
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.temp = try buffer.decodeUint32()
            else if ( field_number == 3 and wire_type == 5 ) 
                mia_Mesagho.v_viento = try buffer.decodeFloat()
            else if ( field_number == 4 and wire_type == 5 ) 
                mia_Mesagho.dir_viento = try buffer.decodeFloat();
        }


        return mia_Mesagho;
    }
};    // EstMeteo

pub const SnrTrafico = struct {
    seccion: []const u8,
    carriles: u32,
    vel_media: []f32,
    vehiculos_min: []f32,

    pub fn initDefault(allocator: all.Allocator) !SnrTrafico {
        return SnrTrafico {
            .seccion = try allocator.dupe(u8, ""),
            .carriles = 0,
            .vel_media = try allocator.alloc(f32, 0),
            .vehiculos_min = try allocator.alloc(f32, 0),
        };
    }

    pub fn deinit(self: *const SnrTrafico, allocator: all.Allocator) void {
        allocator.free(self.seccion);
        allocator.free(self.vel_media);
        allocator.free(self.vehiculos_min);
    }

    pub fn setSeccion(
        self: *SnrTrafico,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.seccion);
        self.seccion = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *SnrTrafico, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, SnrTrafico, @as(*SnrTrafico, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *SnrTrafico, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, SnrTrafico, @as(*SnrTrafico, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !SnrTrafico {
        return try legiTiponElTeksto(allocator, SnrTrafico, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !SnrTrafico {
        return try legiTiponElDosiero(allocator, SnrTrafico, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const SnrTrafico, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}seccion: \"{s}\"\n",.{ind, self.seccion });
        try bufro.print(allocator,"{s}carriles: {any}\n",.{ind, self.carriles });
        for(self.vel_media) |obj| {
            try bufro.print(allocator,"{s}vel_media: {any}\n",.{ind, obj });
        }
        for(self.vehiculos_min) |obj| {
            try bufro.print(allocator,"{s}vehiculos_min: {any}\n",.{ind, obj });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !SnrTrafico {
        var mia_Mesagho= try SnrTrafico.initDefault(allocator); 

        var vel_media_list: std.ArrayList(f32) = .empty;         var vehiculos_min_list: std.ArrayList(f32) = .empty; 
        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "seccion" ) ) { 
                allocator.free(mia_Mesagho.seccion);
                mia_Mesagho.seccion = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "carriles" ) ) { 
                mia_Mesagho.carriles =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "vel_media" ) ) { 
                try vel_media_list.append(allocator, std.fmt.parseFloat(f32,val) catch 0.0);
                continue;
            }
            if( equal(u8, tok, "vehiculos_min" ) ) { 
                try vehiculos_min_list.append(allocator, std.fmt.parseFloat(f32,val) catch 0.0);
                continue;
            }
        }
        allocator.free(mia_Mesagho.vel_media);
        mia_Mesagho.vel_media = try vel_media_list.toOwnedSlice(allocator); 
        allocator.free(mia_Mesagho.vehiculos_min);
        mia_Mesagho.vehiculos_min = try vehiculos_min_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const SnrTrafico, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, SnrTrafico, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const SnrTrafico, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, SnrTrafico, @as(*SnrTrafico, self), path, b_formato);
    }

    fn seriigi(self: *const SnrTrafico, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        for (self.vehiculos_min) |item| {
            tuta_longo += try buffer.encodeFloat( item );
            tuta_longo += try buffer.encodeVarint(37);
        }  // 9 rept - no def - no varlong 

        for (self.vel_media) |item| {
            tuta_longo += try buffer.encodeFloat( item );
            tuta_longo += try buffer.encodeVarint(29);
        }  // 9 rept - no def - no varlong 

        tuta_longo += try buffer.encodeUint32( self.carriles );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        const seccion_longa = try buffer.encodeString( self.seccion );
        tuta_longo += seccion_longa;
        tuta_longo += try buffer.encodeVarint(seccion_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !SnrTrafico {
        return try deseriigiTiponElBin(allocator, SnrTrafico, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !SnrTrafico {
        return try deseriigiTiponElDosiero(allocator, SnrTrafico, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !SnrTrafico {
        var mia_Mesagho= try SnrTrafico.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var vel_media_list: std.ArrayList(f32) = .empty; 
        var vehiculos_min_list: std.ArrayList(f32) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.seccion = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.carriles = try buffer.decodeUint32()
            else if ( field_number == 3 and wire_type == 5 ) 
                { try vel_media_list.append( allocator, try buffer.decodeFloat() ); }
            else if ( field_number == 4 and wire_type == 5 ) 
                { try vehiculos_min_list.append( allocator, try buffer.decodeFloat() ); }
        }

        mia_Mesagho.vel_media = try vel_media_list.toOwnedSlice(allocator); 
        mia_Mesagho.vehiculos_min = try vehiculos_min_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};    // SnrTrafico

pub const PanelInfoV = struct {
    nombre: []const u8,
    elementos: []PanelBase,

    pub fn initDefault(allocator: all.Allocator) !PanelInfoV {
        return PanelInfoV {
            .nombre = try allocator.dupe(u8, ""),
            .elementos = try allocator.alloc(PanelBase, 0),
        };
    }

    pub fn deinit(self: *const PanelInfoV, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        for (self.elementos) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.elementos);
    }

    pub fn setNombre(
        self: *PanelInfoV,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *PanelInfoV, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, PanelInfoV, @as(*PanelInfoV, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *PanelInfoV, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, PanelInfoV, @as(*PanelInfoV, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !PanelInfoV {
        return try legiTiponElTeksto(allocator, PanelInfoV, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !PanelInfoV {
        return try legiTiponElDosiero(allocator, PanelInfoV, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const PanelInfoV, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        for(self.elementos) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const elementos_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(elementos_text);

            try bufro.print(allocator, "{s}elementos {{\n{s}{s}}}\n", .{ ind, elementos_text, ind });
        }

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !PanelInfoV {
        var mia_Mesagho= try PanelInfoV.initDefault(allocator); 

        var elementos_list: std.ArrayList(PanelBase) = .empty; 
        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "elementos" ) ) { 
                const sub_msg = try PanelBase.legiElProtobufTeksto(allocator, it); 
                try elementos_list.append(allocator, sub_msg); 
                continue;
            }
        }
        for (mia_Mesagho.elementos) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.elementos);
        mia_Mesagho.elementos = try elementos_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const PanelInfoV, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, PanelInfoV, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const PanelInfoV, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, PanelInfoV, @as(*PanelInfoV, self), path, b_formato);
    }

    fn seriigi(self: *const PanelInfoV, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
    for (self.elementos) |item| {
        const elementos_longa = try item.seriigi( allocator, buffer );
        tuta_longo += elementos_longa;
        tuta_longo += try buffer.encodeVarint(elementos_longa);
        tuta_longo += try buffer.encodeVarint(18);
    }  // 11  rept - no def - varlong 

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !PanelInfoV {
        return try deseriigiTiponElBin(allocator, PanelInfoV, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !PanelInfoV {
        return try deseriigiTiponElDosiero(allocator, PanelInfoV, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !PanelInfoV {
        var mia_Mesagho= try PanelInfoV.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var elementos_list: std.ArrayList(PanelBase) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                { try elementos_list.append( allocator, try PanelBase.deseriigi(allocator, buffer, try buffer.decodeVarint() ) ); }
        }

        mia_Mesagho.elementos = try elementos_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }
};    // PanelInfoV

pub const PanelBase = struct {
    pub const Datos = union(enum) {
        none: void,
        senial: SenialInfo,
        texto: TextoInfo,
    };

    nombre: []const u8,
    tipo: TipoPanel,
    datos: Datos,

    pub fn initDefault(allocator: all.Allocator) !PanelBase {
        return PanelBase {
            .nombre = try allocator.dupe(u8, ""),
            .tipo = std.meta.intToEnum(TipoPanel, 0) catch unreachable,
            .datos = .{ .none = {} },
        };
    }

    fn deinitDatos(self: *const PanelBase, allocator: all.Allocator) void {
        switch (self.datos) {
            .none => {},
            .senial => |*v| v.deinit(allocator),
            .texto => |*v| v.deinit(allocator),
        }
    }

    pub fn deinit(self: *const PanelBase, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        self.deinitDatos(allocator);
    }

    pub fn setNombre(
        self: *PanelBase,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *PanelBase, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, PanelBase, @as(*PanelBase, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *PanelBase, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, PanelBase, @as(*PanelBase, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !PanelBase {
        return try legiTiponElTeksto(allocator, PanelBase, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !PanelBase {
        return try legiTiponElDosiero(allocator, PanelBase, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const PanelBase, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        try bufro.print(allocator, "{s}tipo: {s}\n", .{ ind, @tagName(self.tipo) });
        switch (self.datos) {
            .none => {},
            .senial => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const senial_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(senial_text);

                try bufro.print(allocator, "{s}senial {{\n{s}{s}}}\n", .{ ind, senial_text, ind });
            },
            .texto => |val| {
                const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
                defer allocator.free(indent);
                const texto_text = try val.skribiAlProtobufTeksto(allocator, indent);
                defer allocator.free(texto_text);

                try bufro.print(allocator, "{s}texto {{\n{s}{s}}}\n", .{ ind, texto_text, ind });
            },
        }


        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !PanelBase {
        var mia_Mesagho= try PanelBase.initDefault(allocator); 


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "tipo" ) ) { 
                mia_Mesagho.tipo = parseEnumValue(TipoPanel, val) catch (std.meta.intToEnum(TipoPanel, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "senial" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const datos_senial_val = try SenialInfo.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitDatos(allocator);
                mia_Mesagho.datos = .{ .senial = datos_senial_val };
                continue;
            }
            if( equal(u8, tok, "texto" ) ) {
                if( ! equal(u8, val, "{" ) ) return error.InvalidFormat;
                const datos_texto_val = try TextoInfo.legiElProtobufTeksto(allocator, it);
                mia_Mesagho.deinitDatos(allocator);
                mia_Mesagho.datos = .{ .texto = datos_texto_val };
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const PanelBase, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, PanelBase, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const PanelBase, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, PanelBase, @as(*PanelBase, self), path, b_formato);
    }

    fn seriigi(self: *const PanelBase, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        switch (self.datos) {
            .none => {},
            .senial => |val| {
                const datos_senial_longa = try val.seriigi(allocator, buffer);
                tuta_longo += datos_senial_longa;
                tuta_longo += try buffer.encodeVarint(datos_senial_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 20) << 3) | 2);
            },
            .texto => |val| {
                const datos_texto_longa = try val.seriigi(allocator, buffer);
                tuta_longo += datos_texto_longa;
                tuta_longo += try buffer.encodeVarint(datos_texto_longa);
                tuta_longo += try buffer.encodeVarint((@as(u32, 21) << 3) | 2);
            },
        }

        tuta_longo += try buffer.encodeVarint( @intFromEnum(self.tipo) );
        tuta_longo += try buffer.encodeVarint(16);
        //5 req - no def - no varlong

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !PanelBase {
        return try deseriigiTiponElBin(allocator, PanelBase, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !PanelBase {
        return try deseriigiTiponElDosiero(allocator, PanelBase, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !PanelBase {
        var mia_Mesagho= try PanelBase.initDefault(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;


        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 20 and wire_type == 2 )
            {
                const datos_senial_val = try SenialInfo.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitDatos(allocator);
                mia_Mesagho.datos = .{ .senial = datos_senial_val };
            }
            else if ( field_number == 21 and wire_type == 2 )
            {
                const datos_texto_val = try TextoInfo.deseriigi(
                    allocator,
                    buffer,
                    try buffer.decodeVarint(),
                );
    
                mia_Mesagho.deinitDatos(allocator);
                mia_Mesagho.datos = .{ .texto = datos_texto_val };
            }
            else if ( field_number == 1 and wire_type == 2 ) 
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.tipo = try std.meta.intToEnum(TipoPanel, try buffer.decodeVarint() ) ;
        }


        return mia_Mesagho;
    }
};    // PanelBase

pub const SenialInfo = struct {
    nombre: []const u8,
    senial: []const u8,

    pub fn initDefault(allocator: all.Allocator) !SenialInfo {
        return SenialInfo {
            .nombre = try allocator.dupe(u8, ""),
            .senial = try allocator.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *const SenialInfo, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        allocator.free(self.senial);
    }

    pub fn setNombre(
        self: *SenialInfo,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn setSenial(
        self: *SenialInfo,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.senial);
        self.senial = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *SenialInfo, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, SenialInfo, @as(*SenialInfo, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *SenialInfo, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, SenialInfo, @as(*SenialInfo, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !SenialInfo {
        return try legiTiponElTeksto(allocator, SenialInfo, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !SenialInfo {
        return try legiTiponElDosiero(allocator, SenialInfo, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const SenialInfo, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        try bufro.print(allocator,"{s}senial: \"{s}\"\n",.{ind, self.senial });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !SenialInfo {
        var mia_Mesagho= try SenialInfo.initDefault(allocator); 


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "senial" ) ) { 
                allocator.free(mia_Mesagho.senial);
                mia_Mesagho.senial = try allocator.dupe(u8, val);
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const SenialInfo, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, SenialInfo, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const SenialInfo, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, SenialInfo, @as(*SenialInfo, self), path, b_formato);
    }

    fn seriigi(self: *const SenialInfo, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        const senial_longa = try buffer.encodeString( self.senial );
        tuta_longo += senial_longa;
        tuta_longo += try buffer.encodeVarint(senial_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !SenialInfo {
        return try deseriigiTiponElBin(allocator, SenialInfo, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !SenialInfo {
        return try deseriigiTiponElDosiero(allocator, SenialInfo, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !SenialInfo {
        var mia_Mesagho= try SenialInfo.initDefault(allocator);

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
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.senial = try buffer.decodeString(  try buffer.decodeVarint() );
        }


        return mia_Mesagho;
    }
};    // SenialInfo

pub const TextoInfo = struct {
    nombre: []const u8,
    texto: []const u8,

    pub fn initDefault(allocator: all.Allocator) !TextoInfo {
        return TextoInfo {
            .nombre = try allocator.dupe(u8, ""),
            .texto = try allocator.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *const TextoInfo, allocator: all.Allocator) void {
        allocator.free(self.nombre);
        allocator.free(self.texto);
    }

    pub fn setNombre(
        self: *TextoInfo,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.nombre);
        self.nombre = try allocator.dupe(u8, value);
    }

    pub fn setTexto(
        self: *TextoInfo,
        allocator: all.Allocator,
        value: []const u8,
    ) !void {
        allocator.free(self.texto);
        self.texto = try allocator.dupe(u8, value);
    }

    pub fn skribiAlTeksto(self: *TextoInfo, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, TextoInfo, @as(*TextoInfo, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *TextoInfo, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, TextoInfo, @as(*TextoInfo, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !TextoInfo {
        return try legiTiponElTeksto(allocator, TextoInfo, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !TextoInfo {
        return try legiTiponElDosiero(allocator, TextoInfo, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const TextoInfo, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        try bufro.print(allocator,"{s}nombre: \"{s}\"\n",.{ind, self.nombre });
        try bufro.print(allocator,"{s}texto: \"{s}\"\n",.{ind, self.texto });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !TextoInfo {
        var mia_Mesagho= try TextoInfo.initDefault(allocator); 


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "nombre" ) ) { 
                allocator.free(mia_Mesagho.nombre);
                mia_Mesagho.nombre = try allocator.dupe(u8, val);
                continue;
            }
            if( equal(u8, tok, "texto" ) ) { 
                allocator.free(mia_Mesagho.texto);
                mia_Mesagho.texto = try allocator.dupe(u8, val);
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const TextoInfo, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, TextoInfo, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const TextoInfo, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, TextoInfo, @as(*TextoInfo, self), path, b_formato);
    }

    fn seriigi(self: *const TextoInfo, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        const texto_longa = try buffer.encodeString( self.texto );
        tuta_longo += texto_longa;
        tuta_longo += try buffer.encodeVarint(texto_longa);
        tuta_longo += try buffer.encodeVarint(18);
        //7  req - no def - varlong

        const nombre_longa = try buffer.encodeString( self.nombre );
        tuta_longo += nombre_longa;
        tuta_longo += try buffer.encodeVarint(nombre_longa);
        tuta_longo += try buffer.encodeVarint(10);
        //7  req - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !TextoInfo {
        return try deseriigiTiponElBin(allocator, TextoInfo, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !TextoInfo {
        return try deseriigiTiponElDosiero(allocator, TextoInfo, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !TextoInfo {
        var mia_Mesagho= try TextoInfo.initDefault(allocator);

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
                mia_Mesagho.nombre = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.texto = try buffer.decodeString(  try buffer.decodeVarint() );
        }


        return mia_Mesagho;
    }
};    // TextoInfo

};   // cctrol

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
            parsed = zon.parse.fromSlice(T, allocator, @ptrCast(input), null, .{}) catch |err| {
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
            var it: TokenIterType = std.mem.tokenizeAny(u8, input, ":\", \n\r\t");
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
