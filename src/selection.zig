const std = @import("std");
const replica = @import("replica.zig");
const main = @import("main.zig");
const StackStringZig = @import("stack_string.zig");
const global_constants = @import("constants.zig");

pub const operations_server = struct {
    pub const Operation = enum(u8) {
        print = 0,
        add = 1,
        make_string = 2,
        login_server = 3,
    };

    pub const operations = struct {
        pub const print = struct {
            pub const Body = void;
            pub const Result = StackStringZig.StackString(64);
            pub const State = struct {
                is_waited_add: bool = false,
                add_result: add.Result,
                print_result: make_string.Result,
            };
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                _ = body;

                const repd: *replica.ReplicaType(
                    operations_server,
                ) = @alignCast(@ptrCast(rep));
                if (state.is_waited_add) {
                    // std.debug.print("print after added got: {}\r\n", .{state.add_result});
                    result.* = state.print_result;
                    return .done;
                }
                // std.debug.print("from print \r\n", .{});
                const add_message_id = repd.call_local(.add, add.Body{ .a = 2, .b = 2 }, &state.add_result);
                repd.add_wait(&add_message_id);
                const make_string_message_id = repd.call_local(.make_string, make_string.Body{}, &state.print_result);
                repd.add_wait(&make_string_message_id);
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
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
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
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
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
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                _ = rep;
                _ = state;
                _ = body;
                result.* = Result{
                    .is_logged_in_successfully = true,
                };
                return .done;
            }
        };
    };

    pub fn BodyType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).Body;
    }

    pub fn ResultType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).Result;
    }

    pub fn StateType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).State;
    }

    pub fn CallType(comptime operation: Operation) fn (
        *anyopaque,
        *BodyType(operation),
        *ResultType(operation),
        *StateType(operation),
    ) replica.Handled_Status {
        return @field(operations, @tagName(operation)).call;
    }

    comptime {
        for (std.meta.fields(operations)) |field| {
            const TBody = @field(operations, field.name).Body;
            if (@alignOf(TBody) != 16) {
                @compileError("body " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TBody)));
            }

            const TResult = @field(operations, field.name).Result;
            if (@alignOf(TResult) != 16) {
                @compileError("result " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TResult)));
            }
            const TState = @field(operations, field.name).State;
            if (@alignOf(TState) != 16) {
                @compileError("state " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TState)));
            }
        }
    }
};

pub const operations_client = struct {
    pub const Operation = enum(u8) {
        login_client = 0,
    };

    pub const operations = struct {
        pub const login_client = struct {
            pub const Body = struct {
                username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
                password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
            };
            pub const Result = struct {};
            pub const State = struct {
                is_has_ran: bool = false,
                login_result: operations_server.operations.login_server.Result = .{ .is_logged_in_successfully = false },
            };
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                const repd: *replica.ReplicaType(
                    operations_client,
                ) = @alignCast(@ptrCast(rep));
                _ = result;
                if (state.is_has_ran) {
                    return .done;
                }
                const add_message_id = repd.call_remote(
                    operations_server,
                    .login_server,
                    operations_server.operations.login_server.Body{
                        .username = body.username,
                        .password = body.password,
                    },
                    &state.login_result,
                );
                repd.add_wait(&add_message_id);
                state.is_has_ran = true;
                return .wait;
            }
        };
    };

    pub fn BodyType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).Body;
    }

    pub fn ResultType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).Result;
    }

    pub fn StateType(comptime operation: Operation) type {
        return @field(operations, @tagName(operation)).State;
    }

    pub fn CallType(comptime operation: Operation) fn (
        *anyopaque,
        *BodyType(operation),
        *ResultType(operation),
        *StateType(operation),
    ) replica.Handled_Status {
        return @field(operations, @tagName(operation)).call;
    }

    comptime {
        for (std.meta.fields(operations)) |field| {
            const TBody = @field(operations, field.name).Body;
            if (@alignOf(TBody) != 16) {
                @compileError("body " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TBody)));
            }

            const TResult = @field(operations, field.name).Result;
            if (@alignOf(TResult) != 16) {
                @compileError("result " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TResult)));
            }
            const TState = @field(operations, field.name).State;
            if (@alignOf(TState) != 16) {
                @compileError("state " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TState)));
            }
        }
    }
};
