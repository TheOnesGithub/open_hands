const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const lmdb = @import("lmdb");

// todo: make a better name
pub const system = struct {
    pub const Operation = enum(u8) {
        login_client = 0,
    };

    pub const operations = struct {
        pub const login_client = struct {
            pub const Body = struct {};
            pub const Result = struct {};
            pub const State = struct {};
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                _ = rep;
                _ = state;
                _ = body;
                _ = result;
                std.debug.print("login client kv\r\n", .{});
                return .done;
            }
        };
    };
};
