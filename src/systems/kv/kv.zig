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
                    _ = body;
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

                        users_db.set("aaa", "foo") catch |err| {
                            std.debug.print("failed to set key/value: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };
                        users_db.set("bbb", "bar") catch |err| {
                            std.debug.print("failed to set key/value: {s}\r\n", .{@errorName(err)});
                            return .done;
                        };

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
                    _ = self;
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
}
