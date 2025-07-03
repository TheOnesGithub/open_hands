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
) type {
    return struct {
        const Replica = @This();
        app_state_data: [global_constants.message_number_max]AppState = undefined,

        temp_return: *const fn (AppState, []align(16) u8) void = undefined,
        current_message: u32 = 1,
        messages: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_ids: [global_constants.message_number_max]uuid.UUID =
            undefined,
        messages_state: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_statuses: [global_constants.message_number_max]Message_Status =
            [_]Message_Status{.Available} ** global_constants.message_number_max,
        message_indexs: [global_constants.message_number_max]u32 = undefined,
        message_waiting_on_count: [global_constants.message_number_max]u8 = [_]u8{0} ** global_constants.message_number_max,

        message_wait_on_map_buffer: [global_constants.message_wait_on_map_buffer_size]u8 = undefined,
        message_wait_on_map: AutoHashMap(uuid.UUID, Message_Request_Value) = undefined,
        fba: std.heap.FixedBufferAllocator = undefined,

        top: usize = 0,

        const Options = struct {
            temp_return: *const fn (AppState, []align(16) u8) void,
        };

        pub fn push(self: *Replica, value: u32) !void {
            if (self.top < global_constants.message_number_max) {
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
            // allocator: Allocator,
            options: Options,
        ) !void {
            // try self.state_machine.init(
            //     // allocator,
            //     // &self.grid,
            //     options.state_machine_options,
            // );
            //
            // errdefer self.state_machine.deinit();
            // errdefer self.state_machine.deinit(allocator);

            self.fba = FixedBufferAllocator.init(&self.message_wait_on_map_buffer);
            const fixed_buffer_allocator = self.fba.allocator();
            self.message_wait_on_map = AutoHashMap(uuid.UUID, Message_Request_Value).init(fixed_buffer_allocator);

            self.* = .{
                .temp_return = options.temp_return,
                .current_message = 0,
                .message_indexs = self.message_indexs,
                .message_statuses = self.message_statuses,
                .message_waiting_on_count = self.message_waiting_on_count,
                .messages = self.messages,
                .message_ids = self.message_ids,
                .messages_state = self.messages_state,
                .top = 0,
                .message_wait_on_map = self.message_wait_on_map,
                .message_wait_on_map_buffer = self.message_wait_on_map_buffer,
                .fba = self.fba,
            };
        }

        /// Free all memory and unref all messages held by the replica.
        /// This does not deinitialize the Storage or Time.
        pub fn deinit(
            self: *Replica,
            // allocator: Allocator,
        ) void {
            _ = self;
            // self.state_machine.deinit(allocator);
        }

        pub fn tick(self: *Replica) void {
            var i: usize = self.top;
            while (i > 0) {
                i -= 1;
                const idx = self.message_indexs[i];
                if (self.message_statuses[idx] == .Ready or (self.message_statuses[idx] == .Suspended and self.message_waiting_on_count[idx] == 0)) {
                    // Remove the item by shifting the others up
                    for (i..self.top - 1) |j| {
                        self.message_indexs[j] = self.message_indexs[j + 1];
                    }
                    self.top -= 1;
                    // return idx;

                    self.current_message = idx;
                    var hs: Handled_Status = undefined;
                    const h: *message_header.Header = @ptrCast(&self.messages[idx][0]);
                    if (h.command == .request) {
                        const h_request: *message_header.Header.Request(System.Operation) = @ptrCast(h);
                        inline for (std.meta.fields(System.Operation)) |field| {
                            const op_enum_value = @field(System.Operation, field.name);
                            if (h_request.operation == op_enum_value) {
                                var buffer: [global_constants.message_size_max]u8 align(16) = undefined;
                                const temp = &buffer;
                                const header_reply: *message_header.Header.Reply(System.Operation) = @ptrCast(@constCast(temp));
                                header_reply.* = message_header.Header.Reply(System.Operation){
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
                                const r: *Result = @ptrCast(@constCast(&temp[@sizeOf(message_header.Header.Reply(System.Operation))..][0]));
                                header_reply.size = @sizeOf(Result) + @sizeOf(message_header.Header.Reply(System.Operation));
                                hs = self.execute(
                                    op_enum_value,
                                    &self.messages[idx],
                                    @constCast(r),
                                    &self.messages_state[idx],
                                );

                                if (hs == .not_done) {
                                    self.message_statuses[idx] = .Ready;
                                    self.push(idx) catch {
                                        return;
                                    };
                                } else if (hs == .wait) {
                                    self.message_statuses[idx] = .Suspended;
                                    self.push(self.current_message) catch undefined;
                                } else if (hs == .done) {
                                    // TODO: return the value
                                    if (self.message_wait_on_map.get(self.message_ids[idx])) |value| {
                                        _ = self.message_wait_on_map.remove(self.message_ids[idx]); // Remove the key-value pair
                                        if (value.is_fiber_waiting) {
                                            self.message_waiting_on_count[value.waiting_index] = self.message_waiting_on_count[value.waiting_index] - 1;
                                        }
                                        std.debug.assert(value.reply_size < @sizeOf(Result) + 1);
                                        const casted_reply: *Result = @alignCast(@ptrCast(&self.messages_state[value.waiting_index][value.reply_offset]));
                                        casted_reply.* = r.*;
                                        self.message_statuses[self.current_message] = .Available;
                                    } else {
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
        }

        pub fn call_remote(
            self: *Replica,
            comptime Remote_Operations: type,
            comptime operation: Remote_Operations.Operation,
            body: Operations.BodyType(Remote_Operations, operation),
            reply: *Operations.ResultType(Remote_Operations, operation),
        ) uuid.UUID {
            _ = self;
            _ = reply;
            const message_id = uuid.UUID.v4();

            var buffer: [global_constants.message_size_max]u8 align(16) = undefined;
            const temp = &buffer;
            // const temp = &self.messages[fiber_index][0];
            const t2: *message_header.Header.Request(Remote_Operations.Operation) = @ptrCast(@constCast(temp));
            t2.* = message_header.Header.Request(Remote_Operations.Operation){
                .request = 0,
                .command = .request,
                .client = 0,
                .operation = operation,
                .cluster = 0,
                .release = 0,
                .message_id = message_id,
            };
            const header_size = @sizeOf(message_header.Header.Request(Remote_Operations.Operation));
            const Body = Operations.BodyType(Remote_Operations, operation);
            var ptr_as_int = @intFromPtr(temp);
            ptr_as_int = ptr_as_int + header_size;
            const operation_struct: *Body = @ptrFromInt(ptr_as_int);
            operation_struct.* = body;

            inline for (RemoteServices) |remote_service| {
                if (remote_service.service_type == Remote_Operations) {
                    remote_service.call(temp, buffer.len);
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
            std.debug.assert(reply_offset < global_constants.message_body_size_max);

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
                const t2: *message_header.Header.Request(System.Operation) = @ptrCast(temp);
                t2.* = message_header.Header.Request(System.Operation){
                    .request = 0,
                    .command = .request,
                    .client = 0,
                    .operation = operation,
                    .cluster = 0,
                    .release = 0,
                    .message_id = message_id,
                };
                const header_size = @sizeOf(message_header.Header.Request(System.Operation));
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
            if (self.message_wait_on_map.getPtr(message_id.*)) |value| {
                value.is_fiber_waiting = true;
                self.message_waiting_on_count[self.current_message] = self.message_waiting_on_count[self.current_message] + 1;
                return;
            }
            return; //has already geten the value back

        }

        pub fn execute(
            self: *Replica,
            comptime operation: System.Operation,
            message_body_used: *align(16) [global_constants.message_body_size_max]u8,
            res: *Operations.ResultType(System, operation),
            message_state: *align(16) [global_constants.message_body_size_max]u8,
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

            return Call(self, operation_struct, res, state);
        }
    };
}

pub fn u8_slice_ptr_from_struct_ref(comptime T: type, value: *T) *[@sizeOf(T)]u8 {
    const ptr: [*]u8 = @ptrCast(value);
    return ptr[0..@sizeOf(T)];
}
