const std = @import("std");

const Config = @import("../generated/Config.zig").k6bus.config;
const Security = @import("../generated/Security.zig").k6bus.security;
const Msg = @import("../generated/types.zig").k6bus.Msg;

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
const MatrixTransport = @import("matrix_transport.zig").MatrixTransport;
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
    running: std.atomic.Value(bool) = .init(false),
    closed: std.atomic.Value(bool) = .init(false),

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
        const app_cfg = try ReadConfigParams(allocator, domain_id);
        return try createDomain(allocator, domain_id, app_cfg, dispatch_mode, dispatch_batch_time_ms);
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
        const app_cfg = try ReadConfigParamsFromFile(allocator, config_file);
        return try createDomain(allocator, domain_id, app_cfg, dispatch_mode, dispatch_batch_time_ms);
    }

    // ========================================================================
    // createDomain
    // ========================================================================
    // Common part of createEx and createFromFileEx (the only difference
    // between them is how app_cfg is obtained: default/cwd or from a file).
    //
    // app_cfg is a TEMPORARY construct used only during init: it is passed
    // by value and this method frees it on exit (defer app_cfg.deinit).
    //
    // dom_cfg (via GetDomainCfg) is a BORROWED VIEW of app_cfg (it shares
    // its heap memory); it is NOT owned: do not call dom_cfg.deinit() (a
    // double-free with app_cfg.deinit). It is only valid during init(),
    // which runs before app_cfg is freed. Anyone keeping slices after init
    // must duplicate them (Guidelines rule: "every component that keeps
    // strings or slices after init must duplicate them").
    //
    // Case "domain not found in app_cfg": GetDomainCfg creates it and ADDS
    // it to app_cfg.domains, so that app_cfg.deinit() frees it like the
    // rest. Both cases return a borrowed view of app_cfg.
    // ========================================================================
    fn createDomain(
        allocator: std.mem.Allocator,
        domain_id: u32,
        app_cfg: Config.AppConfig,
        dispatch_mode: ?Config.DispatchMode,
        dispatch_batch_time_ms: ?u32,
    ) !*Self {
        // The fn parameters are const: a local mutable copy (shares the heap
        // memory with the caller) so &app_cfg can be passed to GetDomainCfg
        // and freed here on exit.
        var app_cfg_mut = app_cfg;
        defer app_cfg_mut.deinit(allocator);

        var dom_cfg = try GetDomainCfg(allocator, &app_cfg_mut, domain_id);

        if (dispatch_mode) |v|
            dom_cfg.dispatch_mode = v;

        if (dispatch_batch_time_ms) |v|
            dom_cfg.dispatch_batch_time_ms = v;

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        try self.init(allocator, domain_id, app_cfg_mut, dom_cfg);

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

            .running = .init(false),
            .closed = .init(false),

            .cipher = undefined,
            .logger = undefined,
        };

        // Cleanup if anything fails from here on: every resource registers its
        // errdefer as soon as it is acquired, and they run in reverse order.
        // Before, a failure in the middle (e.g. a transport that cannot open
        // the socket) leaked EVERYTHING already created -queues, logger,
        // already registered transports and the registry lists- because
        // createDomain only destroyed the struct (L1, 2026-09-15).
        errdefer self.registry.deinit(self.allocator);
        errdefer self.transports.deinit(self.allocator);

        try self.upstream.init(
            self,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(dom_cfg.dispatch_batch_time_ms orelse 0),
        );
        errdefer self.upstream.close();

        try self.downstream.init(
            self,
            dom_cfg.dispatch_mode orelse .IMMEDIATE,
            @intCast(dom_cfg.dispatch_batch_time_ms orelse 0),
        );
        errdefer self.downstream.close();

        self.logger =
            try Logger.init(
                allocator,
                domain_id,
                app_cfg.activate_trace orelse false,
                app_cfg.trace_level orelse 3,
            );
        errdefer self.logger.deinit();

        // LoadCipher always leaves self.cipher initialized (in the clear when
        // there is no valid key): from here on it can be freed without fear.
        try self.LoadCipher(dom_cfg);
        errdefer self.cipher.deinit();

        // The transports already created are closed (close() is destructive
        // and self-unregistering). The errdefer goes BEFORE the load so that
        // it also covers a LoadTransports failure halfway through the list.
        errdefer {
            while (self.takeFirstTransport()) |t| t.close();
        }
        try self.LoadTransports(dom_cfg);

        try self.CreateCrossConnections(dom_cfg);

        if (dom_cfg.start_at_init orelse true) {
            try self.start();
        }
    }

    fn deinit(self: *Self) void {
        self.registry.deinit(self.allocator);
        self.transports.deinit(self.allocator);
        self.cipher.deinit();
        self.logger.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *Self) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release); // = true;

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
        if (self.closed.load(.acquire)) return;
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release); // = false;

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
        return self.running.load(.acquire);
    }

    /// Coordinates the complete Domain shutdown.
    /// Concurrency:
    /// - The first caller performs the shutdown.
    /// - Concurrent or later calls return immediately.
    /// - Only the owning thread may destroy/free the Domain storage after close().
    /// - Internal component close() functions are called only from this method.
    pub fn close(self: *Self) void {
        if (self.closed.swap(true, .acq_rel)) return;
        // self.closed = true;

        self.logger.info("Closing Domain {d}...", .{self.id}, @src());
        self.running.store(false, .release); // = false;

        self.downstream.close();

        // Each transport closes itself (destructive close()): it is extracted
        // from the registry before closing, so no references are left behind.
        while (self.takeFirstTransport()) |transport| {
            transport.close();
        }

        self.upstream.close();

        while (self.takeFirstSubscriber()) |subscriber| {
            subscriber.close();
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

    //// ////////////////////////
    // Operations with subscribers
    //// ////////////////////////
    pub fn registerSubscriber(self: *Self, channel: u64, msgType: u64, subscriber: ifcSubscriber) !void {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        try self.registry.append(self.allocator, .{
            .channel = channel,
            .msgType = msgType,
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

    fn takeFirstSubscriber(self: *Self) ?ifcSubscriber {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        if (self.registry.items.len == 0) return null;

        const registration = self.registry.swapRemove(0);
        _ = self.subscriber_count.fetchSub(1, .monotonic);

        return registration.subscriber;
    }

    fn takeSubscriber(self: *Self, target: ifcSubscriber) ?ifcSubscriber {
        self.registry_lock.lock();
        defer self.registry_lock.unlock();

        var i: usize = 0;
        while (i < self.registry.items.len) : (i += 1) {
            if (self.registry.items[i].subscriber.ptr == target.ptr) {
                const registration = self.registry.swapRemove(i);
                _ = self.subscriber_count.fetchSub(1, .monotonic);

                return registration.subscriber;
            }
        }
        return null;
    }

    /// Coordinated close path for a registered subscriber: it extracts and
    /// closes it (same contract as the transports: one-shot destructive
    /// close(), self-unregistering). No-op if it was no longer registered.
    pub fn closeSubscriber(self: *Self, target: ifcSubscriber) void {
        const subscriber = self.takeSubscriber(target) orelse return;
        subscriber.close();
    }

    //// ////////////////////////
    // Operations with transports
    //// ////////////////////////
    /// Registers a transport: from here on the Domain uses it (downstream
    /// dispatch) and starts coordinating its close. It does NOT change its
    /// state: a started transport keeps running and a stopped one stays
    /// stopped (its manual enqueues work the same, registered or not).
    /// D1 contract (2026-09-10): a closed transport (close()) is never in the
    /// registry; calls on an already closed pointer are UB.
    pub fn registerTransport(self: *Self, transport: ifcTransport) !void {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        try self.transports.append(self.allocator, transport);
    }

    /// Unregisters a transport KEEPING its state (if it runs, it keeps
    /// running; it only stops receiving the Domain downstream; the user can
    /// still enqueue by hand). It does NOT close it: closing it remains the
    /// responsibility of its owner (close()). No-op if it was not registered.
    pub fn unregisterTransport(self: *Self, transport: ifcTransport) void {
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

    fn takeFirstTransport(self: *Self) ?ifcTransport {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        if (self.transports.items.len == 0) return null;

        return self.transports.swapRemove(0);
    }

    fn takeTransport(self: *Self, target: ifcTransport) ?ifcTransport {
        self.transport_lock.lock();
        defer self.transport_lock.unlock();

        var i: usize = 0;
        while (i < self.transports.items.len) : (i += 1) {
            if (self.transports.items[i].ptr == target.ptr) {
                return self.transports.swapRemove(i);
            }
        }

        return null;
    }

    /// Coordinated close path for a registered transport: it extracts it from
    /// the registry and closes it (one-shot destructive close()). The close()
    /// of the transport also tries to unregister, but here it is no longer
    /// there (no-op). No-op if it was no longer registered.
    pub fn closeTransport(self: *Self, target: ifcTransport) void {
        const transport = self.takeTransport(target) orelse return;

        transport.close();
    }

    //// ////////////////////////
    // Configs and other helpers
    //// ////////////////////////
    fn MakeDefaultAppConfigWithDomain(allocator: std.mem.Allocator, domain_id: u32) !Config.AppConfig {
        var app = try Config.AppConfig.initDefault(allocator);
        errdefer app.deinit(allocator);

        // initDefault() creates domains as an empty slice.
        // We replace it with a slice holding one default DomainConfig.
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

    fn GetDomainCfg(allocator: std.mem.Allocator, app_cfg: *Config.AppConfig, domain_id: u32) !Config.DomainConfig {
        for (app_cfg.domains) |dom| {
            if (dom.id == domain_id)
                return dom;
        }

        // Case "domain not present in app_cfg": it is created and ADDED to
        // app_cfg.domains, so that app_cfg.deinit() frees it. That way both
        // cases return a borrowed view of app_cfg (no ownership asymmetry
        // and no ad-hoc objects left unfreed).
        var dom = try Config.DomainConfig.initDefault(allocator);
        dom.id = @intCast(domain_id);

        app_cfg.domains = try allocator.realloc(
            app_cfg.domains,
            app_cfg.domains.len + 1,
        );
        app_cfg.domains[app_cfg.domains.len - 1] = dom;

        return dom;
    }

    /// Loads the domain encryption from a ZON key REGISTRY
    /// (sec/<algo>.zon.keyreg) + the key_id from the configuration.
    ///
    /// Policy (Guidelines 8, 2026-09-10): startup NEVER fails because of
    /// encryption. If the registry/key_id is missing, the id does not exist,
    /// the file cannot be read or the key is EXPIRED -> it starts UNENCRYPTED
    /// (in the clear) and WARNS through the logger. With a valid key ->
    /// encryption active and a warning if it expires soon.
    fn LoadCipher(self: *Self, dom_cfg: Config.DomainConfig) !void {
        const AVISO_DIAS: i64 = 7;

        const reg_file = dom_cfg.key_registry_file orelse {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: el dominio {d} no define key_registry_file", .{self.id}, @src());
            return;
        };

        if (!std.mem.endsWith(u8, reg_file, ".zon.keyreg")) {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: '{s}' no es un registro ZON (.zon.keyreg)", .{reg_file}, @src());
            return;
        }

        var registro = Security.KeyRegistry.legiElDosiero(self.allocator, reg_file, .TF_ZIG_ZON) catch |err| {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: no se pudo leer el registro '{s}': {s}", .{ reg_file, @errorName(err) }, @src());
            return;
        };
        defer registro.deinit(self.allocator);

        const key_id = dom_cfg.key_id orelse {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: '{s}' ({d} clave(s)) sin key_id en la configuracion", .{ reg_file, registro.keys.len }, @src());
            return;
        };

        const elegida = blk: {
            for (registro.keys) |*rec| {
                if (rec.key_id == key_id) break :blk rec;
            }
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: key_id {d} no esta en '{s}' ({d} clave(s))", .{ key_id, reg_file, registro.keys.len }, @src());
            return;
        };

        const ahora = std.time.timestamp();
        if (keyCaducada(elegida.expires_on, ahora)) {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: la clave {d} de '{s}' caduco el {s}", .{ key_id, reg_file, elegida.expires_on }, @src());
            return;
        }

        self.cipher = Cipher.create(self.allocator, elegida.*) catch |err| {
            self.cipher = try Cipher.createNoCipher(self.allocator);
            self.logger.warning("SIN CIFRAR: clave {d} invalida ({s})", .{ key_id, @errorName(err) }, @src());
            return;
        };

        self.logger.info("Cifrado activo: registro '{s}', clave {d}, modo {s}, caduca {s}", .{
            reg_file,
            key_id,
            @tagName(elegida.mode),
            elegida.expires_on,
        }, @src());

        const dias = diasHasta(elegida.expires_on, ahora);
        if (dias <= AVISO_DIAS) {
            self.logger.warning("CUIDADO: la clave {d} caduca en {d} dia(s) ({s})", .{ key_id, dias, elegida.expires_on }, @src());
        }
    }

    /// true if the ISO 8601 UTC timestamp is already in the past.
    fn keyCaducada(iso: []const u8, ahora: i64) bool {
        const t = isoAepoch(iso) orelse return false;
        return ahora >= t;
    }

    fn diasHasta(iso: []const u8, ahora: i64) i64 {
        const t = isoAepoch(iso) orelse return 0;
        return @divFloor(t - ahora, 24 * 60 * 60);
    }

    /// "YYYY-MM-DDTHH:MM:SSZ" -> epoch UTC (null if it does not fit).
    fn isoAepoch(iso: []const u8) ?i64 {
        if (iso.len != 20) return null;
        if (iso[4] != '-' or iso[7] != '-' or iso[10] != 'T' or iso[13] != ':' or iso[16] != ':' or iso[19] != 'Z') return null;

        const year = std.fmt.parseInt(u16, iso[0..4], 10) catch return null;
        const mes = std.fmt.parseInt(u8, iso[5..7], 10) catch return null;
        const dia = std.fmt.parseInt(u8, iso[8..10], 10) catch return null;
        const hora = std.fmt.parseInt(u8, iso[11..13], 10) catch return null;
        const min = std.fmt.parseInt(u8, iso[14..16], 10) catch return null;
        const seg = std.fmt.parseInt(u8, iso[17..19], 10) catch return null;
        if (mes < 1 or mes > 12 or dia < 1 or dia > 31) return null;
        if (hora > 23 or min > 59 or seg > 60) return null;

        const dias_mes = [12]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var dias: i64 = 0;
        var y: u16 = 1970;
        while (y < year) : (y += 1) dias += if (bisiesto(y)) 366 else 365;
        var m: u8 = 1;
        while (m < mes) : (m += 1) {
            dias += dias_mes[m - 1];
            if (m == 2 and bisiesto(year)) dias += 1;
        }
        dias += @as(i64, dia) - 1;
        return dias * 24 * 60 * 60 + @as(i64, hora) * 3600 + @as(i64, min) * 60 + seg;
    }

    fn bisiesto(year: u16) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    fn LoadTransports(self: *Self, dom_cfg: Config.DomainConfig) !void {
        // ========================================================================
        // Default transport
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
            try self.registerTransport(mcast.transport());
        }

        // ========================================================================
        // Configured transports
        // ========================================================================
        for (dom_cfg.transports) |tr_cfg| {
            const name = tr_cfg.name;
            switch (tr_cfg.kind) {
                .LOOP => {
                    const cfg = switch (tr_cfg.params) {
                        .loop => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    const loop_t = try LoopTransport.create(self, name, @intCast(cfg.delay_ms orelse 200));
                    try self.registerTransport(loop_t.transport());
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
                            @intCast(cfg.send_buffer orelse 1 * 1024 * 1024),
                            @intCast(cfg.receive_buffer orelse 1 * 1024 * 1024),
                        );
                    try self.registerTransport(mcast.transport());
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
                            @intCast(cfg.send_buffer orelse 1 * 1024 * 1024),
                            @intCast(cfg.receive_buffer orelse 1 * 1024 * 1024),
                        );
                    try self.registerTransport(bcast.transport());
                },

                .UDPSTAR => {
                    const cfg = switch (tr_cfg.params) {
                        .udpstar => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    var endpoints: std.ArrayList(EndPoint) = .empty;
                    defer endpoints.deinit(self.allocator);

                    for (cfg.end_points) |ep| {
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
                            @intCast(cfg.send_buffer orelse 1 * 1024 * 1024),
                            @intCast(cfg.receive_buffer orelse 1 * 1024 * 1024),
                        );
                    try self.registerTransport(udpstar.transport());
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
                            @intCast(cfg.send_buffer orelse 1 * 1024 * 1024),
                            @intCast(cfg.receive_buffer orelse 1 * 1024 * 1024),
                        );
                    try self.registerTransport(usoxstar.transport());
                },

                .MATRIX => {
                    const cfg = switch (tr_cfg.params) {
                        .matrix => |cfg| cfg,
                        else => return error.InvalidTransportConfig,
                    };
                    // BASE64 encoding is intrinsic to Matrix (its medium only
                    // accepts JSON): MatrixTransport sets it in the
                    // PacketProcessor, it is not configuration (see Encoding
                    // in packet_processor.zig).
                    const matrix_t =
                        try MatrixTransport.create(
                            self,
                            name,
                            cfg,
                        );
                    try self.registerTransport(matrix_t.transport());
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
        // Example:
        // CrossConnectors = {
        //   { T1 T2 T3 }
        //   { T4 T5 }
        // }
        // generates:
        // group1:
        //   T1 <-> T2
        //   T1 <-> T3
        //   T2 <-> T3
        // group2:
        //   T4 <-> T5

        self.transport_lock.lockShared();
        defer self.transport_lock.unlockShared();

        for (dom_cfg.cross_connectors) |xcc| {
            // Fewer than two transports makes no sense.
            if (xcc.transports.len < 2) continue;

            // Look up the transports of the group.
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

            // Create the full mesh.
            for (group.items) |src| {
                for (group.items) |dst| {
                    if (src.ptr == dst.ptr) continue;
                    // FUTURE:
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
    msgType: u64,
    subscriber: ifcSubscriber,
};
