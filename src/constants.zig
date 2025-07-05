const Header = @import("message_header.zig");
const uuid = @import("uuid.zig");

pub const operations_reserved: u8 = 128;

pub const message_size_max = 1024;
pub const message_body_size_max = message_size_max - @sizeOf(Header);
pub const message_number_max = 1024;
pub const message_wait_on_map_buffer_size = message_number_max * @sizeOf(uuid.UUID);

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

pub const MAX_USERNAME_LENGTH = 16;
pub const MAX_EMAIL_LENGTH = 64;
pub const MAX_PASSWORD_LENGTH = 64;
pub const max_display_name_length = 64;
pub const PASSWORD_HASH_LENGTH = 128;

pub const max_key_length = 512;
pub const max_value_length = 1024 * 1024 * 25;
