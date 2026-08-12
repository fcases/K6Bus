const std = @import("std");

const k6bus = @import("k6bus");
const BinaryFormat = k6bus.Config.BinaryFormat;
const Msg = k6bus.Msg;
const Utils = k6bus.MsgUtils;
const ifcSubscriber = k6bus.ifcSubscriber;

const EstacionFile = @import("Estacion.zig");
pub const Estacion = EstacionFile.demo1.Estacion;
const BinaraFormato = EstacionFile.BinaraFormato;

// ---------------------------------------------------------
// Callback tipado
// ---------------------------------------------------------

pub const EstacionCallback = *const fn (channel_name: []const u8, estacion: *const Estacion) void;

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
                binaryFormatToBinaraFormato(self.domain.dom_cfg.binary_format),
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
    name: []const u8,
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

        self.bf_protobuzg = binaryFormatToBinaraFormato(domain.dom_cfg.binary_format);

        const id = @intFromPtr(self) >> 4 & 0xFFFF;
        const nombre = try std.fmt.allocPrint(domain.allocator, "EstacionSubscriber_{X:0>4}", .{id});
        defer domain.allocator.free(nombre);
        self.name = try domain.allocator.dupe(u8, nombre);

        self.qm =
            try k6bus.QueueMgr.create(domain, self.name, domain.dom_cfg.dispatch_mode, @intCast(domain.dom_cfg.dispatch_batch_time_ms), self, dispatchMsg);

        try domain.registerSubscriber(self.channel, ifcSubscriber.init(self));

        if (domain.dom_cfg.start_at_init) {
            try self.start();
        }
    }

    fn deinit(self: *Self) void {
        self.domain.allocator.free(self.channel_name);
        self.domain.allocator.free(self.name);
    }

    //
    // Callback de qm, que llama a callback de usuario
    //
    fn dispatchMsg(owner: *anyopaque, msg_list: []const Msg) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        for (msg_list) |*msg| {
            defer Utils.freeMsg(self.domain.allocator, @constCast(msg));

            if (msg.msgType != self.msgType) continue;

            var estacion =
                Estacion.deseriigiElBin(
                    self.domain.allocator,
                    msg.payLoad,
                    self.bf_protobuzg,
                ) catch continue;
            defer estacion.deinit(self.domain.allocator);

            self.callback(self.channel_name, &estacion);
        }
    }

    //
    // Implementacion del interfaz ifcSubscriber
    //
    pub fn start(self: *Self) !void {
        try self.qm.start();
    }

    pub fn stop(self: *Self) void {
        self.qm.stop();
    }

    pub fn close(self: *Self) void {
        self.domain.unregisterSubscriber(ifcSubscriber.init(self));
        self.qm.close();

        self.deinit();
        self.domain.allocator.destroy(self);
    }

    pub fn enqueue(self: *Self, msg: Msg) !void {
        try self.qm.enqueue(msg);
    }
};

// BinaryFormat viene de Config.proto y representa formatos configurables de K6Bus.
// BinaraFormato lo genera ProtobuZig para las funciones generales de seriigi/deseriigi.
// Aunque ambos sean enum(u64), Zig los trata como tipos distintos.
// Los valores comunes se mantienen sincronizados para permitir conversion por valor.
pub fn binaryFormatToBinaraFormato(v: BinaryFormat) BinaraFormato {
    return std.meta.intToEnum(
        BinaraFormato,
        @intFromEnum(v),
    ) catch .BF_PROTOBUF;
}
