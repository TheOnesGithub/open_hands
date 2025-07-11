const std = @import("std");
const uuid = @import("uuid.zig");
const stack_string = @import("stack_string.zig");
const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");
pub const ReplicaZig = @import("replica.zig");
pub const client = @import("systems/client/client.zig");
const Operations = @import("operations.zig");
const AppState = @import("systems/client/client.zig").AppState;
const gateway = @import("systems/gateway/gateway.zig");
const shared = @import("shared.zig");
const component_string = @import("components/string.zig");
const RzMenu = @import("components/rz/menu.zig").Component;

const ComponentVTable = @import("components/component.zig").ComponentVTable;

const allocator = std.heap.wasm_allocator;

var replica: client.Replica = undefined;

pub extern fn send(ptr: [*]const u8, len: usize) void;

pub extern fn print_wasm(ptr: [*]const u8, len: usize) void;

pub extern fn update_data(ptr: [*]const u8, len: usize) void;

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

export fn server_return(ptr: [*]const u8, len: usize) void {
    const t = "ran from wasm";
    print_wasm(t, t.len);
    print_wasm(ptr, len);

    const data = ptr[0..len];

    if (data.len < @sizeOf(message_header.Header.Reply(gateway.system))) {
        const temp = "received message is too small\n";
        print_wasm(temp, temp.len);
        return;
    }

    // copy the data to a buffer that is aligned
    var buffer2: [1024 * 4]u8 align(16) = undefined;
    const temp = buffer2[0..data.len];
    @memcpy(temp, data);

    // std.debug.print("received from kv: {any}\n", .{data});
    // cast data to a recieved header
    const header: *message_header.Header.Reply(gateway.system) = @ptrCast(&buffer2);
    // get the message id
    const message_id = header.message_id;
    // std.debug.print("message id: {any}\n", .{message_id});
    const user_id_2 = message_id.toHex(.lower);
    print_wasm(&user_id_2, user_id_2.len);

    // print the numer of item in the map
    // make the numer a stirng
    // const map_message_0 = std.fmt.allocPrint(allocator, "map size: {}", .{replica.message_wait_on_map.count()}) catch {
    //     return;
    // };
    print_wasm(@ptrCast(&replica.message_wait_on_map.count()), @sizeOf(u32));

    // TODO:
    // route the reply to the corrent message based on the message id
    // this needs to be able to interact with the replica
    // this needs to be made thread safe
    if (replica.message_wait_on_map.get(message_id)) |value| {
        const map_message = "got message from map";
        print_wasm(map_message, map_message.len);
        if (value.is_fiber_waiting) {
            replica.message_waiting_on_count[value.waiting_index] = replica.message_waiting_on_count[value.waiting_index] - 1;
        }
        //TODO: check that size of the data received matches the size of the data expected

        // std.debug.assert(value.reply_size < @sizeOf(Operations.ResultType(kv.system, header.operation)) + 1);
        // const casted_reply: *Operations.ResultType(kv.system, header.operation) = @alignCast(@ptrCast(&replica.messages_state[value.waiting_index][value.reply_offset]));

        // casted_reply.* = buffer[@sizeOf(message_header.Header.Reply(kv.system))..header.size];
        // @memcpy(casted_reply, buffer[@sizeOf(message_header.Header.Reply(kv.system))..header.size]);
        // @memcpy(std.mem.asBytes(casted_reply), buffer[@sizeOf(message_header.Header.Reply(kv.system.Operation))..header.size]);
        @memcpy(
            replica.messages_state[value.waiting_index][value.reply_offset .. value.reply_offset + (header.size - @sizeOf(message_header.Header.Reply(gateway.system)))],
            buffer2[@sizeOf(message_header.Header.Reply(gateway.system))..header.size],
        );

        // std.debug.print("got vk reply chcek\r\n", .{});
    }
}

pub export fn updateContent() *const u8 {
    // first 4 bytes are the length of the string

    const BufferSize = 50000;

    var writer = shared.BufferWriter.init(&allocator, BufferSize) catch {
        const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        return &empty[0];
    };

    writer.set_lens();

    var c_battle = @import("components/rz/pages/battle.zig").Component{};
    var battle_ptr = c_battle.get_compenent();

    var rz_menu = RzMenu{ .content = &battle_ptr };
    var rz_menu_ptr = rz_menu.get_compenent();
    rz_menu_ptr.render(&writer) catch {
        const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        return &empty[0];
    };

    const addr_int: usize = @intFromPtr(writer.buffer.ptr);
    const addr: *u8 = @ptrFromInt(addr_int + writer.position_header);
    return addr;
}

pub export fn set_menu(index_left_to_right: u8) *const u8 {
    const BufferSize = 50000;

    var writer = shared.BufferWriter.init(&allocator, BufferSize) catch {
        const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        return &empty[0];
    };

    writer.set_lens();

    switch (index_left_to_right) {
        4 => {
            var home = @import("components/rz/pages/home.zig").Component{
                .username = client.global_state.username.?.to_slice() catch {
                    const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                    return &empty[0];
                },
                .display_name = client.global_state.display_name.?.to_slice() catch {
                    const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                    return &empty[0];
                },
            };
            var home_ptr = home.get_compenent();
            home_ptr.render(&writer) catch {
                const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                return &empty[0];
            };
        },
        1 => {
            var cards = @import("components/rz/pages/cards.zig").Component{};
            var cards_ptr = cards.get_compenent();
            cards_ptr.render(&writer) catch {
                const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                return &empty[0];
            };
        },
        2 => {
            var battle = @import("components/rz/pages/battle.zig").Component{};
            var battle_ptr = battle.get_compenent();
            battle_ptr.render(&writer) catch {
                const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                return &empty[0];
            };
        },
        3 => {
            var clan = @import("components/rz/pages/clan.zig").Component{};
            var clan_ptr = clan.get_compenent();
            clan_ptr.render(&writer) catch {
                const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                return &empty[0];
            };
        },
        0 => {
            var shop = @import("components/rz/pages/shop.zig").Component{};
            var shop_ptr = shop.get_compenent();
            shop_ptr.render(&writer) catch {
                const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
                return &empty[0];
            };
        },
        else => {
            const empty = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
            return &empty[0];
        },
    }

    const addr_int: usize = @intFromPtr(writer.buffer.ptr);
    const addr: *u8 = @ptrFromInt(addr_int + writer.position_header);
    return addr;
}
