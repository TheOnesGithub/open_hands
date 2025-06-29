const std = @import("std");

pub fn StackString(comptime N: usize) type {
    return extern struct {
        const Self = @This();
        _len: u8 align(1) = 0,
        _str: [N]u8 align(1) = [_]u8{0} ** N,

        pub fn init(str_data: []const u8) @This() {
            std.debug.assert(str_data.len <= N);
            // if (str_data.len > N) {
            //     return error.OutOfMemory;
            // }
            var result: @This() = @This(){
                ._len = @intCast(str_data.len),
                ._str = undefined,
            };
            std.mem.copyBackwards(u8, &result._str, str_data);
            return result;
        }

        pub fn to_slice(self: *Self) ![]const u8 {
            if (self._len > N) {
                //TODO: this should be a more specific error
                return error.OutOfMemory;
            }
            return self._str[0..self._len];
        }
    };
}
