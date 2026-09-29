// msg_utils.zig
//
// Ownership utilities for k6bus.Msg (types.zig).
//
// Responsibilities:
//
// - Deep clone of Msg.
// - Release of Msg dynamic memory.
// - Keep all the Msg ownership logic in a single place.
//
// Note:
// Msg itself is passed by value.
// These functions only manage the dynamic memory
// associated with its slices.
//

const std = @import("std");
const all = std.mem;

// const Msg = @import("msg.zig").Msg;
const Msg = @import("../generated/types.zig").k6bus.Msg;

/// Creates a deep copy of a message.
///
/// The following are duplicated:
/// - channels
/// - payLoad
///
/// Copied by value:
/// - msgType
pub fn cloneMsg(allocator: all.Allocator, src: *const Msg) !Msg {
    const cloned_channels =
        try allocator.dupe(u64, src.channels);

    errdefer allocator.free(cloned_channels);

    const cloned_payload =
        try allocator.dupe(u8, src.payLoad);

    errdefer allocator.free(cloned_payload);

    return Msg{
        .channels = cloned_channels,
        .msgType = src.msgType,
        .payLoad = cloned_payload,
    };
}

/// Releases the dynamic memory associated with a Msg.
///
/// It does not free the Msg itself.
///
/// Typical usage:
///
/// var msg: Msg = ...;
/// msg_utils.free(allocator, &msg);
///
pub fn freeMsg(allocator: all.Allocator, msg: *Msg) void {
    // allocator.free(msg.channels);
    // allocator.free(msg.payLoad);
    msg.deinit(allocator);

    msg.channels = &.{};
    msg.payLoad = &.{};
}

/// Releases every message of a list.
///
/// It does not destroy the ArrayList.
/// It only releases the internal resources of each Msg.
pub fn freeMsgsFromSlice(allocator: all.Allocator, msgs: []Msg) void {
    for (msgs) |*msg| {
        freeMsg(allocator, msg);
    }
}

/// Clones a complete list of messages.
///
/// Each resulting Msg owns its own
/// channels and payload.
pub fn cloneMsgSlice(allocator: all.Allocator, msgs: []const Msg) ![]Msg {
    const result =
        try allocator.alloc(Msg, msgs.len);

    var cloned_count: usize = 0;
    errdefer {
        freeMsgsFromSlice(allocator, result[0..cloned_count]);
        allocator.free(result);
    }

    for (msgs, 0..) |msg, i| {
        result[i] = try cloneMsg(allocator, &msg);
        cloned_count += 1;
    }

    return result;
}

/// Releases a list created through cloneMsgSlice().
///
/// Releases:
/// - payloads
/// - channels
/// - Msg array
pub fn freeClonedMsgSlice(allocator: all.Allocator, msgs: []Msg) void {
    freeMsgsFromSlice(allocator, msgs);

    allocator.free(msgs);
}
