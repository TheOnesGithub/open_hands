const std = @import("std");
const Allocator = std.mem.Allocator;

const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");

pub const Handled_Status = enum {
    not_done,
    done,
    wait,
};

pub const Message_Status = enum {
    Available,
    Ready,
    Running,
    Suspended,
    Reserved,
};

pub fn ReplicaType(
    comptime StateMachine: type,
    // comptime MessageBus: type,
    // comptime Time: type,
) type {
    return struct {
        const Replica = @This();
        state_machine: StateMachine,

        // buffer:[]
        messages: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_state_data: [global_constants.message_number_max][global_constants.message_size_max]u8 align(16) =
            undefined,
        message_statuses: [global_constants.message_number_max]Message_Status =
            [_]Message_Status{.Available} ** global_constants.message_number_max,
        message_indexs: [global_constants.message_number_max]u32 = undefined,
        message_waiting_on_count: [global_constants.message_number_max]u8 = [_]u8{0} ** global_constants.message_number_max,

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

            self.* = .{
                .message_indexs = self.message_indexs,
                .message_state_data = self.message_state_data,
                .message_statuses = self.message_statuses,
                .message_waiting_on_count = self.message_waiting_on_count,
                .messages = self.messages,
                .top = 0,
                .state_machine = self.state_machine,
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

                    var hs: Handled_Status = undefined;
                    const h: *message_header.Header = @ptrCast(&self.messages[idx][0]);
                    if (h.command == .request) {
                        const h_request: *message_header.Header.Request = @ptrCast(h);
                        switch (h_request.operation) {
                            .print => {
                                hs = self.state_machine.execute(
                                    .print,
                                    &self.messages[idx],
                                    &self.message_state_data[idx],
                                );
                            },
                            .pulse => {
                                hs = self.state_machine.execute(
                                    .pulse,
                                    &self.messages[idx],
                                    &self.message_state_data[idx],
                                );
                            },
                            .add => {
                                hs = self.state_machine.execute(
                                    .add,
                                    &self.messages[idx],
                                    &self.message_state_data[idx],
                                );
                            },
                        }
                    }
                    if (hs == .not_done) {
                        self.message_statuses[idx] = .Ready;
                        self.push(idx) catch {
                            return;
                        };
                    } else if (hs == .wait) {
                        self.message_statuses[idx] = .Suspended;
                    }
                    // if (h.into_any() == .request) {
                    //     self.state_machine.execute(self.messages[idx]);
                    // }
                }
            }
        }
    };
}
