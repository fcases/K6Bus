const core = struct {
    const cipherFile = @import("core/cipher.zig");
    const domainFile = @import("core/domain.zig");
    const encodingFile = @import("core/encoding.zig");
    const hashFile = @import("core/hash.zig");
    const loggerFile = @import("core/logger.zig");
    const loop_transportFile = @import("core/loop_transport.zig");
    const msg_utilsFile = @import("core/msg_utils.zig");
    const queue_mgrFile = @import("core/queue_mgr.zig");
    const stream_queueFile = @import("core/stream_queue.zig");
    const packet_processorFile = @import("core/packet_processor.zig");
    const ifc_transportFile = @import("core/ifc_transport.zig");
    const udp_transportFile = @import("core/udp_transport.zig");
    const ifcSubscriberFile = @import("core/ifc_subscriber.zig");
};

const generated = struct {
    const ConfigFile = @import("generated/Config.zig");
    const MsgFile = @import("generated/Msg.zig");
    const PacketFile = @import("generated/Packet.zig");
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
pub const LoopTransport = core.loop_transportFile.LoopTransport;
pub const MsgUtils = core.msg_utilsFile;
pub const QueueMgr = core.queue_mgrFile.QueueMgr;
//pub const StreamQueue = core.stream_queueFile.StreamQueue;
pub const PacketProcessor = core.packet_processorFile.PacketProcessor;
pub const ifcTransport = core.ifc_transportFile.ifcTransport;
pub const MCastTransport = core.udp_transportFile.MCastTransport;
pub const BCastTransport = core.udp_transportFile.BCastTransport;

pub const Config = generated.ConfigFile.k6bus.config;
pub const Msg = generated.MsgFile.k6bus.msg.Msg;
//pub const Packet = generated.PacketFile.k6bus.pkgpb.Packet;
pub const Security = generated.SecurityFile.k6bus.security;

pub const ifcSubscriber = core.ifcSubscriberFile.ifcSubscriber;
