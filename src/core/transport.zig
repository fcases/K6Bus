// transport.zig

const std = @import("std");

const Domain = @import("domain.zig").Domain;
const QueueMgr = @import("queue_mgr.zig").QueueMgr;

const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;
const Packet = @import("../generated/Packet.zig").k6bus.pkgpb.Packet;
const Config = @import("../generated/Config.zig").k6bus.config;

pub const SendBytesFn = *const fn (owner: *anyopaque, wire_bytes: []const u8) bool;
pub const ReceiveLoopFn = *const fn (owner: *anyopaque) void;

pub const Transport = struct {
    domain: *Domain,
    name: []const u8,

    receive_own_msgs: bool,
    encoding: Config.EncodingDef,

    qm: QueueMgr,
    rx_thread: ?std.Thread = null,

    running: bool = false,
    owner: *anyopaque,

    send_bytes_fn: SendBytesFn,
    receive_loop_fn: ReceiveLoopFn,

    cross_connections: std.ArrayList(*Transport),

    const Self = @This();

    pub fn init(
        self: *Self,
        domain: *Domain,
        name: []const u8,
        receive_own_msgs: bool,
        encoding: Config.EncodingDef,
        owner: *anyopaque,
        send_bytes_fn: SendBytesFn,
        receive_loop_fn: ReceiveLoopFn,
    ) !void {
        self.domain = domain;
        self.name = try domain.allocator.dupe(u8, name);

        self.receive_own_msgs = receive_own_msgs;
        self.encoding = encoding;
        self.owner = owner;

        self.send_bytes_fn = send_bytes_fn;
        self.receive_loop_fn = receive_loop_fn;

        self.qm =
            try QueueMgr.create(
                domain,
                name,
                domain.dom_cfg.DispatchMode orelse .IMMEDIATE,
                @intCast(domain.dom_cfg.DispatchBatchTimeMs orelse 0),
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
    }

    pub fn pause(self: *Self) void {
        if (!self.running) return;

        self.running = false;
        self.qm.pause();
    }

    pub fn close(self: *Self) void {
        self.running = false;

        self.qm.close();

        if (self.rx_thread) |t| {
            t.join();
        }

        self.rx_thread = null;

        self.domain.allocator.free(self.name);
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
        var packet = try Packet.deseriigiElBin(self.domain.allocator, red_bytes, self.domain.dom_cfg.BinaryFormat);
        defer packet.liberigiMemoron(self.domain.allocator);

        // 4) MsgList
        const msg_list = packet.messages;

        // 6) Domain
        try self.dispatchUpstream(msg_list);
    }

    pub fn dispatchUpstream(self: *Self, msg_list: []const Msg) void {
        // 1) CrossConnector
        for (self.cross_connections.items) |other| {
            _ = other.qm.enqueueMany(msg_list);
        }

        // 2) Subscribers ediante domain y streamqueue up
        self.domain.onMsgListReceived(msg_list) catch {};
    }

    fn dispatchMsgList(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        var packet = Packet.initDefault(self.domain.allocator) catch return;
        // defer packet.liberigiMemoron(self.domain.allocator); Para cuando haya LiberiMemoron en Packet.
        packet.messages = self.domain.allocator.dupe(Msg, msg_list) catch return;

        const red_bytes = packet.seriigiAlBin(self.domain.allocator, self.domain.dom_cfg.BinaryFormat) catch return;
        defer self.domain.allocator.free(red_bytes);

        const black_bytes = try self.domain.cipher.encrypt(self.domain.allocator, red_bytes);
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
        self.receive_own_msgs = false;
    }
};
