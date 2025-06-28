const std = @import("std");
const constants = @import("constants.zig");
const global_constants = @import("constants.zig");

pub const Operation = enum(u8) {
    /// Operations exported by TigerBeetle:
    pulse = constants.operations_reserved + 0,

    // for testing
    print = constants.operations_reserved + 1,
    add = constants.operations_reserved + 2,
};

const add_request_struct = struct {
    a: u32,
    b: u32,
};
pub fn EventType(comptime operation: Operation) type {
    return switch (operation) {
        .pulse => void,
        .print => void,
        .add => add_request_struct,
    };
}

pub fn ResultType(comptime operation: Operation) type {
    return switch (operation) {
        .pulse => void,
        .print => void,
        .add => u32,
    };
}

pub fn CallType(comptime operation: Operation) fn (EventType(operation), *align(16) [1024]u8) ResultType(operation) {
    return switch (operation) {
        .pulse => print,
        .print => print,
        .add => add,
    };
}

fn print(
    // timestamp: u64,
    message_body_used: void,
    output_buffer: *align(16) [global_constants.message_body_size_max]u8,
) void {
    _ = message_body_used;
    _ = output_buffer;
    std.debug.print("ran print \r\n", .{});
}

fn add(
    // timestamp: u64,
    message_body_used: add_request_struct,
    output_buffer: *align(16) [global_constants.message_body_size_max]u8,
) u32 {
    _ = output_buffer;
    const added = message_body_used.a + message_body_used.b;
    std.debug.print("ran add {} + {} = {} \r\n", .{ message_body_used.a, message_body_used.b, added });
    return added;
}
