const std = @import("std");

const parser = @import("parser.zig");
const generator = @import("generator.zig");

const MAX_PROTO_SIZE: usize = 16 * 1024 * 1024;

// ------------------------------------------------------------
// CLI
// ------------------------------------------------------------
// Usage:
//
//   k6b-genpubsub --proto_dir protos --output_dir src/runtime cctrol.proto
//
// Intent:
//   --proto_dir
//       Directory where the .proto file is located.
//   --output_dir
//       Directory where <proto_base>_pubsub.zig will be generated.
//   proto_file
//       Input .proto file name.
//
// Example:
//   k6b-genpubsub \
//       --proto_dir examples/demo2/protos \
//       --output_dir examples/demo2/src/runtime \
//       cctrol.proto
//
// Output:
//   examples/demo2/src/runtime/cctrol_pubsub.zig
//
// Notes:
//
//   - Only top-level messages get Publisher/Subscriber wrappers.
//   - Internal messages are intentionally ignored.
//   - The generated file expects generic_pubsub.zig and <proto_base>.zig
//     in the same output directory.
// ------------------------------------------------------------
const CliArgs = struct {
    proto_dir: []const u8,
    output_dir: []const u8,
    proto_file: []const u8,

    pub fn deinit(self: *CliArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.proto_dir);
        allocator.free(self.output_dir);
        allocator.free(self.proto_file);

        self.* = undefined;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("k6b-genpubsub: GPA detected leaks\n", .{});
        }
    }

    const allocator = gpa.allocator();

    var cli = parseArgs(allocator) catch |err| {
        switch (err) {
            error.HelpRequested => {
                printUsage();
                return;
            },
            error.MissingProtoDir,
            error.MissingOutputDir,
            error.MissingProtoFile,
            error.TooManyProtoFiles,
            error.UnknownArgument,
            => {
                printUsage();
                return err;
            },
            else => return err,
        }
    };
    defer cli.deinit(allocator);

    try run(allocator, cli);
}

fn run(allocator: std.mem.Allocator, cli: CliArgs) !void {
    const proto_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{
            cli.proto_dir,
            cli.proto_file,
        },
    );
    defer allocator.free(proto_path);

    const proto_base_name = std.fs.path.stem(cli.proto_file);

    std.debug.print("k6b-genpubsub: reading proto: {s}\n", .{proto_path});

    const proto_text = try std.fs.cwd().readFileAlloc(allocator, proto_path, MAX_PROTO_SIZE);
    defer allocator.free(proto_text);

    // Ensure output directory exists.
    try std.fs.cwd().makePath(cli.output_dir);

    // ------------------------------------------------------------
    // Minimal .proto analysis
    // ------------------------------------------------------------
    // genpubsub is not a full protobuf parser. It only extracts:
    //   - package
    //   - top-level messages
    //
    // Internal messages are deliberately ignored. If the user wants
    // pub/sub wrappers for a message, that message must be top-level.
    //
    // Expected parser.zig API:
    //   pub const ProtoSummary = struct {
    //       package_name: []const u8,
    //       proto_base_name: []const u8,
    //       messages: []const []const u8,
    //
    //       pub fn deinit(
    //           self: *ProtoSummary,
    //           allocator: std.mem.Allocator,
    //       ) void { ... }
    //   };
    //   pub fn analyzeProto(
    //       allocator: std.mem.Allocator,
    //       text: []const u8,
    //       proto_base_name: []const u8,
    //   ) !ProtoSummary;
    // ------------------------------------------------------------
    var summary = try parser.analyzeProto(
        allocator,
        proto_text,
        proto_base_name,
    );
    defer summary.deinit(allocator);

    std.debug.print("k6b-genpubsub: package: {s}\n", .{summary.package_name});
    std.debug.print("k6b-genpubsub: top-level messages: {d}\n", .{summary.messages.len});
    for (summary.messages) |msg_name| {
        std.debug.print("  - {s}\n", .{msg_name});
    }

    // ------------------------------------------------------------
    // Generation
    // ------------------------------------------------------------
    // Expected generator.zig API:
    //   pub fn writePubSubFile(
    //       allocator: std.mem.Allocator,
    //       summary: parser.ProtoSummary,
    //       output_dir: []const u8,
    //   ) !void;
    //
    // It must generate:
    //   <output_dir>/<proto_base_name>_pubsub.zig
    //
    // Example:
    //   cctrol.proto -> cctrol_pubsub.zig
    //
    // The generated file should assume it lives in the same directory as:
    //   - cctrol.zig
    //   - generic_pubsub.zig
    //
    // Therefore it can generate simple imports:
    //   const pubsub = @import("generic_pubsub.zig");
    //   const ProtoFile = @import("cctrol.zig");
    //   const Pkg = ProtoFile.cctrol;
    // ------------------------------------------------------------
    try generator.writePubSubFile(allocator, summary, cli.output_dir);

    std.debug.print(
        "k6b-genpubsub: generated {s}/{s}_pubsub.zig\n",
        .{
            cli.output_dir,
            summary.proto_base_name,
        },
    );
}

fn parseArgs(allocator: std.mem.Allocator) !CliArgs {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // executable name

    var proto_dir: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var proto_file: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "--help"))
        {
            return error.HelpRequested;
        }

        if (std.mem.eql(u8, arg, "--proto_dir")) {
            const value = args.next() orelse return error.MissingProtoDir;

            if (proto_dir) |old| {
                allocator.free(old);
            }

            proto_dir = try allocator.dupe(u8, value);
            continue;
        }

        if (std.mem.eql(u8, arg, "--output_dir")) {
            const value = args.next() orelse return error.MissingOutputDir;

            if (output_dir) |old| {
                allocator.free(old);
            }

            output_dir = try allocator.dupe(u8, value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("k6b-genpubsub: unknown argument: {s}\n", .{arg});
            return error.UnknownArgument;
        }

        if (proto_file != null) {
            return error.TooManyProtoFiles;
        }

        proto_file = try allocator.dupe(u8, arg);
    }

    if (proto_dir == null) {
        return error.MissingProtoDir;
    }

    if (output_dir == null) {
        return error.MissingOutputDir;
    }

    if (proto_file == null) {
        return error.MissingProtoFile;
    }

    return .{
        .proto_dir = proto_dir.?,
        .output_dir = output_dir.?,
        .proto_file = proto_file.?,
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  k6b-genpubsub --proto_dir <proto_dir> --output_dir <output_dir> <file.proto>
        \\
        \\Example:
        \\  k6b-genpubsub \\
        \\      --proto_dir examples/demo2/protos \\
        \\      --output_dir examples/demo2/src/runtime \\
        \\      cctrol.proto
        \\
        \\This tool generates:
        \\  <output_dir>/<proto_base_name>_pubsub.zig
        \\
        \\Notes:
        \\  - Only top-level messages get Publisher/Subscriber wrappers.
        \\  - Internal messages are intentionally ignored.
        \\  - The generated file expects generic_pubsub.zig and <proto_base>.zig
        \\    in the same output directory.
        \\
    , .{});
}
