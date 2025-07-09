const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const system_gateway = @import("../gateway/gateway.zig").system;
const send = @import("../../wasm.zig").send;
const uuid = @import("../../uuid.zig");

const print_wasm = @import("../../wasm.zig").print_wasm;

pub const AppState = struct {};

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
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
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
                    },
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    _ = result;
                    if (state.is_has_ran) {
                        const ran_check = "ran check";
                        print_wasm(ran_check, ran_check.len);
                        const user_id_2 = state.*.login_result.user_id.toHex(.lower);
                        print_wasm(&user_id_2, user_id_2.len);
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
        };
    };
}
