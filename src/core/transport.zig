// transport.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;
const Logger = @import("logger.zig").Logger;
const Utils = @import("msg_utils.zig");

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Packet = @import("../generated/Packet.zig").k6bus.pkgpb.Packet;
const Config = @import("../generated/Config.zig").k6bus.config;
const BinaraFormato = @import("../generated/Packet.zig").BinaraFormato;

pub const SendBytesFn = *const fn (owner: *anyopaque, wire_bytes: []const u8) bool;
pub const ReceiveLoopFn = *const fn (owner: *anyopaque) void;
pub const CloseFn = *const fn (owner: *anyopaque) void;

var logger: *Logger = undefined;

pub const TransportStats = struct {
    serialize_ns: u64 = 0,
    clone_ns: u64 = 0,
    free_ns: u64 = 0,
    encrypt_ns: u64 = 0,
    base64_ns: u64 = 0,
    send_ns: u64 = 0,
};

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
    close_fn: CloseFn,

    cross_connections: std.ArrayList(*Transport) = .empty,
    stats: TransportStats = .{},

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
        close_fn: CloseFn,
    ) !void {
        self.domain = domain;
        logger = &domain.logger;

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
        self.close_fn = close_fn;
        self.cross_connections = .empty;

        self.qm =
            try QueueMgr.create(domain, name, domain.dom_cfg.dispatch_mode orelse .IMMEDIATE, @intCast(domain.dom_cfg.dispatch_batch_time_ms orelse 0), self, dispatchMsgList, noOp);

        self.stats = .{};
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
        logger.info("{s} started.", .{self.qm.name}, @src());
    }

    pub fn stop(self: *Self) void {
        if (!self.running) return;

        self.running = false;
        self.qm.stop();
        logger.info("{s} stopped.", .{self.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.running = false;

        self.qm.close();

        if (self.rx_thread) |t| {
            t.join();
        }

        self.rx_thread = null;

        logger.info(
            "{s} perf clone={d:.2}ms free={d:.2}ms seri={d:.2}ms enc={d:.2}ms b64={d:.2}ms send={d:.2}ms",
            .{
                "LoopTransport",
                @as(f64, @floatFromInt(self.stats.clone_ns)) /
                    std.time.ns_per_ms,
                @as(f64, @floatFromInt(self.stats.free_ns)) /
                    std.time.ns_per_ms,
                @as(f64, @floatFromInt(self.stats.serialize_ns)) /
                    std.time.ns_per_ms,
                @as(f64, @floatFromInt(self.stats.encrypt_ns)) /
                    std.time.ns_per_ms,
                @as(f64, @floatFromInt(self.stats.base64_ns)) /
                    std.time.ns_per_ms,
                @as(f64, @floatFromInt(self.stats.send_ns)) /
                    std.time.ns_per_ms,
            },
            @src(),
        );
        logger.info("{s} closed.", .{self.name}, @src());
        self.domain.allocator.free(self.name);
    }

    pub fn closeOwner(self: *Self) void {
        self.domain.removeTransport(self);
        self.close();
        self.close_fn(self.owner);
    }

    fn receiveThread(self: *Self) void {
        self.receive_loop_fn(self.owner);
    }

    pub fn receiveBytes(self: *Self, wire_bytes: []const u8) !void {
        if (!self.domain.running) return error.DomainClosed;

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
        logger.info("{s} dispatched {d} messages", .{ self.qm.name, msg_list.len }, @src());
    }

    fn dispatchUpstream(self: *Self, msg_list: []const Msg) !void {
        if (!self.domain.running) {
            Utils.freeClonedMsgSlice(self.domain.allocator, @constCast(msg_list));
            return error.DomainClosed;
        }

        // 1) CrossConnector
        for (self.cross_connections.items) |other| {
            const cloned = try Utils.cloneMsgSlice(self.domain.allocator, msg_list);

            other.qm.enqueueMany(cloned) catch {
                Utils.freeClonedMsgSlice(self.domain.allocator, cloned);
                logger.warning("{s} failed to enqueue messages for cross-connection {s}", .{ self.qm.name, other.name }, @src());
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

        const t0 = std.time.nanoTimestamp();
        packet.messages =
            Utils.cloneMsgSlice(
                self.domain.allocator,
                msg_list,
            ) catch return;
        const t1 = std.time.nanoTimestamp();
        self.stats.clone_ns += @intCast(t1 - t0);
        // packet.messages = Utils.cloneMsgSlice(self.domain.allocator, msg_list) catch return;
        defer packet.deinit(self.domain.allocator);

        const t2 = std.time.nanoTimestamp();
        Utils.freeMsgsFromSlice(
            self.domain.allocator,
            @constCast(msg_list),
        );
        const t3 = std.time.nanoTimestamp();
        self.stats.free_ns += @intCast(t3 - t2);
        // Utils.freeMsgsFromSlice(self.domain.allocator, @constCast(msg_list));

        const t4 = std.time.nanoTimestamp();
        const red_bytes =
            packet.seriigiAlBin(
                self.domain.allocator,
                self.bf_protobuzg,
            ) catch return;
        const t5 = std.time.nanoTimestamp();
        self.stats.serialize_ns += @intCast(t5 - t4);
        // const red_bytes = packet.seriigiAlBin(self.domain.allocator, self.bf_protobuzg) catch return;
        defer self.domain.allocator.free(red_bytes);

        const t6 = std.time.nanoTimestamp();
        const black_bytes =
            self.domain.cipher.encrypt(
                self.domain.allocator,
                red_bytes,
            ) catch red_bytes;

        const t7 = std.time.nanoTimestamp();
        self.stats.encrypt_ns += @intCast(t7 - t6);
        // const black_bytes = self.domain.cipher.encrypt(self.domain.allocator, red_bytes) catch red_bytes;
        defer {
            if (black_bytes.ptr != red_bytes.ptr)
                self.domain.allocator.free(black_bytes);
        }

        const t8 = std.time.nanoTimestamp();
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

        const t9 = std.time.nanoTimestamp();
        self.stats.base64_ns += @intCast(t9 - t8);
        // const wire_bytes =
        //     switch (self.encoding) {
        //         .RAW => black_bytes,

        //         .BASE64 => blk: {
        //             const enc = std.base64.standard.Encoder;
        //             const len = enc.calcSize(black_bytes.len);
        //             const tmp = self.domain.allocator.alloc(u8, len) catch return;
        //             _ = enc.encode(tmp, black_bytes);
        //             break :blk tmp;
        //         },
        //     };
        defer {
            if (wire_bytes.ptr != black_bytes.ptr)
                self.domain.allocator.free(wire_bytes);
        }

        const t10 = std.time.nanoTimestamp();
        _ = self.send_bytes_fn(self.owner, wire_bytes);
        const t11 = std.time.nanoTimestamp();
        self.stats.send_ns += @intCast(t11 - t10);
        // _ = self.send_bytes_fn(self.owner, wire_bytes);
    }

    pub fn crossConnect(self: *Self, other: *Transport) !void {
        try self.cross_connections.append(other);
    }

    fn noOp(owner: *anyopaque) void {
        _ = owner;
    }
};
