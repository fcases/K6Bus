const std = @import("std");
const parser = @import("parser.zig");

// ============================================================================
// OUTPUT KIND
// ============================================================================
// gen_pubsub genera dos ficheros paralelos:
//   <proto_base_name>_pubsub.zig
//       Publishers y subscribers basados en los tipos raw.
//   <proto_base_name>_safe_pubsub.zig
//       Publishers y subscribers basados en la API segura.
// Ambos ficheros se generan desde el mismo ProtoSummary y recorren la misma
// lista de mensajes top-level.
// ============================================================================

const OutputKind = enum {
    raw,
    safe,
};

// ============================================================================
// PUBLIC API
// ============================================================================

// ----------------------------------------------------------------------------
// Genera:
//   <output_dir>/<proto_base_name>_pubsub.zig
// El fichero generado asume que está en el mismo directorio que:
//   - generic_pubsub.zig
//   - <proto_base_name>.zig
// Ejemplo:
//   cctrol.proto
//       -> cctrol.zig
//       -> cctrol_pubsub.zig
// Imports generados:
//   const pubsub = @import("generic_pubsub.zig");
//   const ProtoFile = @import("cctrol.zig");
//   const Pkg = ProtoFile.cctrol;
// ----------------------------------------------------------------------------

pub fn writePubSubFile(
    allocator: std.mem.Allocator,
    summary: parser.ProtoSummary,
    output_dir: []const u8,
) !void {
    try writeGeneratedFile(allocator, summary, output_dir, .raw);
}

// ----------------------------------------------------------------------------
// Genera:
//   <output_dir>/<proto_base_name>_safe_pubsub.zig
// El fichero generado asume que está en el mismo directorio que:
//   - safe_pubsub.zig
//   - <proto_base_name>_api.zig
// Ejemplo:
//   cctrol.proto
//       -> cctrol_api.zig
//       -> cctrol_safe_pubsub.zig
// Imports generados:
//   const pubsub = @import("safe_pubsub.zig");
//   const ApiFile = @import("cctrol_api.zig");
// SafePublisher y SafeSubscriber deducen el tipo raw desde el campo impl
// contenido en cada tipo de la API segura.
// ----------------------------------------------------------------------------

pub fn writeSafePubSubFile(
    allocator: std.mem.Allocator,
    summary: parser.ProtoSummary,
    output_dir: []const u8,
) !void {
    try writeGeneratedFile(allocator, summary, output_dir, .safe);
}

// ----------------------------------------------------------------------------
// Genera los dos ficheros en una sola llamada:
//   <proto_base_name>_pubsub.zig
//   <proto_base_name>_safe_pubsub.zig
// ----------------------------------------------------------------------------
pub fn writeAllPubSubFiles(
    allocator: std.mem.Allocator,
    summary: parser.ProtoSummary,
    output_dir: []const u8,
) !void {
    try writePubSubFile(allocator, summary, output_dir);
    try writeSafePubSubFile(allocator, summary, output_dir);
}

// ============================================================================
// COMMON FILE GENERATION
// ============================================================================
fn writeGeneratedFile(
    allocator: std.mem.Allocator,
    summary: parser.ProtoSummary,
    output_dir: []const u8,
    kind: OutputKind,
) !void {
    const suffix = switch (kind) {
        .raw => "_pubsub.zig",
        .safe => "_safe_pubsub.zig",
    };

    const output_file_name = try std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{
            summary.proto_base_name,
            suffix,
        },
    );
    defer allocator.free(output_file_name);

    const output_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{
            output_dir,
            output_file_name,
        },
    );
    defer allocator.free(output_path);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    switch (kind) {
        .raw => {
            try writeRawHeader(allocator, &buf, summary);
        },
        .safe => {
            try writeSafeHeader(allocator, &buf, summary);
        },
    }

    for (summary.messages) |msg_name| {
        switch (kind) {
            .raw => {
                try writeRawMessageWrappers(allocator, &buf, msg_name);
            },
            .safe => {
                try writeSafeMessageWrappers(allocator, &buf, msg_name);
            },
        }
    }

    const file = try std.fs.cwd().createFile(
        output_path,
        .{
            .truncate = true,
        },
    );
    defer file.close();

    try file.writeAll(buf.items);
}

