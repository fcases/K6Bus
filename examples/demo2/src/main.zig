// ============================================================================
// demo2 - main.zig
// ============================================================================
// Variant of main.zig, to compare:
//   - message building with the generated SAFE API (cctrol_api.zig),
//     with no manual ownership handling (dupe/clone setters, errdefers);
//   - subscriber teardown per the NEW contract: via
//     domain.closeSubscriber(sub.subscriber()), coordinated by the
//     Domain (sub.close() is not called directly any more).
// Callbacks still receive the RAW type (the subscriber deserializes to the
// raw); only building uses the safe API. To publish we pass &x.impl
// (the impl IS the raw).
// Compilation (outside the normal build.zig, to compare with main.zig):
//   build2.zig with root = src/main2.zig, or:
//   zig build-exe src/main2.zig ... with the k6bus module linked
// ============================================================================
const std = @import("std");
const k6bus = @import("k6bus");

const CctrolFile = @import("runtime/cctrol.zig");
const Cctrol = CctrolFile.cctrol;

const ApiFile = @import("runtime/cctrol_api.zig");
const sCctrol = ApiFile;

const PubSub = @import("runtime/cctrol_pubsub.zig");
const EstMeteo_Publisher = PubSub.EstMeteo_Publisher;
const SnrTrafico_Publisher = PubSub.SnrTrafico_Publisher;
const PanelInfoV_Publisher = PubSub.PanelInfoV_Publisher;
const EstMeteo_Subscriber = PubSub.EstMeteo_Subscriber;
const SnrTrafico_Subscriber = PubSub.SnrTrafico_Subscriber;
const PanelInfoV_Subscriber = PubSub.PanelInfoV_Subscriber;

const sPubSub = @import("runtime/cctrol_safe_pubsub.zig");
const EstMeteo_sPublisher = sPubSub.EstMeteo_Publisher;
const SnrTrafico_sPublisher = sPubSub.SnrTrafico_Publisher;
const PanelInfoV_sPublisher = sPubSub.PanelInfoV_Publisher;
const EstMeteo_sSubscriber = sPubSub.EstMeteo_Subscriber;
const SnrTrafico_sSubscriber = sPubSub.SnrTrafico_Subscriber;
const PanelInfoV_sSubscriber = sPubSub.PanelInfoV_Subscriber;

const DEFAULT_DOMAIN_ID: u32 = 77;

const Role = enum {
    cctrol,
    remotas,
};

const CliConfig = struct {
    role: Role,
    config_file: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const result = gpa.deinit();
        if (result == .leak) {
            std.debug.print("GPA detected leaks\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const cli = try parseArgs(allocator);
    // var domain = try k6bus.Domain.createFromFile(allocator, DEFAULT_DOMAIN_ID, cli.config_file);
    var domain: *k6bus.Domain = undefined;
    if (cli.config_file) |f| {
        domain = try k6bus.Domain.createFromFile(allocator, DEFAULT_DOMAIN_ID, f);
    } else {
        domain = try k6bus.Domain.create(allocator, DEFAULT_DOMAIN_ID);
    }
    defer domain.close();

    switch (cli.role) {
        .remotas => try runRemotas(allocator, domain),
        .cctrol => try runCctrol(allocator, domain),
    }
}

// ------------------------------------------------------------
// CLI (identical to main.zig)
// ------------------------------------------------------------
fn parseArgs(allocator: std.mem.Allocator) !CliConfig {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // executable

    const role_text = args.next() orelse {
        printUsage();
        return error.MissingRole;
    };

    var cfg = CliConfig{
        .role = parseRole(role_text) orelse {
            printUsage();
            return error.InvalidRole;
        },
    };

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--config_file")) {
            cfg.config_file = args.next() orelse return error.MissingConfigFile;
            continue;
        }

        std.debug.print("Unknown argument: {s}\n", .{arg});
        printUsage();
        return error.InvalidArgument;
    }

    return cfg;
}

