const std = @import("std");
const k6bus = @import("k6bus");

const generic_pubsub = @import("generic_pubsub.zig");

const Msg = k6bus.Msg;
const Utils = k6bus.MsgUtils;
const BinaryFormat = k6bus.Config.BinaryFormat;
const ifcSubscriber = k6bus.ifcSubscriber;

// ============================================================================
// HELPERS
// ============================================================================
//
// Los tipos generados por la API segura contienen:
//
//     impl: DatumRaw
//
// SafePublisher utiliza el raw interno para delegar en GenericPublisher.
// SafeSubscriber utiliza el tipo raw para calcular el mismo msgType que la
// versión raw, pero deserializa directamente un DatumApi.
// ============================================================================

fn RawType(comptime DatumApi: type) type {
    if (!@hasField(DatumApi, "impl")) {
        @compileError(
            @typeName(DatumApi) ++
                " no contiene el campo impl requerido por safe_pubsub",
        );
    }

    return @FieldType(DatumApi, "impl");
}

// ============================================================================
// FORMAT CONVERSION
// ============================================================================
//
// Config.BinaryFormat y el BinaraFormato generado por ProtobuZig son enums
// diferentes aunque compartan los mismos valores.
//
// Esta conversión mantiene el formato configurado en Domain.
// ============================================================================

fn binaryFormatToBinaraFormato(
    comptime BinaraFormato: type,
    value: BinaryFormat,
) BinaraFormato {
    return std.meta.intToEnum(
        BinaraFormato,
        @intFromEnum(value),
    ) catch .BF_PROTOBUF;
}

// ============================================================================
// SAFE PUBLISHER
// ============================================================================
//
// SafePublisher es un wrapper genérico sobre GenericPublisher.
//
// DatumApi:
//     Wrapper generado en <package>_api.zig.
//
// DatumRaw:
//     Tipo deducido desde DatumApi.impl.
//
// La publicación:
//
//     - recibe un DatumApi;
//     - presta &datum.impl al GenericPublisher;
//     - no modifica DatumApi;
//     - no adquiere ownership de DatumApi;
//     - reutiliza todo el flujo raw de serialización y envío.
// ============================================================================

pub fn SafePublisher(
    comptime DatumApi: type,
    comptime BinaraFormato: type,
) type {
    const DatumRaw = RawType(DatumApi);

    const GenericPublisherType =
        generic_pubsub.GenericPublisher(
            DatumRaw,
            BinaraFormato,
        );

    return struct {
        generic_publisher: GenericPublisherType,

        const Self = @This();

        // --------------------------------------------------------------------
        // CREATE
        // --------------------------------------------------------------------

        pub fn create(
            domain: *k6bus.Domain,
        ) !Self {
            return .{
                .generic_publisher = try GenericPublisherType.create(domain),
            };
        }

        // --------------------------------------------------------------------
        // PUBLISH
        // --------------------------------------------------------------------

        pub fn publish(
            self: *Self,
            channel_name: []const u8,
            datum: *const DatumApi,
        ) !bool {
            return try self.generic_publisher.publish(
                channel_name,
                &datum.impl,
            );
        }

        // --------------------------------------------------------------------
        // PUBLISH TO CHANNELS
        // --------------------------------------------------------------------

        pub fn publishToChannels(
            self: *Self,
            channel_names: []const []const u8,
            datum: *const DatumApi,
        ) !bool {
            return try self.generic_publisher.publishToChannels(
                channel_names,
                &datum.impl,
            );
        }
    };
}

// ============================================================================
// SAFE SUBSCRIBER
// ============================================================================
//
// SafeSubscriber es una implementación genérica autónoma.
//
// Está basada en la estructura y los contratos de GenericSubscriber, pero:
//
//     - trabaja directamente con DatumApi;
//     - almacena una callback segura;
//     - deserializa mediante DatumApi.deserializeFromBin();
//     - entrega exclusivamente tipos de la API segura.
//
// El objeto registrado en Domain es directamente SafeSubscriber.
//
// No existe:
//
//     - un GenericSubscriber interno;
//     - un wrapper adicional;
//     - una callback comptime;
//     - un contexto global;
//     - una vista superficial del dato raw.
//
// DatumApi es owned temporalmente por SafeSubscriber durante el callback.
//
// La callback:
//
//     - no debe ejecutar datum.deinit();
//     - no debe conservar datum ni sus slices internos;
//     - puede ejecutar datum.clone() si necesita conservar una copia owned.
// ============================================================================

