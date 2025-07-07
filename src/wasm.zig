const std = @import("std");
const uuid = @import("uuid.zig");
const stack_string = @import("stack_string.zig");
const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");
pub const ReplicaZig = @import("replica.zig");
pub const client = @import("systems/client/client.zig");
const Operations = @import("operations.zig");
const AppState = @import("systems/client/client.zig").AppState;

const allocator = std.heap.wasm_allocator;

var replica: client.Replica = undefined;

pub extern fn send(ptr: [*]const u8, len: usize) void;

pub extern fn print_wasm(ptr: [*]const u8, len: usize) void;

fn handle_network_reply(message_id: uuid.UUID, buffer_ptr: [*]u8) void {
    _ = buffer_ptr;
    _ = message_id;
}

var system_instance: client.system = client.system{};
var buffer: *align(16) [1024 * 4]u8 = undefined;

pub export fn init() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator2 = arena.allocator();

    replica.init(
        allocator2,
        &system_instance,
        .{ .temp_return = &temp_return },
    ) catch undefined;

    const temp_buffer = allocator.alloc(
        u8,
        (1024 * 4) + 16,
    ) catch {
        return;
    };
    // defer allocator.free(buffer);

    if (@intFromPtr(temp_buffer.ptr) % 16 == 0) {
        buffer = @ptrCast(@alignCast((temp_buffer.ptr)));
    } else {
        // buffer = @ptrFromInt(@intFromPtr(buffer.ptr) + (16 - (@intFromPtr(buffer.ptr) % 16)));
        buffer = @ptrCast(@alignCast(temp_buffer[(16 - (@intFromPtr(temp_buffer.ptr) % 16))..]));
    }

    std.debug.assert(@intFromPtr(buffer.ptr) % 16 == 0);
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
    _ = replica.tick(buffer);
}

pub export fn signup(
    username_ptr: [*]const u8,
    username_len: usize,
    email_ptr: [*]const u8,
    email_len: usize,
    password_ptr: [*]const u8,
    password_len: usize,
) void {
    if (username_len > global_constants.MAX_USERNAME_LENGTH) {
        return;
    }
    if (email_len > global_constants.MAX_EMAIL_LENGTH) {
        return;
    }
    if (password_len > global_constants.MAX_PASSWORD_LENGTH) {
        return;
    }

    const username_str = username_ptr[0..username_len];
    const email_str = email_ptr[0..email_len];
    const password_str = password_ptr[0..password_len];

    const username = stack_string.StackString(u8, global_constants.MAX_USERNAME_LENGTH).init(username_str);
    const email = stack_string.StackString(u8, global_constants.MAX_EMAIL_LENGTH).init(email_str);
    const password = stack_string.StackString(u8, global_constants.MAX_PASSWORD_LENGTH).init(password_str);

    if (replica.resurveAvailableFiber()) |fiber_index| {
        const temp = &replica.messages[fiber_index][0];
        const t2: *message_header.Header.Request(client.system) = @constCast(@alignCast(@ptrCast(temp)));
        t2.* = message_header.Header.Request(client.system){
            .request = 0,
            .command = .request,
            .client = 0,
            .operation = .signup_client,
            .cluster = 0,
            .release = 0,
            .message_id = uuid.UUID.v4(),
        };
        const header_size = @sizeOf(message_header.Header.Request(client.system));
        const Body = Operations.BodyType(client.system, .signup_client);
        var ptr_as_int = @intFromPtr(temp);
        ptr_as_int = ptr_as_int + header_size;
        const operation_struct: *Body = @ptrFromInt(ptr_as_int);
        operation_struct.username = username;
        operation_struct.email = email;
        operation_struct.password = password;

        replica.message_statuses[fiber_index] = .Ready;
        replica.push(fiber_index) catch undefined;
    }
}

export fn login(
    email_ptr: [*]const u8,
    email_len: usize,
    password_ptr: [*]const u8,
    password_len: usize,
) void {
    if (email_len > global_constants.MAX_EMAIL_LENGTH) {
        return;
    }
    if (password_len > global_constants.MAX_PASSWORD_LENGTH) {
        return;
    }

    const email_str = email_ptr[0..email_len];
    const password_str = password_ptr[0..password_len];

    const email = stack_string.StackString(u8, global_constants.MAX_EMAIL_LENGTH).init(email_str);
    const password = stack_string.StackString(u8, global_constants.MAX_PASSWORD_LENGTH).init(password_str);

    // add it to the state machine so on call back it can route it?

    // const Body = Operations.BodyType(.login_client);
    // const body: Body = .{ .username = username, .password = password };
    // replica.call_local(.add, body, reply: *Operations.ResultType(operation))

    if (replica.resurveAvailableFiber()) |fiber_index| {
        const temp = &replica.messages[fiber_index][0];
        const t2: *message_header.Header.Request(client.system) = @constCast(@alignCast(@ptrCast(temp)));
        t2.* = message_header.Header.Request(client.system){
            .request = 0,
            .command = .request,
            .client = 0,
            .operation = .login_client,
            .cluster = 0,
            .release = 0,
            .message_id = uuid.UUID.v4(),
        };
        const header_size = @sizeOf(message_header.Header.Request(client.system));
        const Body = Operations.BodyType(client.system, .login_client);
        var ptr_as_int = @intFromPtr(temp);
        ptr_as_int = ptr_as_int + header_size;
        const operation_struct: *Body = @ptrFromInt(ptr_as_int);
        operation_struct.email = email;
        operation_struct.password = password;

        replica.message_statuses[fiber_index] = .Ready;
        replica.push(fiber_index) catch undefined;
    }

    // _ = call_remote(.add, body);
}

const Operation = @import("operations.zig").Operation;

fn temp_return(app_state: AppState, message: []align(16) u8) void {
    _ = app_state;
    _ = message;
    // send(message.ptr, message.len);
}
