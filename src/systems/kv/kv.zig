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
    global_constants.message_number_max,
    global_constants.message_size_max,
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
            read = 0,
            write = 1,
        };

        pub const operations = struct {
            pub const read = struct {
                pub const Body = extern struct {
                    key: StackStringZig.StackString(u16, global_constants.max_key_length),
                };
                pub const Result = extern struct {
                    is_value_found: bool = false,
                    value: StackStringZig.StackString(u32, global_constants.max_value_length),
                };
                pub const State = struct {};
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = connection_state;
                    _ = rep;
                    _ = state;
                    std.debug.print("read attempt: {}\r\n", .{body.*.key});

                    const txn = lmdb.Transaction.init(self.system_data.*, .{ .mode = .ReadOnly }) catch |err| {
                        std.debug.print("failed to init read transaction: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };
                    errdefer txn.abort();

                    const tenant_db = txn.database("tenant", .{ .create = true }) catch |err| {
                        std.debug.print("failed to open database: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    const maybe_value = tenant_db.get(
                        body.*.key.to_slice() catch |err| {
                            std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                            return .done;
                        },
                    ) catch |err| {
                        std.debug.print("failed to get key/value: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    if (maybe_value) |value| {
                        result.*.value = StackStringZig.StackString(u32, global_constants.max_value_length).init(value);
                        result.*.is_value_found = true;
                        std.debug.print("read key: {any} value: {any}\r\n", .{ body.*.key, value });
                    } else {
                        std.debug.print("value not found\r\n", .{});
                    }

                    txn.commit() catch |err| {
                        std.debug.print("failed to commit transaction: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    return .done;
                }
            };
            pub const write = struct {
                pub const Body = extern struct {
                    key: StackStringZig.StackString(u16, global_constants.max_key_length),
                    value: StackStringZig.StackString(u32, global_constants.max_value_length),
                };
                pub const Result = extern struct {
                    success: bool,
                };
                pub const State = struct {};
                pub fn call(self: *System, rep: *anyopaque, body: *Body, result: *Result, state: *State, connection_state: *anyopaque) replica.Handled_Status {
                    _ = connection_state;
                    _ = rep;
                    _ = state;

                    result.*.success = false;

                    const txn = lmdb.Transaction.init(self.system_data.*, .{ .mode = .ReadWrite }) catch |err| {
                        std.debug.print("failed to init write transaction: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };
                    errdefer txn.abort();

                    const tenant_db = txn.database("tenant", .{ .create = true }) catch |err| {
                        std.debug.print("failed to open database: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    tenant_db.set(
                        body.*.key.to_slice() catch |err| {
                            std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                            return .done;
                        },
                        body.*.value.to_slice() catch |err| {
                            std.debug.print("failed to get from stack string: {s}\r\n", .{@errorName(err)});
                            return .done;
                        },
                    ) catch |err| {
                        std.debug.print("failed to set key/value: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    txn.commit() catch |err| {
                        std.debug.print("failed to commit transaction: {s}\r\n", .{@errorName(err)});
                        return .done;
                    };

                    std.debug.print("stored key: {any} value: {any}\r\n", .{ body.*.key, body.*.value });

                    result.*.success = true;
                    return .done;
                }
            };
        };
    };
}