fn parseRole(text: []const u8) ?Role {
    if (std.mem.eql(u8, text, "cctrol")) return .cctrol;
    if (std.mem.eql(u8, text, "remotas")) return .remotas;
    return null;
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  k6bus_demo2 cctrol  [--config_file cfg/k6bus.Demo2.pb.cfg]
        \\  k6bus_demo2 remotas [--config_file cfg/k6bus.Demo2.pb.cfg]
        \\
        \\Roles:
        \\  remotas  - publishes EstMeteo on channel "meteos" with key m
        \\             publishes SnrTrafico on channel "trafico" with key t
        \\             listens to PanelInfoV on channel "paneles"
        \\
        \\  cctrol   - listens to EstMeteo on channel "meteos"
        \\             listens to SnrTrafico on channel "trafico"
        \\             publishes PanelInfoV on channel "paneles" with key p
        \\
    , .{});
}

// ------------------------------------------------------------
// Role: remotas
// ------------------------------------------------------------
fn runRemotas(allocator: std.mem.Allocator, domain: *k6bus.Domain) !void {
    std.debug.print("REMOTAS mode\n", .{});
    std.debug.print("m -> publish EstMeteo on channel meteos\n", .{});
    std.debug.print("t -> publish SnrTrafico on channel trafico\n", .{});
    std.debug.print("q -> quit\n", .{});

    var meteo_pub = try EstMeteo_sPublisher.create(domain);
    var trafico_pub = try SnrTrafico_sPublisher.create(domain);

    // New contract: teardown is coordinated by the Domain.
    const panel_sub = try PanelInfoV_sSubscriber.create(
        domain,
        "paneles",
        onPanelInfo,
    );
    defer domain.closeSubscriber(panel_sub.subscriber());

    while (true) {
        const key = try readKey();
        switch (key) {
            'm' => {
                var meteo = try makeMeteo(allocator);
                defer meteo.deinit(allocator);

                _ = try meteo_pub.publish("meteos", &meteo);
                std.debug.print("REMOTAS: EstMeteo published on meteos\n", .{});
            },

            't' => {
                var trafico = try makeTrafico(allocator);
                defer trafico.deinit(allocator);

                _ = try trafico_pub.publish("trafico", &trafico);
                std.debug.print("REMOTAS: SnrTrafico published on trafico\n", .{});
            },

            'q' => break,

            else => {},
        }
    }
}

// ------------------------------------------------------------
// Role: cctrol
// ------------------------------------------------------------
fn runCctrol(allocator: std.mem.Allocator, domain: *k6bus.Domain) !void {
    std.debug.print("CCTROL mode\n", .{});
    std.debug.print("p -> publish PanelInfoV on channel paneles\n", .{});
    std.debug.print("q -> quit\n", .{});

    // New contract: teardown coordinated by the Domain.
    const meteo_sub = try EstMeteo_Subscriber.create(
        domain,
        "meteos",
        onMeteo,
    );
    defer domain.closeSubscriber(meteo_sub.subscriber());

    const trafico_sub = try SnrTrafico_Subscriber.create(
        domain,
        "trafico",
        onTrafico,
    );
    defer domain.closeSubscriber(trafico_sub.subscriber());

    var panel_pub = try PanelInfoV_Publisher.create(domain);

    while (true) {
        const key = try readKey();
        switch (key) {
            'p' => {
                var panel = try makePanelOrder(allocator);
                defer panel.deinit(allocator);

                _ = try panel_pub.publish("paneles", &panel.impl);
                std.debug.print("CCTROL: PanelInfoV published on paneles\n", .{});
            },

            'q' => break,

            else => {},
        }
    }
}

// ------------------------------------------------------------
// Callbacks (they receive the RAW type, as in main.zig)
// ------------------------------------------------------------
fn onMeteo(channel_name: []const u8, meteo: *const Cctrol.EstMeteo) void {
    std.debug.print(
        "CCTROL: received EstMeteo on channel {s}: nombre={s} temp={d} viento={d:.2} dir={d:.2}\n",
        .{
            channel_name,
            meteo.nombre,
            meteo.temp,
            meteo.v_viento,
            meteo.dir_viento,
        },
    );
}

fn onTrafico(channel_name: []const u8, trafico: *const Cctrol.SnrTrafico) void {
    std.debug.print(
        "CCTROL: received SnrTrafico on channel {s}: seccion={s} carriles={d} vel_media_count={d} veh_min_count={d}\n",
        .{
            channel_name,
            trafico.seccion,
            trafico.carriles,
            trafico.vel_media.len,
            trafico.vehiculos_min.len,
        },
    );
}