// ============================================================================
// RAW FILE HEADER
// ============================================================================
fn writeRawHeader(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    summary: parser.ProtoSummary,
) !void {
    try buf.print(allocator,
        \\// ------------------------------------------------------------
        \\// Auto-generated by k6b-genpubsub.
        \\// Source proto: {s}.proto
        \\// Package: {s}
        \\// Raw pub/sub bindings.
        \\// Generic pub/sub engine:
        \\//   generic_pubsub.zig
        \\// Raw message implementation:
        \\//   {s}.zig
        \\// Do not edit by hand unless you know what you are doing.
        \\// ------------------------------------------------------------
        \\
        \\const pubsub = @import("generic_pubsub.zig");
        \\const ProtoFile = @import("{s}.zig");
        \\
    , .{
        summary.proto_base_name,
        summary.package_name,
        summary.proto_base_name,
        summary.proto_base_name,
    });

    if (summary.package_name.len > 0) {
        try buf.print(allocator,
            \\const Pkg = ProtoFile.{s};
            \\
            \\
        , .{
            summary.package_name,
        });
    } else {
        try buf.print(allocator,
            \\const Pkg = ProtoFile;
            \\
            \\
        , .{});
    }
}

// ============================================================================
// SAFE FILE HEADER
// ============================================================================
fn writeSafeHeader(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    summary: parser.ProtoSummary,
) !void {
    try buf.print(allocator,
        \\// ------------------------------------------------------------
        \\// Auto-generated by k6b-genpubsub.
        \\// Source proto: {s}.proto
        \\// Package: {s}
        \\// Safe pub/sub bindings.
        \\// Generic safe pub/sub engine:
        \\//   safe_pubsub.zig
        \\// Safe message API:
        \\//   {s}_api.zig
        \\// Raw pub/sub bindings remain available in:
        \\//   {s}_pubsub.zig
        \\// Do not edit by hand unless you know what you are doing.
        \\// ------------------------------------------------------------
        \\
        \\const pubsub = @import("safe_pubsub.zig");
        \\const ApiFile = @import("{s}_api.zig");
        \\
        \\
    , .{
        summary.proto_base_name,
        summary.package_name,
        summary.proto_base_name,
        summary.proto_base_name,
        summary.proto_base_name,
    });
}

// ============================================================================
// RAW MESSAGE WRAPPERS
// ============================================================================
// Para cada mensaje top-level M se genera:
//   pub const M_Publisher =
//       pubsub.GenericPublisher(
//           Pkg.M,
//           ProtoFile.BinaraFormato,
//       );
//   pub const M_Subscriber =
//       pubsub.GenericSubscriber(
//           Pkg.M,
//           ProtoFile.BinaraFormato,
//       );
// Los tipos raw siguen disponibles en:
//   <proto_base_name>_pubsub.zig
// ============================================================================
fn writeRawMessageWrappers(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    msg_name: []const u8,
) !void {
    try buf.print(allocator,
        \\// ============================================================================
        \\// {s}
        \\// ============================================================================
        \\pub const {s}_Publisher =
        \\    pubsub.GenericPublisher(Pkg.{s}, ProtoFile.BinaraFormato);
        \\
        \\pub const {s}_Subscriber =
        \\    pubsub.GenericSubscriber(Pkg.{s}, ProtoFile.BinaraFormato);
        \\
        \\
    , .{
        msg_name,
        msg_name,
        msg_name,
        msg_name,
        msg_name,
    });
}

// ============================================================================
// SAFE MESSAGE WRAPPERS
// ============================================================================
// Para cada mensaje top-level M se genera:
//   pub const M_Publisher =
//       pubsub.SafePublisher(
//           ApiFile.M,
//           ApiFile.BinaraFormato,
//       );
//   pub const M_Subscriber =
//       pubsub.SafeSubscriber(
//           ApiFile.M,
//           ApiFile.BinaraFormato,
//       );
// SafePublisher:
//   - expone DatumApi;
//   - deduce DatumRaw desde DatumApi.impl;
//   - delega la publicación en GenericPublisher.
// SafeSubscriber:
//   - expone DatumApi;
//   - deduce DatumRaw desde DatumApi.impl;
//   - calcula msgType con DatumRaw;
//   - deserializa directamente DatumApi;
//   - almacena una callback segura recibida en create().
// ============================================================================
fn writeSafeMessageWrappers(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    msg_name: []const u8,
) !void {
    try buf.print(allocator,
        \\// ============================================================================
        \\// {s}
        \\// ============================================================================
        \\pub const {s}_Publisher =
        \\    pubsub.SafePublisher(ApiFile.{s}, ApiFile.BinaraFormato);
        \\
        \\pub const {s}_Subscriber =
        \\    pubsub.SafeSubscriber(ApiFile.{s}, ApiFile.BinaraFormato);
        \\
        \\
    , .{
        msg_name,
        msg_name,
        msg_name,
        msg_name,
        msg_name,
    });
}
