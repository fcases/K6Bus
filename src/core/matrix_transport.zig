// ============================================================================
// MatrixTransport
// ============================================================================
//
// Transporte K6Bus sobre Matrix (protocolo cliente-server de Matrix.org).
// Sigue el patron de ciclo de vida de los transportes REALES (udp/usoxstar),
// NO el de LoopTransport (que es simulacion/pruebas):
//   - running atomico leido por el hilo RX (mainLoop) sin mutex;
//   - stop() = pck_processor.stop() + running=false + join();
//   - el hilo RX se sale SOLO cuando running cae; errores -> warning+reintento.
//
// Idea de diseno (validada con la PoC examples/matrix_poc, ya eliminada):
//
//   - Todas las instancias K6Bus comparten UN MISMO usuario de Matrix y
//     pertenecen a la misma sala (room).
//   - Cada instancia inicia sesion con ese usuario (cada login crea un
//     "device" distinto del mismo usuario).
//   - TX: los WireBytes (BASE64, codificacion intrinseca del transporte:
//     Matrix solo admite JSON) se envian como contenido de un evento custom:
//
//         type: "k6bus.wire"
//         content: { "b64": "<WireBytes base64>" }
//
//   - RX: polling de GET /_matrix/client/v3/sync filtrando desde su ultimo
//     next_batch (long-poll ~SYNC_TIMEOUT_MS). Los eventos k6bus.wire de la
//     sala se decodifican y se entregan a PacketProcessor.receiveBytes().
//   - DEDUP del eco propio: el eco de un evento enviado por ESTA instancia
//     llega en su propio /sync con unsigned.transaction_id (solo al device
//     emisor). Si el txn coincide con uno pendiente nuestro, se descarta.
//     Las demas instancias (mismo usuario, otros devices) reciben el mismo
//     evento SIN ese txn y lo aceptan.
//
// Memory: NADA de arenas: se usa directamente self.domain.allocator (como el
// resto de transportes) con liberacion explicita de cada asignacion.
// std.json.parseFromSlice gestiona su propio arena interno (Parsed.deinit()).
//
// Al arrancar se hace un sync inicial SIN "since" solo para obtener el
// next_batch base: el backlog historico de la sala NO se procesa (semantica
// de "solo lo que llega mientras la instancia esta viva", como un socket).
//
// Proxy: ProxyConfig opcional -> std.http.Client.https_proxy (CONNECT).
// Cifrado y codificacion: pertenecen al PacketProcessor, no a este transporte.
//
// Concurrencia:
//   - hilo TX: cola del QueueMgr del PacketProcessor llama a sendBytes().
//   - hilo RX: mainLoop hace el polling de /sync y entrega a receiveBytes().
//   - doHttp crea un std.http.Client por peticion: sin estado compartido
//     entre hilos (token de solo lectura tras start()).
//
// ============================================================================
const std = @import("std");

const PacketProcessor = @import("packet_processor.zig").PacketProcessor;
const Domain = @import("domain.zig").Domain;
const Logger = @import("logger.zig").Logger;
const ifcTransport = @import("ifc_transport.zig").ifcTransport;

const Config = @import("../generated/Config.zig").k6bus.config;
const Msg = @import("../generated/types.zig").k6bus.Msg;

const EVENT_TYPE = "k6bus.wire";
const DEFAULT_SERVER = "https://matrix.org";

/// Long-poll del /sync en ms (idle: una peticion vacia cada ~3 s). El join de
/// stop() queda acotado por el poll en curso (sin poder abortar el HTTP en
/// vuelo; lo mismo que el recv timeout de udp/usoxstar, pero a escala HTTP).
const SYNC_TIMEOUT_MS: u32 = 3000;
/// Backoff entre reintentos de sync tras un error transitorio.
const RETRY_BACKOFF_MS: u64 = 1000;
/// Maximo de transaction_id pendientes recordados para el dedup.
const MAX_OUTSTANDING_TXNS: usize = 512;

