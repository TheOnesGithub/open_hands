const std = @import("std");

pub const operations = struct {
    pub const pulse = struct {
        pub const event = void;
        pub const result = void;
        pub fn call(payload: event, output: *align(16) [1024]u8) result {
            _ = output;
            _ = payload;
        }
    };
    pub const print = struct {
        pub const event = void;
        pub const result = void;
        pub fn call(payload: event, output: *align(16) [1024]u8) result {
            _ = output;
            _ = payload;
        }
    };
    pub const add = struct {
        pub const event = struct {
            a: u32,
            b: u32,
        };
        pub const result = u32;
        pub fn call(payload: event, output: *align(16) [1024]u8) result {
            _ = output;
            const added = payload.a + payload.b;
            std.debug.print("ran add {} + {} = {} \r\n", .{ payload.a, payload.b, added });
            return added;
        }
    };
};
