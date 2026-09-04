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
pub const Config = generated.ConfigFile.k6bus.config;
pub const Msg = generated.TypesFile.k6bus.Msg;
//pub const Packet = generated.TypesFile.k6bus.Packet;
pub const Security = generated.SecurityFile.k6bus.security;

pub const ifcSubscriber = core.ifcSubscriberFile.ifcSubscriber;
pub const exports_c = core.exportsCFile;
