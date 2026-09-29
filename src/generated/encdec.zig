const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const mem = std.mem;
const assert = std.debug.assert;

// Difino de generalaj eraroj (povas esti plivastigita)
const ProtobufError = error{
    EndOfBuffer,
    UnknownWireType,
    AllocationFailed,
    WriteError,
};

// ----------------------------------------
// ## DecodeBuffer
// ----------------------------------------

// Ekvivalento de 'public class DecodeBuffer'
pub const DecodeBuffer = struct {
    // `buffer`: tabelo sen posedanto (unowned) de la bufro malkodota.
    // Ni uzas `[]const u8`, cxar ni ne modifos la originan bufron.
    buffer: []const u8,
    // `internal_buffer`: opcia `?[]u8` por kiam la strukturo posedas la bufron.
    // La `allocator` estus uzata por liberigi tion.
    internal_buffer: ?[]u8,
    allocator: Allocator, // Bezonata por `internal_buffer`, `decode_string`, `decode_bytes`
    read_index: usize,
    @"error": bool, // Ni konservas la eraran kampon, kvankam Zig preferas eksplicitajn erarojn en la funkcioj

    // Konstruilo `public DecodeBuffer (uint8[] buffer, size_t offset = 0, ssize_t length = -1)`
    pub fn init(allocator: Allocator, buf: []const u8, offset: usize, length: isize) DecodeBuffer {
        var start_index = offset;
        if (start_index > buf.len) {
            start_index = buf.len;
        }

        var len: usize = 0;
        if (length < 0) {
            len = buf.len - start_index;
        } else {
            const requested_len: usize = @intCast(length);
            len = if (requested_len < buf.len - start_index) requested_len else buf.len - start_index;
        }

        return DecodeBuffer{
            .buffer = buf[start_index .. start_index + len],
            .internal_buffer = null,
            .allocator = allocator,
            .read_index = 0,
            .@"error" = false,
        };
    }

    // Konstruilo `public DecodeBuffer.sized (size_t size)`
    pub fn initSized(allocator: Allocator, size: usize) ProtobufError!DecodeBuffer {
        const internal_buffer = allocator.alloc(u8, size) catch return ProtobufError.AllocationFailed;

        const buffer = internal_buffer; // La labora slice estas la tuta interna bufro

        return DecodeBuffer{
            .buffer = buffer,
            .internal_buffer = internal_buffer,
            .allocator = allocator,
            .read_index = 0,
            .@"error" = false,
        };
    }

    // `reset`
    pub fn reset(self: *DecodeBuffer) void {
        self.read_index = 0;
        self.@"error" = false;
    }

    // Memorliberigo se `initSized` estis uzata (ne origina, sed necesa en Zig)
    pub fn deinit(self: *DecodeBuffer) void {
        if (self.internal_buffer) |buf| {
            self.allocator.free(buf);
        }
    }

    // `decode_varint`: redonas `error union` por pli bona erartraktado.
    pub fn decodeVarint(self: *DecodeBuffer) ProtobufError!u64 {
        var value: u64 = 0;
        var shift: u8 = 0; // Uzi u3 por 7-bitaj sxovoj

        while (self.read_index < self.buffer.len) {
            const byte = @as(u64, self.buffer[self.read_index]);
            self.read_index += 1;

            // `|u64` por certigi, ke la bita OR estas kun u64
            value |= (byte & 0x7F) << @truncate(shift);

            if ((byte & 0x80) == 0) {
                return value;
            }

            shift += 7;
            if (shift >= 64) {
                // Se ni atingas tiun punkton, la varint estas tro longa por u64
                self.@"error" = true;
                return ProtobufError.EndOfBuffer;
            }
        }

        // Se ni eliras la buklon, la bufro finigxis pli frue ol la varint
        self.@"error" = true;
        return ProtobufError.EndOfBuffer;
    }

    // Helpa funkcio por legi N bitokojn
    fn readBytes(self: *DecodeBuffer, count: usize) ProtobufError![]const u8 {
        if (self.read_index + count > self.buffer.len) {
            self.read_index = self.buffer.len;
            self.@"error" = true;
            return ProtobufError.EndOfBuffer;
        }

        const data = self.buffer[self.read_index .. self.read_index + count];
        self.read_index += count;
        return data;
    }

    // `decode_fixed64`

    pub fn decodeFixed64(self: *DecodeBuffer) ProtobufError!u64 {
        const data = try self.readBytes(8);

        if (data.len < 8) return ProtobufError.EndOfBuffer;

        const ptr: *const [8]u8 = @ptrCast(data.ptr);
        return mem.readInt(u64, ptr, .little);
    }

    // `decode_fixed32`
    pub fn decodeFixed32(self: *DecodeBuffer) ProtobufError!u32 {
        const data = try self.readBytes(4);

        const ptr_array_fijo: *const [4]u8 = @ptrCast(data.ptr);

        return mem.readInt(u32, ptr_array_fijo, .little);
        // return mem.readInt(u32, data.ptr, .little);
    }

    // `decode_double` - oni uzas `@floatCast`, ne punterojn.
    pub fn decodeDouble(self: *DecodeBuffer) ProtobufError!f64 {
        const v = try self.decodeFixed64();
        // bita reinterpretado: u64 al f64
        return @bitCast(v);
    }

    // `decode_float`
    pub fn decodeFloat(self: *DecodeBuffer) ProtobufError!f32 {
        const v = try self.decodeFixed32();
        // bita reinterpretado: u32 al f32
        return @bitCast(v);
    }

    // `decode_int64` (varint)
    pub fn decodeInt64(self: *DecodeBuffer) ProtobufError!i64 {
        const v = try self.decodeVarint();
        // bita reinterpretado: u64 al i64
        return @bitCast(v);
    }

    // `decode_uint64` (varint)
    pub fn decodeUint64(self: *DecodeBuffer) ProtobufError!u64 {
        return self.decodeVarint();
    }

    // `decode_int32` (varint)
    pub fn decodeInt32(self: *DecodeBuffer) ProtobufError!i32 {
        // En Zig, la kastado trancxos/etendos automatike.
        return @intCast(try self.decodeInt64());
    }

    // `decode_uint32` (varint)
    pub fn decodeUint32(self: *DecodeBuffer) ProtobufError!u32 {
        // En Zig, la kastado trancxos/etendos automatike.
        return @intCast(try self.decodeVarint());
    }

    // `decode_bool` (varint)
    pub fn decodeBool(self: *DecodeBuffer) ProtobufError!bool {
        return (try self.decodeVarint()) != 0;
    }

    // `decode_string` - bezonas la `allocator` por krei la string.
    pub fn decodeString(self: *DecodeBuffer, length: usize) ProtobufError![]u8 {
        const data = try self.readBytes(length);

        // Kopias la bitokan slice al nova memoro (uzebla kiel UTF-8 string)
        // const str_slice = try self.allocator.dupe(u8, data);
        const str_slice = self.allocator.dupe(u8, data) catch return error.AllocationFailed;

        // **Noto**: la fonto supozas, ke la bitoka tabelo estas valida string.
        // Zig preferas `[]u8` por muteblaj aux sen-NULL-finaj stringoj.
        return str_slice;
    }

    // `decode_bytes` - bezonas la `allocator` por krei `ByteArray` (bitokoj).
    pub fn decodeBytes(self: *DecodeBuffer, length: usize) ProtobufError![]u8 {
        const data = try self.readBytes(length);

        // Kreas kaj redonas kopion de la legitaj bitokoj, kun `allocator`-memoro
        return self.allocator.dupe(u8, data) catch return ProtobufError.AllocationFailed;
    }

    // `decode_sfixed32`
    pub fn decodeSfixed32(self: *DecodeBuffer) ProtobufError!i32 {
        const v = try self.decodeFixed32();
        return @bitCast(v);
    }

    // `decode_sfixed64`
    pub fn decodeSfixed64(self: *DecodeBuffer) ProtobufError!i64 {
        const v = try self.decodeFixed64();
        return @bitCast(v);
    }

    // `decode_sint32` (ZigZag)
    pub fn decodeSint32(self: *DecodeBuffer) ProtobufError!i32 {
        const value = try self.decodeVarint();
        // ZigZag decoding: (value >> 1) ^ (-(value & 1))
        return @intCast((value >> 1) ^ (@as(u64, @intCast(value & 1)) * 0xFFFFFFFFFFFFFFFF));
    }

    // `decode_sint64` (ZigZag)
    pub fn decodeSint64(self: *DecodeBuffer) ProtobufError!i64 {
        const value = try self.decodeVarint();
        // ZigZag decoding: (value >> 1) ^ (-(value & 1))
        return @intCast((value >> 1) ^ (@as(u64, @intCast(value & 1)) * 0xFFFFFFFFFFFFFFFF));
    }

};