pub const MatrixTransport = struct {
    domain: *Domain,
    logger: *Logger = undefined,
    name: []const u8,

    pck_processor: PacketProcessor,

    // Copias propias de la configuracion (Directrices: todo componente que
    // conserve strings despues de init debe duplicarlos).
    server: []const u8,
    user: []const u8,
    password: []const u8,
    room: []const u8, // "#alias:server" o "!roomid:server"
    proxy: ?ProxyCopy = null,

    // Estado de ciclo de vida. Mismo patron que udp_transport/usoxstar:
    //   - running es ATOMICO: el hilo RX lo lee sin mutex en su while.
    //   - stopping + cond coordinan stop()/start() concurrentes.
    //   - stop() = pck_processor.stop() + running=false + join(): el hilo RX
    //     sale cuando el poll en curso termina (maximo ~SYNC_TIMEOUT_MS).
    rx_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
    stopping: bool = false,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    ifc_transport: ifcTransport,

    // Sesion Matrix (solo lectura despues de start()).
    token: []const u8 = "",
    device_id: []const u8 = "",
    room_id: []const u8 = "",

    // Solo lo toca el hilo RX (escritura) y start() antes de lanzarlo.
    next_batch: ?[]const u8 = null,
    /// Atómico: lo escribe el hilo RX y lo puede leer cualquiera (espera
    /// determinista antes de publicar; ver isInitialSyncDone()).
    initial_sync_done: std.atomic.Value(bool) = .init(false),

    // Txns pendientes (TX los anade, RX los consume). Bajo mutex.
    txn_list: std.ArrayList([]const u8) = .empty,
    txn_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(1),
    /// Marca de tiempo del arranque: hace que los txn sean UNICOS entre
    /// ejecuciones. Matrix trata PUT /send con un txn ya usado como
    /// idempotente y devuelve el evento ORIGINAL (antiguo, anterior al
    /// next_batch base -> invisible para el /sync). Con device_id
    /// determinista + contador reiniciado por arranque, los reenvios de cada
    /// nueva ejecucion eran no-ops (bug detectado en el E2E 2026-09-09):
    /// txn = "k6b{epoch_ms}-{contador}".
    txn_epoch_ms: u64 = 0,

    const Self = @This();

    /// Copia de ProxyConfig poseida por el transporte.
    pub const ProxyCopy = struct {
        server: []const u8,
        port: u16,
        user: ?[]const u8 = null,
        password: ?[]const u8 = null,
    };

    pub fn create(
        domain: *Domain,
        name: []const u8,
        cfg: Config.MatrixTransportConfig,
    ) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        try self.init(domain, name, cfg);

        self.logger = &domain.logger;

        return self;
    }

    fn init(
        self: *Self,
        domain: *Domain,
        name: []const u8,
        cfg: Config.MatrixTransportConfig,
    ) !void {
        self.domain = domain;

        const server = try domain.allocator.dupe(u8, trimServer(cfg.server));
        errdefer domain.allocator.free(server);
        const user = try domain.allocator.dupe(u8, cfg.user);
        errdefer domain.allocator.free(user);
        const password = try domain.allocator.dupe(u8, cfg.password);
        errdefer domain.allocator.free(password);
        const room = try domain.allocator.dupe(u8, cfg.room);
        errdefer domain.allocator.free(room);
        const duped_name = try domain.allocator.dupe(u8, name);
        errdefer domain.allocator.free(duped_name);

        var proxy_copy: ?ProxyCopy = null;
        if (cfg.proxy) |px| {
            const px_server = try domain.allocator.dupe(u8, px.server);
            errdefer domain.allocator.free(px_server);
            // Igual que la password del transporte: proxy.user/proxy.password
            // admiten literal directo o Base64 con prefijo "b64:" (se
            // decodifican al duplicar; el cfg no guarda credenciales en claro).
            const px_user = if (px.user) |u|
                try dupeOrDecode(domain.allocator, u)
            else
                null;
            errdefer if (px_user) |u| domain.allocator.free(u);
            const px_password = if (px.password) |p|
                try dupeOrDecode(domain.allocator, p)
            else
                null;
            errdefer if (px_password) |p| domain.allocator.free(p);

            proxy_copy = .{
                .server = px_server,
                .port = @intCast(px.port orelse 8080),
                .user = px_user,
                .password = px_password,
            };
        }

        self.name = duped_name;
        self.server = server;
        self.user = user;
        self.password = password;
        self.room = room;
        self.proxy = proxy_copy;

        self.pck_processor = undefined;
        self.mutex = .{};
        self.cond = .{};
        self.running = std.atomic.Value(bool).init(false);
        self.stopping = false;
        self.rx_thread = null;
        self.ifc_transport = undefined;

        self.token = "";
        self.device_id = "";
        self.room_id = "";
        self.next_batch = null;
        self.initial_sync_done = std.atomic.Value(bool).init(false);
        self.txn_list = .empty;
        self.txn_counter = std.atomic.Value(u64).init(1);
        self.txn_epoch_ms = @intCast(std.time.milliTimestamp());

        // El codificado BASE64 es una constante de DESARROLLO de este
        // transporte (su medio solo admite JSON), no configuracion.
        try self.pck_processor.init(domain, self.name, .MATRIX, .BASE64, self, sendBytes);
        self.ifc_transport = ifcTransport.init(self);
    }

    fn deinit(self: *Self) void {
        const alloc = self.domain.allocator;

        alloc.free(self.name);
        alloc.free(self.server);
        alloc.free(self.user);
        alloc.free(self.password);
        alloc.free(self.room);
        if (self.proxy) |px| {
            alloc.free(px.server);
            if (px.user) |u| alloc.free(u);
            if (px.password) |p| alloc.free(p);
        }
        if (self.token.len > 0) alloc.free(self.token);
        if (self.device_id.len > 0) alloc.free(self.device_id);
        if (self.room_id.len > 0) alloc.free(self.room_id);
        if (self.next_batch) |nb| alloc.free(nb);

        alloc.destroy(self);
    }

    fn trimServer(s: []const u8) []const u8 {
        while (s.len > 0 and s[s.len - 1] == '/') return s[0 .. s.len - 1];
        if (s.len == 0) return DEFAULT_SERVER;
        return s;
    }

    // ============================================================================
    // ifcTransport interface implementation
    // ============================================================================
    pub fn start(self: *Self) !void {
        self.mutex.lock();

        if (self.stopping) {
            self.mutex.unlock();
            return error.TransportStopping;
        }
        if (self.running.load(.acquire)) {
            self.mutex.unlock();
            return;
        }

        if (self.room.len == 0) {
            self.logger.err("{s} config.room vacio: se necesita '#alias' o '!roomid'.", .{self.name}, @src());
            self.mutex.unlock();
            return error.MatrixRoomRequired;
        }

        // Login + join (puede tardar ~1 s; start() se invoca en el arranque
        // del Domain, igual que udp/usoxstar preparan sus sockets aqui).
        self.login() catch |err| {
            self.logger.err("{s} login Matrix fallo: {s}", .{self.name, @errorName(err)}, @src());
            self.mutex.unlock();
            return err;
        };

        self.pck_processor.start() catch |err| {
            self.logger.err("{s} pck_processor.start fallo: {s}", .{self.name, @errorName(err)}, @src());
            self.mutex.unlock();
            return err;
        };

        self.running.store(true, .release);

        self.rx_thread = std.Thread.spawn(.{}, mainLoop, .{self}) catch |err| {
            self.running.store(false, .release);
            self.mutex.unlock();

            self.pck_processor.stop();
            return err;
        };

        self.mutex.unlock();
        self.logger.info("{s} started (matrix user={s} room={s} device={s}).", .{ self.name, self.user, self.room, self.device_id }, @src());
    }

    pub fn stop(self: *Self) void {
        self.mutex.lock();
        while (self.stopping) self.cond.wait(&self.mutex);

        if (!self.running.load(.acquire)) {
            self.mutex.unlock();
            return;
        }
        self.stopping = true;
        self.mutex.unlock();

        // Deja de aceptar mensajes nuevos; el hilo TX drena su cola.
        self.pck_processor.stop();

        // El hilo RX sale cuando el poll en curso termina
        // (maximo ~SYNC_TIMEOUT_MS, igual que udp/usoxstar salen por el
        // recv timeout: no se puede abortar el HTTP en vuelo).
        self.running.store(false, .release);
        self.join();

        self.mutex.lock();
        self.stopping = false;
        self.cond.broadcast();
        self.mutex.unlock();

        self.logger.info("{s} stopped.", .{self.name}, @src());
    }

    pub fn close(self: *Self) void {
        // Contrato de cierre (D1, 2026-09-10): close() es de UN SOLO USO y
        // destructivo (como free()): primero DESREGISTRA (asi el Domain ya no
        // tiene referencias; el lock exclusivo espera a los dispatch en vuelo),
        // luego para los hilos, libera recursos y libera el struct. Cualquier
        // llamada posterior sobre este puntero es UB, y llamar dos veces a
        // close() tambien lo es.
        self.domain.unregisterTransport(self.transport());

        self.stop();

        self.pck_processor.close();

        // Liberar txns pendientes que nunca fueron reconocidos.
        self.mutex.lock();
        for (self.txn_list.items) |t| self.domain.allocator.free(t);
        self.txn_list.deinit(self.domain.allocator);
        self.mutex.unlock();

        self.logger.info("matrixT {s} terminated.", .{self.name}, @src());
        self.deinit();
    }

    fn join(self: *Self) void {
        if (self.rx_thread) |t| {
            t.join();
        }
        self.rx_thread = null;
        self.logger.info("{s} rx_thread finished", .{self.name}, @src());
    }

    pub fn enqueue(self: *Self, msg: Msg) !void {
        try self.pck_processor.enqueue(msg);
    }

    pub fn enqueueMany(self: *Self, msg_list: []const Msg) !void {
        try self.pck_processor.enqueueMany(msg_list);
    }

    pub fn crossConnect(self: *Self, other: ifcTransport) !void {
        try self.pck_processor.crossConnect(other);
    }

    pub fn getName(self: *Self) []const u8 {
        return self.name;
    }

    /// Interfaz ifcTransport del transporte, para registrarlo/conectarlo/cerrarlo.
    /// Estilo: allocator = gpa.allocator()  ->  dom.registerTransport(t.transport()).
    pub fn transport(self: *Self) ifcTransport {
        return self.ifc_transport;
    }

    /// Consulta de estado (solo lectura): true cuando el sync inicial (el que
    /// fija el next_batch base) ya termino. Sirve para esperar de forma
    /// determinista antes de publicar: los eventos anteriores al baseline NO
    /// se procesan (semantica "solo lo vivo"), asi que en un E2E/publicador
    /// conviene esperar a esto en el receptor.
    pub fn isInitialSyncDone(self: *const Self) bool {
        return self.initial_sync_done.load(.acquire);
    }

    // ============================================================================
    // TX: sendBytes (llamado desde el hilo del QueueMgr del PacketProcessor)
    // ============================================================================
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));
        const alloc = self.domain.allocator;

        if (self.token.len == 0 or self.room_id.len == 0) {
            self.logger.warning("{s} sendBytes sin sesion lista; descartando {d} bytes", .{ self.name, wire_bytes.len }, @src());
            return false;
        }

        const txn_num = self.txn_counter.fetchAdd(1, .monotonic);
        const txn = std.fmt.allocPrint(alloc, "k6b{d}-{d}", .{ self.txn_epoch_ms, txn_num }) catch return false;
        defer alloc.free(txn);

        const room_enc = pctEncode(alloc, self.room_id) catch return false;
        defer alloc.free(room_enc);

        const url = std.fmt.allocPrint(
            alloc,
            "{s}/_matrix/client/v3/rooms/{s}/send/{s}/{s}",
            .{ self.server, room_enc, EVENT_TYPE, txn },
        ) catch return false;
        defer alloc.free(url);

        // wire_bytes es BASE64 (codificacion intrinseca del transporte): no
        // necesita escapes JSON.
        const content = std.fmt.allocPrint(alloc, "{{\"b64\":\"{s}\"}}", .{wire_bytes}) catch return false;
        defer alloc.free(content);

        const resp = self.doHttp(.PUT, url, content) catch |err| {
            self.logger.warning("{s} PUT send fallo: {s}", .{self.name, @errorName(err)}, @src());
            return false;
        };
        defer alloc.free(resp.body);
        if (!is2xx(resp.status)) {
            self.logger.warning("{s} PUT send HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
            return false;
        }

        // Recordar el txn para descartar el eco propio en el /sync.
        self.rememberTxn(txn);

        self.logger.trace("{s} sent {d} bytes (txn {s})", .{ self.name, wire_bytes.len, txn }, @src());
        return true;
    }

    fn rememberTxn(self: *Self, txn: []const u8) void {
        const duped = self.domain.allocator.dupe(u8, txn) catch return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.txn_list.items.len >= MAX_OUTSTANDING_TXNS) {
            // El eco no llego (p.ej. reinicio de sesion): descartar el mas viejo.
            self.logger.warning("{s} txn pendientes al limite; olvidando el mas antiguo", .{self.name}, @src());
            const old = self.txn_list.orderedRemove(0);
            self.domain.allocator.free(old);
        }
        self.txn_list.append(self.domain.allocator, duped) catch {
            self.domain.allocator.free(duped);
        };
    }

    /// Si el txn es nuestro (eco propio), lo consume y devuelve true.
    fn consumeOwnTxn(self: *Self, txn: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.txn_list.items.len) : (i += 1) {
            if (std.mem.eql(u8, self.txn_list.items[i], txn)) {
                const owned = self.txn_list.orderedRemove(i);
                self.domain.allocator.free(owned);
                return true;
            }
        }
        return false;
    }

    // ============================================================================
    // RX: hilo de polling de /sync
    // ============================================================================
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        // Mismo patron que udp/usoxstar mainLoop: se sale SOLO cuando
        // running cae (stop()); los errores se registran y se reintentan.
        while (self.running.load(.acquire)) {
            self.syncOnce() catch |err| {
                if (!self.running.load(.acquire)) break;

                self.logger.warning("{s} sync error {s}; reintentando en {d} ms", .{ self.name, @errorName(err), RETRY_BACKOFF_MS }, @src());
                std.Thread.sleep(RETRY_BACKOFF_MS * std.time.ns_per_ms);
            };
        }

        self.logger.info("{s} salida de while en mainLoop", .{self.name}, @src());
    }

    fn syncOnce(self: *Self) !void {
        const alloc = self.domain.allocator;

        const since = self.next_batch;

        var url: std.ArrayList(u8) = .empty;
        defer url.deinit(alloc);
        try url.appendSlice(alloc, self.server);
        try url.appendSlice(alloc, "/_matrix/client/v3/sync?timeout=");
        var tbuf: [16]u8 = undefined;
        const tstr = try std.fmt.bufPrint(&tbuf, "{d}", .{SYNC_TIMEOUT_MS});
        try url.appendSlice(alloc, tstr);
        if (since) |s| {
            try url.appendSlice(alloc, "&since=");
            const enc = try pctEncode(alloc, s);
            defer alloc.free(enc);
            try url.appendSlice(alloc, enc);
        }

        const resp = try self.doHttp(.GET, url.items, null);
        defer alloc.free(resp.body);
        if (resp.status == 401) {
            self.logger.warning("{s} sync 401: token invalido", .{self.name}, @src());
            return;
        }
        if (!is2xx(resp.status)) {
            self.logger.warning("{s} sync HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
            return;
        }

        var parsed = std.json.parseFromSlice(std.json.Value, alloc, resp.body, .{}) catch |err| {
            self.logger.warning("{s} sync JSON invalido: {s}", .{self.name, @errorName(err)}, @src());
            return;
        };
        defer parsed.deinit();

        // next_batch -> copia de larga vida.
        if (parsed.value.object.get("next_batch")) |nb| {
            if (self.next_batch) |old| alloc.free(old);
            self.next_batch = try alloc.dupe(u8, nb.string);
        }

        // El primer sync (sin since) solo fija el next_batch base: el backlog
        // historico de la sala NO se procesa.
        if (!self.initial_sync_done.load(.acquire)) {
            self.initial_sync_done.store(true, .release);
            self.logger.info("{s} sync inicial OK, next_batch=...{s}", .{ self.name, self.next_batch.?[self.next_batch.?.len - 8 ..] }, @src());
            return;
        }

        // Procesar eventos k6bus.wire de nuestra sala. Las slices de los
        // eventos (b64, txn) viven en el arbol 'parsed' (vivo hasta el final
        // de esta funcion); receiveBytes() las consume sincronamente.
        var processed: usize = 0;
        var timeline_total: usize = 0;
        var room_found = false;
        if (parsed.value.object.get("rooms")) |rooms| {
            if (rooms.object.get("join")) |join_map| {
                if (join_map.object.get(self.room_id)) |room| {
                    room_found = true;
                    if (room.object.get("timeline")) |timeline| {
                        if (timeline.object.get("events")) |evs| {
                            timeline_total = evs.array.items.len;
                            for (evs.array.items) |ev| {
                                if (!self.handleEvent(ev)) continue;
                                processed += 1;
                            }
                        }
                    }
                }
            }
        }
        self.logger.trace("{s} sync: sala={} timeline={d} k6bus.wire procesados={d}", .{ self.name, room_found, timeline_total, processed }, @src());
        if (processed > 0) {
            self.logger.trace("{s} sync procesados {d} evento(s) k6bus.wire", .{ self.name, processed }, @src());
        }
    }

    /// Devuelve true si el evento era nuestro (consumido), false si era ajeno.
    fn handleEvent(self: *Self, ev: std.json.Value) bool {
        const evt = ev.object;

        const etype = (evt.get("type") orelse return false).string;
        if (!std.mem.eql(u8, etype, EVENT_TYPE)) return false;

        // Dedup por transaction_id: el eco propio trae el txn que usamos.
        if (evt.get("unsigned")) |unsigned| {
            if (unsigned.object.get("transaction_id")) |txn_val| {
                const txn = txn_val.string;
                if (self.consumeOwnTxn(txn)) {
                    self.logger.trace("{s} eco propio descartado (txn {s})", .{ self.name, txn }, @src());
                    return false;
                }
            }
        }

        const evid: []const u8 = if (evt.get("event_id")) |e| e.string else "?";

        const content = evt.get("content") orelse {
            self.logger.warning("{s} evento k6bus.wire sin content", .{self.name}, @src());
            return false;
        };
        const b64 = content.object.get("b64") orelse {
            self.logger.warning("{s} evento k6bus.wire sin content.b64", .{self.name}, @src());
            return false;
        };

        self.logger.trace("{s} evento ajeno aceptado ev=...{s} ({d} bytes b64)", .{ self.name, evid[evid.len - @min(evid.len, 8) ..], b64.string.len }, @src());

        // Entregar a PacketProcessor (decodifica/descifra/deserializa y sube
        // al Domain). wire_bytes solo se usa durante la llamada.
        self.pck_processor.receiveBytes(b64.string) catch |err| switch (err) {
            error.DomainClosed => return false,
            else => {
                self.logger.warning("{s} receiveBytes fallo: {s}", .{self.name, @errorName(err)}, @src());
                return false;
            },
        };
        return true;
    }

    // ============================================================================
    // Sesion Matrix: login + join
    // ============================================================================
    fn login(self: *Self) !void {
        const alloc = self.domain.allocator;

        const device_name = try self.makeDeviceId(alloc);
        defer alloc.free(device_name);

        // La password puede venir directa o en Base64 (prefijo "b64:", costumbre
        // del proyecto: el cfg no guarda el password en claro). Se decodifica
        // antes de enviarla al login.
        const pw = self.resolvePassword(alloc) catch |err| {
            self.logger.err("{s} password 'b64:' invalida: {s}", .{ self.name, @errorName(err) }, @src());
            return error.MatrixPasswordDecodeFailed;
        };
        defer if (pw.ptr != self.password.ptr) alloc.free(pw);

        // {"identifier":{"type":"m.id.user","user":...},"password":...,
        //  "initial_device_display_name":...,"device_id":...,"type":"m.login.password"}
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(alloc);
        try body.appendSlice(alloc, "{\"identifier\":{\"type\":\"m.id.user\",\"user\":");
        try escJsonAppend(alloc, &body, self.user);
        try body.appendSlice(alloc, "},\"password\":");
        try escJsonAppend(alloc, &body, pw);
        try body.appendSlice(alloc, ",\"initial_device_display_name\":");
        try escJsonAppend(alloc, &body, self.name);
        try body.appendSlice(alloc, ",\"device_id\":");
        try escJsonAppend(alloc, &body, device_name);
        try body.appendSlice(alloc, ",\"type\":\"m.login.password\"}");

        const url = try std.fmt.allocPrint(alloc, "{s}/_matrix/client/v3/login", .{self.server});
        defer alloc.free(url);

        const resp = try self.doHttp(.POST, url, body.items);
        defer alloc.free(resp.body);
        if (!is2xx(resp.status)) {
            self.logger.err("{s} login HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
            return error.MatrixLoginFailed;
        }

        var parsed = std.json.parseFromSlice(std.json.Value, alloc, resp.body, .{}) catch |err| {
            self.logger.err("{s} login JSON invalido: {s}", .{self.name, @errorName(err)}, @src());
            return error.MatrixLoginFailed;
        };
        defer parsed.deinit();

        const token = (parsed.value.object.get("access_token") orelse return error.MatrixLoginFailed).string;
        const device_id = (parsed.value.object.get("device_id") orelse return error.MatrixLoginFailed).string;
        const user_id = if (parsed.value.object.get("user_id")) |u| u.string else "";

        self.token = try alloc.dupe(u8, token);
        self.device_id = try alloc.dupe(u8, device_id);

        self.logger.info("{s} login OK: {s} device={s}", .{ self.name, user_id, device_id }, @src());

        // Unirse a la sala configurada (alias '#...' o id '!...').
        try self.joinRoom();
    }

    /// device_id por ARRANQUE: prefijo legible del transporte + epoch en hex.
    ///
    /// NO se reutiliza entre ejecuciones a proposito: Synapse cachea las
    /// respuestas de /sync por device, asi que un device reutilizado puede
    /// devolver un initial sync CACHEADO (baseline viejo) y el transporte
    /// recibiria como "nuevos" eventos antiguos (defecto detectado 2026-09-10
    /// en el E2E: 3 eventos viejos replayed). Con device nuevo el baseline es
    /// siempre fresco. Coste: se acumulan devices en la cuenta (deuda R9:
    /// hacer logout al cerrar para limpiarlos). Solo [A-Za-z0-9._-].
    fn makeDeviceId(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(alloc);
        try out.appendSlice(alloc, "k6bus");
        for (self.name) |c| {
            const ok = std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.';
            if (ok and out.items.len < 40) try out.append(alloc, c);
        }
        var buf: [24]u8 = undefined;
        const suf = try std.fmt.bufPrint(&buf, "-{x}", .{self.txn_epoch_ms});
        try out.appendSlice(alloc, suf);
        return out.toOwnedSlice(alloc);
    }

    /// Password lista para el login:
    ///   - "b64:<base64>" -> copia decodificada (owned, el caller la libera);
    ///   - cualquier otro literal -> se usa tal cual (borrowed).
    /// El prefijo "b64:" permite guardar el password en Base64 en el fichero
    /// de configuracion sin dejarlo en claro, manteniendo compatibilidad con
    /// configs que ya usan el literal directo.
    fn resolvePassword(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
        if (std.mem.startsWith(u8, self.password, "b64:")) {
            return try decodeB64(alloc, self.password[4..]);
        }
        return self.password;
    }

    fn joinRoom(self: *Self) !void {
        const alloc = self.domain.allocator;

        const enc = try pctEncode(alloc, self.room);
        defer alloc.free(enc);

        const url = try std.fmt.allocPrint(alloc, "{s}/_matrix/client/v3/join/{s}", .{ self.server, enc });
        defer alloc.free(url);

        const resp = try self.doHttp(.POST, url, "{}");
        defer alloc.free(resp.body);
        if (is2xx(resp.status)) {
            var parsed = try std.json.parseFromSlice(std.json.Value, alloc, resp.body, .{});
            defer parsed.deinit();
            const rid = (parsed.value.object.get("room_id") orelse return error.MatrixJoinFailed).string;
            self.room_id = try alloc.dupe(u8, rid);
            self.logger.info("{s} join OK: {s} -> {s}", .{ self.name, self.room, rid }, @src());
            return;
        }

        // Join fallo (403: no miembro / no publica). Para alias probamos
        // resolver por directory y damos un error claro.
        if (self.room.len > 0 and self.room[0] == '#') {
            const durl = try std.fmt.allocPrint(alloc, "{s}/_matrix/client/v3/directory/room/{s}", .{ self.server, enc });
            defer alloc.free(durl);

            const dresp = try self.doHttp(.GET, durl, null);
            defer alloc.free(dresp.body);
            if (is2xx(dresp.status)) {
                var dparsed = try std.json.parseFromSlice(std.json.Value, alloc, dresp.body, .{});
                defer dparsed.deinit();
                const rid = (dparsed.value.object.get("room_id") orelse return error.MatrixJoinFailed).string;
                self.room_id = try alloc.dupe(u8, rid);
                self.logger.info("{s} miembro de {s} -> {s} (room_id por directory)", .{ self.name, self.room, rid }, @src());
                return;
            }
        }
        self.logger.err("{s} join fallo HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
        return error.MatrixJoinFailed;
    }

    // ============================================================================
    // HTTP (un std.http.Client por peticion; TLS integrado en Zig 0.15)
    // ============================================================================
    const HttpResult = struct {
        status: u16,
        body: []const u8, // owned por el caller (domain.allocator)
    };

    fn doHttp(
        self: *Self,
        method: std.http.Method,
        url: []const u8,
        payload: ?[]const u8,
    ) !HttpResult {
        const alloc = self.domain.allocator;

        var client = std.http.Client{ .allocator = alloc };
        defer client.deinit();

        // Proxy opcional (CONNECT para https).
        var proxy_obj: ?std.http.Client.Proxy = null;
        if (self.proxy) |px| {
            var auth: ?[]const u8 = null;
            if (px.user) |u| {
                const up = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ u, px.password orelse "" });
                defer alloc.free(up);
                const b64 = try encodeB64(alloc, up);
                defer alloc.free(b64);
                auth = try std.fmt.allocPrint(alloc, "Basic {s}", .{b64});
            }
            defer if (auth) |a| alloc.free(a);
            proxy_obj = .{
                .protocol = .plain,
                .host = px.server,
                .authorization = auth,
                .port = px.port,
                .supports_connect = true,
            };
        }
        if (proxy_obj) |*p| client.https_proxy = p;

        const uri = try std.Uri.parse(url);

        var auth_hdr: ?[]const u8 = null;
        defer if (auth_hdr) |a| alloc.free(a);
        if (self.token.len > 0) {
            auth_hdr = try std.fmt.allocPrint(alloc, "Bearer {s}", .{self.token});
        }

        var req = try client.request(method, uri, .{
            .redirect_behavior = .unhandled,
            .headers = .{
                .accept_encoding = .{ .override = "identity" },
                .content_type = if (payload != null) .{ .override = "application/json" } else .omit,
                .authorization = if (auth_hdr) |a| .{ .override = a } else .omit,
                .user_agent = .{ .override = "k6bus-matrix/0.1" },
            },
        });
        defer req.deinit();

        if (payload) |p| {
            req.transfer_encoding = .{ .content_length = p.len };
            var bw = try req.sendBodyUnflushed(&.{});
            try bw.writer.writeAll(p);
            try bw.end();
            try req.connection.?.flush();
        } else {
            try req.sendBodiless();
        }

        var response = try req.receiveHead(&.{});
        const status: u16 = @intFromEnum(response.head.status);

        var transfer_buf: [512]u8 = undefined;
        const reader = response.reader(&transfer_buf);
        const body = try reader.allocRemaining(alloc, .unlimited);

        return .{ .status = status, .body = body };
    }

    fn is2xx(status: u16) bool {
        return status >= 200 and status < 300;
    }
};

