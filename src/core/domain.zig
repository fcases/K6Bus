const std = @import("std");

const Config = @import("../generated/Config.zig").k6bus.config;
const Security = @import("../generated/Security.zig").k6bus.security;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

const StreamQueue = @import("stream_queue.zig").StreamQueue;
const StreamMode = @import("stream_queue.zig").StreamMode;
const BatchMode = @import("stream_queue.zig").BatchMode;

const QueueMgr = @import("queue_mgr.zig").QueueMgr;

const Transport = @import("transport.zig").Transport;
const Cipher = @import("cipher.zig").Cipher;
const LoopTransport = @import("loop_transport.zig").LoopTransport;
const Logger = @import("logger.zig").Logger;

const ConfigFileNames = struct {
    pub const zon = "k6bus.App.zon.cfg";
    pub const pb = "k6bus.App.pb.cfg";
    pub const json = "k6bus.App.json.cfg";
};

pub const Domain = struct {
    allocator: std.mem.Allocator,
    id: u32,
    dom_cfg: Config.DomainCfg,

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

    pub fn create(allocator: std.mem.Allocator, domain_id: u32) !Self {
        const app_cfg = try ReadConfigParams(allocator);
        const dom_cfg = try GetDomainCfg(allocator, app_cfg, domain_id);

        var self = Self{
            .allocator = allocator,
            .id = domain_id,
            .dom_cfg = dom_cfg,

            // .registry = std.ArrayList(SubscriberRegistration).init(allocator),
            // .transports = std.ArrayList(*Transport).init(allocator),
            .registry = .empty,
            .transports = .empty,

            .upstream = undefined,
            .downstream = undefined,

            .cipher = undefined,
            .logger = undefined,
        };

        // self.upstream = try self.upstream.init(
        try self.upstream.init(
            &self,
            StreamMode.UP,
            dom_cfg.DispatchMode orelse .IMMEDIATE,
            @intCast(dom_cfg.DispatchBatchTimeMs orelse 0),
        );
        // self.downstream = try self.downstream.init(
        try self.downstream.init(
            &self,
            StreamMode.DOWN,
            dom_cfg.DispatchMode orelse .IMMEDIATE,
            @intCast(dom_cfg.DispatchBatchTimeMs orelse 0),
        );
        self.logger = try Logger.init(allocator, domain_id, app_cfg.ActivateTrace orelse false, @intCast(app_cfg.TraceLevel orelse 0));

        try self.LoadCipher();
        try self.LoadTransports();
        try self.CreateCrossConnections();

        if (dom_cfg.StartAtInit orelse true) {
            try self.start();
        }

        return self;
    }

    fn deinit(self: *Self) void {
        self.registry.deinit();
        self.transports.deinit();
        self.logger.deinit();
    }

    pub fn start(self: *Self) !void {
        if (self.running) return;
        self.running = true;

        try self.upstream.start();
        try self.downstream.start();

        // FUTURO:
        // start transportes
    }

    pub fn pause(self: *Self) !void {
        if (!self.running) return;
        self.running = false;

        try self.upstream.pause();
        try self.downstream.pause();

        // FUTURO:
        // pause transportes
    }

    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    pub fn close(self: *Self) void {
        self.running = false;

        self.upstream.close();
        self.downstream.close();

        // FUTURO:
        // cerrar transportes

        // FUTURO:
        // cerrar subscribers

        self.deinit();
    }

    /// comes from Publisher -> Domain
    pub fn sendMsg(self: *Self, msg: *Msg) !void {
        try self.downstream.qm.enqueue(msg);
    }

    /// Comes from Transport -> Domain
    pub fn onMsgListReceived(self: *Self, msg_list: []*Msg) !void {
        if (self.dom_cfg.DirectDispatchToSubs) {
            self.upstream.dispatchToSubscribers(msg_list);
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

    fn GetDomainCfg(allocator: std.mem.Allocator, app_cfg: Config.AppConfig, domain_id: u32) !Config.DomainCfg {
        for (app_cfg.Domains) |dom| {
            if (dom.Id == domain_id)
                return dom;
        }

        var dom = try Config.DomainCfg.initDefault(allocator);
        dom.Id = @intCast(domain_id);
        return dom;
    }

    fn LoadCipher(self: *Self) !void {
        const key_file =
            self.dom_cfg.KeyFile orelse {
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
        if (self.dom_cfg.ActivateDefaultTransport orelse true) {
            // OPCIÓN ACTUAL
            // Mientras MCastTransport no esté terminado,
            // el código de aplicación puede crear manualmente
            // el LoopTransport y añadirlo mediante:
            var LoopT = try LoopTransport.create(self, "DefaultLoopT", 300);
            try self.addTransport(&LoopT.transport);

            // Cuando MCast esté completo:
            // const mcast = try MCastTransport.create(self.allocator,self,"DefaultMCast",null);
            // try self.addTransport(mcast);
        }

        // Transportes configurados
        for (self.dom_cfg.Transports) |tr_cfg| {
            switch (tr_cfg.Kind) {
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

        for (self.dom_cfg.CrossConnectors) |xcc| {
            // Menos de dos transportes no tiene sentido.
            if (xcc.Transports.len < 2) continue;

            // Buscar los transportes del grupo.
            // var group = std.ArrayList(*Transport).init(self.allocator);
            var group: std.ArrayList(*Transport) = .empty;
            defer group.deinit(self.allocator);

            for (xcc.Transports) |wanted_name| {
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
