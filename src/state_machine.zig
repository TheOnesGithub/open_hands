const std = @import("std");
const assert = std.debug.assert;
const sl = @import("selection.zig");

const global_constants = @import("constants.zig");

pub fn StateMachineType(
    // comptime Storage: type,
    comptime config: global_constants.StateMachineConfig,
) type {
    assert(config.message_body_size_max > 0);
    // assert(config.lsm_compaction_ops > 0);
    // assert(global_constants.vsr_operations_reserved > 0);

    return struct {
        const StateMachine = @This();
        pub const Operation = sl.Operation;

        pub const constants = struct {
            pub const message_body_size_max = config.message_body_size_max;
        };

        pub fn EventType(comptime operation: Operation) type {
            return switch (operation) {
                .pulse => void,
                .print => void,
            };
        }

        pub fn ResultType(comptime operation: Operation) type {
            return switch (operation) {
                .pulse => void,
                .print => void,
            };
        }

        pub fn execute(
            self: *StateMachine,
            // timestamp: u64,
            // comptime operation: Operation,
            operation: Operation,
            // message_body_used: []align(16) const u8,
            message_body_used: *align(16) [constants.message_body_size_max]u8,
            output_buffer: *align(16) [constants.message_body_size_max]u8,
        ) usize {
            // comptime assert(!operation_is_multi_batch(operation));
            // comptime assert(operation_is_batchable(operation));

            switch (operation) {
                .pulse => return self.print(
                    // timestamp,
                    message_body_used,
                    output_buffer,
                ),
                .print => return self.print(
                    message_body_used,
                    output_buffer,
                ),
                // else => comptime unreachable,
            }
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

        fn print(
            self: *StateMachine,
            // timestamp: u64,
            message_body_used: *align(16) [constants.message_body_size_max]u8,
            output_buffer: *align(16) [constants.message_body_size_max]u8,
        ) usize {
            _ = self;
            _ = message_body_used;
            _ = output_buffer;
            std.debug.print("ran print \r\n", .{});
            return 0;
        }
    };
}
