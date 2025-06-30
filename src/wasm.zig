const std = @import("std");
const uuid = @import("uuid.zig");
const stack_string = @import("stack_string.zig");
const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");
const Operations = @import("operations.zig");

const allocator = std.heap.wasm_allocator;

const MAX_USERNAME_LENGTH = 16;
const MAX_PASSWORD_LENGTH = 64;

extern fn send(ptr: [*]const u8, len: usize) void;

fn handle_network_reply(message_id: uuid.UUID, buffer_ptr: [*]u8) void {
    _ = buffer_ptr;
    _ = message_id;
}

pub export fn init() void {}

pub export fn alloc(size: usize) ?[*]u8 {
    return if (allocator.alloc(u8, size)) |slice|
        slice.ptr
    else |_|
        null;
}

pub export fn free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

export fn login(
    username_ptr: [*]const u8,
    username_len: usize,
    password_ptr: [*]const u8,
    password_len: usize,
) void {
    if (username_len > MAX_USERNAME_LENGTH) {
        return;
    }
    if (password_len > MAX_PASSWORD_LENGTH) {
        return;
    }
    const username_str = username_ptr[0..username_len];
    const password_str = password_ptr[0..password_len];

    const username = stack_string.StackString(MAX_USERNAME_LENGTH).init(username_str);
    const password = stack_string.StackString(MAX_PASSWORD_LENGTH).init(password_str);

    _ = username;
    _ = password;

    const buffer: [global_constants.message_size_max]u8 align(16) = undefined;
    // const temp = &self.app.replica.messages[fiber_index][0];
    const temp = &buffer;
    const t2: *message_header.Header.Request = @ptrCast(@constCast(temp));
    t2.* = message_header.Header.Request{
        .request = 0,
        .command = .request,
        .client = 0,
        .operation = .add,
        .cluster = 0,
        .release = 0,
        // .size =
    };
    const header_size = @sizeOf(message_header.Header.Request);
    const Event = Operations.BodyType(.add);
    var ptr_as_int = @intFromPtr(temp);
    ptr_as_int = ptr_as_int + header_size;
    const operation_struct: *Event = @ptrFromInt(ptr_as_int);
    operation_struct.a = 1;
    operation_struct.b = 2;

    send(temp, buffer.len);
}
