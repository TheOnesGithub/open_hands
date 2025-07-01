const std = @import("std");
const replica = @import("replica.zig");
const main = @import("main.zig");
const StackStringZig = @import("stack_string.zig");
const global_constants = @import("constants.zig");

pub const operations = struct {
    pub const print = struct {
        pub const Body = void;
        pub const Result = StackStringZig.StackString(64);
        pub const State = struct {
            is_waited_add: bool = false,
            add_result: add.Result,
            print_result: make_string.Result,
        };
        pub fn call(rep: *main.Replica, body: *Body, result: *Result, state: *State) replica.Handled_Status {
            _ = body;
            if (state.is_waited_add) {
                // std.debug.print("print after added got: {}\r\n", .{state.add_result});
                result.* = state.print_result;
                return .done;
            }
            // std.debug.print("from print \r\n", .{});
            const add_message_id = rep.call_local(.add, add.Body{ .a = 2, .b = 2 }, &state.add_result);
            rep.add_wait(&add_message_id);
            const make_string_message_id = rep.call_local(.make_string, make_string.Body{}, &state.print_result);
            rep.add_wait(&make_string_message_id);
            state.is_waited_add = true;
            return .wait;
        }
    };
    pub const add = struct {
        pub const Body = struct {
            a: u32,
            b: u32,
        };
        pub const Result = u32;
        pub const State = struct {};
        pub fn call(rep: *main.Replica, body: *Body, result: *Result, state: *State) replica.Handled_Status {
            _ = rep;
            _ = state;
            const added = body.a + body.b;
            result.* = added;
            return .done;
        }
    };
    pub const make_string = struct {
        pub const Body = struct {};
        pub const Result = StackStringZig.StackString(64);
        pub const State = struct {};
        pub fn call(rep: *main.Replica, body: *Body, result: *Result, state: *State) replica.Handled_Status {
            _ = rep;
            _ = state;
            _ = body;
            result.* = Result.init("made string in make string");
            return .done;
        }
    };

    pub const login_server = struct {
        pub const Body = struct {
            username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
            password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
        };
        pub const Result = struct {
            is_logged_in_successfully: bool,
        };
        pub const State = struct {};
        pub fn call(rep: *main.Replica, body: *Body, result: *Result, state: *State) replica.Handled_Status {
            _ = rep;
            _ = state;
            _ = body;
            result.* = Result{
                .is_logged_in_successfully = true,
            };
            return .done;
        }
    };

    pub const login_client = struct {
        pub const Body = struct {
            username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
            password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
        };
        pub const Result = struct {};
        pub const State = struct {
            is_has_ran: bool = false,
            login_result: login_server.Result = .{ .is_logged_in_successfully = false },
        };
        pub fn call(rep: *main.Replica, body: *Body, result: *Result, state: *State) replica.Handled_Status {
            _ = result;
            if (state.is_has_ran) {
                return .done;
            }
            const add_message_id = rep.call_remote(.login_server, login_server.Body{
                .username = body.username,
                .password = body.password,
            }, &state.login_result);
            rep.add_wait(&add_message_id);
            state.is_has_ran = true;
            return .wait;
        }
    };
};
