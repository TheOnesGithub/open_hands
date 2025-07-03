const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const lmdb = @import("lmdb");
const httpz = @import("httpz");
pub const AppState = struct {
    conn: *httpz.websocket.Conn,
};

pub const remote_services = [_]replica.RemoteService{};

// todo: make a better name
pub const system = struct {
    pub const Operation = enum(u8) {
        login_client = 0,
    };

    pub const operations = struct {
        pub const login_client = struct {
            pub const Body = struct {
                username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
                password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
            };
            pub const Result = struct {
                is_logged_in_successfully: bool,
            };
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
