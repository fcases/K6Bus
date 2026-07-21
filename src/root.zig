const core = struct {
    const domain = @import("core/domain.zig");
    const encoding = @import("core/encoding.zig");
    const hash = @import("core/hash.zig");
    const logger = @import("core/logger.zig");
    const loop_transport = @import("core/loop_transport.zig");
    const queue_mgr = @import("core/queue_mgr.zig");
    const cipher = @import("core/cipher.zig");
    const stream_queue = @import("core/stream_queue.zig");
    const transport = @import("core/transport.zig");
};

const generated = struct {
    const MsgFile = @import("generated/Msg.zig");
    const PacketFile = @import("generated/Packet.zig");
    const ConfigFile = @import("generated/Config.zig");
    const SecurityFile = @import("generated/Security.zig");
};

// ------------------------------------------------------------
// API pública principal
// ------------------------------------------------------------

pub const Domain = core.domain.Domain;
pub const Logger = core.logger;
pub const QueueMgr = core.queue_mgr;
pub const Transport = core.transport;
pub const Hash = core.hash;

pub const Msg = generated.MsgFile.k6bus.msg.Msg;
//pub const Packet = generated.PacketFile.k6bus.pkgpb.Packet;

pub const Config = generated.ConfigFile.k6bus.config;
pub const Security = generated.SecurityFile.k6bus.security;
