const std = @import("std");

pub const MessageType = enum(u8) {
    GetRequest,
    GetResponse,
    SetRequest,
    SetResponse,
    Error,
};

pub const KvMessage = union(MessageType) {
    GetRequest: GetRequestPayload,
    GetResponse: GetResponsePayload,
    SetRequest: SetRequestPayload,
    SetResponse: SetResponsePayload,
    Error: ErrorPayload,

    pub fn serialize(self: KvMessage, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try buffer.append(@intFromEnum(self.tag));

        switch (self) {
            .GetRequest => |payload| {
                try buffer.appendSlice(&std.mem.asBytes(&payload.key.len));
                try buffer.appendSlice(payload.key);
            },
            .GetResponse => |payload| {
                try buffer.appendSlice(&std.mem.asBytes(&payload.value.len));
                try buffer.appendSlice(payload.value);
            },
            .SetRequest => |payload| {
                try buffer.appendSlice(&std.mem.asBytes(&payload.key.len));
                try buffer.appendSlice(payload.key);
                try buffer.appendSlice(&std.mem.asBytes(&payload.value.len));
                try buffer.appendSlice(payload.value);
            },
            .SetResponse => |payload| {
                _ = payload; // No payload for SetResponse
            },
            .Error => |payload| {
                try buffer.appendSlice(&std.mem.asBytes(&payload.message.len));
                try buffer.appendSlice(payload.message);
            },
        }
        return buffer.toOwnedSlice();
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !KvMessage {
        if (data.len == 0) return error.InvalidMessage;

        const message_type_int = data[0];
        const message_type = @as(MessageType, @enumFromInt(message_type_int));
        var offset: usize = 1;

        switch (message_type) {
            .GetRequest => {
                const key_len = std.mem.bytesToValue(usize, data[offset..offset + @sizeOf(usize)]);
                offset += @sizeOf(usize);
                const key = try allocator.alloc(u8, key_len);
                @memcpy(key, data[offset..offset + key_len]);
                return KvMessage{ .GetRequest = .{ .key = key } };
            },
            .GetResponse => {
                const value_len = std.mem.bytesToValue(usize, data[offset..offset + @sizeOf(usize)]);
                offset += @sizeOf(usize);
                const value = try allocator.alloc(u8, value_len);
                @memcpy(value, data[offset..offset + value_len]);
                return KvMessage{ .GetResponse = .{ .value = value } };
            },
            .SetRequest => {
                const key_len = std.mem.bytesToValue(usize, data[offset..offset + @sizeOf(usize)]);
                offset += @sizeOf(usize);
                const key = try allocator.alloc(u8, key_len);
                @memcpy(key, data[offset..offset + key_len]);

                const value_len = std.mem.bytesToValue(usize, data[offset + key_len .. offset + key_len + @sizeOf(usize)]);
                offset += key_len + @sizeOf(usize);
                const value = try allocator.alloc(u8, value_len);
                @memcpy(value, data[offset..offset + value_len]);
                return KvMessage{ .SetRequest = .{ .key = key, .value = value } };
            },
            .SetResponse => {
                return KvMessage{ .SetResponse = .{} };
            },
            .Error => {
                const message_len = std.mem.bytesToValue(usize, data[offset..offset + @sizeOf(usize)]);
                offset += @sizeOf(usize);
                const message = try allocator.alloc(u8, message_len);
                @memcpy(message, data[offset..offset + message_len]);
                return KvMessage{ .Error = .{ .message = message } };
            },
        }
    }
};

pub const GetRequestPayload = struct {
    key: []const u8,
};

pub const GetResponsePayload = struct {
    value: []const u8,
};

pub const SetRequestPayload = struct {
    key: []const u8,
    value: []const u8,
};

pub const SetResponsePayload = struct {};

pub const ErrorPayload = struct {
    message: []const u8,
};