pub fn SafeSubscriber(
    comptime DatumApi: type,
    comptime BinaraFormato: type,
) type {
    const DatumRaw = RawType(DatumApi);

    return struct {
        // --------------------------------------------------------------------
        // CALLBACK
        // --------------------------------------------------------------------

        pub const DatumCallback = *const fn (
            allocator: std.mem.Allocator,
            channel_name: []const u8,
            datum: *const DatumApi,
        ) void;

        // --------------------------------------------------------------------
        // STATE
        // --------------------------------------------------------------------

        domain: *k6bus.Domain,

        name: []const u8,
        channel_name: []const u8,

        channel: u64,
        msgType: u64,

        callback: DatumCallback,

        qm: k6bus.QueueMgr,

        binary_format: BinaraFormato = .BF_PROTOBUF,

        const Self = @This();

        // --------------------------------------------------------------------
        // CREATE
        // --------------------------------------------------------------------

        pub fn create(
            domain: *k6bus.Domain,
            channel_name: []const u8,
            callback: DatumCallback,
        ) !*Self {
            const self =
                try domain.allocator.create(Self);
            errdefer domain.allocator.destroy(self);

            try self.init(
                domain,
                channel_name,
                callback,
            );

            return self;
        }

        // --------------------------------------------------------------------
        // INIT
        // --------------------------------------------------------------------

        fn init(
            self: *Self,
            domain: *k6bus.Domain,
            channel_name: []const u8,
            callback: DatumCallback,
        ) !void {
            const allocator = domain.allocator;

            self.domain = domain;
            self.callback = callback;

            self.channel_name =
                try allocator.dupe(u8, channel_name);
            errdefer allocator.free(self.channel_name);

            self.channel =
                k6bus.Hash.hashChannel(channel_name);

            // El hash se calcula con DatumRaw para mantener interoperabilidad
            // entre publishers y subscribers raw y seguros.
            self.msgType = k6bus.Hash.hashMsgType(
                domain.id,
                @typeName(DatumRaw),
            );

            self.binary_format =
                binaryFormatToBinaraFormato(
                    BinaraFormato,
                    domain.dom_cfg.binary_format,
                );

            const id =
                @intFromPtr(self) >> 4 & 0xFFFF;

            self.name = try std.fmt.allocPrint(
                allocator,
                "{s}SafeSubscriber_{X:0>4}",
                .{
                    @typeName(DatumRaw),
                    id,
                },
            );
            errdefer allocator.free(self.name);

            self.qm = try k6bus.QueueMgr.create(
                domain,
                self.name,
                domain.dom_cfg.dispatch_mode,
                @intCast(
                    domain.dom_cfg.dispatch_batch_time_ms,
                ),
                self,
                dispatchMsg,
            );
            errdefer self.qm.close();

            const subscriber_ifc =
                ifcSubscriber.init(self);

            try domain.registerSubscriber(
                self.channel,
                self.msgType,
                subscriber_ifc,
            );
            errdefer domain.unregisterSubscriber(
                subscriber_ifc,
            );

            if (domain.dom_cfg.start_at_init) {
                try self.start();
            }
        }

        // --------------------------------------------------------------------
        // DEINIT
        // --------------------------------------------------------------------

        fn deinit(self: *Self) void {
            const allocator = self.domain.allocator;

            allocator.free(self.name);
            allocator.free(self.channel_name);
        }

        // --------------------------------------------------------------------
        // DISPATCH
        // --------------------------------------------------------------------
        //
        // QueueMgr transfiere a dispatchMsg el ownership de los Msg contenidos
        // en msg_list.
        //
        // Cada Msg se libera exactamente una vez mediante Utils.freeMsg().
        //
        // El DatumApi deserializado pertenece temporalmente a esta función y
        // se destruye después de ejecutar la callback.
        // --------------------------------------------------------------------

        fn dispatchMsg(
            owner: *anyopaque,
            msg_list: []const Msg,
        ) void {
            const self: *Self =
                @ptrCast(@alignCast(owner));

            const allocator =
                self.domain.allocator;

            for (msg_list) |*msg| {
                defer Utils.freeMsg(
                    allocator,
                    @constCast(msg),
                );

                if (msg.msgType != self.msgType) {
                    continue;
                }

                var datum =
                    DatumApi.deserializeFromBin(
                        allocator,
                        msg.payLoad,
                        self.binary_format,
                    ) catch |err| {
                        self.domain.logger.warning(
                            "{s} failed to deserialize {s}: {}",
                            .{
                                self.name,
                                @typeName(DatumRaw),
                                err,
                            },
                            @src(),
                        );

                        continue;
                    };
                defer datum.deinit(allocator);

                self.callback(
                    allocator,
                    self.channel_name,
                    &datum,
                );
            }
        }

        // --------------------------------------------------------------------
        // START
        // --------------------------------------------------------------------

        pub fn start(self: *Self) !void {
            try self.qm.start();
        }

        // --------------------------------------------------------------------
        // STOP
        // --------------------------------------------------------------------

        pub fn stop(self: *Self) void {
            self.qm.stop();
        }

        // --------------------------------------------------------------------
        // CLOSE
        // --------------------------------------------------------------------
        //
        // Domain debe extraer el subscriber del registro antes de llamar a
        // close().
        //
        // Baja dinámica:
        //
        //     domain.closeSubscriber(subscriber.interface());
        //
        // Cierre global:
        //
        //     Domain.takeFirstSubscriber()
        //         -> subscriber.close()
        //
        // No se llama a unregisterSubscriber() desde close().
        // --------------------------------------------------------------------

        pub fn close(self: *Self) void {
            self.qm.close();

            self.deinit();
            self.domain.allocator.destroy(self);
        }

        // --------------------------------------------------------------------
        // ENQUEUE
        // --------------------------------------------------------------------
        //
        // En éxito, QueueMgr adquiere el ownership del Msg.
        //
        // En error, el caller conserva el ownership completo del Msg.
        // --------------------------------------------------------------------

        pub fn enqueue(
            self: *Self,
            msg: Msg,
        ) !void {
            try self.qm.enqueue(msg);
        }

        // --------------------------------------------------------------------
        // INTERFACE
        // --------------------------------------------------------------------

        pub fn interface(
            self: *Self,
        ) ifcSubscriber {
            return ifcSubscriber.init(self);
        }
    };
}
