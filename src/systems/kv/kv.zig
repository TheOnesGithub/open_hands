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

pub const Replica = replica.ReplicaType(
    system,
    AppState,
    &remote_services,
);

pub const system = SystemType(*const lmdb.Environment);

const PASSWORD_HASH_LENGTH = 128;

// todo: make a better name
pub fn SystemType(comptime SystemDataType: type) type {
    return struct {
        const System = @This();
        system_data: SystemDataType = undefined,
        pub fn init(
            self: *System,
            system_data_ptr: SystemDataType,
        ) !void {
            self.* = .{
                .system_data = system_data_ptr,
            };
        }
        pub const Operation = enum(u8) {
            signup = 0,
            login = 1,
        };

        pub const operations = struct {
            pub const signup = struct {
                pub const Body = struct {
                    username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
                    email: StackStringZig.StackString(global_constants.MAX_EMAIL_LENGTH),
                    password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {
                    is_signed_up_successfully: bool,
                };
                pub const State = struct {};
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = rep;
                    _ = state;
                    _ = result;

                    {
                        const txn = lmdb.Transaction.init(self.system_data.*, .{ .mode = .ReadWrite }) catch |err| {
                            std.debug.print("failed to init transaction: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };
                        errdefer txn.abort();

                        const users_db = txn.database("users", .{ .create = true }) catch |err| {
                            std.debug.print("failed to open database: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };

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
                        var out: [PASSWORD_HASH_LENGTH]u8 = undefined;
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

                        users_db.set(
                            body.*.username.to_slice() catch |err| {
                                std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                                return .done;
                            },
                            hash_str,
                        ) catch |err| {
                            std.debug.print("failed to set key/value: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };
                        std.debug.print("hash str: {s}\r\n", .{hash_str});

                        txn.commit() catch |err| {
                            std.debug.print("failed to commit transaction: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };
                    }
                    std.debug.print("signup kv\r\n", .{});
                    return .done;
                }
            };

            pub const login = struct {
                pub const Body = struct {
                    username: StackStringZig.StackString(global_constants.MAX_USERNAME_LENGTH),
                    password: StackStringZig.StackString(global_constants.MAX_PASSWORD_LENGTH),
                };
                pub const Result = struct {
                    is_logged_in_successfully: bool,
                };
                pub const State = struct {};
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State) replica.Handled_Status {
                    _ = rep;
                    _ = state;
                    _ = result;
                    std.debug.print("login client kv\r\n", .{});
                    const txn = lmdb.Transaction.init(self.system_data.*, .{ .mode = .ReadWrite }) catch |err| {
                        std.debug.print("failed to init transaction: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };
                    errdefer txn.abort();

                    const users_db = txn.database("users", .{ .create = true }) catch |err| {
                        std.debug.print("failed to open database: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    const maybe_user = users_db.get(
                        body.*.username.to_slice() catch |err| {
                            std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                            return .done;
                        },
                    ) catch |err| {
                        std.debug.print("failed to get key/value: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    if (maybe_user) |user| {
                        std.debug.print("user: {s}\r\n", .{user});
                    } else {
                        std.debug.print("user not found\r\n", .{});
                    }

                    return .done;
                }
            };
        };
    };
}
