// ============================================================================
// MatrixTransport
// ============================================================================
//
// K6Bus transport over Matrix (Matrix.org client-server protocol).
// Follows the lifecycle pattern of the REAL transports (udp/usoxstar),
// NOT the LoopTransport one (which is simulation/testing):
//   - atomic running, read by the RX thread (mainLoop) without a mutex;
//   - stop() = pck_processor.stop() + running=false + join();
//   - the RX thread exits ONLY when running drops; errors -> warn+retry.
//
// Design idea (validated with the PoC examples/matrix_poc, now removed):
//
//   - All K6Bus instances share ONE SINGLE Matrix user and
//     belong to the same room.
//   - Each instance logs in with that user (each login creates a
//     different "device" of the same user).
//   - TX: the WireBytes (BASE64, intrinsic encoding of the transport:
//     Matrix only accepts JSON) are sent as the content of a custom event:
//
//         type: "k6bus.wire"
//         content: { "b64": "<WireBytes base64>" }
//
//   - RX: polling of GET /_matrix/client/v3/sync filtered from its last
//     next_batch (long-poll ~SYNC_TIMEOUT_MS). The k6bus.wire events of
//     the room are decoded and delivered to PacketProcessor.receiveBytes().
//   - DEDUP of our own echo: the echo of an event sent by THIS instance
//     arrives on its own /sync with unsigned.transaction_id (only to the
//     sending device). If the txn matches one of our pending ones, dropped.
//     The other instances (same user, other devices) receive the same
//     event WITHOUT that txn and accept it.
//
// Memory: NO arenas: self.domain.allocator is used directly (like the
// rest of the transports) with explicit free of every allocation.
// std.json.parseFromSlice manages its own internal arena (Parsed.deinit()).
//
// At startup an initial sync WITHOUT "since" is done only to obtain the
// base next_batch: the historical room backlog is NOT processed ("only
// what arrives while the instance is alive" semantics, like a socket).
//
// Proxy: optional ProxyConfig -> std.http.Client.https_proxy (CONNECT).
// Encryption and encoding: belong to the PacketProcessor, not this transport.
//
// Concurrency:
//   - TX thread: QueueMgr queue of the PacketProcessor calls sendBytes().
//   - RX thread: mainLoop polls /sync and delivers to receiveBytes().
//   - doHttp creates one std.http.Client per request: no shared state
//     between threads (token is read-only after start()).
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

/// Long-poll of /sync in ms (idle: one empty request every ~3 s). The join of
/// stop() is bounded by the poll in flight (the in-flight HTTP cannot be
/// aborted; same as the recv timeout of udp/usoxstar, but at HTTP scale).
const SYNC_TIMEOUT_MS: u32 = 3000;
/// Backoff between sync retries after a transient error.
const RETRY_BACKOFF_MS: u64 = 1000;
/// Maximum of pending transaction_id remembered for the dedup.
const MAX_OUTSTANDING_TXNS: usize = 512;

