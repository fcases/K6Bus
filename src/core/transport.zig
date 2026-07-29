// transport.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;
const Utils = @import("msg_utils.zig");

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Packet = @import("../generated/Packet.zig").k6bus.pkgpb.Packet;
const Config = @import("../generated/Config.zig").k6bus.config;
const BinaraFormato = @import("../generated/Packet.zig").BinaraFormato;

pub const SendBytesFn = *const fn (owner: *anyopaque, wire_bytes: []const u8) bool;
pub const ReceiveLoopFn = *const fn (owner: *anyopaque) void;

pub const Transport = struct {
    domain: *Domain,
    name: []const u8,
    kind: Config.TransportKind,

    binary_format: Config.BinaryFormat,
    bf_protobuzg: BinaraFormato = .BF_PROTOBUF,
    encoding: Config.Encoding,

    qm: QueueMgr,
    rx_thread: ?std.Thread = null,

    running: bool = false,
    owner: *anyopaque,

    send_bytes_fn: SendBytesFn,
    receive_loop_fn: ReceiveLoopFn,

    cross_connections: std.ArrayList(*Transport) = .empty,

    const Self = @This();

    pub fn init(
        self: *Self,
        domain: *Domain,
        name: []const u8,
        kind: Config.TransportKind,
        encoding: Config.Encoding,
        owner: *anyopaque,
        send_bytes_fn: SendBytesFn,
        receive_loop_fn: ReceiveLoopFn,
    ) !void {
        self.domain = domain;
        self.name = try domain.allocator.dupe(u8, name);
        self.kind = kind;

        self.binary_format = domain.dom_cfg.binary_format orelse .BF_PROTOBUF;
        self.bf_protobuzg = switch (self.binary_format) {
            .BF_PROTOBUF => .BF_PROTOBUF,
            .BF_ASN1_DER => .BF_ASN1_DER,
            .BF_OMG_CDR => .BF_OMG_CDR,
            else => return error.UnsupportedBinaryFormat,
        };

        self.encoding = encoding;
        self.owner = owner;

        self.send_bytes_fn = send_bytes_fn;
        self.receive_loop_fn = receive_loop_fn;

        self.cross_connections = .empty;

        self.qm =
            try QueueMgr.create(
                domain,
                name,
                domain.dom_cfg.dispatch_mode orelse .IMMEDIATE,
                @intCast(domain.dom_cfg.dispatch_batch_time_ms orelse 0),
                self,
                dispatchMsgList,
            );
    }

    pub fn start(self: *Self) !void {
        if (self.running) return;

        self.running = true;
        try self.qm.start();

        self.rx_thread =
            try std.Thread.spawn(
                .{},
                receiveThread,
                .{self},
            );
        self.domain.logger.info("{s} started.", .{self.qm.name}, @src());
    }

    pub fn stop(self: *Self) void {
        if (!self.running) return;

        self.running = false;
        self.qm.stop();
        self.domain.logger.info("{s} stopped.", .{self.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.running = false;

        self.qm.close();

        if (self.rx_thread) |t| {
            t.join();
        }

        self.rx_thread = null;

        self.domain.allocator.free(self.name);
        self.domain.logger.info("{s} closed.", .{self.qm.name}, @src());
    }

    fn receiveThread(self: *Self) void {
        self.receive_loop_fn(self.owner);
    }

    pub fn receiveBytes(self: *Self, wire_bytes: []const u8) !void {
        // 1) Decode
        const black_bytes =
            switch (self.encoding) {
                .RAW => wire_bytes,
                .BASE64 => blk: {
                    const dec = std.base64.standard.Decoder;
                    const len = try dec.calcSizeForSlice(wire_bytes);
                    const tmp = try self.domain.allocator.alloc(u8, len);

                    try dec.decode(tmp, wire_bytes);
                    break :blk tmp;
                },
            };

        defer {
            if (black_bytes.ptr != wire_bytes.ptr)
                self.domain.allocator.free(black_bytes);
        }

        // 2) Decrypt
        const red_bytes = try self.domain.cipher.decrypt(self.domain.allocator, black_bytes);
        defer {
            if (red_bytes.ptr != black_bytes.ptr)
                self.domain.allocator.free(red_bytes);
        }

        // 3) Packet
        var packet = try Packet.deseriigiElBin(self.domain.allocator, red_bytes, self.bf_protobuzg);
        defer packet.deinit(self.domain.allocator);

        // 4) MsgList
        const msg_list = try Utils.cloneMsgSlice(self.domain.allocator, packet.messages);

        // 6) Domain

        try self.dispatchUpstream(msg_list);
        self.domain.logger.info("{s} dispatched {d} messages", .{ self.qm.name, msg_list.len }, @src());
    }

    pub fn dispatchUpstream(self: *Self, msg_list: []const Msg) !void {
        // 1) CrossConnector
        for (self.cross_connections.items) |other| {
            const cloned = try Utils.cloneMsgSlice(self.domain.allocator, msg_list);

            other.qm.enqueueMany(cloned) catch {
                Utils.freeClonedMsgSlice(self.domain.allocator, cloned);
                self.domain.logger.warning("{s} failed to enqueue messages for cross-connection {s}", .{ self.qm.name, other.name }, @src());
                continue;
            };
            self.domain.allocator.free(cloned);
        }

        // 2) StreamQueueUP
        const cloned_up = try Utils.cloneMsgSlice(self.domain.allocator, msg_list);
        // errdefer Utils.freeClonedMsgSlice(self.domain.allocator, cloned_up);
        try self.domain.onMsgListReceived(cloned_up);
        self.domain.allocator.free(cloned_up);

        // 3) Original
        Utils.freeClonedMsgSlice(self.domain.allocator, @constCast(msg_list));
    }

    fn dispatchMsgList(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        var packet = Packet.initDefault(self.domain.allocator) catch return;
        // packet.messages = @constCast(msg_list);
        packet.messages = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch return;
        defer packet.deinit(self.domain.allocator);
        Utils.freeMsgsFromSlice(self.domain.allocator, @constCast(msg_list));

        const red_bytes = packet.seriigiAlBin(self.domain.allocator, self.bf_protobuzg) catch return;
        defer self.domain.allocator.free(red_bytes);

        const black_bytes = self.domain.cipher.encrypt(self.domain.allocator, red_bytes) catch red_bytes;
        defer {
            if (black_bytes.ptr != red_bytes.ptr)
                self.domain.allocator.free(black_bytes);
        }

        const wire_bytes =
            switch (self.encoding) {
                .RAW => black_bytes,

                .BASE64 => blk: {
                    const enc = std.base64.standard.Encoder;
                    const len = enc.calcSize(black_bytes.len);
                    const tmp = self.domain.allocator.alloc(u8, len) catch return;
                    _ = enc.encode(tmp, black_bytes);
                    break :blk tmp;
                },
            };

        defer {
            if (wire_bytes.ptr != black_bytes.ptr)
                self.domain.allocator.free(wire_bytes);
        }

        _ = self.sendBytes(wire_bytes);
    }

    pub fn sendBytes(self: *Self, wire_bytes: []const u8) bool {
        return self.send_bytes_fn(self.owner, wire_bytes);
    }

    pub fn crossConnect(self: *Self, other: *Transport) !void {
        try self.cross_connections.append(other);

        // Evita bucles infinitos.
        // self.receive_own_msgs = false;
    }
};
