const std = @import("std");
pub const Level = enum(u8) {
    err = 0,
    warning = 1,
    info = 2,
    trace = 3,

    pub fn label(self: Level) []const u8 {
        return switch (self) {
            .err => "ERROR",
            .warning => "WARN",
            .info => "INFO",
            .trace => "TRACE",
        };
    }
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    dom_id: u32,
    active: bool = false,
    level: Level = .err,
    mutex: std.Thread.Mutex = .{},
    file: ?std.fs.File = null,
    file_name: []u8 = &.{},
    wr_buffer: [4096]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, dom_id: u32, active: bool, level_int: i32) !Logger {
        var l = Logger{ .allocator = allocator, .dom_id = dom_id, .active = active, .level = switch (level_int) {
            0 => .err,
            1 => .warning,
            2 => .info,
            else => .trace,
        } };

        if (active) {
            const ts = std.time.timestamp();
            const epoch = std.time.epoch;
            const sec = epoch.EpochSeconds{ .secs = @intCast(ts) };

            const day = sec.getEpochDay();
            const ymd = day.calculateYearDay();
            const md = ymd.calculateMonthDay();

            const tod = sec.getDaySeconds();
            const secs = tod.secs;

            const hora = secs / 3600;
            const minuto = (secs % 3600) / 60;
            const segundo = secs % 60;

            l.file_name = try std.fmt.allocPrint(
                allocator,
                "Dom{d:0>3}_{d:0>4}{d:0>2}{d:0>2}_{d:0>2}:{d:0>2}:{d:0>2}_UTC.log",
                .{ l.dom_id, ymd.year, @intFromEnum(md.month), md.day_index + 1, hora, minuto, segundo },
            );
            l.file = try std.fs.cwd().createFile(l.file_name, .{ .truncate = true });
            l.info("Logger started", .{}, @src());
        }
        return l;
    }

    pub fn deinit(self: *Logger) void {
        if (self.active) self.info("Logger: Thread finished - K6BusLogger", .{}, @src());
        if (self.file) |f| f.close();
        if (self.file_name.len > 0) self.allocator.free(self.file_name);
    }

    fn enabled(self: *Logger, lvl: Level) bool {
        return self.active and @intFromEnum(lvl) <= @intFromEnum(self.level);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
        self.write(.err, fmt, args, src);
    }

    pub fn warning(self: *Logger, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
        self.write(.warning, fmt, args, src);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
        self.write(.info, fmt, args, src);
    }

    pub fn trace(self: *Logger, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
        self.write(.trace, fmt, args, src);
    }

    pub fn write(self: *Logger, lvl: Level, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
        if (!self.enabled(lvl)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const f = self.file orelse return;

        const ts = std.time.timestamp();
        const epoch = std.time.epoch;
        const sec = epoch.EpochSeconds{ .secs = @intCast(ts) };

        const day = sec.getEpochDay();
        const ymd = day.calculateYearDay();
        const md = ymd.calculateMonthDay();

        const tod = sec.getDaySeconds();
        const secs = tod.secs;

        const hora = secs / 3600;
        const minuto = (secs % 3600) / 60;
        const segundo = secs % 60;

        const pre =
            std.fmt.allocPrint(
                self.allocator,
                "Dom{d:0>3}_{s}:\t{d:0>4}{d:0>2}{d:0>2}_{d:0>2}:{d:0>2}:{d:0>2} UTC\t\t{s}, L-{d}: {s}\n\t",
                .{
                    self.dom_id,
                    lvl.label(),
                    ymd.year,
                    @intFromEnum(md.month),
                    md.day_index + 1,
                    hora,
                    minuto,
                    segundo,
                    std.fs.path.basename(src.file),
                    src.line,
                    src.fn_name,
                },
            ) catch return;
        defer self.allocator.free(pre);

        const msg =
            std.fmt.allocPrint(
                self.allocator,
                fmt,
                args,
            ) catch return;
        defer self.allocator.free(msg);

        f.writeAll(pre) catch return;
        f.writeAll(msg) catch return;
        f.writeAll("\n") catch return;
    }
};