pub const MatrixTransport = struct {
    domain: *Domain,
    logger: *Logger = undefined,
    name: []const u8,

    pck_processor: PacketProcessor,

    // Own copies of the configuration (Guidelines: every component that
    // keeps strings after init must duplicate them).
    server: []const u8,
    user: []const u8,
    password: []const u8,
    room: []const u8, // "#alias:server" or "!roomid:server"
    proxy: ?ProxyCopy = null,

    // Lifecycle state. Same pattern as udp_transport/usoxstar:
    //   - running is ATOMIC: the RX thread reads it mutex-free in its while.
    //   - stopping + cond coordinate concurrent stop()/start() calls.
    //   - stop() = pck_processor.stop() + running=false + join(): the RX
    //     thread exits when the poll in flight ends (at most ~SYNC_TIMEOUT_MS).
    rx_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
    stopping: bool = false,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    ifc_transport: ifcTransport,

    // Matrix session (read-only after start()).
    token: []const u8 = "",
    device_id: []const u8 = "",
    room_id: []const u8 = "",

    // Only the RX thread touches it (write) and start() before launching it.
    next_batch: ?[]const u8 = null,
    /// Atomic: written by the RX thread and readable by anyone (a
    /// deterministic wait before publishing; see isInitialSyncDone()).
    initial_sync_done: std.atomic.Value(bool) = .init(false),

    // Pending txns (TX adds them, RX consumes them). Under mutex.
    txn_list: std.ArrayList([]const u8) = .empty,
    txn_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(1),
    /// Startup timestamp: makes the txn UNIQUE across runs. Matrix treats a
    /// PUT /send that carries an already used txn as idempotent and returns
    /// the ORIGINAL event back (old, earlier than the base next_batch ->
    /// invisible to the /sync). With a deterministic device_id plus a
    /// counter that is restarted on every run, the resends of each new run
    /// were no-ops (bug detected in the E2E 2026-09-09): the txn is
    /// "k6b{epoch_ms}-{counter}".
    txn_epoch_ms: u64 = 0,

    const Self = @This();

    /// ProxyConfig copy owned by the transport.
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
            // Same as the transport password: proxy.user/proxy.password
            // accept a direct literal or Base64 with the "b64:" prefix
            // (they are decoded on dupe; the cfg keeps no plaintext creds).
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

        // The BASE64 encoding is a DEVELOPMENT constant of this
        // transport (its medium only accepts JSON), not configuration.
        try self.pck_processor.init(domain, self.name, .BASE64, self, sendBytes);
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
            self.logger.err("{s} empty config.room: an '#alias' or '!roomid' is required.", .{self.name}, @src());
            self.mutex.unlock();
            return error.MatrixRoomRequired;
        }

        // Login + join (may take ~1 s; start() is invoked at Domain
        // startup, just as udp/usoxstar prepare their sockets here).
        self.login() catch |err| {
            self.logger.err("{s} Matrix login failed: {s}", .{self.name, @errorName(err)}, @src());
            self.mutex.unlock();
            return err;
        };

        self.pck_processor.start() catch |err| {
            self.logger.err("{s} pck_processor.start failed: {s}", .{self.name, @errorName(err)}, @src());
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

        // Stop accepting new messages; the TX thread drains its queue.
        self.pck_processor.stop();

        // The RX thread exits when the poll in flight finishes
        // (at most ~SYNC_TIMEOUT_MS, same as udp/usoxstar exiting via the
        // recv timeout: the in-flight HTTP cannot be aborted).
        self.running.store(false, .release);
        self.join();

        self.mutex.lock();
        self.stopping = false;
        self.cond.broadcast();
        self.mutex.unlock();

        self.logger.info("{s} stopped.", .{self.name}, @src());
    }

    pub fn close(self: *Self) void {
        // Close contract (D1, 2026-09-10): close() is SINGLE USE and
        // destructive (like free()): first it UNREGISTERS (the Domain then
        // holds no references; the exclusive lock waits for dispatches in
        // flight), then stops the threads, frees resources and frees the
        // struct. Any later call on this pointer is UB, and calling close()
        // twice is UB too.
        self.domain.unregisterTransport(self.transport());

        self.stop();

        self.pck_processor.close();

        // Free pending txns that were never acknowledged.
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

    /// The transport's ifcTransport interface, to register/connect/close it.
    /// Style: allocator = gpa.allocator()  ->  dom.registerTransport(t.transport()).
    pub fn transport(self: *Self) ifcTransport {
        return self.ifc_transport;
    }

    /// Status query (read-only): true when the initial sync (the one that
    /// sets the base next_batch) has already finished. It is used to wait in
    /// a deterministic way before publishing: events before the baseline are
    /// NOT processed ("only live" semantics), so in an E2E/publisher it is
    /// advisable to wait for this on the receiver side.
    pub fn isInitialSyncDone(self: *const Self) bool {
        return self.initial_sync_done.load(.acquire);
    }

    // ============================================================================
    // TX: sendBytes (called from the PacketProcessor QueueMgr thread)
    // ============================================================================
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));
        const alloc = self.domain.allocator;

        if (self.token.len == 0 or self.room_id.len == 0) {
            self.logger.warning("{s} sendBytes with no ready session; dropping {d} bytes", .{ self.name, wire_bytes.len }, @src());
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

        // wire_bytes is BASE64 (the transport's intrinsic encoding): it needs
        // no JSON escapes.
        const content = std.fmt.allocPrint(alloc, "{{\"b64\":\"{s}\"}}", .{wire_bytes}) catch return false;
        defer alloc.free(content);

        const resp = self.doHttp(.PUT, url, content) catch |err| {
            self.logger.warning("{s} PUT send failed: {s}", .{self.name, @errorName(err)}, @src());
            return false;
        };
        defer alloc.free(resp.body);
        if (!is2xx(resp.status)) {
            self.logger.warning("{s} PUT send HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
            return false;
        }

        // Remember the txn to discard our own echo in the /sync.
        self.rememberTxn(txn);

        self.logger.trace("{s} sent {d} bytes (txn {s})", .{ self.name, wire_bytes.len, txn }, @src());
        return true;
    }

    fn rememberTxn(self: *Self, txn: []const u8) void {
        const duped = self.domain.allocator.dupe(u8, txn) catch return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.txn_list.items.len >= MAX_OUTSTANDING_TXNS) {
            // The echo never arrived (e.g. session restart): drop the oldest.
            self.logger.warning("{s} pending txns at the limit; forgetting the oldest one", .{self.name}, @src());
            const old = self.txn_list.orderedRemove(0);
            self.domain.allocator.free(old);
        }
        self.txn_list.append(self.domain.allocator, duped) catch {
            self.domain.allocator.free(duped);
        };
    }

    /// If the txn is ours (our own echo), it consumes it and returns true.
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
    // RX: /sync polling thread
    // ============================================================================
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        // Same pattern as the udp/usoxstar mainLoop: it exits ONLY when
        // running drops (stop()); errors are logged and retried.
        while (self.running.load(.acquire)) {
            self.syncOnce() catch |err| {
                if (!self.running.load(.acquire)) break;

                self.logger.warning("{s} sync error {s}; retrying in {d} ms", .{ self.name, @errorName(err), RETRY_BACKOFF_MS }, @src());
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
            self.logger.warning("{s} sync 401: invalid token", .{self.name}, @src());
            return;
        }
        if (!is2xx(resp.status)) {
            self.logger.warning("{s} sync HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
            return;
        }

        var parsed = std.json.parseFromSlice(std.json.Value, alloc, resp.body, .{}) catch |err| {
            self.logger.warning("{s} invalid sync JSON: {s}", .{self.name, @errorName(err)}, @src());
            return;
        };
        defer parsed.deinit();

        // next_batch -> long-lived copy.
        if (parsed.value.object.get("next_batch")) |nb| {
            if (self.next_batch) |old| alloc.free(old);
            self.next_batch = try alloc.dupe(u8, nb.string);
        }

        // The first sync (no since) only sets the base next_batch: the
        // historical room backlog is NOT processed.
        if (!self.initial_sync_done.load(.acquire)) {
            self.initial_sync_done.store(true, .release);
            self.logger.info("{s} sync inicial OK, next_batch=...{s}", .{ self.name, self.next_batch.?[self.next_batch.?.len - 8 ..] }, @src());
            return;
        }

        // Process the k6bus.wire events of our room. The slices of the
        // events (b64, txn) live in the 'parsed' tree (alive until the end
        // of this function); receiveBytes() consumes them synchronously.
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

    /// Returns true if the event was ours (consumed), false if it was foreign.
    fn handleEvent(self: *Self, ev: std.json.Value) bool {
        const evt = ev.object;

        const etype = (evt.get("type") orelse return false).string;
        if (!std.mem.eql(u8, etype, EVENT_TYPE)) return false;

        // Dedup by transaction_id: our own echo carries the txn we used.
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
            self.logger.warning("{s} k6bus.wire event with no content", .{self.name}, @src());
            return false;
        };
        const b64 = content.object.get("b64") orelse {
            self.logger.warning("{s} k6bus.wire event with no content.b64", .{self.name}, @src());
            return false;
        };

        self.logger.trace("{s} evento ajeno aceptado ev=...{s} ({d} bytes b64)", .{ self.name, evid[evid.len - @min(evid.len, 8) ..], b64.string.len }, @src());

        // Deliver to PacketProcessor (decodes/decrypts/deserializes and
        // pushes to the Domain). wire_bytes is only used during the call.
        self.pck_processor.receiveBytes(b64.string) catch |err| switch (err) {
            error.DomainClosed => return false,
            else => {
                self.logger.warning("{s} receiveBytes failed: {s}", .{self.name, @errorName(err)}, @src());
                return false;
            },
        };
        return true;
    }

    // ============================================================================
    // Matrix session: login + join
    // ============================================================================
    fn login(self: *Self) !void {
        const alloc = self.domain.allocator;

        const device_name = try self.makeDeviceId(alloc);
        defer alloc.free(device_name);

        // The password may come direct or in Base64 ("b64:" prefix, a
        // project custom: the cfg does not store the password in plaintext).
        // It is decoded before being sent to the login.
        const pw = self.resolvePassword(alloc) catch |err| {
            self.logger.err("{s} invalid 'b64:' password: {s}", .{ self.name, @errorName(err) }, @src());
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
            self.logger.err("{s} invalid login JSON: {s}", .{self.name, @errorName(err)}, @src());
            return error.MatrixLoginFailed;
        };
        defer parsed.deinit();

        const token = (parsed.value.object.get("access_token") orelse return error.MatrixLoginFailed).string;
        const device_id = (parsed.value.object.get("device_id") orelse return error.MatrixLoginFailed).string;
        const user_id = if (parsed.value.object.get("user_id")) |u| u.string else "";

        self.token = try alloc.dupe(u8, token);
        self.device_id = try alloc.dupe(u8, device_id);

        self.logger.info("{s} login OK: {s} device={s}", .{ self.name, user_id, device_id }, @src());

        // Join the configured room (alias '#...' or id '!...').
        try self.joinRoom();
    }

    /// device_id per STARTUP: readable transport prefix + epoch in hex.
    ///
    /// It is NOT reused across runs on purpose: Synapse caches the
    /// /sync responses per device, so a reused device may return a CACHED
    /// initial sync (old baseline) and the transport would receive the old
    /// events as "new" ones (defect detected 2026-09-10 in the E2E:
    /// 3 old events replayed). With a new device the baseline is always
    /// fresh. Cost: devices pile up in the account (R9 debt: do a
    /// logout on close to clean them up). Only [A-Za-z0-9._-].
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

    /// Password ready for the login:
    ///   - "b64:<base64>" -> decoded copy (owned, the caller frees it);
    ///   - any other literal -> used as is (borrowed).
    /// The "b64:" prefix allows storing the password in Base64 in the
    /// configuration file without leaving it in plaintext, keeping
    /// compatibility with configs that already use the direct literal.
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

        // Join failed (403: not a member / not public). For an alias we try
        // to resolve it via directory and return a clear error.
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
        self.logger.err("{s} join failed HTTP {d}: {s}", .{ self.name, resp.status, resp.body }, @src());
        return error.MatrixJoinFailed;
    }

    // ============================================================================
    // HTTP (one std.http.Client per request; TLS built into Zig 0.15)
    // ============================================================================
    const HttpResult = struct {
        status: u16,
        body: []const u8, // owned by the caller (domain.allocator)
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

        // Optional proxy (CONNECT for https).
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
// Free-standing helpers
// ============================================================================

/// Percent-encode (Matrix ids/aliases carry '!', '#', ':').
/// Returns an owned slice (free it with allocator.free).
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

/// Appends string `s` to `out`, escaped as a JSON string (with quotes).
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

/// Duplicates `s` as is, or if it starts with "b64:" returns the decoded
/// form (owned in both cases). Used for the proxy credentials.
fn dupeOrDecode(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, s, "b64:")) {
        return try decodeB64(allocator, s[4..]);
    }
    return allocator.dupe(u8, s);
}

/// Decodes standard base64 (with padding). Returns an owned slice.
fn decodeB64(allocator: std.mem.Allocator, code: []const u8) ![]const u8 {
    const b64 = std.base64.standard;
    const dec_len = try b64.Decoder.calcSizeForSlice(code);
    const buf = try allocator.alloc(u8, dec_len);
    try b64.Decoder.decode(buf, code);
    return buf;
}
