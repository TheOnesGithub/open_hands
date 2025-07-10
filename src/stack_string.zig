const std = @import("std");
const assert = std.debug.assert;

pub fn StackString(comptime SizeType: type, comptime N: usize) type {
    assert(N > 0);
    assert(N <= std.math.maxInt(SizeType));
    assert(@typeInfo(SizeType) == .int);
    return extern struct {
        const Self = @This();
        _len: SizeType align(1) = 0,
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

        pub fn to_compact_slice(self: *Self) ![]const u8 {
            if (self._len > N) {
                //TODO: this should be a more specific error
                return error.OutOfMemory;
            }
        }

        pub fn append(self: *Self, slice: []const u8) !void {
            if (slice.len > std.math.maxInt(SizeType)) {
                return error.OutOfMemory;
            }

            const casted_len: SizeType = @intCast(slice.len);

            if (self._len + casted_len > N) {
                //TODO: this should be a more specific error
                return error.OutOfMemory;
            }
            @memcpy(self._str[self._len .. self._len + casted_len], slice);
            self._len += casted_len;
        }
    };
}
