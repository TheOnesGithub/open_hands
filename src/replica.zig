const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const Operations = @import("operations.zig");

const uuid = @import("uuid.zig");

const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");

const httpz = @import("httpz");
const builtin = @import("builtin");

pub const Handled_Status = enum(u8) {
    done = 0,
    not_done = 1,
    wait = 2,
    ignore = 3,
};

pub const Message_Status = enum {
    Available,
    Ready,
    Running,
    Suspended,
    Reserved,
};

pub const Message_Request_Value = struct {
    waiting_index: u32,
    is_fiber_waiting: bool,
    reply_offset: usize,
    reply_size: usize,
};

pub const RemoteService = struct {
    service_type: type,
    call: *const fn (ptr: [*]const u8, len: usize) void,
};

pub fn ReplicaType(
    comptime System: type,
    comptime AppState: type,
    comptime RemoteServices: anytype,
    comptime message_number_max: usize,
    comptime message_size_max: usize,
) type {
    return struct {
        const Replica = @This();

        system: *System = undefined,
        app_state_data: [message_number_max]AppState = undefined,

        temp_return: *const fn (AppState, []align(16) u8) void = undefined,
        current_message: u32 = 1,
        messages: *[message_number_max][message_size_max]u8 =
            undefined,
        message_ids: [message_number_max]uuid.UUID =
            undefined,
        messages_state: *[message_number_max][message_size_max]u8 =
            undefined,
        message_statuses: [message_number_max]Message_Status =
            [_]Message_Status{.Available} ** message_number_max,
        message_indexs: [message_number_max]u32 = undefined,
        message_waiting_on_count: [message_number_max]u8 = [_]u8{0} ** message_number_max,

        // message_wait_on_map_buffer: [global_constants.message_wait_on_map_buffer_size]u8 = undefined,
        message_wait_on_map_buffer: [1024 * 1024 * 26]u8 = undefined,

        message_wait_on_map: AutoHashMap(uuid.UUID, Message_Request_Value) = undefined,
        fba: std.heap.FixedBufferAllocator = undefined,
        remote_request_buffer: *[message_size_max]u8 = undefined,

        top: usize = 0,

        const Options = struct {
            temp_return: *const fn (AppState, []align(16) u8) void,
        };

        pub fn push(self: *Replica, value: u32) !void {
            if (self.top < message_number_max) {
                self.message_indexs[self.top] = value;
                self.top += 1;
            } else {
                return error.Overflow;
            }
        }

        pub fn findAvailableFiber(self: *Replica) ?u32 {
            for (self.message_statuses, 0..) |status, index| {
                if (status == .Available) {
                    return @intCast(index);
                }
            }
            return null;
        }

        pub fn resurveAvailableFiber(self: *Replica) ?u32 {

            // self.stack.mutex.lock();
            if (self.findAvailableFiber()) |fiber_index| {
                self.message_statuses[fiber_index] = .Reserved;
                // self.stack.mutex.unlock();
                return fiber_index;
            } else {
                // self.stack.mutex.unlock();
                return null;
            }
        }

        pub fn init(
            self: *Replica,
            allocator: Allocator,
            system: *System,
            options: Options,
        ) !void {
            // const messages = try allocator.alignedAlloc([]u8, 16, global_constants.message_number_max);
            const messages = try allocator.alignedAlloc(
                [message_size_max]u8,
                16,
                message_number_max,
            );

            const messages_state = try allocator.alignedAlloc(
                [message_size_max]u8,
                16,
                message_number_max,
            );

            const remote_request_buffer = try allocator.alignedAlloc(
                u8,
                16,
                message_size_max,
            );

            // Allocate each message buffer
            // for (messages, message_buffers) |*msg, *buffer| {
            //     msg.* = buffer;
            // }

            self.fba = FixedBufferAllocator.init(&self.message_wait_on_map_buffer);
            const fixed_buffer_allocator = self.fba.allocator();
            self.message_wait_on_map = AutoHashMap(uuid.UUID, Message_Request_Value).init(fixed_buffer_allocator);

            self.* = .{
                .system = system,
                .temp_return = options.temp_return,
                .current_message = 0,
                .message_indexs = self.message_indexs,
                .message_statuses = self.message_statuses,
                .message_waiting_on_count = self.message_waiting_on_count,
                .messages = @ptrCast(messages.ptr),
                .message_ids = self.message_ids,
                .messages_state = @ptrCast(messages_state.ptr),
                .top = 0,
                .message_wait_on_map = self.message_wait_on_map,
                .message_wait_on_map_buffer = self.message_wait_on_map_buffer,
                .fba = self.fba,
                .remote_request_buffer = @ptrCast(remote_request_buffer.ptr),
            };

            std.debug.assert(@intFromPtr(self.remote_request_buffer) % 16 == 0);
        }

        /// Free all memory and unref all messages held by the replica.
        /// This does not deinitialize the Storage or Time.
        pub fn deinit(
            self: *Replica,
            allocator: Allocator,
        ) void {
            _ = self;
            _ = allocator;
        }

        // return true if a message was processed
        pub fn tick(self: *Replica, buffer: *align(16) [message_size_max]u8) bool {
            if (!builtin.cpu.arch.isWasm()) {
                // std.debug.print("r tick\r\n", .{});
            }
            var i: usize = self.top;
            var processed: bool = false;
            while (i > 0) {
                i -= 1;
                const idx = self.message_indexs[i];
                if (self.message_statuses[idx] == .Ready or (self.message_statuses[idx] == .Suspended and self.message_waiting_on_count[idx] == 0)) {
                    if (!builtin.cpu.arch.isWasm()) {
                        std.debug.print("tick: processing message with status: {any}\r\n", .{self.message_statuses[idx]});
                        std.debug.print("number of waiting on: {any}\r\n", .{self.message_waiting_on_count[idx]});
                    }
                    processed = true;
                    // Remove the item by shifting the others up
                    for (i..self.top - 1) |j| {
                        self.message_indexs[j] = self.message_indexs[j + 1];
                    }
                    self.top -= 1;
                    // return idx;

                    self.current_message = idx;
                    var hs: Handled_Status = undefined;
                    const h: *message_header.Header = @ptrCast(@alignCast(&self.messages[idx]));
                    if (h.command == .request) {
                        const h_request: *message_header.Header.Request(System) = @ptrCast(h);
                        if (comptime !builtin.cpu.arch.isWasm()) {
                            std.debug.print("got tick message id: {}\r\n", .{h_request.message_id});
                        }
                        // var buffer: [global_constants.message_size_max]u8 align(16) = undefined;
                        inline for (std.meta.fields(System.Operation)) |field| {
                            const op_enum_value = @field(System.Operation, field.name);
                            if (h_request.operation == op_enum_value) {
                                const temp = buffer;
                                const header_reply: *message_header.Header.Reply(System) = @ptrCast(@constCast(temp));
                                header_reply.* = message_header.Header.Reply(System){
                                    .request = 0,
                                    .command = .reply,
                                    .client = 0,
                                    .cluster = 0,
                                    .release = 0,
                                    .message_id = h_request.message_id,
                                    .replica = 0,
                                    .request_checksum = 0,
                                    .op = 0,
                                    .commit = 0,
                                    .timestamp = 0,
                                    .view = 0,
                                };
                                const Result = Operations.ResultType(System, op_enum_value);
                                // var r: Result = undefined;
                                const r: *Result = @ptrCast(@constCast(&temp[@sizeOf(message_header.Header.Reply(System))..][0]));
                                header_reply.size = @sizeOf(Result) + @sizeOf(message_header.Header.Reply(System));
                                hs = self.execute(
                                    op_enum_value,
                                    @alignCast(&self.messages[idx]),
                                    @constCast(r),
                                    @alignCast(&self.messages_state[idx]),
                                );

                                if (hs == .not_done) {
                                    self.message_statuses[idx] = .Ready;
                                    self.push(idx) catch {
                                        return true;
                                    };
                                } else if (hs == .wait) {
                                    self.message_statuses[idx] = .Suspended;
                                    self.push(self.current_message) catch undefined;
                                } else if (hs == .done) {
                                    // TODO: return the value
                                    if (self.message_wait_on_map.get(self.message_ids[idx])) |value| {
                                        _ = self.message_wait_on_map.remove(self.message_ids[idx]); // Remove the key-value pair
                                        if (value.is_fiber_waiting) {
                                            if (!builtin.cpu.arch.isWasm()) {
                                                std.debug.print("decrementing waiting on count\r\n", .{});
                                            }
                                            self.message_waiting_on_count[value.waiting_index] = self.message_waiting_on_count[value.waiting_index] - 1;
                                        }
                                        std.debug.assert(value.reply_size < @sizeOf(Result) + 1);
                                        const casted_reply: *Result = @alignCast(@ptrCast(&self.messages_state[value.waiting_index][value.reply_offset]));
                                        casted_reply.* = r.*;
                                        self.message_statuses[self.current_message] = .Available;
                                    } else {
                                        if (comptime !builtin.cpu.arch.isWasm()) {
                                            std.debug.print("remote return message id: {}\r\n", .{h_request.message_id});
                                        }
                                        self.temp_return(self.app_state_data[idx], buffer[0..header_reply.size]);
                                        // const ptr: [*]const u8 = @ptrCast(&buffer[0]);
                                        // self.temp_return(h_request.message_id, ptr[0..header_reply.size]);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return processed;
        }

        pub fn call_remote(
            self: *Replica,
            comptime Remote_Operations: type,
            comptime operation: Remote_Operations.Operation,
            body: Operations.BodyType(Remote_Operations, operation),
            reply: *Operations.ResultType(Remote_Operations, operation),
        ) !uuid.UUID {
            if (comptime !builtin.cpu.arch.isWasm()) {
                std.debug.print("in replica call remote \r\n", .{});
            }

            const reply_offset = @intFromPtr(reply) - @intFromPtr(&self.messages_state[self.current_message][0]);
            std.debug.assert(reply_offset < (message_size_max - @sizeOf(message_header.Header.Reply(Remote_Operations))));

            const message_id = uuid.UUID.v4();
            const message_request_value = Message_Request_Value{
                .waiting_index = self.current_message,
                .is_fiber_waiting = false,
                .reply_offset = reply_offset,
                .reply_size = @sizeOf(Operations.ResultType(Remote_Operations, operation)),
            };
            if (comptime !builtin.cpu.arch.isWasm()) {
                std.debug.print("putting message id in map: {}\r\n", .{message_id});
            }
            self.message_wait_on_map.put(message_id, message_request_value) catch |err| {
                if (!builtin.cpu.arch.isWasm()) {
                    std.debug.print("failed to put message id in map: {}\r\n", .{message_id});
                    std.debug.print("error: {s}\r\n", .{@errorName(err)});
                }
                return err;
            };
            if (comptime !builtin.cpu.arch.isWasm()) {
                std.debug.print("in replica call remote 2\r\n", .{});
            }

            // var buffer: [global_constants.message_size_max]u8 align(16) = undefined;
            // const temp = &buffer;
            // const temp = self.fba.allocator().alignedAlloc(u8, 16, message_size_max) catch |err| {
            //     if (comptime !builtin.cpu.arch.isWasm()) {
            //         std.debug.print("in replica call remote 4\r\n", .{});
            //         std.debug.print("failed to allocate buffer of size: {} error: {}\r\n", .{ message_size_max, err });
            //     }
            //     return message_id;
            // };
            // defer self.fba.allocator().free(temp);
            if (comptime !builtin.cpu.arch.isWasm()) {
                std.debug.print("in replica call remote 3\r\n", .{});
            }

            std.debug.assert(@intFromPtr(self.remote_request_buffer) % 16 == 0);
            // const temp = &self.messages[fiber_index][0];
            const t2: *message_header.Header.Request(Remote_Operations) = @alignCast(@ptrCast(@constCast(self.remote_request_buffer)));
            t2.* = message_header.Header.Request(Remote_Operations){
                .request = 0,
                .command = .request,
                .client = 0,
                .operation = operation,
                .cluster = 0,
                .release = 0,
                .message_id = message_id,
            };
            const header_size = @sizeOf(message_header.Header.Request(Remote_Operations));
            const Body = Operations.BodyType(Remote_Operations, operation);
            var ptr_as_int = @intFromPtr(self.remote_request_buffer);
            ptr_as_int = ptr_as_int + header_size;
            const operation_struct: *Body = @ptrFromInt(ptr_as_int);
            operation_struct.* = body;

            if (comptime !builtin.cpu.arch.isWasm()) {
                std.debug.print("call remote before inline\r\n", .{});
            }
            inline for (RemoteServices) |remote_service| {
                if (remote_service.service_type == Remote_Operations) {
                    remote_service.call(@constCast(@ptrCast(self.remote_request_buffer)), message_size_max);
                }
            }

            return message_id;
        }

        pub fn call_local(
            self: *Replica,
            comptime operation: System.Operation,
            body: Operations.BodyType(System, operation),
            reply: *Operations.ResultType(System, operation),
        ) uuid.UUID {
            const reply_offset = @intFromPtr(reply) - @intFromPtr(&self.messages_state[self.current_message][0]);
            std.debug.assert(reply_offset < (message_size_max - @sizeOf(message_header.Header.Reply(System))));

            const message_id = uuid.UUID.v4();
            const message_request_value = Message_Request_Value{
                .waiting_index = self.current_message,
                .is_fiber_waiting = false,
                .reply_offset = reply_offset,
                .reply_size = @sizeOf(Operations.ResultType(System, operation)),
            };
            self.message_wait_on_map.put(message_id, message_request_value) catch undefined;

            if (self.resurveAvailableFiber()) |fiber_index| {
                const temp = &self.messages[fiber_index][0];
                const t2: *message_header.Header.Request(System) = @ptrCast(temp);
                t2.* = message_header.Header.Request(System){
                    .request = 0,
                    .command = .request,
                    .client = 0,
                    .operation = operation,
                    .cluster = 0,
                    .release = 0,
                    .message_id = message_id,
                };
                const header_size = @sizeOf(message_header.Header.Request(System));
                const Body = Operations.BodyType(System, operation);
                var ptr_as_int = @intFromPtr(temp);
                ptr_as_int = ptr_as_int + header_size;
                const operation_struct: *Body = @ptrFromInt(ptr_as_int);
                operation_struct.* = body;

                self.message_ids[fiber_index] = message_id;
                self.message_statuses[fiber_index] = .Ready;
                self.push(fiber_index) catch {
                    return message_id;
                };
            }

            return message_id;
        }

        pub fn add_wait(self: *Replica, message_id: *const uuid.UUID) void {
            if (!builtin.cpu.arch.isWasm()) {
                std.debug.print("started add wait message_id: {any}\r\n", .{message_id});
                std.debug.print("wait count: {any}\r\n", .{self.message_wait_on_map.count()});
            }

            // print all items is the message wait on map
            if (!builtin.cpu.arch.isWasm()) {
                var iter = self.message_wait_on_map.iterator();
                while (iter.next()) |item| {
                    std.debug.print("message id: {any}\r\n", .{item.key_ptr.*});
                }
            }

            if (self.message_wait_on_map.getPtr(message_id.*)) |value| {
                value.is_fiber_waiting = true;
                if (!builtin.cpu.arch.isWasm()) {
                    std.debug.print("incrementing waiting on count\r\n", .{});
                }
                self.message_waiting_on_count[self.current_message] = self.message_waiting_on_count[self.current_message] + 1;
                return;
            }
            return; //has already geten the value back

        }

        pub fn execute(
            self: *Replica,
            comptime operation: System.Operation,
            message_body_used: *align(16) [message_size_max]u8,
            res: *Operations.ResultType(System, operation),
            message_state: *align(16) [message_size_max]u8,
        ) Handled_Status {
            // _ = self;
            // comptime assert(!operation_is_multi_batch(operation));
            // comptime assert(operation_is_batchable(operation));

            const Body = Operations.BodyType(System, operation);
            // const Result = Operations.ResultType(operation);
            const State = Operations.StateType(System, operation);
            const Call = Operations.CallType(System, operation);
            const header_size = @sizeOf(message_header.Header.Request(System));
            var ptr_as_int = @intFromPtr(message_body_used);
            ptr_as_int = ptr_as_int + header_size;
            const operation_struct: *Body = @ptrFromInt(ptr_as_int);

            const state: *State = @ptrCast(message_state);

            return Call(self.system, self, operation_struct, res, state);
        }
    };
}

pub fn u8_slice_ptr_from_struct_ref(comptime T: type, value: *T) *[@sizeOf(T)]u8 {
    const ptr: [*]u8 = @ptrCast(value);
    return ptr[0..@sizeOf(T)];
}
