const std = @import("std");
const Config = @import("../generated/Config.zig").k6bus.config.ConfigDef;
const EncodingKind = Config.EncodingDef;

pub const Encoding = struct {
    kind: EncodingKind = .RAW,
    pub fn raw() Encoding {
        return .{ .kind = .RAW };
    }
    pub fn base64() Encoding {
        return .{ .kind = .BASE64 };
    }
    pub fn encode(self: Encoding, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        return switch (self.kind) {
            .RAW => try allocator.dupe(u8, input),
            .BASE64 => blk: {
                const e = std.base64.standard.Encoder;
                const out = try allocator.alloc(u8, e.calcSize(input.len));
                _ = e.encode(out, input);
                break :blk out;
            },
        };
    }
    pub fn decode(self: Encoding, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        return switch (self.kind) {
            .RAW => try allocator.dupe(u8, input),
            .BASE64 => blk: {
                const d = std.base64.standard.Decoder;
                const out = try allocator.alloc(u8, try d.calcSizeForSlice(input));
                try d.decode(out, input);
                break :blk out;
            },
        };
    }
};
