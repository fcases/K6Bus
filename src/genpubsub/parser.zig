const std = @import("std");

// ------------------------------------------------------------
// ProtoSummary
// ------------------------------------------------------------
// genpubsub only needs a very small subset of a .proto file:
//   - package name
//   - top-level message names
//   - proto base name, taken from the input file name without .proto
//
// It intentionally ignores:
//   - fields
//   - enums
//   - oneofs
//   - services
//   - imports
//   - nested messages
//
// If a message must have Publisher/Subscriber wrappers, it must be
// declared as a top-level message.
// ------------------------------------------------------------

pub const ProtoSummary = struct {
    package_name: []const u8,
    proto_base_name: []const u8,
    messages: []const []const u8,

    pub fn deinit(self: *ProtoSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.package_name);
        allocator.free(self.proto_base_name);

        for (self.messages) |msg| {
            allocator.free(msg);
        }
        allocator.free(self.messages);

        self.* = undefined;
    }
};

// ------------------------------------------------------------
// Public API
// ------------------------------------------------------------
pub fn analyzeProto(allocator: std.mem.Allocator, text: []const u8, proto_base_name: []const u8) !ProtoSummary {
    const normalized = try normalizeProtoText(allocator, text);
    defer allocator.free(normalized);

    var package_name: ?[]const u8 = null;
    var messages = std.ArrayList([]const u8).empty;

    errdefer {
        if (package_name) |pkg| allocator.free(pkg);
        for (messages.items) |msg|  allocator.free(msg);
        messages.deinit(allocator);
    }

    var it = std.mem.tokenizeAny(u8, normalized, " \n\r\t;");

    var prev: ?[]const u8 = null;
    var depth: usize = 0;

    while (it.next()) |tok| {
        if (std.mem.eql(u8, tok, "{")) {
            depth += 1;
            prev = tok;
            continue;
        }

        if (std.mem.eql(u8, tok, "}")) {
            if (depth == 0) {
                return error.UnbalancedClosingBrace;
            }

            depth -= 1;
            prev = tok;
            continue;
        }

        if (prev) |p| {
            if (std.mem.eql(u8, p, "package")) {
                if (package_name) |old| {
                    allocator.free(old);
                }

                package_name = try allocator.dupe(u8, tok);
                prev = tok;
                continue;
            }

            if (std.mem.eql(u8, p, "message") and depth == 0) {
                try messages.append(
                    allocator,
                    try allocator.dupe(u8, tok),
                );

                prev = tok;
                continue;
            }
        }

        prev = tok;
    }

    if (depth != 0) {
        return error.UnbalancedOpeningBrace;
    }

    const final_package_name = if (package_name) |pkg|
        pkg
    else
        try allocator.dupe(u8, "");

    package_name = null;

    return .{
        .package_name = final_package_name,
        .proto_base_name = try allocator.dupe(u8, proto_base_name),
        .messages = try messages.toOwnedSlice(allocator),
    };
}

// ------------------------------------------------------------
// Very small normalizer
// ------------------------------------------------------------
// This function deliberately avoids building a full tokenizer.
//
// It produces text suitable for std.mem.tokenizeAny(), by:
//   - removing line comments:
//       // ...
//   - removing block comments:
//       /* ... */
//   - replacing string literals with a neutral token:
//       "some text { message Fake }"  ->  STRING
//   - adding spaces around structural tokens:
//       { } ;
//
// Why replace strings?
//   Because strings may contain characters such as:
//       "{"
//       "}"
//       "message"
//   and those must not affect depth counting or message detection.
//
// This is still not a full .proto parser; it is intentionally only
// robust enough for package/top-level-message extraction.
// ------------------------------------------------------------
fn normalizeProtoText(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        // Whitespace
        if (std.ascii.isWhitespace(c)) {
            try out.append(allocator, c);
            i += 1;
            continue;
        }

        // Line comment: // ...
        if (i + 1 < text.len and text[i] == '/' and text[i + 1] == '/') {
            i += 2;

            while (i < text.len and text[i] != '\n') {
                i += 1;
            }

            if (i < text.len and text[i] == '\n') {
                try out.append(allocator, '\n');
                i += 1;
            }

            continue;
        }

        // Block comment: /* ... */
        if (i + 1 < text.len and text[i] == '/' and text[i + 1] == '*') {
            i += 2;

            while (i + 1 < text.len) {
                if (text[i] == '*' and text[i + 1] == '/') {
                    i += 2;
                    break;
                }

                i += 1;
            }

            // If the block comment is unterminated, consume until EOF.
            if (i + 1 >= text.len) {
                i = text.len;
            }

            try out.append(allocator, ' ');
            continue;
        }

        // String literal: "..." or '...'
        if (c == '"' or c == '\'') {
            const quote = c;

            // Replace whole string with a neutral token.
            try out.appendSlice(allocator, " STRING ");

            i += 1;

            while (i < text.len) {
                const sc = text[i];

                if (sc == '\\') {
                    // Skip escaped character if present.
                    i += 1;
                    if (i < text.len) {
                        i += 1;
                    }
                    continue;
                }

                i += 1;

                if (sc == quote) {
                    break;
                }
            }

            continue;
        }

        // Structural tokens we care about
        switch (c) {
            '{', '}', ';' => {
                try out.append(allocator, ' ');
                try out.append(allocator, c);
                try out.append(allocator, ' ');
                i += 1;
                continue;
            },

            else => {},
        }

        // Any other byte is copied as-is.
        try out.append(allocator, c);
        i += 1;
    }

    return try out.toOwnedSlice(allocator);
}

// ------------------------------------------------------------
// Tests
// ------------------------------------------------------------
test "analyzeProto extracts package and top-level messages" {
    const allocator = std.testing.allocator;

    const proto_text =
        \\syntax = "proto2";
        \\package cctrol;
        \\
        \\message CCtrol {
        \\    required string nombre = 1;
        \\}
        \\
        \\message Outer {
        \\    message Inner {
        \\        required string ignored = 1;
        \\    }
        \\}
    ;

    var summary = try analyzeProto(
        allocator,
        proto_text,
        "cctrol",
    );
    defer summary.deinit(allocator);

    try std.testing.expectEqualStrings("cctrol", summary.package_name);
    try std.testing.expectEqualStrings("cctrol", summary.proto_base_name);

    try std.testing.expectEqual(@as(usize, 2), summary.messages.len);
    try std.testing.expectEqualStrings("CCtrol", summary.messages[0]);
    try std.testing.expectEqualStrings("Outer", summary.messages[1]);
}

test "analyzeProto ignores message tokens inside strings and comments" {
    const allocator = std.testing.allocator;

    const proto_text =
        \\syntax = "proto2";
        \\package demo;
        \\
        \\// message FakeComment { }
        \\
        \\/*
        \\message FakeBlock {
        \\}
        \\*/
        \\
        \\message Real {
        \\    optional string texto = 1 [default = "papapa { message FakeString }"];
        \\}
        \\
        \\message Another {
        \\}
    ;

    var summary = try analyzeProto(
        allocator,
        proto_text,
        "demo",
    );
    defer summary.deinit(allocator);

    try std.testing.expectEqualStrings("demo", summary.package_name);
    try std.testing.expectEqualStrings("demo", summary.proto_base_name);

    try std.testing.expectEqual(@as(usize, 2), summary.messages.len);
    try std.testing.expectEqualStrings("Real", summary.messages[0]);
    try std.testing.expectEqualStrings("Another", summary.messages[1]);
}