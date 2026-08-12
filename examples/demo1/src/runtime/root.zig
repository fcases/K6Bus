pub const estacion_ps = @import("estacion_pubsub.zig");
pub const EstacionFile = @import("Estacion.zig");

pub const Estacion = EstacionFile.demo1.Estacion;
pub const EstacionPublisher = estacion_ps.EstacionPublisher;
pub const EstacionSubscriber = estacion_ps.EstacionSubscriber;
