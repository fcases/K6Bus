// ============================================================================
// demo3_matrix - E2E validation of the K6Bus Matrix transport.
//
// Two processes (roles a/b), each with a Domain id 77 and its own
// Matrix transport ("matrixA" / "matrixB"). Both transports use THE
// SAME Matrix user and the same room: two "devices" of one user.
//
// Note: src/runtime/ is a local COPY of the Estacion runtime from
// examples/demo1 (same proto => msgType); re-copy if that runtime changes.
//
// Validation flow (A publishes N, B receives them over Matrix):
//   1. Start B first: it sets its base next_batch (the room's
//      historical backlog is NOT processed; only live traffic arrives).
//   2. A publishes N -> subA receives them locally; matrixA sends
//      them to the room.
//   3. B receives the N messages via matrixB's /sync.
//   4. subA must end up at EXACTLY N: if matrixA's own echo were
//      re-injected (broken dedup by unsigned.transaction_id) => 2N.
//
// Usage:
//   (terminal 1) zig build run -- b <user> <password> [room] [N]
//   (terminal 2) zig build run -- a <user> <password> [room] [N]
//
// Each role waits for ITS initial sync (baseline) to end before
// subscribing/publishing: events before the baseline are discarded by
// design (only what arrives live is processed).
//
//   room: '#alias:server' or '!roomid:server' (default #lasala:matrix.org)
//
// The password is passed as an argument: it never lands in the repo.
// ============================================================================
const std = @import("std");
const k6bus = @import("k6bus");

const ApiFile = @import("runtime/Estacion_api.zig");
const Estacion = ApiFile.Estacion;

const PubSub = @import("runtime/Estacion_safe_pubsub.zig");
const Estacion_Publisher = PubSub.Estacion_Publisher;
const Estacion_Subscriber = PubSub.Estacion_Subscriber;

const DOMAIN_ID: u32 = 77;
const CHANNEL = "estacion_channel";

var received = std.atomic.Value(usize).init(0);

const Role = enum { a, b };

pub fn main() !void {
    realMain() catch |e| {
        std.debug.print("[demo3_matrix] FATAL: {s}\n", .{@errorName(e)});
        if (@errorReturnTrace()) |t| std.debug.dumpStackTrace(t.*);
        std.process.exit(1);
    };
}

fn realMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .thread_safe = true }){};
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("[demo3_matrix] GPA detected leaks\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("usage: k6bus_demo3_matrix <a|b> <user> <password> [room] [N]\n", .{});
        std.process.exit(2);
    }
    const role: Role = if (std.ascii.eqlIgnoreCase(args[1], "a")) .a else if (std.ascii.eqlIgnoreCase(args[1], "b")) .b else {
        std.debug.print("invalid role: '{s}' (use 'a' or 'b')\n", .{args[1]});
        std.process.exit(2);
    };
    const user = args[2];
    const password = args[3];
    const room: []const u8 = if (args.len > 4 and args[4].len > 0) args[4] else "#lasala:matrix.org";
    const count: usize = if (args.len > 5) std.fmt.parseInt(usize, args[5], 10) catch 3 else 3;

    std.debug.print("== demo3_matrix role={s}: Matrix transport E2E ==\n", .{@tagName(role)});
    std.debug.print("  user: {s}  room: {s}  N={d}\n", .{ user, room, count });

    // ------------------------------------------------------------------
    // Domain (config: k6bus.App.pb.cfg of the cwd, no default transport)
    // ------------------------------------------------------------------
    var dom = try k6bus.Domain.createEx(allocator, DOMAIN_ID, null, null);
    defer dom.close();

    // ------------------------------------------------------------------
    // Matrix transport (programmatic: credentials from the argument)
    // ------------------------------------------------------------------
    const mcfg = k6bus.Config.MatrixTransportConfig{
        .server = "https://matrix.org",
        .user = user,
        .password = password,
        .room = room,
        .proxy = null,
    };

    const transport_name: []const u8 = switch (role) {
        .a => "matrixA",
        .b => "matrixB",
    };

    const mt = try k6bus.MatrixTransport.create(dom, transport_name, mcfg);
    try dom.registerTransport(mt.transport());
    try mt.start();

    std.debug.print("  transport {s} started; waiting for login+initial sync...\n", .{transport_name});

    // The initial sync (baseline) takes ~10 s: it is awaited deterministically
    // (60 s deadline). Publishing BEFORE the receiver's baseline would make
    // its events be discarded ("only live" semantics).
    const t_sync = std.time.milliTimestamp();
    while (!mt.isInitialSyncDone()) {
        if (std.time.milliTimestamp() - t_sync > 60_000) {
            std.debug.print("[FAIL] timeout waiting for the initial sync\n", .{});
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }
    std.debug.print("  initial sync ready in {d} ms\n", .{std.time.milliTimestamp() - t_sync});

    // ------------------------------------------------------------------
    // Subscriber (both roles) and Publisher (role a only)
    // ------------------------------------------------------------------
    const sub = try Estacion_Subscriber.create(dom, CHANNEL, callback);
    defer dom.closeSubscriber(sub.subscriber());

    var publ: ?Estacion_Publisher = null;
    if (role == .a) {
        publ = try Estacion_Publisher.create(dom);
    }

    std.debug.print("  subscriber ready (channel '{s}')\n", .{CHANNEL});

    switch (role) {
        .a => try roleA(allocator, &publ.?, count),
        .b => try roleB(count),
    }
}

