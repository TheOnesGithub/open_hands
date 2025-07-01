const std = @import("std");
const uuid = @import("uuid.zig");
const stack_string = @import("stack_string.zig");
const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");
const Operations = @import("operations.zig");
pub const StateMachineZig = @import("state_machine.zig");
pub const ReplicaZig = @import("replica.zig");

pub const StateMachine =
    StateMachineZig.StateMachineType(global_constants.state_machine_config);
pub const Replica = ReplicaZig.ReplicaType(StateMachine);

const allocator = std.heap.wasm_allocator;

const MAX_USERNAME_LENGTH = 16;
const MAX_PASSWORD_LENGTH = 64;

const replica: Replica = undefined;

extern fn send(ptr: [*]const u8, len: usize) void;

fn handle_network_reply(message_id: uuid.UUID, buffer_ptr: [*]u8) void {
    _ = buffer_ptr;
    _ = message_id;
}

pub export fn init() void {
    replica.init(.{});
}

pub export fn alloc(size: usize) ?[*]u8 {
    return if (allocator.alloc(u8, size)) |slice|
        slice.ptr
    else |_|
        null;
}

pub export fn free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

pub export fn tick() void {
    replica.tick();
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

    // add it to the state machine so on call back it can route it?
    _ = username;
    _ = password;

    // const Body = Operations.BodyType(.add);
    // const body: Body = .{ .a = 1, .b = 4 };
    // replica.call_local(.add, body, reply: *Operations.ResultType(operation))

    if (replica.resurveAvailableFiber()) |fiber_index| {
        const temp = &replica.messages[fiber_index][0];
        const t2: *message_header.Header.Request = @ptrCast(temp);
        t2.* = message_header.Header.Request{
            .request = 0,
            .command = .request,
            .client = 0,
            .operation = .add,
            .cluster = 0,
            .release = 0,
        };
        const header_size = @sizeOf(message_header.Header.Request);
        const Body = Operations.BodyType(.add);
        var ptr_as_int = @intFromPtr(temp);
        ptr_as_int = ptr_as_int + header_size;
        const operation_struct: *Body = @ptrFromInt(ptr_as_int);
        operation_struct.a = 1;
        operation_struct.b = 2;

        replica.message_statuses[fiber_index] = .Ready;
        try replica.push(fiber_index);
    }

    // _ = call_remote(.add, body);
}

const Operation = @import("operations.zig").Operation;

// pub fn call_remote(
//     comptime operation: Operation,
//     body: Operations.BodyType(operation),
// ) uuid.UUID {
//     const message_id = uuid.UUID.v4();
//
//     const buffer: [global_constants.message_size_max]u8 align(16) = undefined;
//     const temp = &buffer;
//     // const temp = &self.messages[fiber_index][0];
//     const t2: *message_header.Header.Request = @ptrCast(@constCast(temp));
//     t2.* = message_header.Header.Request{
//         .request = 0,
//         .command = .request,
//         .client = 0,
//         .operation = operation,
//         .cluster = 0,
//         .release = 0,
//     };
//     const header_size = @sizeOf(message_header.Header.Request);
//     const Body = Operations.BodyType(operation);
//     var ptr_as_int = @intFromPtr(temp);
//     ptr_as_int = ptr_as_int + header_size;
//     const operation_struct: *Body = @ptrFromInt(ptr_as_int);
//     operation_struct.* = body;
//
//     send(temp, buffer.len);
//     return message_id;
// }
