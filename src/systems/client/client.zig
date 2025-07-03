const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const system_gateway = @import("../gateway/gateway.zig").system;
const send = @import("../../wasm.zig").send;

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
            pub const Result = struct {};
            pub const State = struct {
                is_has_ran: bool = false,
                login_result: system_gateway.operations.login_server.Result = .{ .is_logged_in_successfully = false },
            };
            pub fn call(rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                const repd: *replica.ReplicaType(
                    system,
                    AppState,
                    &remote_services,
                ) = @alignCast(@ptrCast(rep));
                _ = result;
                if (state.is_has_ran) {
                    return .done;
                }
                const add_message_id = repd.call_remote(
                    system_gateway,
                    .login_server,
                    system_gateway.operations.login_server.Body{
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
};
