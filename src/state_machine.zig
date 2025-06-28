const std = @import("std");
const assert = std.debug.assert;
const sl = @import("selection.zig");

const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");

const Operations = @import("operations.zig");

pub fn StateMachineType(
    // comptime Storage: type,
    comptime config: global_constants.StateMachineConfig,
) type {
    assert(config.message_body_size_max > 0);
    // assert(config.lsm_compaction_ops > 0);
    // assert(global_constants.vsr_operations_reserved > 0);

    return struct {
        const StateMachine = @This();
        pub const Operation = Operations.Operation;

        pub const constants = struct {
            pub const message_body_size_max = config.message_body_size_max;
        };

        pub fn execute(
            self: *StateMachine,
            // timestamp: u64,
            comptime operation: Operation,
            // operation: Operation,
            // message_body_used: []align(16) const u8,
            message_body_used: *align(16) [constants.message_body_size_max]u8,
            output_buffer: *align(16) [constants.message_body_size_max]u8,
        ) usize {
            _ = self;
            // comptime assert(!operation_is_multi_batch(operation));
            // comptime assert(operation_is_batchable(operation));

            const Event = Operations.EventType(operation);
            const Result = Operations.ResultType(operation);
            const Call = Operations.CallType(operation);
            const header_size = @sizeOf(message_header.Header.Request);
            var ptr_as_int = @intFromPtr(message_body_used);
            ptr_as_int = ptr_as_int + header_size;
            const operation_struct: *Event = @ptrFromInt(ptr_as_int);

            if (comptime Result == void) {
                Call(operation_struct.*, output_buffer);
            } else {
                _ = Call(operation_struct.*, output_buffer);
            }

            // switch (operation) {
            //     .pulse => return self.print(
            //         // timestamp,
            //         operation_struct.*,
            //         output_buffer,
            //     ),
            //     .print => return self.print(
            //         operation_struct.*,
            //         output_buffer,
            //     ),
            //     // else => comptime unreachable,
            // }
            return 0;
        }

        // fn execute_create(
        //     self: *StateMachine,
        //     comptime operation: Operation,
        //     // timestamp: u64,
        //     batch: []const u8,
        //     output_buffer: []u8,
        // ) usize {
        //     comptime assert(operation == .create_accounts or
        //         operation == .create_transfers or
        //         operation == .deprecated_create_accounts or
        //         operation == .deprecated_create_transfers);
        //
        //     const Event = EventType(operation);
        //     const Result = ResultType(operation);
        //     _ = self;
        //     _ = batch;
        //     _ = output_buffer;
        //     _ = Event;
        //     _ = Result;
        // }

    };
}
