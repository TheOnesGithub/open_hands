const std = @import("std");
const uuid = @import("uuid.zig");
const stack_string = @import("stack_string.zig");
const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");
// const Operations = @import("operations.zig");
// pub const StateMachineZig = @import("state_machine.zig");
pub const ReplicaZig = @import("replica.zig");

const sl = @import("selection.zig");

// pub const StateMachine =
//     StateMachineZig.StateMachineType(global_constants.state_machine_config, sl.operations_client);
pub const Replica = ReplicaZig.ReplicaType(sl.operations_client);

const allocator = std.heap.wasm_allocator;

var replica: Replica = undefined;

pub extern fn send(ptr: [*]const u8, len: usize) void;

fn handle_network_reply(message_id: uuid.UUID, buffer_ptr: [*]u8) void {
    _ = buffer_ptr;
    _ = message_id;
}

pub export fn init() void {
    replica.init(.{ .temp_return = &temp_return }) catch undefined;
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
    if (username_len > global_constants.MAX_USERNAME_LENGTH) {
        return;
    }
    if (password_len > global_constants.MAX_PASSWORD_LENGTH) {
        return;
    }

    const username_str = username_ptr[0..username_len];
    const password_str = password_ptr[0..password_len];

    const username = stack_string.StackString(global_constants.MAX_USERNAME_LENGTH).init(username_str);
    const password = stack_string.StackString(global_constants.MAX_PASSWORD_LENGTH).init(password_str);

    // add it to the state machine so on call back it can route it?

    // const Body = Operations.BodyType(.login_client);
    // const body: Body = .{ .username = username, .password = password };
    // replica.call_local(.add, body, reply: *Operations.ResultType(operation))

    if (replica.resurveAvailableFiber()) |fiber_index| {
        const temp = &replica.messages[fiber_index][0];
        const t2: *message_header.Header.Request(sl.operations_client.Operation) = @ptrCast(temp);
        t2.* = message_header.Header.Request(sl.operations_client.Operation){
            .request = 0,
            .command = .request,
            .client = 0,
            .operation = .login_client,
            .cluster = 0,
            .release = 0,
            .message_id = uuid.UUID.v4(),
        };
        const header_size = @sizeOf(message_header.Header.Request(sl.operations_client.Operation));
        const Body = sl.operations_client.BodyType(.login_client);
        var ptr_as_int = @intFromPtr(temp);
        ptr_as_int = ptr_as_int + header_size;
        const operation_struct: *Body = @ptrFromInt(ptr_as_int);
        operation_struct.username = username;
        operation_struct.password = password;

        replica.message_statuses[fiber_index] = .Ready;
        replica.push(fiber_index) catch undefined;
    }

    // _ = call_remote(.add, body);
}

const Operation = @import("operations.zig").Operation;

fn temp_return(message_id: uuid.UUID, message: []align(16) u8) void {
    _ = message_id;
    _ = message;
    // send(message.ptr, message.len);
}
