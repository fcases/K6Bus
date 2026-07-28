const std = @import("std");

const k6bus = @import("k6bus");
const BinaryFormat = k6bus.Config.BinaryFormat;

const EstacionFile = @import("Estacion.zig");
pub const Estacion = EstacionFile.demo1.Estacion;
const BinaraFormato = EstacionFile.BinaraFormato;

// ---------------------------------------------------------
// Callback tipado
// ---------------------------------------------------------

pub const EstacionCallback =
    *const fn (channel_name: []const u8, estacion: *const Estacion) void;

// ---------------------------------------------------------
// Publisher
// ---------------------------------------------------------

pub const EstacionPublisher = struct {
    domain: *k6bus.Domain,
    msgType: u64,

    const Self = @This();

    pub fn create(domain: *k6bus.Domain) !Self {
        var self: Self = undefined;

        self.domain = domain;
        self.msgType = k6bus.Hash.hashMsgType(domain.id, @typeName(Estacion));

        return self;
    }

    pub fn publish(self: *Self, channel_name: []const u8, estacion: *const Estacion) !bool {
        const channels = [_][]const u8{channel_name};
        return self.publishToChannels(&channels, estacion);
    }

    pub fn publishToChannels(self: *Self, channel_names: []const []const u8, estacion: *const Estacion) !bool {
        const payload =
            try estacion.seriigiAlBin(
                self.domain.allocator,
                transformBinF2BinF(self.domain.dom_cfg.binary_format orelse .BF_PROTOBUF),
            );
        // defer self.domain.allocator.free(payload);

        var channel_hashes =
            self.domain.allocator.alloc(u64, channel_names.len) catch return false;
        // defer self.domain.allocator.free(channel_hashes);

        for (channel_names, 0..) |channel_name, i| {
            channel_hashes[i] = k6bus.Hash.hashChannel(channel_name);
        }

        const msg = k6bus.Msg{
            .channels = channel_hashes,
            .msgType = self.msgType,
            .payLoad = payload,
        };

        try self.domain.sendMsg(msg);
        return true;
    }
};

// ---------------------------------------------------------
// Subscriber
// ---------------------------------------------------------

pub const EstacionSubscriber = struct {
    domain: *k6bus.Domain,
    qm: k6bus.QueueMgr,
    callback: EstacionCallback,

    channel_name: []const u8,
    channel: u64,
    msgType: u64,
    bf_protobuzg: BinaraFormato = .BF_PROTOBUF,

    const Self = @This();

    pub fn create(
        domain: *k6bus.Domain,
        channel_name: []const u8,
        callback: EstacionCallback,
    ) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        try self.init(domain, channel_name, callback);

        return self;
    }

    fn init(
        self: *Self,
        domain: *k6bus.Domain,
        channel_name: []const u8,
        callback: EstacionCallback,
    ) !void {
        self.domain = domain;
        self.callback = callback;

        self.channel_name = try domain.allocator.dupe(u8, channel_name);
        self.channel = k6bus.Hash.hashChannel(channel_name);
        self.msgType = k6bus.Hash.hashMsgType(domain.id, @typeName(Estacion));

        self.bf_protobuzg = transformBinF2BinF(domain.dom_cfg.binary_format orelse .BF_PROTOBUF);

        const tid = std.Thread.getCurrentId();
        const nombre = try std.fmt.allocPrint(
            domain.allocator,
            "EstacionSubscriber_{d}",
            .{tid},
        );
        defer domain.allocator.free(nombre);

        self.qm =
            try k6bus.QueueMgr.create(
                domain,
                nombre,
                domain.dom_cfg.dispatch_mode orelse .IMMEDIATE,
                @intCast(domain.dom_cfg.dispatch_batch_time_ms orelse 0),
                self,
                dispatchMsg,
            );

        try domain.registerSubscriber(self.channel, &self.qm);

        if (domain.dom_cfg.start_at_init orelse true) {
            try self.qm.start();
        }
    }

    fn dispatchMsg(owner: *anyopaque, msg_list: []const k6bus.Msg) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        for (msg_list) |msg| {
            if (msg.msgType != self.msgType) continue;

            var estacion =
                Estacion.deseriigiElBin(
                    self.domain.allocator,
                    msg.payLoad,
                    self.bf_protobuzg,
                ) catch continue;
            // defer estacion.liberigiMemoron(self.domain.allocator);
            defer estacion.deinit(self.domain.allocator);

            self.callback(self.channel_name, &estacion);
        }
    }

    pub fn start(self: *Self) !void {
        try self.qm.start();
    }

    pub fn pause(self: *Self) void {
        self.qm.pause();
    }

    pub fn close(self: *Self) void {
        self.qm.close();

        self.domain.allocator.free(
            self.channel_name,
        );
    }
};

// ---------------------------------------------------------
// Helpers cómodos (opcional)
// ---------------------------------------------------------

pub fn newEstacionPublisher(
    domain: *k6bus.Domain,
) !EstacionPublisher {
    return try EstacionPublisher.create(domain);
}

pub fn newEstacionSubscriber(
    domain: *k6bus.Domain,
    channel: []const u8,
    callback: EstacionCallback,
) !EstacionSubscriber {
    return try EstacionSubscriber.create(domain, channel, callback);
}

pub fn transformBinF2BinF(pb_bf: BinaryFormat) BinaraFormato {
    return switch (pb_bf) {
        .BF_PROTOBUF => .BF_PROTOBUF,
        .BF_ASN1_DER => .BF_ASN1_DER,
        .BF_OMG_CDR => .BF_OMG_CDR,
        else => return .BF_PROTOBUF,
    };
}