// ============================================================================
// Helpers libres
// ============================================================================

/// Percent-encode (los ids/aliases de Matrix llevan '!', '#', ':').
/// Devuelve una slice owned (liberar con allocator.free).
fn pctEncode(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const hex = "0123456789ABCDEF";
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (s) |c| {
        const safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~';
        if (safe) {
            try out.append(allocator, c);
        } else {
            try out.append(allocator, '%');
            try out.append(allocator, hex[c >> 4]);
            try out.append(allocator, hex[c & 0x0f]);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Anade a `out` el string `s` escapado como string JSON (con comillas).
fn escJsonAppend(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

fn encodeB64(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const b64 = std.base64.standard;
    const enc_len = b64.Encoder.calcSize(data.len);
    const buf = try allocator.alloc(u8, enc_len);
    _ = b64.Encoder.encode(buf, data);
    return buf;
}

/// Duplica `s` tal cual, o si empieza por "b64:" devuelve la decodificacion
/// (owned en ambos casos). Usado para las credenciales del proxy.
fn dupeOrDecode(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, s, "b64:")) {
        return try decodeB64(allocator, s[4..]);
    }
    return allocator.dupe(u8, s);
}

/// Decodifica base64 estandar (con padding). Devuelve slice owned.
fn decodeB64(allocator: std.mem.Allocator, code: []const u8) ![]const u8 {
    const b64 = std.base64.standard;
    const dec_len = try b64.Decoder.calcSizeForSlice(code);
    const buf = try allocator.alloc(u8, dec_len);
    try b64.Decoder.decode(buf, code);
    return buf;
}
