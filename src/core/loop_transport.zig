// loop_transport.zig

const std = @import("std");

const Transport = @import("transport.zig").Transport;
const Domain = @import("domain.zig").Domain;
const Logger = @import("logger.zig").Logger;

const Config = @import("../generated/Config.zig").k6bus.config;

pub const LoopTransport = struct {
    transport: Transport,
    delay_ms: u32 = 300,

    mutex: std.Thread.Mutex = .{},
    queue: std.ArrayList([]const u8),

    my_logger: *Logger = undefined,

    const Self = @This();

    pub fn create(domain: *Domain, name: []const u8, delay_ms: u32) !*Self {
        const self = try domain.allocator.create(Self);
        errdefer domain.allocator.destroy(self);

        try self.init(domain, name, delay_ms);

        return self;
    }

    pub fn init(self: *Self, domain: *Domain, name: []const u8, delay_ms: u32) !void {
        self.delay_ms = delay_ms;

        // self.queue = std.ArrayList([]const u8).init(domain.allocator);
        self.queue = .empty;
        self.my_logger = &domain.logger;

        try self.transport.init(
            domain,
            name,
            Config.Encoding.RAW,
            self,
            sendBytes,
            mainLoop,
        );
    }

    pub fn start(self: *Self) !void {
        try self.transport.start();

        self.my_logger.info("{s} started.", .{self.transport.qm.name}, @src());
    }

    pub fn stop(self: *Self) void {
        self.transport.stop();

        self.my_logger.info("{s} stopped.", .{self.transport.qm.name}, @src());
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();

        for (self.queue.items) |bytes| {
            self.transport.domain.allocator.free(bytes);
        }
        self.queue.deinit();
        self.mutex.unlock();
        self.transport.close();

        self.my_logger.info("{s} terminated.", .{self.transport.qm.name}, @src());
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

                self.my_logger.info("{s} queued {d} bytes for sending back to domain", .{ self.transport.qm.name, bytes.len }, @src());
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

        self.queue.append(self.transport.domain.allocator, copia) catch {
            self.transport.domain.allocator.free(copia);
            return false;
        };

        self.my_logger.info("{s} queued {d} bytes for sending back to domain", .{ self.transport.qm.name, wire_bytes.len }, @src());

        return true;
    }
};
