const Header = @import("message_header.zig");

pub const operations_reserved: u8 = 128;

pub const message_size_max = 1024;
pub const message_body_size_max = message_size_max - @sizeOf(Header);
pub const message_number_max = 1024;

pub const StateMachineConfig = struct {
    // release: vsr.Release,
    message_body_size_max: comptime_int,
    // lsm_compaction_ops: comptime_int,
};

pub const state_machine_config = StateMachineConfig{
    // .release = config.process.release,
    .message_body_size_max = message_body_size_max,
    // .lsm_compaction_ops = lsm_compaction_ops,
};
