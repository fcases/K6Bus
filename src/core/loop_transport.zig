// loop_transport.zig

const std = @import("std");

const Transport = @import("transport.zig").Transport;
const Domain = @import("domain.zig").Domain;

const Config = @import("../generated/Config.zig").k6bus.config;

pub const LoopTransport = struct {
    transport: Transport,
    delay_ms: u32 = 300,

    mutex: std.Thread.Mutex = .{},
    queue: std.ArrayList([]const u8),

    const Self = @This();

    pub fn create(domain: *Domain, name: []const u8, delay_ms: u32) !Self {
        var self: Self = undefined;

        try self.init(domain, name, delay_ms);

        return self;
    }

    pub fn init(self: *Self, domain: *Domain, name: []const u8, delay_ms: u32) !void {
        self.delay_ms = delay_ms;

        self.queue = std.ArrayList([]const u8).init(domain.allocator);

        try self.transport.init(
            domain,
            name,
            true, // ReceiveOwnMessages
            Config.EncodingDef.RAW,
            self,
            sendBytes,
            mainLoop,
        );
    }

    pub fn start(self: *Self) !void {
        try self.transport.start();
    }

    pub fn pause(self: *Self) void {
        self.transport.pause();
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();

        for (self.queue.items) |bytes| {
            self.transport.domain.allocator.free(bytes);
        }
        self.queue.deinit();
        self.mutex.unlock();
        self.transport.close();
    }

    // ------------------------------------------------------------------------
    // RX MainLoop
    // ------------------------------------------------------------------------
    fn mainLoop(owner: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(owner));

        while (self.transport.running) {
            var wire_bytes: ?[]const u8 = null;

            self.mutex.lock();
            if (self.queue.items.len > 0) {
                wire_bytes = self.queue.orderedRemove(0);
            }
            self.mutex.unlock();

            if (wire_bytes) |bytes| {
                std.Thread.sleep(@as(u64, self.delay_ms) * std.time.ns_per_ms);

                self.transport.receiveBytes(bytes) catch {};
                self.transport.domain.allocator.free(bytes);
            } else {
                std.Thread.sleep(10 * std.time.ns_per_ms);
            }
        }
    }

    // ------------------------------------------------------------------------
    // TX
    // ------------------------------------------------------------------------
    fn sendBytes(owner: *anyopaque, wire_bytes: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(owner));

        const copia = self.transport.domain.allocator.dupe(u8, wire_bytes) catch return false;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.queue.append(copia) catch {
            self.transport.domain.allocator.free(copia);
            return false;
        };

        return true;
    }
};
