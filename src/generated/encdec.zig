const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const mem = std.mem;
const assert = std.debug.assert;

// Definición de errores generales (se puede expandir)
const ProtobufError = error{
    EndOfBuffer,
    UnknownWireType,
    AllocationFailed,
    WriteError,
};

// ----------------------------------------
// ## DecodeBuffer
// ----------------------------------------

// Equivalente a 'public class DecodeBuffer'
pub const DecodeBuffer = struct {
    // `buffer`: array sin dueño (unowned) del buffer a decodificar.
    // Usamos `[]const u8` porque no modificaremos el buffer de origen.
    buffer: []const u8,
    // `internal_buffer`: Opcional `?[]u8` para cuando la struct es dueña del buffer.
    // El allocator se usaría para liberar esto.
    internal_buffer: ?[]u8,
    allocator: Allocator, // Necesario para `internal_buffer`, `decode_string`, `decode_bytes`
    read_index: usize,
    @"error": bool, // Mantenemos el campo de error, aunque Zig prefiere el manejo de errores explícito en las funciones

    // Constructor `public DecodeBuffer (uint8[] buffer, size_t offset = 0, ssize_t length = -1)`
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

    // Constructor `public DecodeBuffer.sized (size_t size)`
    pub fn initSized(allocator: Allocator, size: usize) ProtobufError!DecodeBuffer {
        const internal_buffer = allocator.alloc(u8, size) catch return ProtobufError.AllocationFailed;

        const buffer = internal_buffer; // El slice de trabajo es el buffer interno completo

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

    // Liberación de memoria si se usó `initSized` (no en el original, pero necesario en Zig)
    pub fn deinit(self: *DecodeBuffer) void {
        if (self.internal_buffer) |buf| {
            self.allocator.free(buf);
        }
    }

    // `decode_varint`: Devuelve un `error union` para un mejor manejo de errores.
    pub fn decodeVarint(self: *DecodeBuffer) ProtobufError!u64 {
        var value: u64 = 0;
        var shift: u8 = 0; // Usar u3 para 7-bit shifts

        while (self.read_index < self.buffer.len) {
            const byte = @as(u64, self.buffer[self.read_index]);
            self.read_index += 1;

            // `|u64` para asegurarse que el bitwise OR es con u64
            value |= (byte & 0x7F) << @truncate(shift);

            if ((byte & 0x80) == 0) {
                return value;
            }

            shift += 7;
            if (shift >= 64) {
                // Si llegamos aquí, el varint es demasiado largo para un u64
                self.@"error" = true;
                return ProtobufError.EndOfBuffer;
            }
        }

        // Si salimos del bucle, es porque se acabó el buffer antes de terminar el varint
        self.@"error" = true;
        return ProtobufError.EndOfBuffer;
    }

    // Helper para leer N bytes
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

    // `decode_double` - Se utiliza `@floatCast` en lugar de punteros.
    pub fn decodeDouble(self: *DecodeBuffer) ProtobufError!f64 {
        const v = try self.decodeFixed64();
        // reinterpretación de bits: u64 a f64
        return @bitCast(v);
    }

    // `decode_float`
    pub fn decodeFloat(self: *DecodeBuffer) ProtobufError!f32 {
        const v = try self.decodeFixed32();
        // reinterpretación de bits: u32 a f32
        return @bitCast(v);
    }

    // `decode_int64` (varint)
    pub fn decodeInt64(self: *DecodeBuffer) ProtobufError!i64 {
        const v = try self.decodeVarint();
        // reinterpretación de bits: u64 a i64
        return @bitCast(v);
    }

    // `decode_uint64` (varint)
    pub fn decodeUint64(self: *DecodeBuffer) ProtobufError!u64 {
        return self.decodeVarint();
    }

    // `decode_int32` (varint)
    pub fn decodeInt32(self: *DecodeBuffer) ProtobufError!i32 {
        // En Zig, el casting truncará/extenderá automáticamente.
        return @intCast(try self.decodeInt64());
    }

    // `decode_uint32` (varint)
    pub fn decodeUint32(self: *DecodeBuffer) ProtobufError!u32 {
        // En Zig, el casting truncará/extenderá automáticamente.
        return @intCast(try self.decodeVarint());
    }

    // `decode_bool` (varint)
    pub fn decodeBool(self: *DecodeBuffer) ProtobufError!bool {
        return (try self.decodeVarint()) != 0;
    }

    // `decode_string` - Requiere el `allocator` para crear la string.
    pub fn decodeString(self: *DecodeBuffer, length: usize) ProtobufError![]u8 {
        const data = try self.readBytes(length);

        // Copia el slice de bytes a una nueva memoria como un slice de bytes (que sirve como string UTF-8)
        // const str_slice = try self.allocator.dupe(u8, data);
        const str_slice = self.allocator.dupe(u8, data) catch return error.AllocationFailed;

        // **Nota**: En la fuente original, se asume que el byte array es una string válida.
        // Zig prefiere arrays de bytes (`[]u8`) para strings mutables o sin NULL-terminador.
        return str_slice;
    }

    // `decode_bytes` - Requiere el `allocator` para crear el `ByteArray` (slice de bytes).
    pub fn decodeBytes(self: *DecodeBuffer, length: usize) ProtobufError![]u8 {
        const data = try self.readBytes(length);

        // Crea y retorna una copia de los bytes leídos, con memoria gestionada por el allocator
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

    // `decode_unknown_field` - Requiere el `allocator` para `data` y para `UnknownField` (si se estuviera alocando).
    // Aquí, alocamos solo `data` internamente.
    // pub fn decodeUnknownField(self: *DecodeBuffer, key: u64) ProtobufError!UnknownField {
    //     var value = UnknownField{
    //         .key = key,
    //         .varint = 0,
    //         .data = &[_]u8{},
    //     };
    //     const wire_type: u3 = @intCast(key & 0x7);

    //     switch (wire_type) {
    //         0 => { // varint
    //             value.varint = try self.decodeVarint();
    //         },
    //         1 => { // 64-bit
    //             value.data = try self.decodeBytes(8);
    //         },
    //         2 => { // length-delimited
    //             const length = try self.decodeVarint();
    //             // Ojo: Protobuf usa `u64` para el length, pero `usize` es más seguro para el tamaño del array en Zig.
    //             if (length > std.math.maxInt(usize)) {
    //                 self.@"error" = true;
    //                 return ProtobufError.EndOfBuffer; // Length too big
    //             }
    //             value.data = try self.decodeBytes(@intCast(length));
    //         },
    //         5 => { // 32-bit
    //             value.data = try self.decodeBytes(4);
    //         },
    //         else => {
    //             std.log.err("Unknown wire type {}", .{wire_type});
    //             self.@"error" = true;
    //             return ProtobufError.UnknownWireType;
    //         },
    //     }

    //     return value;
    // }
};

// ----------------------------------------
// ## EncodeBuffer
// ----------------------------------------

// Equivalente a 'public class EncodeBuffer'
pub const EncodeBuffer = struct {
    allocator: Allocator, // Necesario para `allocate`
    buffer: []u8, // Buffer interno (siempre propiedad de la struct)
    write_index: usize,

    // Constructor `public EncodeBuffer (size_t size = 1024)`
    pub fn init(allocator: Allocator, size: usize) ProtobufError!EncodeBuffer {
        const init_size = if (size == 0) 1 else size;
        const buf = allocator.alloc(u8, init_size) catch return ProtobufError.AllocationFailed;

        var self = EncodeBuffer{
            .allocator = allocator,
            .buffer = buf,
            .write_index = buf.len,
        };
        // `reset()` en el original establece `write_index = buffer.length;`
        self.reset();
        return self;
    }

    // Liberación de memoria (necesario en Zig)
    pub fn deinit(self: *EncodeBuffer) void {
        self.allocator.free(self.buffer);
    }

    // `reset`
    pub fn reset(self: *EncodeBuffer) void {
        // En el original, el índice de escritura comienza al final del buffer
        self.write_index = self.buffer.len;
    }

    // `data` (Propiedad 'unowned uint8[] data')
    // Retorna el slice de bytes ya escritos (que se encuentran al final del buffer en esta implementación)
    pub fn data(self: *EncodeBuffer) []const u8 {
        // Como el `write_index` retrocede, los datos a devolver son desde `write_index` hasta el final
        return self.buffer[self.write_index..];
    }

    // `allocate` (private void allocate)
    fn allocate(self: *EncodeBuffer, size: usize) ProtobufError!void {
        const written_len = self.buffer.len - self.write_index;
        const required = size + written_len;

        if (required <= self.buffer.len) {
            return;
        }

        // Doblar el buffer hasta que haya espacio suficiente (crecimiento exponencial)
        var new_length = self.buffer.len;
        while (required > new_length) {
            new_length *= 2;
        }

        // Reallocar y copiar los datos (Zig usa `realloc` o `realloc_exact` si el allocator lo soporta)
        // Usaremos `realloc` que es más seguro y común en `std.mem.Allocator`
        self.buffer = self.allocator.realloc(self.buffer, new_length) catch return ProtobufError.AllocationFailed;

        // Mover los datos existentes al final del nuevo buffer para liberar espacio al principio
        const write_offset = new_length - self.buffer.len;

        // Mover el slice escrito hacia atrás
        // Los datos a mover son `self.buffer[self.write_index..self.buffer.len]`, es decir, el slice `data()` actual
        // Lo movemos a `self.buffer[self.write_index + write_offset ..]`
        // mem.copy(u8, self.buffer[self.write_index + write_offset .. new_length], self.buffer[self.write_index..self.buffer.len]);
        @memcpy(self.buffer[self.write_index + write_offset .. new_length], self.buffer[self.write_index..self.buffer.len]);

        // Ajustar el índice de escritura
        self.write_index += write_offset;
    }

    // `encode_varint` - Retorna el número de bytes escritos.
    pub fn encodeVarint(self: *EncodeBuffer, value: u64) ProtobufError!usize {
        // Calcula cuántos octetos se necesitan
        var n_octets: usize = 0;
        var temp_v = value;

        if (temp_v == 0) {
            n_octets = 1;
        } else {
            // El varint más largo tiene 10 bytes para un u64
            while (temp_v != 0) : (temp_v >>= 7) {
                n_octets += 1;
            }
        }

        // Asegura el espacio
        try self.allocate(n_octets);
        self.write_index -= n_octets;

        temp_v = value;
        var i: usize = 0;

        // Escribe los bytes, de manera inversa al cálculo de varint
        while (true) {
            if (i == n_octets - 1) {
                // Último byte (no tiene el bit MSB a 1)
                self.buffer[self.write_index + i] = @intCast(temp_v & 0x7F);
                break;
            }

            // Byte con el bit MSB a 1
            self.buffer[self.write_index + i] = 0x80 | @as(u8, @intCast(temp_v & 0x7F));
            temp_v >>= 7;
            i += 1;
        }

        // El algoritmo del código original escribe el varint de forma inversa,
        // llenando de derecha a izquierda en el buffer (que a su vez está invertido).
        // Adaptaremos el bucle para coincidir con la lógica original, que era "backward write".

        // (Nota: El original de Vala escribía de derecha a izquierda en el buffer
        //  que ya había sido 'desplazado' a la izquierda por `write_index -= n_octets;`.
        //  La implementación anterior ya hace lo mismo, solo que iterando de `i=0` a `n_octets-1`).

        return n_octets;
    }

    // Helper para escribir N bytes
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

        // Uso de `std.mem.writeInt` para manejo correcto de endianness (pequeño-endian en Protobuf)
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

    // `encode_string` - Asume que la string es un slice de bytes (`[]const u8`)
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
