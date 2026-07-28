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
    const transportFile = @import("core/transport.zig");
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
pub const Transport = core.transportFile.Transport;

pub const Config = generated.ConfigFile.k6bus.config;
pub const Msg = generated.MsgFile.k6bus.msg.Msg;
//pub const Packet = generated.PacketFile.k6bus.pkgpb.Packet;
pub const Security = generated.SecurityFile.k6bus.security;
