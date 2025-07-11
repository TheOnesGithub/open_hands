const std = @import("std");

// const allocator = std.heap.wasm_allocator;

pub fn struct_from_slice(comptime T: type, slice: []const u8) *T {
    std.debug.assert(@sizeOf(T) == slice.len);
    const int = @intFromPtr(slice.ptr);
    const struct_ptr: *T = @ptrFromInt(int);
    return struct_ptr;
}

pub const BufferWriter = struct {
    const Self = @This();

    position_header: usize,
    position_body: usize,
    buffer: []u8,

    pub fn init(allocator2: *const std.mem.Allocator, buffer_len: usize) !Self {
        var bufferWriter = BufferWriter{
            .buffer = undefined,
            .position_header = 4,
            .position_body = 8,
        };

        // const alined_len = try std.math.divCeil(usize, buffer_len, 4);
        // bufferWriter.buffer = try allocator2.alignedAlloc(U8, 32, alined_len);
        bufferWriter.buffer = try allocator2.alloc(u8, buffer_len);

        bufferWriter.position_header = 4;
        bufferWriter.position_body = 8;

        bufferWriter.set_lens();

        return bufferWriter;
    }

    pub fn init_with_headers(allocator2: *const std.mem.Allocator, headers: std.json.Value, buffer_len: usize) !Self {
        var bufferWriter = BufferWriter{
            .buffer = undefined,
            .position_header = 4,
            .position_body = 8,
        };

        bufferWriter.buffer = try allocator2.alloc(u8, buffer_len);

        var fba = std.heap.FixedBufferAllocator.init(bufferWriter.buffer[4..]);
        var header_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(headers, .{}, header_string.writer());
        const header_len = header_string.items.len;

        bufferWriter.position_header = header_len + 4;
        bufferWriter.position_body = header_len + 8;

        bufferWriter.set_lens();

        return bufferWriter;
    }

    pub fn write_to_body(self: *Self, data: []const u8) !void {
        if (self.position_body + data.len > self.buffer.len) {
            return error.BufferOverflow; // Handle buffer overflow
        }
        std.mem.copyForwards(u8, self.buffer[self.position_body..], data);
        self.position_body += data.len;

        self.set_lens();
    }

    pub fn write_to_header(self: *Self, data: []const u8) !void {
        if (self.position_header + data.len > self.buffer.len) {
            return error.BufferOverflow; // Handle buffer overflow
        }
        // std.mem.copyForwards(u8, self.buffer[self.position_header - 1 ..], data);
        // self.position_header += data.len;
        // self.buffer[self.position_header - 1] = '}';
        // self.position_body = self.position_header + 4;
        std.mem.copyForwards(u8, self.buffer[self.position_header..], data);
        self.position_header += data.len;
        // self.buffer[self.position_header - 1] = '}';
        self.position_body = self.position_header + 4;
    }

    pub fn set_lens(self: *Self) void {
        const u32_header_len: u32 = @intCast(self.position_header - 4);
        const bytes_header_len = @as([4]u8, @bitCast(u32_header_len));
        std.mem.copyForwards(u8, self.buffer[0..4], &bytes_header_len);

        const u32_body_len: u32 = @intCast(self.position_body - (self.position_header + 4));
        const bytes_body_len = @as([4]u8, @bitCast(u32_body_len));
        std.mem.copyForwards(u8, self.buffer[self.position_header .. self.position_header + 4], &bytes_body_len);
    }
};

pub fn splitOnMarkers(comptime input: []const u8) []const []const u8 {
    @setEvalBranchQuota(20000000);
    var result: [16][]const u8 = undefined;
    var count: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        const start_marker = std.mem.indexOfPos(u8, input, i, "{{") orelse {
            // No more markers — capture the rest
            result[count] = std.mem.trim(u8, input[i..], "\r\n");
            count += 1;
            break;
        };

        // capture pre-marker content (may be empty)
        result[count] = std.mem.trim(u8, input[i..start_marker], "\r\n");
        count += 1;

        const end_marker = std.mem.indexOfPos(u8, input, start_marker, "}}") orelse break;
        const content_start = end_marker + 2;

        i = content_start;
    }

    return result[0..count];
}
