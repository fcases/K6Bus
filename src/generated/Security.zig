const std = @import("std");
const dbg = std.debug;
const all = std.mem;
const equal = std.mem.eql;
const  io = std.Io;

const encdec = @import("encdec.zig");
const EncodeBuffer = encdec.EncodeBuffer;
const DecodeBuffer = encdec.DecodeBuffer;

const TokenIterType = std.mem.TokenIterator(u8, .any);

pub const k6bus = struct {

    pub const security = struct {


pub const CryptoMode = enum(u64) {
   CRYPTO_NONE = 0,
   CRYPTO_AES_256_GCM = 1,
   CRYPTO_CHACHA20_POLY1305 = 2,
   CRYPTO_AES_256_CBC = 3,
};

pub const KeyRegistry = struct {
    version: ?u32 = 1 ,
    description: ?[]const u8 = null,
    mode: ?CryptoMode = .CRYPTO_AES_256_GCM ,
    key_id: ?u32 = 0 ,
    key: []const u8,
    iv: ?[]const u8 = null,

    pub fn initDefault(allocator: all.Allocator) !KeyRegistry {
        _ = allocator;
        return KeyRegistry {
            .version = 1,
            .description = null,
            .mode = .CRYPTO_AES_256_GCM,
            .key_id = 0,
            .key = "",
            .iv = null,
        };
    }

    pub fn deinit(self: *KeyRegistry, allocator: all.Allocator) void {
        allocator.free(self.description);
        allocator.free(self.key);
        allocator.free(self.iv);
    }

    pub fn skribiAlTeksto(self: *KeyRegistry, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, KeyRegistry, @as(*KeyRegistry, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *KeyRegistry, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, KeyRegistry, @as(*KeyRegistry, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !KeyRegistry {
        return try legiTiponElTeksto(allocator, KeyRegistry, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !KeyRegistry {
        return try legiTiponElDosiero(allocator, KeyRegistry, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const KeyRegistry, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        if( self.version ) |val|  
            try bufro.print(allocator,"{s}version: {any}\n",.{ ind, val });
        if( self.description ) |val|  
            try bufro.print(allocator,"{s}description: \"{s}\"\n",.{ ind, val });
        if( self.mode ) |val|  
            try bufro.print(allocator,"{s}mode: {any}\n",.{ ind, val });
        if( self.key_id ) |val|  
            try bufro.print(allocator,"{s}key_id: {any}\n",.{ ind, val });
        try bufro.print(allocator,"{s}key: \"{s}\"\n",.{ind, self.key });
        if( self.iv ) |val|  
            try bufro.print(allocator,"{s}iv: \"{s}\"\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !KeyRegistry {
        var mia_Mesagho= try KeyRegistry.initDefault(allocator); 


        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "version" ) ) { 
                mia_Mesagho.version =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "description" ) ) { 
                mia_Mesagho.description =  allocator.dupe(u8, val) catch "";
                continue;
            }
            if( equal(u8, tok, "mode" ) ) { 
                mia_Mesagho.mode = parseEnumValue(CryptoMode, val) catch (std.meta.intToEnum(CryptoMode, 0) catch unreachable);
                continue;
            }
            if( equal(u8, tok, "key_id" ) ) { 
                mia_Mesagho.key_id =  std.fmt.parseInt(u32,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "key" ) ) { 
                mia_Mesagho.key =  allocator.dupe(u8, val) catch "";
                continue;
            }
            if( equal(u8, tok, "iv" ) ) { 
                mia_Mesagho.iv =  allocator.dupe(u8, val) catch "";
                continue;
            }
        }

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const KeyRegistry, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, KeyRegistry, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const KeyRegistry, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, KeyRegistry, @as(*KeyRegistry, self), path, b_formato);
    }

    fn seriigi(self: *const KeyRegistry, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
    if ( self.iv ) |val| {
        const st_longa = try buffer.encodeString( val );
        tuta_longo += st_longa;
        tuta_longo += try buffer.encodeVarint(st_longa);
        tuta_longo += try buffer.encodeVarint(50);
    }  //3  opt - no def - varlong

        const key_longa = try buffer.encodeString( self.key );
        tuta_longo += key_longa;
        tuta_longo += try buffer.encodeVarint(key_longa);
        tuta_longo += try buffer.encodeVarint(42);
        //7  req - no def - varlong

    if( self.key_id ) |val| {
        if( val != 0 )  {
            tuta_longo += try buffer.encodeUint32( val );
            tuta_longo += try buffer.encodeVarint(32);
        }
    }  //2 opt - def - no varlong

    if( self.mode ) |val| {
        if( val != .CRYPTO_AES_256_GCM )  {
            tuta_longo += try buffer.encodeVarint( @intFromEnum(val) );
            tuta_longo += try buffer.encodeVarint(24);
        }
    }  //2 opt - def - no varlong

    if ( self.description ) |val| {
        const st_longa = try buffer.encodeString( val );
        tuta_longo += st_longa;
        tuta_longo += try buffer.encodeVarint(st_longa);
        tuta_longo += try buffer.encodeVarint(18);
    }  //3  opt - no def - varlong

    if( self.version ) |val| {
        if( val != 1 )  {
            tuta_longo += try buffer.encodeUint32( val );
            tuta_longo += try buffer.encodeVarint(8);
        }
    }  //2 opt - def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !KeyRegistry {
        return try deseriigiTiponElBin(allocator, KeyRegistry, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !KeyRegistry {
        return try deseriigiTiponElDosiero(allocator, KeyRegistry, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !KeyRegistry {
        var mia_Mesagho= try KeyRegistry.initDefault(allocator);

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
                mia_Mesagho.version = try buffer.decodeUint32()
            else if ( field_number == 2 and wire_type == 2 ) 
                mia_Mesagho.description = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 3 and wire_type == 0 ) 
                mia_Mesagho.mode = try std.meta.intToEnum(CryptoMode, try buffer.decodeVarint() ) 
            else if ( field_number == 4 and wire_type == 0 ) 
                mia_Mesagho.key_id = try buffer.decodeUint32()
            else if ( field_number == 5 and wire_type == 2 ) 
                mia_Mesagho.key = try buffer.decodeString(  try buffer.decodeVarint() )
            else if ( field_number == 6 and wire_type == 2 ) 
                mia_Mesagho.iv = try buffer.decodeString(  try buffer.decodeVarint() );
        }


        return mia_Mesagho;
    }
};    // KeyRegistry

    };   // security
};   // k6bus

//////////////////////////////////////////////
/// //////////////////////////////////////////
/// //////////////////////////////////////////
//////////////////////////////////////////////

//////////////////////////////////////////////
/// Seriigi Binaran Tipon
/// //////////////////////////////////////////

pub const BinaraFormato = enum(u32) {
    BF_PROTOBUF,
    BF_ASN1_DER,
    BF_OMG_CDR,
    BF_BASE64,
    BF_BINPB2TEKSTO_HEX,
    BF_BINPB2TEKSTO_DEC,
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
            bytes = skribila_asignilo.writer.buffered();
        },
        .TF_JSON => {
            std.json.fmt(self, .{ .whitespace = .indent_3 }).format(&skribila_asignilo.writer) catch |err| {
                std.debug.print("eraro dum seriigo: {}\n", .{err});
                return err;
            };
            bytes = skribila_asignilo.writer.buffered();
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

fn skribiTiponAlDosiero(allocator: all.Allocator, comptime T: type, value: *T, t_formato: TekstaFormato, path: []const u8) !void {
    const teksto = try skribiTiponAlTeksto(allocator, T, value, t_formato);

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
            parsed = std.json.parseFromSliceLeaky(T, allocator, input, .{ .ignore_unknown_fields = true }) catch |err| {
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

    _ = try dosiero.readAll(enhavo[0..dosiera_long]);
    enhavo[dosiera_long] = 0;

    return legiTiponElTeksto(allocator, T, enhavo[0..dosiera_long :0], t_formato);
}
