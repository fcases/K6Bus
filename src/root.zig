const core = struct {
    const cipherFile = @import("core/cipher.zig");
    const domainFile = @import("core/domain.zig");
    const encodingFile = @import("core/encoding.zig");
    const hashFile = @import("core/hash.zig");
    const loggerFile = @import("core/logger.zig");
    const queue_mgrFile = @import("core/queue_mgr.zig");
    const stream_queueFile = @import("core/stream_queue.zig");
    const packet_processorFile = @import("core/packet_processor.zig");

    const ifc_transportFile = @import("core/ifc_transport.zig");
    const loop_transportFile = @import("core/loop_transport.zig");
    const udp_transportFile = @import("core/udp_transport.zig");
    const udp_star_transportFile = @import("core/udpstar_transport.zig");
    const usox_star_trasnportFile = @import("core/usoxstar_transport.zig");
    const matrix_transportFile = @import("core/matrix_transport.zig");
    const ifcSubscriberFile = @import("core/ifc_subscriber.zig");
    const msg_utilsFile = @import("core/msg_utils.zig");

    const exportsCFile = @import("core/exports_c.zig");
};

const generated = struct {
    const ConfigFile = @import("generated/Config.zig");
    const TypesFile = @import("generated/types.zig");
    const SecurityFile = @import("generated/Security.zig");
};

// ------------------------------------------------------------
// API pública principal
// ------------------------------------------------------------

//pub const Cipher = core.cipherFile.Cipher;
pub const Domain = core.domainFile.Domain;
//pub const Encoding = core.encodingFile.Encoding;
pub const Hash = core.hashFile;
pub const Logger = core.loggerFile.Logger;
pub const MsgUtils = core.msg_utilsFile;
pub const QueueMgr = core.queue_mgrFile.QueueMgr;
//pub const StreamQueue = core.stream_queueFile.StreamQueue;
pub const PacketProcessor = core.packet_processorFile.PacketProcessor;

pub const ifcTransport = core.ifc_transportFile.ifcTransport;
pub const LoopTransport = core.loop_transportFile.LoopTransport;
pub const MCastTransport = core.udp_transportFile.MCastTransport;
pub const BCastTransport = core.udp_transportFile.BCastTransport;
pub const UDPStarEndPoint = core.udp_star_transportFile.EndPoint;
pub const UDPStarTransport = core.udp_star_transportFile.UDPStarTransport;
pub const USOXStarTransport = core.usox_star_trasnportFile.USOXStarTransport;
pub const MatrixTransport = core.matrix_transportFile.MatrixTransport;
pub const Config = generated.ConfigFile.k6bus.config;
pub const Msg = generated.TypesFile.k6bus.Msg;
//pub const Packet = generated.TypesFile.k6bus.Packet;
pub const Security = generated.SecurityFile.k6bus.security;

pub const ifcSubscriber = core.ifcSubscriberFile.ifcSubscriber;
pub const exports_c = core.exportsCFile;

// ----------------------------------------------------------------------------
// AGREGADOR DE TESTS (R1, 2026-09-10)
// ----------------------------------------------------------------------------
// `zig build test` compila src/root.zig como raiz: solo se recogen los tests
// de los ficheros que se ANALIZAN. Como los modulos core se importan en
// consts que pueden no referenciarse, este bloque fuerza su analisis y con el
// la recoleccion de sus `test`.
// ----------------------------------------------------------------------------
test {
    _ = @import("core/cipher.zig");
    _ = @import("core/core_tests.zig");
    _ = @import("core/domain.zig");
    _ = @import("core/encoding.zig");
    _ = @import("core/hash.zig");
    _ = @import("core/logger.zig");
    _ = @import("core/msg_utils.zig");
    _ = @import("core/queue_mgr.zig");
    _ = @import("core/stream_queue.zig");
    _ = @import("core/packet_processor.zig");
    _ = @import("core/ifc_transport.zig");
    _ = @import("core/loop_transport.zig");
    _ = @import("core/udp_transport.zig");
    _ = @import("core/udpstar_transport.zig");
    _ = @import("core/usoxstar_transport.zig");
    _ = @import("core/matrix_transport.zig");
    _ = @import("core/ifc_subscriber.zig");
    _ = @import("core/generic_pubsub.zig");
    _ = @import("core/safe_pubsub.zig");
}
