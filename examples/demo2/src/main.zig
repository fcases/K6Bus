const std = @import("std");
const k6bus = @import("k6bus");

const CctrolFile = @import("runtime/cctrol.zig");
const Cctrol = CctrolFile.cctrol;

const PubSub = @import("runtime/cctrol_pubsub.zig");
const EstMeteo_Publisher = PubSub.EstMeteo_Publisher;
const SnrTrafico_Publisher = PubSub.SnrTrafico_Publisher;
const PanelInfoV_Publisher = PubSub.PanelInfoV_Publisher;
const EstMeteo_Subscriber = PubSub.EstMeteo_Subscriber;
const SnrTrafico_Subscriber = PubSub.SnrTrafico_Subscriber;
const PanelInfoV_Subscriber = PubSub.PanelInfoV_Subscriber;

const DEFAULT_DOMAIN_ID: u32 = 77;

const Role = enum {
    cctrol,
    remotas,
};

const CliConfig = struct {
    role: Role,
    config_file: []const u8 = "cfg/k6bus.App.pb.cfg",
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
    var domain = try k6bus.Domain.createFromFile(allocator, DEFAULT_DOMAIN_ID, cli.config_file);
    defer domain.close();

    switch (cli.role) {
        .remotas => try runRemotas(allocator, domain),
        .cctrol => try runCctrol(allocator, domain),
    }
}

// ------------------------------------------------------------
// CLI
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
        \\  k6bus_demo2 cctrol  --config_file config/cctrol.zon
        \\  k6bus_demo2 remotas --config_file config/remotas.zon
        \\
        \\Roles:
        \\  remotas  - publica EstMeteo en canal "meteos" con tecla m
        \\             publica SnrTrafico en canal "trafico" con tecla t
        \\             escucha PanelInfoV en canal "paneles"
        \\
        \\  cctrol   - escucha EstMeteo en canal "meteos"
        \\             escucha SnrTrafico en canal "trafico"
        \\             publica PanelInfoV en canal "paneles" con tecla p
        \\
    , .{});
}

