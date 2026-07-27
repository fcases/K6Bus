pub const estacion = @import("estacion_pubsub.zig");
pub const EstacionFile = @import("Estacion.zig");

pub const Estacion = EstacionFile.demo1.Estacion;
// pub const Estacion = estacion.Estacion;
pub const EstacionPublisher = estacion.EstacionPublisher;
pub const EstacionSubscriber = estacion.EstacionSubscriber;
