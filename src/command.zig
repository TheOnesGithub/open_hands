const std = @import("std");
const assert = std.debug.assert;

pub const Command = enum(u8) {
    // Looking to make backwards incompatible changes here? Make sure to check release.zig for
    // `release_triple_client_min`.

    reserved = 0,

    ping_client = 3,
    pong_client = 4,

    request = 5,
    reply = 8,

    headers = 17,

    eviction = 18,

    // If a command is removed from the protocol, its ordinal is added here and can't be re-used.
    // future_deprected_thing = 0, // start_view with an older version of CheckpointState

    comptime {
        // for (std.enums.values(Command)) |command| {
        //     assert(@intFromEnum(command) < std.enums.values(Command).len);
        // }
    }
};
