const std = @import("std");

const Config = @import("../generated/Config.zig").k6bus.config;
const Security = @import("../generated/Security.zig").k6bus.security;
const Msg = @import("../generated/Msg.zig").k6bus.msg.Msg;

const UpStreamQ = @import("stream_queue.zig").UpStreamQ;
const DownStreamQ = @import("stream_queue.zig").DownStreamQ;
const StreamMode = @import("stream_queue.zig").StreamMode;
const BatchMode = @import("../generated/Config.zig").k6bus.config.DispatchMode;

const QueueMgr = @import("queue_mgr.zig").QueueMgr;

const Cipher = @import("cipher.zig").Cipher;
const ifcTransport = @import("ifc_transport.zig").ifcTransport;
const LoopTransport = @import("loop_transport.zig").LoopTransport;
const MCastTransport = @import("udp_transport.zig").MCastTransport;
const BCastTransport = @import("udp_transport.zig").BCastTransport;
const EndPoint = @import("udpstar_transport.zig").EndPoint;
const UDPStarTransport = @import("udpstar_transport.zig").UDPStarTransport;
const USOXStarTransport = @import("usoxstar_transport.zig").USOXStarTransport;
const Logger = @import("logger.zig").Logger;
const ifcSubscriber = @import("ifc_subscriber.zig").ifcSubscriber;

const ConfigFileNames = struct {
    pub const zon = "k6bus.App.zon.cfg";
    pub const pb = "k6bus.App.pb.cfg";
    pub const json = "k6bus.App.json.cfg";
};

const DomainRuntimeConfig = struct {
    binary_format: Config.BinaryFormat,
    start_at_init: bool,
    dispatch_mode: Config.DispatchMode,
    dispatch_batch_time_ms: u32,
    direct_dispatch_to_subs: bool,
};