// ----------------------------------------
// ## EncodeBuffer
// ----------------------------------------

// Ekvivalento de 'public class EncodeBuffer'
pub const EncodeBuffer = struct {
    allocator: Allocator, // Bezonata por `allocate`
    buffer: []u8, // Interna bufro (cxiam posedata de la strukturo)
    write_index: usize,

    // Konstruilo `public EncodeBuffer (size_t size = 1024)`
    pub fn init(allocator: Allocator, size: usize) ProtobufError!EncodeBuffer {
        const init_size = if (size == 0) 1 else size;
        const buf = allocator.alloc(u8, init_size) catch return ProtobufError.AllocationFailed;

        var self = EncodeBuffer{
            .allocator = allocator,
            .buffer = buf,
            .write_index = buf.len,
        };
        // `reset()` en la originalo starigas `write_index = buffer.length;`
        self.reset();
        return self;
    }

    // Memorliberigo (necesa en Zig)
    pub fn deinit(self: *EncodeBuffer) void {
        self.allocator.free(self.buffer);
    }

    // `reset`
    pub fn reset(self: *EncodeBuffer) void {
        // En la originalo la skriba indekso komencigxas cxe la fino de la bufro
        self.write_index = self.buffer.len;
    }

    // `data` (posedo 'unowned uint8[] data')
    // Redonas la jam skribitajn bitokojn (fine de la bufro, en tiu realigo)
    pub fn data(self: *EncodeBuffer) []const u8 {
        // Cxar `write_index` malantauxeniras, la datumoj iras gxis la fino
        return self.buffer[self.write_index..];
    }

    // // `allocate` (private void allocate)
    // fn allocate(self: *EncodeBuffer, size: usize) ProtobufError!void {
    //     const written_len = self.buffer.len - self.write_index;
    //     const required = size + written_len;

    //     if (required <= self.buffer.len) {
    //         return;
    //     }

    //     // Duobligi la bufron gxis suficxos da spaco (eksponenta kresko)
    //     var new_length = self.buffer.len;
    //     while (required > new_length) {
    //         new_length *= 2;
    //     }

    //     // Realoki kaj kopii la datumojn (Zig uzas `realloc` aux `realloc_exact` se povas)
    //     // Ni uzos `realloc`, pli sekura kaj kutima en `std.mem.Allocator`
    //     self.buffer = self.allocator.realloc(self.buffer, new_length) catch return ProtobufError.AllocationFailed;

    //     // Movi la ekzistantajn datumojn al la fino de la nova bufro, liberigante spacon komence
    //     const write_offset = new_length - self.buffer.len;

    //     // Movi la skribitan slice malantauxen
    //     // La datumoj movotaj estas `self.buffer[self.write_index..self.buffer.len]`, do la slice `data()` nuna
    //     // Ni movas ilin al `self.buffer[self.write_index + write_offset ..]`
    //     // mem.copy(u8, self.buffer[self.write_index + write_offset .. new_length], self.buffer[self.write_index..self.buffer.len]);
    //     @memcpy(self.buffer[self.write_index + write_offset .. new_length], self.buffer[self.write_index..self.buffer.len]);

    //     // Gxustigi la skriban indekson
    //     self.write_index += write_offset;
    // }

    fn allocate(self: *EncodeBuffer, size: usize) ProtobufError!void {
        const written_len = self.buffer.len - self.write_index;
        const required = size + written_len;
        const old_index = self.write_index;
        const old_len = self.buffer.len;

        if (required <= self.buffer.len) {
            return;
        }

        // Duobligi la bufron gxis suficxos da spaco (eksponenta kresko)
        var new_length = self.buffer.len;
        while (required > new_length) {
            new_length *= 2;
        }

        // Realoki kaj kopii la datumojn (Zig uzas `realloc` aux `realloc_exact` se povas)
        // Ni uzos `realloc`, pli sekura kaj kutima en `std.mem.Allocator`
        self.buffer = self.allocator.realloc(self.buffer, new_length) catch return ProtobufError.AllocationFailed;

        // Movi la ekzistantajn datumojn al la fino de la nova bufro, liberigante spacon komence
        const write_offset = new_length - old_len;

        // Movi la skribitan slice malantauxen
        // La datumoj movotaj estas `self.buffer[self.write_index..self.buffer.len]`, do la slice `data()` nuna
        // Ni movas ilin al `self.buffer[self.write_index + write_offset ..]`
        // mem.copy(u8, self.buffer[self.write_index + write_offset .. new_length], self.buffer[self.write_index..self.buffer.len]);
        @memcpy(self.buffer[old_index + write_offset .. new_length], self.buffer[old_index..old_len]);

        // Gxustigi la skriban indekson
        self.write_index = old_index + write_offset;
    }

    // `encode_varint` - redonas la nombron de skribitaj bitokoj.
    pub fn encodeVarint(self: *EncodeBuffer, value: u64) ProtobufError!usize {
        // Kalkulas, kiom da oktetoj necesas
        var n_octets: usize = 0;
        var temp_v = value;

        if (temp_v == 0) {
            n_octets = 1;
        } else {
            // La plej longa varint havas 10 bitokojn por u64
            while (temp_v != 0) : (temp_v >>= 7) {
                n_octets += 1;
            }
        }

        // Certigas la spacon
        try self.allocate(n_octets);
        self.write_index -= n_octets;

        temp_v = value;
        var i: usize = 0;

        // Skribas la bitokojn, inverse al la kalkulo de varint
        while (true) {
            if (i == n_octets - 1) {
                // Lasta bitoko (sen la bito MSB je 1)
                self.buffer[self.write_index + i] = @intCast(temp_v & 0x7F);
                break;
            }

            // Bitoko kun la bito MSB je 1
            self.buffer[self.write_index + i] = 0x80 | @as(u8, @intCast(temp_v & 0x7F));
            temp_v >>= 7;
            i += 1;
        }

        // La algoritmo de la origina kodo skribas la varint inverse,
        // plenigante de dekstre maldekstren (la bufro mem estas inversigita).
        // Ni adaptos la buklon al la origina logiko ("backward write").

        // (Noto: la Vala-originalo skribis de dekstre maldekstren en la bufro
        //  kiun jam 'sxovis' maldekstren `write_index -= n_octets;`.
        //  La antauxa realigo jam faras la samen, nur iteraciante de `i=0` gxis `n_octets-1`).

        return n_octets;
    }

    // Helpa funkcio por skribi N bitokojn
    fn writeBytes(self: *EncodeBuffer, dataN: []const u8) ProtobufError!usize {
        const count = dataN.len;
        try self.allocate(count);
        self.write_index -= count;
        // mem.copy(u8, self.buffer[self.write_index .. self.write_index + count], dataN);
        @memcpy(self.buffer[self.write_index .. self.write_index + count], dataN);
        return count;
    }

    // `encode_fixed64`
    pub fn encodeFixed64(self: *EncodeBuffer, value: u64) ProtobufError!usize {
        try self.allocate(8);
        self.write_index -= 8;

        // `std.mem.writeInt` donas gustan endianness (little-endian en Protobuf)
        mem.writeInt(u64, @ptrCast(self.buffer[self.write_index .. self.write_index + 8]), value, .little);

        return 8;
    }

    // `encode_fixed32`
    pub fn encodeFixed32(self: *EncodeBuffer, value: u32) ProtobufError!usize {
        try self.allocate(4);
        self.write_index -= 4;

        mem.writeInt(u32, @ptrCast(self.buffer[self.write_index .. self.write_index + 4]), value, .little);

        return 4;
    }

    // `encode_double`
    pub fn encodeDouble(self: *EncodeBuffer, value: f64) ProtobufError!usize {
        return self.encodeFixed64(@bitCast(value));
    }

    // `encode_float`
    pub fn encodeFloat(self: *EncodeBuffer, value: f32) ProtobufError!usize {
        return self.encodeFixed32(@bitCast(value));
    }

    // `encode_int64` (varint)
    pub fn encodeInt64(self: *EncodeBuffer, value: i64) ProtobufError!usize {
        return self.encodeVarint(@bitCast(value));
    }

    // `encode_uint64` (varint)
    pub fn encodeUint64(self: *EncodeBuffer, value: u64) ProtobufError!usize {
        return self.encodeVarint(value);
    }

    // `encode_int32` (varint)
    pub fn encodeInt32(self: *EncodeBuffer, value: i32) ProtobufError!usize {
        return self.encodeInt64(@intCast(value));
    }

    // `encode_uint32` (varint)
    pub fn encodeUint32(self: *EncodeBuffer, value: u32) ProtobufError!usize {
        return self.encodeVarint(@intCast(value));
    }

    // `encode_bool` (varint)
    pub fn encodeBool(self: *EncodeBuffer, value: bool) ProtobufError!usize {
        return self.encodeVarint(if (value) 1 else 0);
    }

    // `encode_string` - supozas, ke la string estas bitoka slice (`[]const u8`)
    pub fn encodeString(self: *EncodeBuffer, value: []const u8) ProtobufError!usize {
        return self.writeBytes(value);
    }

    // `encode_bytes`
    pub fn encodeBytes(self: *EncodeBuffer, value: []const u8) ProtobufError!usize {
        return self.writeBytes(value);
    }

    // `encode_sfixed32`
    pub fn encodeSfixed32(self: *EncodeBuffer, value: i32) ProtobufError!usize {
        return self.encodeFixed32(@bitCast(value));
    }

    // `encode_sfixed64`
    pub fn encodeSfixed64(self: *EncodeBuffer, value: i64) ProtobufError!usize {
        return self.encodeFixed64(@bitCast(value));
    }

    // `encode_sint32` (ZigZag)
    pub fn encodeSint32(self: *EncodeBuffer, value: i32) ProtobufError!usize {
        // ZigZag encoding: (value << 1) ^ (value >> 31)
        const encoded = (@as(u32, @intCast(value)) << 1) ^ (@as(u32, @intCast(value)) >> 31);
        return self.encodeVarint(encoded);
    }

    // `encode_sint64` (ZigZag)
    pub fn encodeSint64(self: *EncodeBuffer, value: i64) ProtobufError!usize {
        // ZigZag encoding: (value << 1) ^ (value >> 63)
        const encoded = (@as(u64, @intCast(value)) << 1) ^ (@as(u64, @intCast(value)) >> 63);
        return self.encodeVarint(encoded);
    }
};
