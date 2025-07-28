const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const system_gateway = @import("../gateway/gateway.zig").system;
const send = @import("../../wasm.zig").send;
const uuid = @import("../../uuid.zig");

const print_wasm = @import("../../wasm.zig").print_wasm;

const GlobalState = struct {
    user_id: ?uuid.UUID,
    display_name: ?StackStringZig.StackString(u8, global_constants.max_display_name_length),
    username: ?StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
};

pub var global_state: GlobalState = .{
    .user_id = null,
    .display_name = null,
    .username = null,
};

pub var check_global_state: GlobalState = .{
    .user_id = null,
    .display_name = null,
    .username = null,
};

pub const AppState = struct {};

fn get_channge(comptime CheckType: type, s: *CheckType, check: *CheckType, prefix: []const u8) void {
    const T = @TypeOf(s.*);
    const info = @typeInfo(T).@"struct";
    inline for (info.fields) |field| {
        var skip = false;
        if (std.meta.eql(@field(s.*, field.name), @field(check.*, field.name))) {
            skip = true;
        }

        if (!skip) {
            var buffer: [128]u8 = undefined;

            // Copy both slices into the result
            std.mem.copyForwards(u8, buffer[0..prefix.len], prefix);
            std.mem.copyForwards(u8, buffer[prefix.len .. prefix.len + field.name.len], field.name);
            print_wasm(@ptrCast(&buffer), prefix.len + field.name.len);
            @import("../../wasm.zig").update_data(@ptrCast(&buffer), prefix.len + field.name.len);
        }
    }
}

pub const remote_services = [_]replica.RemoteService{
    .{
        .service_type = @import("../../systems/gateway/gateway.zig").system,
        .call = &call_gateway,
    },
};

pub fn call_gateway(ptr: [*]const u8, len: usize) void {
    send(ptr, len);
}

pub const Replica = replica.ReplicaType(
    system,
    AppState,
    &remote_services,
    5,
    1024 * 4,
);

pub const system = SystemType();
pub fn SystemType() type {
    return struct {
        const System = @This();

        const user_id: ?uuid.UUID = null;

        pub const Operation = enum(u8) {
            signup_client = 0,
            login_client = 1,
            add_timer = 2,
        };

        pub const operations = struct {
            pub const signup_client = struct {
                pub const Body = struct {
                    username: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
                    email: StackStringZig.StackString(u8, global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(u8, global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {};
                pub const State = struct {
                    is_has_ran: bool = false,
                    signup_result: system_gateway.operations.signup.Result = .{ .is_signed_up_successfully = false },
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = connection_state;
                    _ = self;
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    _ = result;
                    if (state.is_has_ran) {
                        return .done;
                    }
                    const add_message_id = repd.call_remote(
                        system_gateway,
                        .signup,
                        system_gateway.operations.signup.Body{
                            .username = body.username,
                            .email = body.email,
                            .password = body.password,
                        },
                        &state.signup_result,
                    ) catch {
                        const temp = "failed to call kv\r\n";
                        print_wasm(temp.ptr, temp.len);
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    return .wait;
                }
            };

            pub const login_client = struct {
                pub const Body = struct {
                    email: StackStringZig.StackString(u8, global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(u8, global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {};
                pub const State = struct {
                    is_has_ran: bool = false,
                    login_result: system_gateway.operations.login.Result = .{
                        .is_logged_in_successfully = false,
                        .user_id = undefined,
                        .display_name = undefined,
                        .username = undefined,
                    },
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = connection_state;
                    _ = self;
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    _ = result;

                    const ran_check_0 = "client login ran check";
                    print_wasm(ran_check_0, ran_check_0.len);
                    if (state.is_has_ran) {
                        const ran_check = "ran check is has ran";
                        print_wasm(ran_check, ran_check.len);

                        if (state.login_result.is_logged_in_successfully) {
                            global_state.user_id = state.login_result.user_id;
                            const user_id_2 = global_state.user_id.?.toHex(.lower);
                            print_wasm(&user_id_2, user_id_2.len);
                            global_state.username = state.login_result.username;
                            const username = global_state.username.?.to_slice() catch {
                                const temp = "failed to get from stack string: {s}\r\n";
                                print_wasm(temp, temp.len);
                                return .done;
                            };
                            print_wasm(username.ptr, username.len);

                            global_state.display_name = state.login_result.display_name;
                            const display_name = global_state.display_name.?.to_slice() catch {
                                const temp = "failed to get from stack string: {s}\r\n";
                                print_wasm(temp, temp.len);
                                return .done;
                            };
                            print_wasm(display_name.ptr, display_name.len);

                            get_channge(GlobalState, &global_state, &check_global_state, ".global_state-");
                        }

                        return .done;
                    }
                    const add_message_id = repd.call_remote(
                        system_gateway,
                        .login,
                        system_gateway.operations.login.Body{
                            .email = body.email,
                            .password = body.password,
                        },
                        &state.login_result,
                    ) catch {
                        const temp = "failed to call kv\r\n";
                        print_wasm(temp.ptr, temp.len);
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    const ran_check = "ran wait check";
                    print_wasm(ran_check, ran_check.len);
                    return .wait;
                }
            };

            pub const add_timer = struct {
                pub const Body = struct {
                    name: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
                    duration: u32,
                };
                pub const Result = struct {};
                pub const State = struct {
                    is_has_ran: bool = false,
                    add_timer_result: system_gateway.operations.add_timer.Result = .{ .is_added_successfully = false },
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = connection_state;
                    _ = self;
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    _ = result;
                    if (state.is_has_ran) {
                        return .done;
                    }
                    const add_message_id = repd.call_remote(
                        system_gateway,
                        .add_timer,
                        system_gateway.operations.add_timer.Body{
                            .name = body.name,
                            .duration = body.duration,
                        },
                        &state.add_timer_result,
                    ) catch {
                        const temp = "failed to call kv\r\n";
                        print_wasm(temp.ptr, temp.len);
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    return .wait;
                }
            };
        };
    };
}
