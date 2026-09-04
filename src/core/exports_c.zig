// ============================================================================
// exports_c.zig
//
// C-compatible API for K6Bus.
//
// This file exposes a small opaque C ABI over the Zig internals.
// C code must not know about Domain, Msg, PacketProcessor, QueueMgr, etc.
//
// First minimal API:
//
//   - k6b_domain_create()
//   - k6b_domain_close()
//   - k6b_domain_send_raw()
//
// ============================================================================

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const Msg = @import("../generated/types.zig").k6bus.Msg;
const Hash = @import("hash.zig").Hash;

// ============================================================================
// C result codes
// ============================================================================

pub const K6B_OK: c_int = 0;
pub const K6B_ERR_NULL: c_int = -1;
pub const K6B_ERR_ALLOC: c_int = -2;
pub const K6B_ERR_DOMAIN: c_int = -3;
pub const K6B_ERR_SEND: c_int = -4;
pub const K6B_ERR_INVALID_ARG: c_int = -5;

// ============================================================================
// Opaque C handle
// ============================================================================
//
// This is the real object behind K6B_Domain* in C.
//
// The C side will only see:
//
//     typedef struct K6B_Domain K6B_Domain;
//
// Internally, the pointer is actually *C_Domain.
//
// ============================================================================

const C_Domain = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .thread_safe = true,
    }),

    domain: *Domain,
};

// ============================================================================
// Helpers
// ============================================================================

fn rawMsgType(domain_id: u32) u64 {
    return Hash.hashMsgType(domain_id, "k6bus.raw");
}

fn sliceFromCBytes(ptr: [*]const u8, len: usize) []const u8 {
    return ptr[0..len];
}

// ============================================================================
// C API
// ============================================================================

export fn k6b_domain_create(domain_id: u32) ?*C_Domain {
    const wrapper =
        std.heap.c_allocator.create(C_Domain) catch return null;

    wrapper.* = .{
        .gpa = .{},
        .domain = undefined,
    };

    const allocator =
        wrapper.gpa.allocator();

    wrapper.domain =
        Domain.create(
            allocator,
            domain_id,
        ) catch {
            _ = wrapper.gpa.deinit();
            std.heap.c_allocator.destroy(wrapper);
            return null;
        };

    return wrapper;
}

export fn k6b_domain_close(handle: ?*C_Domain) void {
    const wrapper = handle orelse return;

    wrapper.domain.close();

    _ = wrapper.gpa.deinit();

    std.heap.c_allocator.destroy(wrapper);
}

export fn k6b_domain_send_raw(
    handle: ?*C_Domain,
    channel_c: ?[*:0]const u8,
    data_ptr: ?[*]const u8,
    data_len: usize,
) c_int {
    const wrapper = handle orelse return K6B_ERR_NULL;

    const channel_z = channel_c orelse return K6B_ERR_INVALID_ARG;

    const data_z = data_ptr orelse return K6B_ERR_INVALID_ARG;

    if (data_len == 0) return K6B_ERR_INVALID_ARG;

    const domain = wrapper.domain;

    const allocator = domain.allocator;

    const channel = std.mem.span(channel_z);

    const payload =
        allocator.dupe(
            u8,
            sliceFromCBytes(
                data_z,
                data_len,
            ),
        ) catch return K6B_ERR_ALLOC;
    errdefer allocator.free(payload);

    const channels =
        allocator.alloc(
            u64,
            1,
        ) catch return K6B_ERR_ALLOC;
    errdefer allocator.free(channels);

    channels[0] = Hash.hashChannel(channel);

    const msg = Msg{
        .channels = channels,
        .msgType = rawMsgType(domain.id),
        .payLoad = payload,
    };

    domain.sendMsg(msg) catch {
        allocator.free(payload);
        allocator.free(channels);
        return K6B_ERR_SEND;
    };

    return K6B_OK;
}
