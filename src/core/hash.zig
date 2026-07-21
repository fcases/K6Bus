// hash.zig
const std = @import("std");

pub const HASH_SEED: u64 = 0;

pub fn hashChannel(
    channel_name: []const u8,
) u64 {

    return std.hash.XxHash3.hash(
        HASH_SEED,
        channel_name,
    );
}

pub fn hashMsgType(
    domain_id: u32,
    type_name: []const u8,
) u64 {

    var h = std.hash.XxHash3.init(
        HASH_SEED,
    );

    h.update(domain_id);
    h.update(".");
    h.update(type_name);

    return h.final();
}