fn onPanelInfo(allocator: std.mem.Allocator, channel_name: []const u8, panel: *const sCctrol.PanelInfoV) void {
    std.debug.print(
        "REMOTAS: received PanelInfoV on channel {s}: nombre={s} elementos={d}\n",
        .{
            channel_name,
            panel.getNombre(),
            panel.getElementosCount(),
        },
    );

    var index: usize = 0;
    while (index < panel.getElementosCount()) : (index += 1) {
        var elem = panel.getElementosAt(allocator, index) catch |err| {
            std.debug.print(
                "  Error getting element {d}: {}\n",
                .{ index, err },
            );
            continue;
        };
        defer elem.deinit(allocator);

        std.debug.print(
            "  PMV panel_base nombre={s} tipo={any}\n",
            .{
                elem.getNombre(),
                elem.getTipo(),
            },
        );

        if (elem.hasDatosSenial()) {
            var senial = elem.getDatosSenial(allocator) catch |err| {
                std.debug.print(
                    "    Error getting signal data: {}\n",
                    .{err},
                );
                continue;
            };
            defer senial.deinit(allocator);

            std.debug.print(
                "    Signal: nombre={s} valor={s}\n",
                .{
                    senial.getNombre(),
                    senial.getSenial(),
                },
            );
        } else if (elem.hasDatosTexto()) {
            var texto = elem.getDatosTexto(allocator) catch |err| {
                std.debug.print(
                    "    Error getting text data: {}\n",
                    .{err},
                );
                continue;
            };
            defer texto.deinit(allocator);

            std.debug.print(
                "    Text: nombre={s} valor={s}\n",
                .{
                    texto.getNombre(),
                    texto.getTexto(),
                },
            );
        } else {
            std.debug.print(
                "    No associated data\n",
                .{},
            );
        }
    }
}

// ------------------------------------------------------------
// Factories with the SAFE API (no manual ownership)
// ------------------------------------------------------------
fn makeMeteo(allocator: std.mem.Allocator) !sCctrol.EstMeteo {
    var meteo = try sCctrol.EstMeteo.initDefault(allocator);
    errdefer meteo.deinit(allocator);

    try meteo.setNombre(allocator, "meteo-remota-1");
    meteo.setTemp(23);
    meteo.setVViento(12.5);
    meteo.setDirViento(270.0);

    return meteo;
}

fn makeTrafico(allocator: std.mem.Allocator) !sCctrol.SnrTrafico {
    var trafico = try sCctrol.SnrTrafico.initDefault(allocator);
    errdefer trafico.deinit(allocator);

    try trafico.setSeccion(allocator, "A-23/KM-12");
    trafico.setCarriles(2);
    try trafico.setVelMedia(allocator, &.{ 82.5, 79.2 });
    try trafico.setVehiculosMin(allocator, &.{ 24.0, 21.0 });

    // Note: the x1000 round-trip loop of main.zig has been left out here
    // (it was a leftover performance test, not demo logic).

    return trafico;
}

fn makePanelOrder(allocator: std.mem.Allocator) !sCctrol.PanelInfoV {
    var panel_txt = try sCctrol.TextoInfo.initDefault(allocator);
    defer panel_txt.deinit(allocator);

    try panel_txt.setNombre(allocator, "R01-PMV01-TXT01");
    try panel_txt.setTexto(allocator, "PRECAUCION: retenciones proximas");

    var panel_base = try sCctrol.PanelBase.initDefault(allocator);
    defer panel_base.deinit(allocator);

    try panel_base.setNombre(allocator, "R01-PMV01-TXT01a");
    panel_base.setTipo(.TEXTO);
    try panel_base.setDatosTexto(allocator, &panel_txt);

    var panel = try sCctrol.PanelInfoV.initDefault(allocator);
    errdefer panel.deinit(allocator);

    try panel.setNombre(allocator, "PANEL-R01-PMV01");
    try panel.appendElementos(allocator, &panel_base);

    return panel;
}

// ------------------------------------------------------------
// Input helper (identical to main.zig)
// ------------------------------------------------------------
fn readKey() !u8 {
    var buf: [1]u8 = undefined;

    while (true) {
        const n = try std.posix.read(
            std.posix.STDIN_FILENO,
            buf[0..],
        );

        if (n == 0) {
            return error.EndOfInput;
        }

        const c = buf[0];

        // Ignore enter and common spaces.
        if (c == '\n' or c == '\r' or c == ' ') {
            continue;
        }

        return c;
    }
}
