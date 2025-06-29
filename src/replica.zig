const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const Operations = @import("operations.zig");
pub const Operation = Operations.Operation;

const uuid = @import("uuid.zig");

const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");

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
};

pub fn ReplicaType(
    comptime StateMachine: type,
    // comptime MessageBus: type,
    // comptime Time: type,
) type {
    return struct {
        const Replica = @This();
        state_machine: StateMachine,

        current_message: u32 = 1,
        messages: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_ids: [global_constants.message_number_max]uuid.UUID =
            undefined,
        message_state_data: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        messages_cache: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_statuses: [global_constants.message_number_max]Message_Status =
            [_]Message_Status{.Available} ** global_constants.message_number_max,
        message_indexs: [global_constants.message_number_max]u32 = undefined,
        message_waiting_on_count: [global_constants.message_number_max]u8 = [_]u8{0} ** global_constants.message_number_max,

        message_wait_on_map_buffer: [global_constants.message_wait_on_map_buffer_size]u8 = undefined,
        message_wait_on_map: AutoHashMap(uuid.UUID, Message_Request_Value) = undefined,
        fba: std.heap.FixedBufferAllocator = undefined,

        top: usize = 0,

        const Options = struct {};

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
            _ = options;
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
                .current_message = 0,
                .message_indexs = self.message_indexs,
                .message_state_data = self.message_state_data,
                .message_statuses = self.message_statuses,
                .message_waiting_on_count = self.message_waiting_on_count,
                .messages = self.messages,
                .message_ids = self.message_ids,
                .messages_cache = self.messages_cache,
                .top = 0,
                .state_machine = self.state_machine,
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
                        const h_request: *message_header.Header.Request = @ptrCast(h);
                        inline for (std.meta.fields(Operation)) |field| {
                            const op_enum_value = @field(Operation, field.name);
                            if (h_request.operation == op_enum_value) {
                                const Result = Operations.ResultType(op_enum_value);
                                var r: Result = undefined;
                                hs = self.state_machine.execute(
                                    self,
                                    op_enum_value,
                                    &self.messages[idx],
                                    &r,
                                    &self.messages_cache[idx],
                                );
                            }
                        }
                    }
                    if (hs == .not_done) {
                        self.message_statuses[idx] = .Ready;
                        self.push(idx) catch {
                            return;
                        };
                    } else if (hs == .wait) {
                        self.message_statuses[idx] = .Suspended;
                        self.push(self.current_message) catch undefined;
                    } else if (hs == .done) {
                        if (self.message_wait_on_map.get(self.message_ids[idx])) |value| {
                            _ = self.message_wait_on_map.remove(self.message_ids[idx]); // Remove the key-value pair
                            if (value.is_fiber_waiting) {
                                self.message_waiting_on_count[value.waiting_index] = self.message_waiting_on_count[value.waiting_index] - 1;
                            }
                            self.message_statuses[self.current_message] = .Available;
                        } else {
                            std.debug.print("this message could be sent from over the network?\n", .{});

                            // SCHEDULER_CONFIG.handle_network_reply(message_id, scheduler_ptr.get_stack_ptr(scheduler_ptr.current_fiber));
                        }
                    }
                    // if (h.into_any() == .request) {
                    //     self.state_machine.execute(self.messages[idx]);
                    // }
                }
            }
        }

        pub fn call_local(
            self: *Replica,
            comptime operation: Operation,
            event: Operations.EventType(operation),
        ) uuid.UUID {
            const message_id = uuid.UUID.v4();
            const message_request_value = Message_Request_Value{
                .waiting_index = self.current_message,
                .is_fiber_waiting = false,
            };
            self.message_wait_on_map.put(message_id, message_request_value) catch undefined;

            if (self.resurveAvailableFiber()) |fiber_index| {
                const temp = &self.messages[fiber_index][0];
                const t2: *message_header.Header.Request = @ptrCast(temp);
                t2.* = message_header.Header.Request{
                    .request = 0,
                    .command = .request,
                    .client = 0,
                    .operation = operation,
                    .cluster = 0,
                    .release = 0,
                };
                const header_size = @sizeOf(message_header.Header.Request);
                const Event = Operations.EventType(operation);
                var ptr_as_int = @intFromPtr(temp);
                ptr_as_int = ptr_as_int + header_size;
                const operation_struct: *Event = @ptrFromInt(ptr_as_int);
                operation_struct.* = event;

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
                // self.stack.fiber_statuses[self.current_fiber] = .Suspended;
                // self.push(self.current_message) catch undefined;

                return;
            }
            return; //has already geten the value back

        }
    };
}
