const pubsub = @import("generic_pubsub.zig");

const CctrolFile = @import("cctrol.zig");
const Cctrol = CctrolFile.cctrol;

pub const CCtrol_Publisher =
    pubsub.GenericPublisher(Cctrol.CCtrol, CctrolFile.BinaraFormato);
pub const EstRemCtrol_Publisher =
    pubsub.GenericPublisher(Cctrol.EstRemCtrol, CctrolFile.BinaraFormato);
pub const EstMeteo_Publisher =
    pubsub.GenericPublisher(Cctrol.EstMeteo, CctrolFile.BinaraFormato);
pub const SnrTrafico_Publisher =
    pubsub.GenericPublisher(Cctrol.SnrTrafico, CctrolFile.BinaraFormato);
pub const PanelInfoV_Publisher =
    pubsub.GenericPublisher(Cctrol.PanelInfoV, CctrolFile.BinaraFormato);
pub const PanelSimple_Publisher =
    pubsub.GenericPublisher(Cctrol.PanelSimple, CctrolFile.BinaraFormato);
pub const SenialInfo_Publisher =
    pubsub.GenericPublisher(Cctrol.SenialInfo, CctrolFile.BinaraFormato);
pub const TextoInfo_Publisher =
    pubsub.GenericPublisher(Cctrol.TextoInfo, CctrolFile.BinaraFormato);

pub const CCtrol_Subscriber =
    pubsub.GenericSubscriber(Cctrol.CCtrol, CctrolFile.BinaraFormato);
pub const EstRemCtrol_Subscriber =
    pubsub.GenericSubscriber(Cctrol.EstRemCtrol, CctrolFile.BinaraFormato);
pub const EstMeteo_Subscriber =
    pubsub.GenericSubscriber(Cctrol.EstMeteo, CctrolFile.BinaraFormato);
pub const SnrTrafico_Subscriber =
    pubsub.GenericSubscriber(Cctrol.SnrTrafico, CctrolFile.BinaraFormato);
pub const PanelInfoV_Subscriber =
    pubsub.GenericSubscriber(Cctrol.PanelInfoV, CctrolFile.BinaraFormato);
pub const PanelSimple_Subscriber =
    pubsub.GenericSubscriber(Cctrol.PanelSimple, CctrolFile.BinaraFormato);
pub const SenialInfo_Subscriber =
    pubsub.GenericSubscriber(Cctrol.SenialInfo, CctrolFile.BinaraFormato);
pub const TextoInfo_Subscriber =
    pubsub.GenericSubscriber(Cctrol.TextoInfo, CctrolFile.BinaraFormato);
