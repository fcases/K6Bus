const std = @import("std");
const k6bus = @import("k6bus");
const Msg = k6bus.Msg;
const Utils = k6bus.MsgUtils;

const BinaryFormat = k6bus.Config.BinaryFormat;

// BinaryFormat viene de Config.proto y representa formatos configurables de K6Bus.
// BinaraFormato lo genera ProtobuZig para las funciones generales de seriigi/deseriigi.
// Aunque ambos sean enum(u64), Zig los trata como tipos distintos.
// Los valores comunes se mantienen sincronizados para permitir conversion por valor.
pub fn binaryFormatToBinaraFormato(comptime BinaraFormato: type, v: BinaryFormat) BinaraFormato {
    return std.meta.intToEnum(
        BinaraFormato,
        @intFromEnum(v),
    ) catch .BF_PROTOBUF;
}

// ---------------------------------------------------------
// Publisher
// ---------------------------------------------------------
pub fn GenericPublisher(comptime Datum: type, comptime BinaraFormato: type) type {
    return struct {
        domain: *k6bus.Domain,
        msgType: u64,

        const Self = @This();

        pub fn create(domain: *k6bus.Domain) !Self {
            return .{
                .domain = domain,
                .msgType = k6bus.Hash.hashMsgType(
                    domain.id,
                    @typeName(Datum),
                ),
            };
        }

        pub fn publish(self: *Self, channel_name: []const u8, datum: *const Datum) !bool {
            const channels = [_][]const u8{channel_name};
            return try self.publishToChannels(channels[0..], datum);
        }

        pub fn publishToChannels(self: *Self, channel_names: []const []const u8, datum: *const Datum) !bool {
            const allocator = self.domain.allocator;

            const payload = try datum.seriigiAlBin(
                allocator,
                binaryFormatToBinaraFormato(
                    BinaraFormato,
                    self.domain.dom_cfg.binary_format,
                ),
            );
            errdefer allocator.free(payload);

            const channel_hashes = try allocator.alloc(u64, channel_names.len);
            errdefer allocator.free(channel_hashes);

            for (channel_names, 0..) |channel_name, i| {
                channel_hashes[i] = k6bus.Hash.hashChannel(channel_name);
            }

            const msg = Msg{
                .channels = channel_hashes,
                .msgType = self.msgType,
                .payLoad = payload,
            };

            try self.domain.sendMsg(msg);

            return true;
        }
    };
}

const ifcSubscriber = k6bus.ifcSubscriber;

// ---------------------------------------------------------
// Subscriber
// ---------------------------------------------------------
pub fn GenericSubscriber(comptime Datum: type, comptime BinaraFormato: type) type {
    return struct {
        const DatumCallback = *const fn (channel_name: []const u8, datum: *const Datum) void;

        domain: *k6bus.Domain,
        name: []const u8,
        qm: k6bus.QueueMgr,
        callback: DatumCallback,

        channel_name: []const u8,
        channel: u64,
        msgType: u64,
        bf_protobuzg: BinaraFormato = .BF_PROTOBUF,

        const Self = @This();

        pub fn create(domain: *k6bus.Domain, channel_name: []const u8, callback: DatumCallback) !*Self {
            const self = try domain.allocator.create(Self);
            errdefer domain.allocator.destroy(self);

            try self.init(domain, channel_name, callback);

            return self;
        }

        fn init(self: *Self, domain: *k6bus.Domain, channel_name: []const u8, callback: DatumCallback) !void {
            self.domain = domain;
            self.callback = callback;

            const allocator = domain.allocator;

            self.channel_name = try allocator.dupe(u8, channel_name);
            errdefer allocator.free(self.channel_name);

            self.channel = k6bus.Hash.hashChannel(channel_name);
            self.msgType = k6bus.Hash.hashMsgType(domain.id, @typeName(Datum));

            self.bf_protobuzg = binaryFormatToBinaraFormato(BinaraFormato, domain.dom_cfg.binary_format);

            const id = @intFromPtr(self) >> 4 & 0xFFFF;
            const nombre = try std.fmt.allocPrint(
                allocator,
                "{s}Subscriber_{X:0>4}",
                .{ @typeName(Datum), id },
            );
            defer allocator.free(nombre);

            self.name = try allocator.dupe(u8, nombre);
            errdefer allocator.free(self.name);

            self.qm = try k6bus.QueueMgr.create(
                domain,
                self.name,
                domain.dom_cfg.dispatch_mode,
                @intCast(domain.dom_cfg.dispatch_batch_time_ms),
                self,
                dispatchMsg,
            );

            try domain.registerSubscriber(self.channel, self.msgType, ifcSubscriber.init(self));
            errdefer domain.unregisterSubscriber(ifcSubscriber.init(self));

            if (domain.dom_cfg.start_at_init) {
                try self.start();
            }
        }

        fn deinit(self: *Self) void {
            self.domain.allocator.free(self.name);
            self.domain.allocator.free(self.channel_name);
        }

        fn dispatchMsg(owner: *anyopaque, msg_list: []const Msg) void {
            const self: *Self = @ptrCast(@alignCast(owner));
            const allocator = self.domain.allocator;

            for (msg_list) |*msg| {
                defer Utils.freeMsg(allocator, @constCast(msg));

                // if (msg.msgType != self.msgType) continue;

                var datum =
                    Datum.deseriigiElBin(
                        allocator,
                        msg.payLoad,
                        self.bf_protobuzg,
                    ) catch continue;
                defer datum.deinit(allocator);

                self.callback(self.channel_name, &datum);
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
            self.qm.close();
            self.deinit();
            self.domain.allocator.destroy(self);
        }

        pub fn enqueue(self: *Self, msg: Msg) !void {
            try self.qm.enqueue(msg);
        }
    };
}
