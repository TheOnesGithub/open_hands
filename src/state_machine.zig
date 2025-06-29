const std = @import("std");
const assert = std.debug.assert;
const sl = @import("selection.zig");
const main = @import("main.zig");

const global_constants = @import("constants.zig");
const message_header = @import("message_header.zig");

const Operations = @import("operations.zig");
const replica = @import("replica.zig");

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
            rep: *main.Replica,
            // timestamp: u64,
            comptime operation: Operation,
            // operation: Operation,
            message_body_used: *align(16) [constants.message_body_size_max]u8,
            res: *Operations.ResultType(operation),
            message_cache: *align(16) [constants.message_body_size_max]u8,
        ) replica.Handled_Status {
            _ = self;
            // comptime assert(!operation_is_multi_batch(operation));
            // comptime assert(operation_is_batchable(operation));

            const Event = Operations.EventType(operation);
            // const Result = Operations.ResultType(operation);
            const Cache = Operations.CacheType(operation);
            const Call = Operations.CallType(operation);
            const header_size = @sizeOf(message_header.Header.Request);
            var ptr_as_int = @intFromPtr(message_body_used);
            ptr_as_int = ptr_as_int + header_size;
            const operation_struct: *Event = @ptrFromInt(ptr_as_int);

            const cache: *Cache = @ptrCast(message_cache);

            return Call(rep, operation_struct, res, cache);
        }
    };
}
