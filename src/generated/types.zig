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


pub const Msg = struct {
    channels: []u64,
    msgType: u64,
    payLoad: []const u8,

    pub fn initDefault(allocator: all.Allocator) !Msg {
        return Msg {
            .channels = try allocator.alloc(u64, 0),
            .msgType = 0,
            .payLoad = try allocator.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *const Msg, allocator: all.Allocator) void {
        allocator.free(self.channels);
        allocator.free(self.payLoad);
    }

    pub fn skribiAlTeksto(self: *Msg, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, Msg, @as(*Msg, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *Msg, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, Msg, @as(*Msg, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !Msg {
        return try legiTiponElTeksto(allocator, Msg, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !Msg {
        return try legiTiponElDosiero(allocator, Msg, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const Msg, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        for(self.channels) |obj| {
            try bufro.print(allocator,"{s}channels: {any}\n",.{ind, obj });
        }
        try bufro.print(allocator,"{s}msgType: {any}\n",.{ind, self.msgType });
        try bufro.print(allocator,"{s}payLoad: {any}\n",.{ind, self.payLoad });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !Msg {
        var mia_Mesagho = try Msg.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var channels_list: std.ArrayList(u64) = .empty;
        errdefer channels_list.deinit(allocator);

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "channels" ) ) {
                try channels_list.append(allocator, std.fmt.parseInt(u64,val,10) catch 0);
                continue;
            }
            if( equal(u8, tok, "msgType" ) ) {
                mia_Mesagho.msgType =  std.fmt.parseInt(u64,val,10) catch 0;
                continue;
            }
            if( equal(u8, tok, "payLoad" ) ) {
                const tmp_payLoad = try unescapePbTextToken(allocator, val);
                allocator.free(mia_Mesagho.payLoad);
                mia_Mesagho.payLoad = tmp_payLoad;
                continue;
            }
        }
        allocator.free(mia_Mesagho.channels);
        mia_Mesagho.channels = try channels_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const Msg, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, Msg, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const Msg, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, Msg, @as(*Msg, self), path, b_formato);
    }

    fn seriigi(self: *const Msg, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        _ = allocator;
        var tuta_longo: usize = 0;
 
        const payLoad_longa = try buffer.encodeBytes( self.payLoad );
        tuta_longo += payLoad_longa;
        tuta_longo += try buffer.encodeVarint(payLoad_longa);
        tuta_longo += try buffer.encodeVarint(26);
        //7  req - no def - varlong

        tuta_longo += try buffer.encodeFixed64( self.msgType );
        tuta_longo += try buffer.encodeVarint(17);
        //5 req - no def - no varlong

        var channels_i: usize = self.channels.len;
        while (channels_i > 0) {
            channels_i -= 1;
            const item = self.channels[channels_i];
            tuta_longo += try buffer.encodeFixed64( item );
            tuta_longo += try buffer.encodeVarint(9);
        }  // 9 rept - no def - no varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !Msg {
        return try deseriigiTiponElBin(allocator, Msg, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !Msg {
        return try deseriigiTiponElDosiero(allocator, Msg, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !Msg {
        var mia_Mesagho = try Msg.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var channels_list: std.ArrayList(u64) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 1 ) 
            { 
                try channels_list.append( 
                    allocator, 
                    try buffer.decodeFixed64()
                );
            }
            else if ( field_number == 2 and wire_type == 1 ) 
                mia_Mesagho.msgType = try buffer.decodeFixed64()
            else if ( field_number == 3 and wire_type == 2 ) 
            {
                const tmp_payLoad = try buffer.decodeBytes(  try buffer.decodeVarint() );
                allocator.free(mia_Mesagho.payLoad);
                mia_Mesagho.payLoad = tmp_payLoad;
            }
        }

        const tmp_channels = try channels_list.toOwnedSlice(allocator);
        allocator.free(mia_Mesagho.channels);
        mia_Mesagho.channels = tmp_channels;

        return mia_Mesagho;
    }
};    // Msg

pub const Packet = struct {
    messages: []Msg,
    OutOfBand: ?u64 = null,

    pub fn initDefault(allocator: all.Allocator) !Packet {
        return Packet {
            .messages = try allocator.alloc(Msg, 0),
            .OutOfBand = null,
        };
    }

    pub fn deinit(self: *const Packet, allocator: all.Allocator) void {
        for (self.messages) |item| {
            item.deinit(allocator);
        }
        allocator.free(self.messages);
    }

    pub fn skribiAlTeksto(self: *Packet, allocator: all.Allocator, t_formato: TekstaFormato) ![]const u8 {
        return try skribiTiponAlTeksto(allocator, Packet, @as(*Packet, self), t_formato);
    }

    pub fn skribiAlDosiero(self: *Packet, allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !void {
        try skribiTiponAlDosiero(allocator, Packet, @as(*Packet, self), path, t_formato);
    }

    pub fn legiElTeksto(allocator: all.Allocator, input: []const u8, t_formato: TekstaFormato) !Packet {
        return try legiTiponElTeksto(allocator, Packet, input, t_formato);
    }

    pub fn legiElDosiero(allocator: all.Allocator, path: []const u8, t_formato: TekstaFormato) !Packet {
        return try legiTiponElDosiero(allocator, Packet, path, t_formato);
    }

    fn skribiAlProtobufTeksto(self: *const Packet, allocator: all.Allocator,ind: []const u8) ![]const u8 {
        var bufro:std.ArrayList(u8)= .empty;

        for(self.messages) |obj| {
            const indent = std.mem.concatWithSentinel(allocator, u8, &[_][]const u8{ ind, "    " }, 0) catch unreachable;
            defer allocator.free(indent);
            const messages_text = try obj.skribiAlProtobufTeksto(allocator, indent);
            defer allocator.free(messages_text);

            try bufro.print(allocator, "{s}messages {{\n{s}{s}}}\n", .{ ind, messages_text, ind });
        }
        if( self.OutOfBand ) |val|  
            try bufro.print(allocator,"{s}OutOfBand: {any}\n",.{ ind, val });

        return bufro.toOwnedSlice(allocator);
    }

    fn legiElProtobufTeksto(allocator: all.Allocator, it: *TokenIterType) !Packet {
        var mia_Mesagho = try Packet.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var messages_list: std.ArrayList(Msg) = .empty;
        errdefer {
            for (messages_list.items) |*item| {
                item.deinit(allocator);
            }
            messages_list.deinit(allocator);
        }

        while (it.next()) |tok| {
            if( equal(u8, tok, "}" ) ) break;
            const val = it.next() orelse return error.InvalidFormat;

            if( equal(u8, tok, "messages" ) ) {
                const sub_msg = try Msg.legiElProtobufTeksto(allocator, it); 
                messages_list.append(allocator, sub_msg) catch |err| {
                    sub_msg.deinit(allocator);
                    return err;
                };
                continue;
            }
            if( equal(u8, tok, "OutOfBand" ) ) {
                mia_Mesagho.OutOfBand =  std.fmt.parseInt(u64,val,10) catch 0;
                continue;
            }
        }
        for (mia_Mesagho.messages) |item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.messages);
        mia_Mesagho.messages = try messages_list.toOwnedSlice(allocator); 

        return mia_Mesagho;
    }

    pub fn seriigiAlBin(self: *const Packet, allocator: all.Allocator, b_formato: BinaraFormato) ![]const u8 {
        return try seriigiTiponAlBin(allocator, Packet, self, b_formato);
    }

    pub fn seriigiAlDosiero(self: *const Packet, allocator: all.Allocator, path: []const u8, b_formato: BinaraFormato) !void {
        return try seriigiTiponAlDosiero(allocator, Packet, @as(*Packet, self), path, b_formato);
    }

    fn seriigi(self: *const Packet, allocator: all.Allocator, buffer: *EncodeBuffer) !usize {
 
        var tuta_longo: usize = 0;
 
        if( self.OutOfBand ) |val| {
            tuta_longo += try buffer.encodeUint64( val );
            tuta_longo += try buffer.encodeVarint(16);
        }   //1 opt - no def - no varlong

        var messages_i: usize = self.messages.len;
        while (messages_i > 0) {
            messages_i -= 1;
            const item = self.messages[messages_i];
            const messages_longa = try item.seriigi( allocator, buffer );
            tuta_longo += messages_longa;
            tuta_longo += try buffer.encodeVarint(messages_longa);
            tuta_longo += try buffer.encodeVarint(10);
        }  // 11  rept - no def - varlong

        return tuta_longo;
    }

    pub fn deseriigiElBin(allocator: all.Allocator,input: []const u8, b_formato: BinaraFormato) !Packet {
        return try deseriigiTiponElBin(allocator, Packet, input, b_formato);
    }

    pub fn deseriigiElDosiero(allocator: all.Allocator, path: [:0]const u8, b_formato: BinaraFormato) !Packet {
        return try deseriigiTiponElDosiero(allocator, Packet, path, b_formato);
    }

    fn deseriigi(allocator: all.Allocator, buffer: *DecodeBuffer, data_length: ?usize) !Packet {
        var mia_Mesagho = try Packet.initDefault(allocator);
        errdefer mia_Mesagho.deinit(allocator);

        var end: usize = undefined;
        if (data_length) |val|
            end = buffer.read_index + val
        else
            end = buffer.buffer.len;

        var messages_list: std.ArrayList(Msg) = .empty; 

        while (buffer.read_index < end) {
            const key: u64 = buffer.decodeVarint() catch 0 ;    
            const wire_type = key & 0x7;  
            const field_number = key >> 3;

            if ( field_number == 1 and wire_type == 2 ) 
            { 
                try messages_list.append( 
                    allocator, 
                    try Msg.deseriigi(allocator, buffer, try buffer.decodeVarint() )
                );
            }
            else if ( field_number == 2 and wire_type == 0 ) 
                mia_Mesagho.OutOfBand = try buffer.decodeUint64();
        }

        const tmp_messages = try messages_list.toOwnedSlice(allocator);
        for (mia_Mesagho.messages) |*item| {
            item.deinit(allocator);
        }
        allocator.free(mia_Mesagho.messages);
        mia_Mesagho.messages = tmp_messages;

        return mia_Mesagho;
    }
};    // Packet

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