pub const Domain = struct {
    allocator: std.mem.Allocator,
    id: u32,
    dom_cfg: DomainRuntimeConfig,

    // Subscribers
    registry_lock: std.Thread.RwLock = .{},
    registry: std.ArrayList(SubscriberRegistration),

    // Transports
    transport_lock: std.Thread.RwLock = .{},
    transports: std.ArrayList(ifcTransport),

    upstream: UpStreamQ = undefined,
    downstream: DownStreamQ = undefined,
    running: bool = false,
    closed: bool = false,

    cipher: Cipher,
    logger: Logger,

    subscriber_count: std.atomic.Value(u32) = .init(0),

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
        var app_cfg = try ReadConfigParams(allocator, domain_id);
        defer app_cfg.deinit(allocator);

        // try app_cfg.skribiAlDosiero(allocator, "k6bus.App.zon2.cfg", .TF_PROTOBUF);
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

    pub fn createFromFile(allocator: std.mem.Allocator, domain_id: u32, config_file: []const u8) !*Self {
        return createFromFileEx(
            allocator,
            domain_id,
            config_file,
            null,
            null,
        );
    }

    pub fn createFromFileEx(allocator: std.mem.Allocator, domain_id: u32, config_file: []const u8, dispatch_mode: ?Config.DispatchMode, dispatch_batch_time_ms: ?u32) !*Self {
        var app_cfg = try ReadConfigParamsFromFile(allocator, config_file);
        defer app_cfg.deinit(allocator);

        var dom_cfg = try GetDomainCfg(allocator, app_cfg, domain_id);

        if (dispatch_mode) |v| {
            dom_cfg.dispatch_mode = v;
        }

        if (dispatch_batch_time_ms) |v| {
            dom_cfg.dispatch_batch_time_ms = v;
        }

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        try self.init(allocator, domain_id, app_cfg, dom_cfg);

        return self;
    }

    fn init(self: *Self, allocator: std.mem.Allocator, domain_id: u32, app_cfg: Config.AppConfig, dom_cfg: Config.DomainConfig) !void {
        self.* = .{
            .allocator = allocator,
            .id = domain_id,
            .dom_cfg = .{
                .binary_format = dom_cfg.binary_format orelse .BF_PROTOBUF,
                .dispatch_batch_time_ms = dom_cfg.dispatch_batch_time_ms orelse 0,
                .dispatch_mode = dom_cfg.dispatch_mode orelse .IMMEDIATE,
                .start_at_init = dom_cfg.start_at_init orelse true,
                .direct_dispatch_to_subs = dom_cfg.direct_dispatch_to_subs orelse false,
            },

            .registry = .empty,
            .transports = .empty,

            .upstream = undefined,
            .downstream = undefined,

            .running = false,
            .closed = false,

            .cipher = undefined,
            .logger = undefined,
        };

        try self.upstream.init(
            self,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(dom_cfg.dispatch_batch_time_ms orelse 0),
        );
        try self.downstream.init(
            self,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(dom_cfg.dispatch_batch_time_ms orelse 0),
        );

        self.logger =
            try Logger.init(
                allocator,
                domain_id,
                app_cfg.activate_trace orelse false,
                app_cfg.trace_level orelse 3,
            );

        try self.LoadCipher(dom_cfg);
        try self.LoadTransports(dom_cfg);
        try self.CreateCrossConnections(dom_cfg);

        if (dom_cfg.start_at_init orelse true) {
            try self.start();
        }
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

        for (self.registry.items) |reg| {
            try reg.subscriber.start();
        }

        try self.upstream.start();

        for (self.transports.items) |t| {
            try t.start();
        }

        try self.downstream.start();
    }

    pub fn stop(self: *Self) !void {
        if (self.closed) return;
        if (!self.running) return;
        self.running = false;

        self.downstream.stop();
        for (self.transports.items) |t| {
            t.stop();
        }
        self.upstream.stop();
        for (self.registry.items) |reg| {
            try reg.subscriber.stop();
        }
    }

    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }

    pub fn close(self: *Self) void {
        if (self.closed) return;
        self.closed = true;

        self.logger.info("Closing Domain {d}...", .{self.id}, @src());
        self.running = false;

        self.downstream.close();
        while (self.transports.items.len > 0) {
            // inernamente se llama a removeTransport()
            self.transports.items[0].close();
        }
        self.upstream.close();
        while (self.registry.items.len > 0) {
            // internamente subscriber debe llamar a unregisterSubscriber()
            //self.registry.items[0].subscriber.closeOwner();
            self.registry.items[0].subscriber.close();
        }

        self.logger.info("Domain Closed {d}...", .{self.id}, @src());
        self.deinit();
    }

    /// comes from Publisher -> Domain
    pub fn sendMsg(self: *Self, msg: Msg) !void {
        try self.downstream.enqueue(msg);
    }

    /// Comes from Transport -> Domain
    pub fn onMsgListReceived(self: *Self, msg_list: []const Msg) !void {
        if (self.dom_cfg.direct_dispatch_to_subs) {
            self.upstream.dispatchToSubscribersDirect(msg_list);
        } else {
            try self.upstream.enqueueMany(msg_list);
        }
    }

    pub fn registerSubscriber(self: *Self, channel: u64, subscriber: ifcSubscriber) !void {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        try self.registry.append(self.allocator, .{
            .channel = channel,
            .subscriber = subscriber,
        });

        _ = self.subscriber_count.fetchAdd(1, .monotonic);
    }

    pub fn unregisterSubscriber(self: *Self, subscriber: ifcSubscriber) void {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        var i: usize = 0;
        while (i < self.registry.items.len) {
            if (self.registry.items[i].subscriber.ptr == subscriber.ptr) {
                _ = self.registry.swapRemove(i);
                _ = self.subscriber_count.fetchSub(1, .monotonic);
                return;
            }
            i += 1;
        }
    }

    pub fn addTransport(self: *Self, transport: ifcTransport) !void {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        try self.transports.append(self.allocator, transport);
    }

    pub fn removeTransport(self: *Self, transport: ifcTransport) void {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        var i: usize = 0;
        while (i < self.transports.items.len) {
            if (self.transports.items[i].ptr == transport.ptr) {
                _ = self.transports.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    fn MakeDefaultAppConfigWithDomain(allocator: std.mem.Allocator, domain_id: u32) !Config.AppConfig {
        var app = try Config.AppConfig.initDefault(allocator);
        errdefer app.deinit(allocator);

        // initDefault() crea domains como slice vacio.
        // Lo sustituimos por un slice con un DomainConfig por defecto.
        allocator.free(app.domains);

        app.domains = try allocator.alloc(Config.DomainConfig, 1);
        app.domains[0] = try Config.DomainConfig.initDefault(allocator);
        app.domains[0].id = domain_id;

        return app;
    }

    fn ReadConfigParams(allocator: std.mem.Allocator, domain_id: u32) !Config.AppConfig {
        if (fileExists(ConfigFileNames.zon)) {
            if (Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.zon, .TF_ZIG_ZON)) |app_cfg| {
                return app_cfg;
            } else |err| {
                std.debug.print(
                    "Error leyendo {s} como ZON: {}. Intentando siguiente formato.\n",
                    .{ ConfigFileNames.zon, err },
                );
            }
        }

        if (fileExists(ConfigFileNames.pb)) {
            if (Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.pb, .TF_PROTOBUF)) |app_cfg| {
                return app_cfg;
            } else |err| {
                std.debug.print(
                    "Error leyendo {s} como Protobuf Text: {}. Intentando siguiente formato.\n",
                    .{ ConfigFileNames.pb, err },
                );
            }
        }

        if (fileExists(ConfigFileNames.json)) {
            if (Config.AppConfig.legiElDosiero(allocator, ConfigFileNames.json, .TF_JSON)) |app_cfg| {
                return app_cfg;
            } else |err| {
                std.debug.print(
                    "Error leyendo {s} como JSON: {}. Usando configuracion por defecto.\n",
                    .{ ConfigFileNames.json, err },
                );
            }
        }

        return try MakeDefaultAppConfigWithDomain(allocator, domain_id);
    }

    fn ReadConfigParamsFromFile(allocator: std.mem.Allocator, config_file: []const u8) !Config.AppConfig {
        if (std.mem.endsWith(u8, config_file, ".zon.cfg")) {
            return try Config.AppConfig.legiElDosiero(
                allocator,
                config_file,
                .TF_ZIG_ZON,
            );
        }

        if (std.mem.endsWith(u8, config_file, ".pb.cfg")) {
            return try Config.AppConfig.legiElDosiero(
                allocator,
                config_file,
                .TF_PROTOBUF,
            );
        }

        if (std.mem.endsWith(u8, config_file, ".json.cfg")) {
            return try Config.AppConfig.legiElDosiero(
                allocator,
                config_file,
                .TF_JSON,
            );
        }

        return error.UnsupportedConfigFormat;
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

    fn LoadCipher(self: *Self, dom_cfg: Config.DomainConfig) !void {
        const key_file =
            dom_cfg.key_file orelse {
                self.cipher = try Cipher.createNoCipher(self.allocator);
                return;
            };

        if (std.mem.endsWith(u8, key_file, ".zon")) {
            const registry = try Security.KeyRecord
                .legiElDosiero(self.allocator, key_file, .TF_ZIG_ZON);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        if (std.mem.endsWith(u8, key_file, ".pb")) {
            const registry = try Security.KeyRecord
                .legiElDosiero(self.allocator, key_file, .TF_PROTOBUF);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        if (std.mem.endsWith(u8, key_file, ".json")) {
            const registry = try Security.KeyRecord
                .legiElDosiero(self.allocator, key_file, .TF_JSON);
            self.cipher = try Cipher.create(self.allocator, registry);
            return;
        }

        self.cipher = try Cipher.createNoCipher(self.allocator);
        return;
        // return error.InvalidKeyFileExtension;
    }

    fn LoadTransports(self: *Self, dom_cfg: Config.DomainConfig) !void {
        // ========================================================================
        // Transporte por defecto
        // ========================================================================
        if (dom_cfg.activate_default_transport orelse true) {
            const mcast =
                try MCastTransport.create(
                    self,
                    "DefaultMCast_00",
                    "239.255.0.11",
                    "Any",
                    40069,
                    1,
                );
            try self.addTransport(mcast.ifc_transport);
        }

        // ========================================================================
        // Transportes configurados
        // ========================================================================
        for (dom_cfg.transports) |tr_cfg| {
            const name = tr_cfg.name;
            switch (tr_cfg.kind) {
                .LOOP => {
                    const loop_t = try LoopTransport.create(
                        self,
                        name,
                        10,
                    );
                    try self.addTransport(loop_t.ifc_transport);
                },

                .MCAST => {
                    const cfg = switch (tr_cfg.params) {
                        .mcast => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    const mcast =
                        try MCastTransport.createEx(
                            self,
                            name,
                            cfg.mcast_address,
                            cfg.local_address orelse "Any",
                            @intCast(cfg.port),
                            @intCast(cfg.ttl orelse 1),
                            @intCast(cfg.send_buffer orelse 134217727),
                            @intCast(cfg.receive_buffer orelse 134217727),
                        );
                    try self.addTransport(mcast.ifc_transport);
                },

                .BCAST => {
                    const cfg = switch (tr_cfg.params) {
                        .bcast => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    const bcast =
                        try BCastTransport.createEx(
                            self,
                            name,
                            cfg.bcast_address,
                            cfg.local_address orelse "Any",
                            @intCast(cfg.port),
                            1,
                            @intCast(cfg.send_buffer orelse 134217727),
                            @intCast(cfg.receive_buffer orelse 134217727),
                        );
                    try self.addTransport(bcast.ifc_transport);
                },

                .UDPSTAR => {
                    const cfg = switch (tr_cfg.params) {
                        .udpstar => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    var endpoints: std.ArrayList(EndPoint) = .empty;
                    defer endpoints.deinit(self.allocator);

                    for (cfg.end_point) |ep| {
                        try endpoints.append(
                            self.allocator,
                            .{
                                .host = ep.host,
                                .port = @intCast(ep.port),
                            },
                        );
                    }
                    const udpstar =
                        try UDPStarTransport.createEx(
                            self,
                            name,
                            cfg.local_address orelse "Any",
                            @intCast(cfg.port),
                            endpoints.items,
                            @intCast(cfg.send_buffer orelse 134217727),
                            @intCast(cfg.receive_buffer orelse 134217727),
                        );
                    try self.addTransport(udpstar.ifc_transport);
                },

                .USOXSTAR => {
                    const cfg = switch (tr_cfg.params) {
                        .usoxstar => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    const usoxstar =
                        try USOXStarTransport.createEx(
                            self,
                            name,
                            cfg.local_socket_path,
                            cfg.remote_socket_paths,
                            @intCast(cfg.send_buffer orelse 134217727),
                            @intCast(cfg.receive_buffer orelse 134217727),
                        );
                    try self.addTransport(usoxstar.ifc_transport);
                },

                .CUSTOM => {
                    self.logger.warning(
                        "CUSTOM transport ignored: {s}",
                        .{name},
                        @src(),
                    );
                },
            }
        }
    }

    fn CreateCrossConnections(self: *Self, dom_cfg: Config.DomainConfig) !void {
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

        for (dom_cfg.cross_connectors) |xcc| {
            // Menos de dos transportes no tiene sentido.
            if (xcc.transports.len < 2) continue;

            // Buscar los transportes del grupo.
            // var group = std.ArrayList(*Transport).init(self.allocator);
            var group: std.ArrayList(ifcTransport) = .empty;
            defer group.deinit(self.allocator);

            for (xcc.transports) |wanted_name| {
                for (self.transports.items) |tr| {
                    if (std.mem.eql(u8, tr.getName(), wanted_name)) {
                        try group.append(self.allocator, tr);
                        break;
                    }
                }
            }

            // Crear malla completa.
            for (group.items) |src| {
                for (group.items) |dst| {
                    if (src.ptr == dst.ptr) continue;
                    // FUTURO:
                    try src.crossConnect(dst);
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
    subscriber: ifcSubscriber,
};
