const std = @import("std");

const Config = @import("../generated/Config.zig").k6bus.config;
const Security = @import("../generated/Security.zig").k6bus.security;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

const StreamQueue = @import("stream_queue.zig").StreamQueue;
const StreamMode = @import("stream_queue.zig").StreamMode;
const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;

const QueueMgr = @import("queue_mgr.zig").QueueMgr;

const Transport = @import("transport.zig").Transport;
const Cipher = @import("cipher.zig").Cipher;
const LoopTransport = @import("loop_transport.zig").LoopTransport;
const MCastTransport = @import("udp_transport.zig").MCastTransport;
const Logger = @import("logger.zig").Logger;

const ConfigFileNames = struct {
    pub const zon = "k6bus.App.zon.cfg";
    pub const pb = "k6bus.App.pb.cfg";
    pub const json = "k6bus.App.json.cfg";
};

pub const Domain = struct {
    allocator: std.mem.Allocator,
    id: u32,
    dom_cfg: Config.DomainConfig,

    // Subscribers
    registry_lock: std.Thread.RwLock = .{},
    registry: std.ArrayList(SubscriberRegistration),

    // Transports
    transport_lock: std.Thread.RwLock = .{},
    transports: std.ArrayList(*Transport),

    upstream: StreamQueue = undefined,
    downstream: StreamQueue = undefined,
    running: bool = false,

    cipher: Cipher,
    logger: Logger,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator, domain_id: u32) !*Self {
        return createEx(
            allocator,
            domain_id,
            null,
            null,
        );
    }

    pub fn createEx(allocator: std.mem.Allocator, domain_id: u32, dispatch_mode: ?Config.DispatchMode, dispatch_batch_time_ms: ?u32) !*Self {
        const app_cfg = try ReadConfigParams(allocator);
        var dom_cfg = try GetDomainCfg(allocator, app_cfg, domain_id);

        if (dispatch_mode) |v|
            dom_cfg.dispatch_mode = v;

        if (dispatch_batch_time_ms) |v|
            dom_cfg.dispatch_batch_time_ms = v;

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        try self.init(allocator, domain_id, app_cfg, dom_cfg);

        return self;
    }

    fn init(self: *Self, allocator: std.mem.Allocator, domain_id: u32, app_cfg: Config.AppConfig, dom_cfg: Config.DomainConfig) !void {
        self.* = .{
            .allocator = allocator,
            .id = domain_id,
            .dom_cfg = dom_cfg,

            .registry = .empty,
            .transports = .empty,

            .upstream = undefined,
            .downstream = undefined,

            .cipher = undefined,
            .logger = undefined,
        };

        try self.upstream.init(
            self,
            StreamMode.UP,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(
                dom_cfg.dispatch_batch_time_ms orelse 0,
            ),
        );
        try self.downstream.init(
            self,
            StreamMode.DOWN,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(
                dom_cfg.dispatch_batch_time_ms orelse 0,
            ),
        );

        self.logger =
            try Logger.init(
                allocator,
                domain_id,
                true,
                3,
            );

        try self.LoadCipher();
        try self.LoadTransports();
        try self.CreateCrossConnections();

        if (dom_cfg.start_at_init orelse true) {
            try self.start();
        }

        _ = app_cfg;
    }

    fn deinit(self: *Self) void {
        self.registry.deinit(self.allocator);
        self.transports.deinit(self.allocator);
        self.logger.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *Self) !void {
        if (self.running) return;
        self.running = true;

        try self.upstream.start();
        try self.downstream.start();

        for (self.transports.items) |t| {
            try t.start();
        }
    }

    pub fn stop(self: *Self) !void {
        if (!self.running) return;
        self.running = false;

        self.upstream.stop();
        self.downstream.stop();

        for (self.transports.items) |t| {
            t.stop();
        }
    }

    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    pub fn close(self: *Self) void {
        self.logger.info("Closing Domain {d}...", .{self.id}, @src());
        self.running = false;

        self.downstream.close();

        while (self.transports.items.len > 0) {
            // inernamente se llama a removeTransport()
            self.transports.items[0].closeOwner();
        }

        self.upstream.close();

        while (self.registry.items.len > 0) {
            // internamente subscriber debe llamar a unregisterSubscriber()
            self.registry.items[0].subscriber.closeOwner();
        }

        self.logger.info("Domain Closed {d}...", .{self.id}, @src());
        self.deinit();
    }

    /// comes from Publisher -> Domain
    pub fn sendMsg(self: *Self, msg: Msg) !void {
        try self.downstream.qm.enqueue(msg);
    }

    /// Comes from Transport -> Domain
    pub fn onMsgListReceived(self: *Self, msg_list: []const Msg) !void {
        if (self.dom_cfg.direct_dispatch_to_subs orelse false) {
            self.upstream.dispatchToSubscribersDirect(msg_list);
        } else {
            try self.upstream.qm.enqueueMany(msg_list);
        }
    }

    pub fn registerSubscriber(self: *Self, channel: u64, subscriber: *QueueMgr) !void {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        try self.registry.append(self.allocator, .{
            .channel = channel,
            .subscriber = subscriber,
        });
    }

    pub fn unregisterSubscriber(self: *Self, subscriber: *QueueMgr) void {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        var i: usize = 0;
        while (i < self.registry.items.len) {
            if (self.registry.items[i].subscriber == subscriber) {
                _ = self.registry.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    pub fn addTransport(self: *Self, transport: *Transport) !void {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        try self.transports.append(self.allocator, transport);
    }

    pub fn removeTransport(self: *Self, transport: *Transport) void {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        var i: usize = 0;
        while (i < self.transports.items.len) {
            if (self.transports.items[i] == transport) {
                _ = self.transports.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    fn ReadConfigParams(allocator: std.mem.Allocator) !Config.AppConfig {
        if (fileExists(ConfigFileNames.zon))
            return Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.zon, .TF_ZIG_ZON);

        if (fileExists(ConfigFileNames.pb))
            return Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.pb, .TF_PROTOBUF);

        if (fileExists(ConfigFileNames.json))
            return Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.json, .TF_JSON);

        return Config.AppConfig.initDefault(allocator);
    }

    fn GetDomainCfg(allocator: std.mem.Allocator, app_cfg: Config.AppConfig, domain_id: u32) !Config.DomainConfig {
        for (app_cfg.domains) |dom| {
            if (dom.id == domain_id)
                return dom;
        }

        var dom = try Config.DomainConfig.initDefault(allocator);
        dom.id = @intCast(domain_id);
        return dom;
    }

    fn LoadCipher(self: *Self) !void {
        const key_file =
            self.dom_cfg.key_file orelse {
                self.cipher = try Cipher.createNoCipher(self.allocator);
                return;
            };

        if (std.mem.endsWith(u8, key_file, ".zon")) {
            const registry = try Security.KeyRegistry
                .legiElDosiero(self.allocator, key_file, .TF_ZIG_ZON);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        if (std.mem.endsWith(u8, key_file, ".pb")) {
            const registry = try Security.KeyRegistry
                .legiElDosiero(self.allocator, key_file, .TF_PROTOBUF);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        if (std.mem.endsWith(u8, key_file, ".json")) {
            const registry = try Security.KeyRegistry
                .legiElDosiero(self.allocator, key_file, .TF_JSON);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        self.cipher = try Cipher.createNoCipher(self.allocator);
        return;
        // return error.InvalidKeyFileExtension;
    }

    fn LoadTransports(self: *Self) !void {
        // Transporte por defecto
        // Si ActivateDefaultTransport == true o no esta definido (es opcional),
        // crear automáticamente un transporte por defecto.
        if (self.dom_cfg.activate_default_transport orelse true) {
            const mcast = try MCastTransport.create(self, "DefaultMCast_01", "239.255.0.11", "Any", 40069, 1);
            try self.addTransport(mcast);
        }

        // Transportes configurados
        for (self.dom_cfg.transports) |tr_cfg| {
            switch (tr_cfg.kind) {
                .LOOP => {
                    const LoopT = try LoopTransport.create(self, "DefaultLoopT_01", 10);
                    try self.addTransport(&LoopT.transport);
                },
                .MCAST => {
                    // FUTURO:
                    // const tr =
                    //     try MCastTransport.create(allocator,self,tr_cfg);
                    // try self.addTransport(tr);
                },
                .BCAST => {
                    // FUTURO:
                    // const tr =
                    //     try BCastTransport.create(allocator,self,tr_cfg);
                    // try self.addTransport(tr);
                },
                .UDPSTAR => {
                    // FUTURO:
                    // const tr =
                    //     try UDPStarTransport.create(allocator,self,tr_cfg);
                    // try self.addTransport(tr);
                },
                .USOXSTAR => {
                    // FUTURO:
                    // const tr =
                    //     try UnixSocketStarTransport.create(allocator,self,tr_cfg);
                    // try self.addTransport(tr);
                },
                .CUSTOM => {
                    // FUTURO
                    // PluginLib
                    // dlopen()
                    // fábrica de transportes
                },
            }
        }
    }

    fn CreateCrossConnections(self: *Self) !void {
        // Ejemplo:
        // CrossConnectors = {
        //   { T1 T2 T3 }
        //   { T4 T5 }
        // }
        // genera:
        // grupo1:
        //   T1 <-> T2
        //   T1 <-> T3
        //   T2 <-> T3
        // grupo2:
        //   T4 <-> T5

        self.transport_lock.lockShared();
        defer self.transport_lock.unlockShared();

        for (self.dom_cfg.cross_connectors) |xcc| {
            // Menos de dos transportes no tiene sentido.
            if (xcc.transports.len < 2) continue;

            // Buscar los transportes del grupo.
            // var group = std.ArrayList(*Transport).init(self.allocator);
            var group: std.ArrayList(*Transport) = .empty;
            defer group.deinit(self.allocator);

            for (xcc.transports) |wanted_name| {
                for (self.transports.items) |tr| {
                    if (std.mem.eql(u8, tr.name, wanted_name)) {
                        try group.append(self.allocator, tr);
                        break;
                    }
                }
            }

            // Crear malla completa.
            for (group.items) |src| {
                for (group.items) |dst| {
                    if (src == dst) continue;
                    // FUTURO:
                    // try src.crossConnect(dst);
                }
            }
        }
    }

    fn fileExists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;

        return true;
    }
};

pub const SubscriberRegistration = struct {
    channel: u64,
    subscriber: *QueueMgr,
};
