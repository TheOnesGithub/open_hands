const std = @import("std");
const constants = @import("constants.zig");

pub const Operation = enum(u8) {
    /// Operations exported by TigerBeetle:
    pulse = constants.operations_reserved + 0,

    // for testing
    print = constants.operations_reserved + 1,
};

pub fn print_test() void {
    std.debug.print("ran print_test\r\n");
}
