const std = @import("std");
const replica = @import("replica.zig");

pub const operations = struct {
    pub const pulse = struct {
        pub const event = void;
        pub const result = void;
        pub fn call(payload: *event, output: *result) replica.Handled_Status {
            _ = output;
            _ = payload;
            return .done;
        }
    };
    pub const print = struct {
        pub const event = void;
        pub const result = void;
        pub fn call(payload: *event, output: *result) replica.Handled_Status {
            _ = output;
            _ = payload;
            return .done;
        }
    };
    pub const add = struct {
        pub const event = struct {
            a: u32,
            b: u32,
        };
        pub const result = u32;
        pub fn call(payload: *event, output: *result) replica.Handled_Status {
            const added = payload.a + payload.b;
            std.debug.print("ran add {} + {} = {} \r\n", .{ payload.a, payload.b, added });
            output.* = added;
            return .done;
        }
    };
};