// ------------------------------------------------------------
// Role: remotas
// ------------------------------------------------------------
fn runRemotas(allocator: std.mem.Allocator, domain: *k6bus.Domain) !void {
    std.debug.print("Modo REMOTAS\n", .{});
    std.debug.print("m -> publicar EstMeteo en canal meteos\n", .{});
    std.debug.print("t -> publicar SnrTrafico en canal trafico\n", .{});
    std.debug.print("q -> salir\n", .{});

    var meteo_pub = try EstMeteo_Publisher.create(domain);
    var trafico_pub = try SnrTrafico_Publisher.create(domain);

    const panel_sub = try PanelInfoV_Subscriber.create(
        domain,
        "paneles",
        onPanelInfo,
    );
    defer panel_sub.close();

    while (true) {
        const key = try readKey();
        switch (key) {
            'm' => {
                var meteo = try makeMeteo(allocator);
                defer meteo.deinit(allocator);

                _ = try meteo_pub.publish("meteos", &meteo);
                std.debug.print("REMOTAS: EstMeteo publicado en meteos\n", .{});
            },

            't' => {
                var trafico = try makeTrafico(allocator);
                defer trafico.deinit(allocator);

                _ = try trafico_pub.publish("trafico", &trafico);
                std.debug.print("REMOTAS: SnrTrafico publicado en trafico\n", .{});
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
    std.debug.print("Modo CCTROL\n", .{});
    std.debug.print("p -> publicar PanelInfoV en canal paneles\n", .{});
    std.debug.print("q -> salir\n", .{});

    const meteo_sub = try EstMeteo_Subscriber.create(
        domain,
        "meteos",
        onMeteo,
    );
    defer meteo_sub.close();

    const trafico_sub = try SnrTrafico_Subscriber.create(
        domain,
        "trafico",
        onTrafico,
    );
    defer trafico_sub.close();

    var panel_pub = try PanelInfoV_Publisher.create(domain);

    while (true) {
        const key = try readKey();
        switch (key) {
            'p' => {
                var panel = try makePanelOrder(allocator);
                defer panel.deinit(allocator);

                _ = try panel_pub.publish("paneles", &panel);
                std.debug.print("CCTROL: PanelInfoV publicado en paneles\n", .{});
            },

            'q' => break,

            else => {},
        }
    }
}

// ------------------------------------------------------------
// Callbacks
// ------------------------------------------------------------
fn onMeteo(channel_name: []const u8, meteo: *const Cctrol.EstMeteo) void {
    std.debug.print(
        "CCTROL: recibido EstMeteo en canal {s}: nombre={s} temp={d} viento={d:.2} dir={d:.2}\n",
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
        "CCTROL: recibido SnrTrafico en canal {s}: seccion={s} carriles={d} vel_media_count={d} veh_min_count={d}\n",
        .{
            channel_name,
            trafico.seccion,
            trafico.carriles,
            trafico.vel_media.len,
            trafico.vehiculos_min.len,
        },
    );
}

fn onPanelInfo(channel_name: []const u8, panel: *const Cctrol.PanelInfoV) void {
    std.debug.print(
        "REMOTAS: recibido PanelInfoV en canal {s}: nombre={s} elementos={d}\n",
        .{
            channel_name,
            panel.nombre,
            panel.elementos.len,
        },
    );

    for (panel.elementos) |elem| {
        std.debug.print(
            "  PMV panel_base nombre={s} tipo={any}\n",
            .{ elem.nombre, elem.tipo },
        );

        switch (elem.datos) {
            .none => {
                std.debug.print("    datos: none\n", .{});
            },
            .senial => |senial| {
                std.debug.print(
                    "    senial: nombre={s} senial={s}\n",
                    .{ senial.nombre, senial.senial },
                );
            },
            .texto => |texto| {
                std.debug.print(
                    "    texto: nombre={s} texto={s}\n",
                    .{ texto.nombre, texto.texto },
                );
            },
        }
    }
}

// ------------------------------------------------------------
// Message factories
// ------------------------------------------------------------
fn makeMeteo(allocator: std.mem.Allocator) !Cctrol.EstMeteo {
    var meteo = try Cctrol.EstMeteo.initDefault(allocator);
    errdefer meteo.deinit(allocator);

    allocator.free(meteo.nombre);
    meteo.nombre = try allocator.dupe(u8, "meteo-remota-1");

    meteo.temp = 23;
    meteo.v_viento = 12.5;
    meteo.dir_viento = 270.0;

    return meteo;
}

fn makeTrafico(allocator: std.mem.Allocator) !Cctrol.SnrTrafico {
    var trafico = try Cctrol.SnrTrafico.initDefault(allocator);
    errdefer trafico.deinit(allocator);

    allocator.free(trafico.seccion);
    trafico.seccion = try allocator.dupe(u8, "A-23/KM-12");

    trafico.carriles = 2;

    allocator.free(trafico.vel_media);
    trafico.vel_media = try allocator.dupe(
        f32,
        &[_]f32{ 82.5, 79.2 },
    );

    allocator.free(trafico.vehiculos_min);
    trafico.vehiculos_min = try allocator.dupe(
        f32,
        &[_]f32{ 24.0, 21.0 },
    );

    return trafico;
}

fn makePanelOrder(allocator: std.mem.Allocator) !Cctrol.PanelInfoV {
    // TextoInfo
    var panel_txt = try Cctrol.TextoInfo.initDefault(allocator);
    var panel_txt_moved = false;
    errdefer if (!panel_txt_moved) panel_txt.deinit(allocator);

    allocator.free(panel_txt.nombre);
    panel_txt.nombre = try allocator.dupe(u8, "R01-PMV01-TXT01");

    allocator.free(panel_txt.texto);
    panel_txt.texto = try allocator.dupe(u8, "PRECAUCION: retenciones proximas");

    // PanelBase
    var panel_base = try Cctrol.PanelBase.initDefault(allocator);
    var panel_base_moved = false;
    errdefer if (!panel_base_moved) panel_base.deinit(allocator);

    allocator.free(panel_base.nombre);
    panel_base.nombre = try allocator.dupe(u8, "R01-PMV01-TXT01a");
    panel_base.tipo = .TEXTO;

    // Transferimos ownership de panel_txt a panel_base.datos.
    panel_base.datos = .{ .texto = panel_txt };
    panel_txt_moved = true;

    // ------------------------------------------------------------
    // PanelInfoV
    // ------------------------------------------------------------
    var panel = try Cctrol.PanelInfoV.initDefault(allocator);
    errdefer panel.deinit(allocator);

    allocator.free(panel.nombre);
    panel.nombre = try allocator.dupe(u8, "PANEL-R01-PMV01");

    // Sustituimos repeated elementos.
    // Ahora normalmente esta vacio, pero lo hacemos bien.
    for (panel.elementos) |*item| {
        item.deinit(allocator);
    }
    allocator.free(panel.elementos);

    panel.elementos = try allocator.alloc(Cctrol.PanelBase, 1);

    // Transferimos ownership de panel_base a panel.elementos[0].
    panel.elementos[0] = panel_base;
    panel_base_moved = true;

    return panel;
}

// ------------------------------------------------------------
// Input helper
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

        // Ignorar enter y espacios comunes.
        if (c == '\n' or c == '\r' or c == ' ') {
            continue;
        }

        return c;
    }
}
