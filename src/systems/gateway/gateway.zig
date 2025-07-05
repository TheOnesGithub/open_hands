const std = @import("std");
const global_constants = @import("../../constants.zig");
const replica = @import("../../replica.zig");
const StackStringZig = @import("../../stack_string.zig");
const uuid = @import("../../uuid.zig");
const httpz = @import("httpz");
const system_kv = @import("../kv/kv.zig").system;

pub const AppState = struct {
    client_message_id: uuid.UUID,
    conn: *httpz.websocket.Conn,
    only_return_body: bool,
};

pub const remote_services = [_]replica.RemoteService{
    .{
        .service_type = @import("../../systems/kv/kv.zig").system,
        .call = &call_kv,
    },
    .{
        .service_type = @import("../../systems/client/client.zig").system,
        .call = &call_client,
    },
};

pub fn call_kv(ptr: [*]const u8, len: usize) void {
    std.debug.print("call kv\r\n", .{});
    if (@import("builtin").cpu.arch != .wasm32) {
        @import("../../gateway.zig").call_kv(ptr, len);
    }
}

pub fn call_client(ptr: [*]const u8, len: usize) void {
    _ = ptr;
    _ = len;
    std.debug.print("call client\r\n", .{});
}

pub const Replica = replica.ReplicaType(
    system,
    AppState,
    &remote_services,
);

const AuthMeta = extern struct {
    created_at: i64,
    updated_at: i64,
    last_login: i64,
};

const KeyEmailAuth = StackStringZig.StackString(global_constants.MAX_EMAIL_LENGTH);
const EmailAuth = extern struct {
    version: u8 = 0,
    user_id: uuid.UUID,
    hash: StackStringZig.StackString(global_constants.PASSWORD_HASH_LENGTH),
    is_verified: bool,
    meta: AuthMeta,
};

const KeyUserProfile = uuid.UUID;
const UserProfile = extern struct {
    version: u8 = 0,
    username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
    display_name: StackStringZig.StackString(global_constants.MAX_DISPLAY_NAME_LENGTH),
    meta: AuthMeta,
};

const KeyLoginAttempt = extern struct {
    user_id: uuid.UUID,
    timestamp: u64,
};
const LoginAttempt = extern struct {
    timestamp: u64,
    success: bool,
    ip_address: [16]u8,
    user_agent: StackStringZig.StackString(128),
    // auth_type: enum { email},
};

pub const system = SystemType();
pub fn SystemType() type {
    return struct {
        const System = @This();

        pub const Operation = enum(u8) {
            print = 0,
            add = 1,
            make_string = 2,
            signup = 3,
            login = 4,
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
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    _ = body;

                    const repd: *Replica = @alignCast(@ptrCast(rep));
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
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
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
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    _ = rep;
                    _ = state;
                    _ = body;
                    result.* = Result.init("made string in make string");
                    return .done;
                }
            };

            pub const signup = struct {
                pub const Body = struct {
                    username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
                    email: StackStringZig.StackString(global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {
                    is_signed_up_successfully: bool,
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                    kv_result: system_kv.operations.write.Result = .{ .success = false },
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    std.debug.print("user is trying to signup\r\n", .{});
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    if (state.is_has_ran) {
                        std.debug.print("state machine back after signup\r\n", .{});
                        result.*.is_signed_up_successfully = state.kv_result.success;
                        return .done;
                    }

                    var buffer: [33 * 1024]u8 = undefined; // 32 KiB buffer + 1 KiB
                    var fba = std.heap.FixedBufferAllocator.init(&buffer);
                    const allocator = fba.allocator();

                    // var salt: [16]u8 = undefined;
                    // std.crypto.random.bytes(&salt);

                    const hash_options: std.crypto.pwhash.argon2.HashOptions = .{
                        .allocator = allocator,
                        .params = .{
                            .t = 3,
                            .m = 32,
                            .p = 4,
                            // .secret = &salt,
                            // .ad = "GildedGeese",
                        },
                        .mode = .argon2id,
                        .encoding = .phc,
                    };
                    var out: [global_constants.PASSWORD_HASH_LENGTH]u8 = undefined;

                    const hash_str = std.crypto.pwhash.argon2.strHash(
                        body.*.password.to_slice() catch |err| {
                            std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                            return .done;
                        },
                        hash_options,
                        &out,
                    ) catch |err| {
                        std.debug.print("failed to hash password: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    const current_time = std.time.milliTimestamp();
                    const add_message_id = repd.call_remote(
                        system_kv,
                        .write,
                        .{
                            .key = StackStringZig.StackString(global_constants.max_key_length).init(
                                body.email.to_slice() catch |err| {
                                    std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                    return .done;
                                },
                            ),
                            .value = StackStringZig.StackString(global_constants.max_value_length).init(std.mem.asBytes(&EmailAuth{
                                .user_id = uuid.UUID.v4(),
                                .hash = StackStringZig.StackString(global_constants.PASSWORD_HASH_LENGTH).init(hash_str),
                                .is_verified = false,
                                .meta = .{
                                    .created_at = current_time,
                                    .updated_at = current_time,
                                    .last_login = current_time,
                                },
                            })),
                        },
                        &state.kv_result,
                    );
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    std.debug.print("added login wait\r\n", .{});
                    return .wait;
                }
            };

            pub const login = struct {
                pub const Body = struct {
                    email: StackStringZig.StackString(global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {
                    is_logged_in_successfully: bool,
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                    kv_result: system_kv.operations.read.Result,
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    std.debug.print("user is trying to login\r\n", .{});
                    // send a message to the database server to check if the username and password are correct
                    // if they are, send a message back to the client saying they are logged in
                    // if not, send a message back saying they are not logged in

                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    _ = result;
                    if (state.is_has_ran) {
                        std.debug.print("state machine got vaule from kv\r\n", .{});
                        return .done;
                    }
                    const add_message_id = repd.call_remote(
                        system_kv,
                        .read,
                        .{
                            .key = StackStringZig.StackString(global_constants.max_key_length).init(
                                body.email.to_slice() catch |err| {
                                    std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                    return .done;
                                },
                            ),
                        },
                        &state.kv_result,
                    );
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    std.debug.print("added login wait\r\n", .{});
                    return .wait;
                }
            };
        };
    };
}
