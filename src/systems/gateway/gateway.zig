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
    user_id: *?uuid.UUID,
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
    global_constants.message_number_max,
    1024 * 4,
);

const AuthMeta = extern struct {
    created_at: i64,
    updated_at: i64,
    last_login: i64,
};

const KeyEmailAuth = StackStringZig.StackString(u8, global_constants.MAX_EMAIL_LENGTH);
const EmailAuth = extern struct {
    version: u8 = 0,
    user_id: uuid.UUID,
    hash: StackStringZig.StackString(u8, global_constants.PASSWORD_HASH_LENGTH),
    is_verified: bool,
    meta: AuthMeta,
};

const KeyUserProfile = uuid.UUID;
const UserProfile = extern struct {
    version: u8 = 0,
    username: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
    display_name: StackStringZig.StackString(u8, global_constants.max_display_name_length),
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
    user_agent: StackStringZig.StackString(u8, 128),
    // auth_type: enum { email},
};

pub const Timer = extern struct {
    name: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
    duration: u32,
};

pub const system = SystemType();
pub fn SystemType() type {
    return struct {
        const System = @This();

        pub const Operation = enum(u8) {
            signup = 1,
            login = 2,
            add_timer = 3,
            get_all_timers = 4,
        };

        pub const operations = struct {
            pub const signup = struct {
                pub const Body = extern struct {
                    username: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
                    email: StackStringZig.StackString(u8, global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(u8, global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = extern struct {
                    is_signed_up_successfully: bool,
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                    kv_result_email_auth: system_kv.operations.write.Result = .{ .success = false },
                    kv_result_created_user: system_kv.operations.write.Result = .{ .success = false },
                    new_user_id: ?uuid.UUID = null,
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = self;
                    std.debug.print("user is trying to signup\r\n", .{});
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    if (state.is_has_ran) {
                        std.debug.print("state machine back after signup\r\n", .{});
                        const connection_state_data: *AppState = @alignCast(@ptrCast(connection_state));
                        connection_state_data.user_id.* = state.new_user_id;

                        result.*.is_signed_up_successfully = state.kv_result_email_auth.success;
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
                    state.new_user_id = uuid.UUID.v4();
                    var add_message_id = repd.call_remote(
                        system_kv,
                        .write,
                        .{
                            .key = StackStringZig.StackString(u16, global_constants.max_key_length).init(
                                body.email.to_slice() catch |err| {
                                    std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                    return .done;
                                },
                            ),
                            .value = StackStringZig.StackString(u32, global_constants.max_value_length).init(std.mem.asBytes(&EmailAuth{
                                .user_id = state.new_user_id.?,
                                .hash = StackStringZig.StackString(u8, global_constants.PASSWORD_HASH_LENGTH).init(hash_str),
                                .is_verified = false,
                                .meta = .{
                                    .created_at = current_time,
                                    .updated_at = current_time,
                                    .last_login = current_time,
                                },
                            })),
                        },
                        &state.kv_result_email_auth,
                    ) catch {
                        std.debug.print("failed to call kv\r\n", .{});
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    var key_user_profile = StackStringZig.StackString(u16, global_constants.max_key_length).init("user_profile");
                    key_user_profile.append(&state.new_user_id.?.bin) catch {
                        std.debug.print("failed to append to key\r\n", .{});
                        return .done;
                    };

                    add_message_id = repd.call_remote(
                        system_kv,
                        .write,
                        .{
                            // UserProfile + user_id
                            .key = key_user_profile,
                            .value = StackStringZig.StackString(u32, global_constants.max_value_length).init(std.mem.asBytes(&UserProfile{
                                .version = 0,
                                .username = body.username,
                                .display_name = StackStringZig.StackString(u8, global_constants.max_display_name_length).init(body.username.to_slice() catch |err| {
                                    std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                    return .done;
                                }),
                                .meta = .{
                                    .created_at = current_time,
                                    .updated_at = current_time,
                                    .last_login = current_time,
                                },
                            })),
                        },
                        &state.kv_result_email_auth,
                    ) catch {
                        std.debug.print("failed to call kv\r\n", .{});
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    std.debug.print("added login wait\r\n", .{});
                    return .wait;
                }
            };

            pub const login = struct {
                pub const Body = extern struct {
                    email: StackStringZig.StackString(u8, global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(u8, global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = extern struct {
                    is_logged_in_successfully: bool,
                    user_id: uuid.UUID,
                    display_name: StackStringZig.StackString(u8, global_constants.max_display_name_length),
                    username: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                    kv_result_email_auth: system_kv.operations.read.Result,
                    is_has_ran_get_user_profile: bool = false,
                    kv_result_user_profile: system_kv.operations.read.Result,
                };
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = self;
                    std.debug.print("user is trying to login\r\n", .{});
                    // send a message to the database server to check if the username and password are correct
                    // if they are, send a message back to the client saying they are logged in
                    // if not, send a message back saying they are not logged in

                    const repd: *Replica = @alignCast(@ptrCast(rep));

                    if (state.is_has_ran) {
                        std.debug.print("state machine got vaule from kv\r\n", .{});

                        std.debug.print("kv result: {any}\r\n", .{state.kv_result_email_auth});

                        if (state.kv_result_email_auth.is_value_found) {
                            std.debug.print("value found\r\n", .{});
                            const value = state.kv_result_email_auth.value.to_slice() catch |err| {
                                std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                return .done;
                            };

                            if (value.len < @sizeOf(EmailAuth)) {
                                std.debug.print("value is smaller than expected struct\r\n", .{});
                                return .done;
                            }
                            const value_casted = std.mem.bytesAsValue(EmailAuth, value[0..@sizeOf(EmailAuth)]);

                            if (!state.is_has_ran_get_user_profile) {
                                // get the user profile
                                var key_user_profile = StackStringZig.StackString(u16, global_constants.max_key_length).init("user_profile");
                                key_user_profile.append(&value_casted.user_id.bin) catch {
                                    std.debug.print("failed to append to key\r\n", .{});
                                    return .done;
                                };

                                const add_message_id = repd.call_remote(
                                    system_kv,
                                    .read,
                                    .{
                                        .key = key_user_profile,
                                    },
                                    &state.kv_result_user_profile,
                                ) catch {
                                    std.debug.print("failed to call kv\r\n", .{});
                                    return .done;
                                };
                                repd.add_wait(&add_message_id);
                                state.is_has_ran_get_user_profile = true;
                                return .wait;
                            }

                            std.debug.print("value casted: {any}\r\n", .{value_casted});

                            const value_casted_user_profile = state.kv_result_user_profile.value.to_slice() catch |err| {
                                std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                return .done;
                            };

                            if (value_casted_user_profile.len < @sizeOf(UserProfile)) {
                                std.debug.print("value is smaller than expected struct\r\n", .{});
                                return .done;
                            }
                            const value_casted_user_profile_casted = std.mem.bytesAsValue(UserProfile, value_casted_user_profile[0..@sizeOf(UserProfile)]);

                            std.debug.print("value casted: {any}\r\n", .{value_casted_user_profile_casted});

                            result.*.is_logged_in_successfully = true;
                            result.*.user_id = value_casted.user_id;
                            result.*.display_name = value_casted_user_profile_casted.display_name;
                            result.*.username = value_casted_user_profile_casted.username;
                            const connection_state_data: *AppState = @alignCast(@ptrCast(connection_state));
                            connection_state_data.user_id.* = result.*.user_id;

                            std.debug.print("result.*.user_id: {any}\r\n", .{result.*.user_id});
                        }

                        return .done;
                    }

                    std.debug.print("if this shows up twice in is a problem\r\n", .{});
                    const add_message_id = repd.call_remote(
                        system_kv,
                        .read,
                        .{
                            .key = StackStringZig.StackString(u16, global_constants.max_key_length).init(
                                body.email.to_slice() catch |err| {
                                    std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                    return .done;
                                },
                            ),
                        },
                        &state.kv_result_email_auth,
                    ) catch {
                        std.debug.print("failed to call kv\r\n", .{});
                        return .done;
                    };
                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    std.debug.print("added login wait\r\n", .{});
                    return .wait;
                }
            };

            pub const add_timer = struct {
                pub const Body = extern struct {
                    name: StackStringZig.StackString(u8, global_constants.MAX_USERNAME_LENGTH),
                    duration: u32,
                };
                pub const Result = extern struct {
                    is_added_successfully: bool,
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                    add_timer_result: system_kv.operations.write.Result = .{ .success = false },
                };
                pub fn call(
                    self: *System,
                    rep: *anyopaque,
                    body: *Body,
                    result: *Result,
                    state: *State,
                    connection_state: *anyopaque,
                ) replica.Handled_Status {
                    _ = self;
                    const connection_state_data: *AppState = @alignCast(@ptrCast(connection_state));
                    std.debug.print("user is trying to add timer user_id: {any}\r\n", .{connection_state_data.user_id.*});
                    _ = result;
                    std.debug.print("user is trying to add timer\r\n", .{});
                    if (connection_state_data.user_id.* == null) {
                        std.debug.print("user is trying to add timer no user id\r\n", .{});
                        return .done;
                    }
                    const repd: *Replica = @alignCast(@ptrCast(rep));
                    if (state.is_has_ran) {
                        std.debug.print("state machine back after add timer\r\n", .{});
                        return .done;
                    }

                    //                                 connection_state_data.user_id.*  to stack string
                    var key = StackStringZig.StackString(u16, global_constants.max_key_length).init(
                        "Timer",
                    );
                    key.append(&connection_state_data.user_id.*.?.bin) catch {
                        std.debug.print("failed to append to key\r\n", .{});
                        return .done;
                    };
                    key.append(body.name.to_slice() catch |err| {
                        std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                        return .done;
                    }) catch {
                        std.debug.print("failed to append to key\r\n", .{});
                        return .done;
                    };
                    var add_message_id = repd.call_remote(
                        system_kv,
                        .write,
                        .{
                            // user_id + timer_name
                            .key = key,
                            .value = StackStringZig.StackString(u32, global_constants.max_value_length).init(std.mem.asBytes(&Timer{
                                .name = body.name,
                                .duration = body.duration,
                            })),
                        },
                        &state.add_timer_result,
                    ) catch {
                        std.debug.print("failed to call kv\r\n", .{});
                        return .done;
                    };

                    repd.add_wait(&add_message_id);
                    state.is_has_ran = true;
                    std.debug.print("added timer wait\r\n", .{});
                    return .wait;
                }
            };

            pub const get_all_timers = struct {
                pub const Body = extern struct {};
                pub const Result = extern struct {
                    // Timers
                };
                pub const State = struct {
                    is_has_ran: bool = false,
                };

                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = self;
                    _ = rep;
                    _ = body;
                    _ = result;
                    _ = state;

                    std.debug.print("get all timers\r\n", .{});

                    return .done;
                }
            };
        };
    };
}