fn roleA(allocator: std.mem.Allocator, publ: *Estacion_Publisher, count: usize) !void {
    var est = try Estacion.initDefault(allocator);
    defer est.deinit(allocator);
    try est.setName(allocator, "Estacion A");
    try est.setUbicacion(allocator, "Origen Matrix A");

    var i: usize = 0;
    while (i < count) : (i += 1) {
        est.setTemperatura(@as(f32, @floatFromInt(i)) + 20.0);
        _ = try publ.publish(CHANNEL, &est);
    }
    std.debug.print("  A published {d} messages; waiting for local delivery ({d})...\n", .{ count, count });

    // Immediate local delivery to the subscriber of the same domain.
    const t0 = std.time.milliTimestamp();
    while (received.load(.monotonic) < count) {
        if (std.time.milliTimestamp() - t0 > 30_000) {
            std.debug.print("  [FAIL] local delivery timeout (received {d} of {d})\n", .{ received.load(.monotonic), count });
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }

    // Extra window: if the own echo were re-injected via matrixA,
    // received would rise above count (broken dedup).
    std.Thread.sleep(8 * std.time.ns_per_s);
    const total = received.load(.monotonic);
    std.debug.print("== Result for role a ==\n", .{});
    std.debug.print("  subA = {d}  expected = {d}\n", .{ total, count });
    if (total == count) {
        std.debug.print("VERDICT A: OK - local delivery without duplicates (matrixA's own echo was discarded)\n", .{});
    } else {
        std.debug.print("VERDICT A: FAIL - subA={d} expected={d} (broken dedup or losses)\n", .{ total, count });
        std.process.exit(4);
    }
}

fn roleB(count: usize) !void {
    std.debug.print("  B waiting for {d} messages from A via Matrix (90 s deadline)...\n", .{count});

    const t0 = std.time.milliTimestamp();
    while (received.load(.monotonic) < count) {
        if (std.time.milliTimestamp() - t0 > 90_000) {
            std.debug.print("  [FAIL] timeout waiting for messages via Matrix (received {d} of {d})\n", .{ received.load(.monotonic), count });
            std.process.exit(3);
        }
        std.Thread.sleep(250 * std.time.ns_per_ms);
    }

    std.Thread.sleep(2 * std.time.ns_per_s);
    const total = received.load(.monotonic);
    std.debug.print("== Result for role b ==\n", .{});
    std.debug.print("  subB = {d}  expected = {d}\n", .{ total, count });
    if (total == count) {
        std.debug.print("VERDICT B: OK - {d} messages received via Matrix from the same user's device\n", .{count});
    } else {
        std.debug.print("VERDICT B: FAIL - subB={d} expected={d}\n", .{ total, count });
        std.process.exit(4);
    }
}

fn callback(
    _: std.mem.Allocator,
    channel_name: []const u8,
    estacion: *const Estacion,
) void {
    _ = channel_name;
    _ = estacion;
    _ = received.fetchAdd(1, .monotonic) + 1;
}
