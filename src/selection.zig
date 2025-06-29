const std = @import("std");
const replica = @import("replica.zig");
const main = @import("main.zig");

pub const operations = struct {
    pub const pulse = struct {
        pub const event = void;
        pub const result = void;
        pub const cache = struct {};
        pub fn call(rep: *main.Replica, payload: *event, output: *result, c: *cache) replica.Handled_Status {
            _ = output;
            _ = payload;
            _ = rep;
            _ = c;
            return .done;
        }
    };
    pub const print = struct {
        pub const event = void;
        pub const result = void;
        pub const cache = struct {
            has_ran: bool = false,
            add_result: ?u32,
        };
        pub fn call(rep: *main.Replica, payload: *event, output: *result, c: *cache) replica.Handled_Status {
            _ = output;
            _ = payload;
            // if (c.add_result) |added| {
            // std.debug.print("print after added {} \r\n", .{added});
            if (c.has_ran) {
                std.debug.print("print after added  \r\n", .{});
                return .done;
            }
            c.has_ran = true;
            std.debug.print("from print \r\n", .{});
            const add_message_id = rep.call_local(.add, add.event{ .a = 2, .b = 2 });
            rep.add_wait(&add_message_id);
            return .wait;
            // _ = add_message_id;

        }
    };
    pub const add = struct {
        pub const event = struct {
            a: u32,
            b: u32,
        };
        pub const result = u32;
        pub const cache = struct {};
        pub fn call(rep: *main.Replica, payload: *event, output: *result, c: *cache) replica.Handled_Status {
            _ = rep;
            _ = c;
            const added = payload.a + payload.b;
            std.debug.print("ran add {} + {} = {} \r\n", .{ payload.a, payload.b, added });
            output.* = added;
            return .done;
        }
    };
};
