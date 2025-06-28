const std = @import("std");
const constants = @import("constants.zig");
const operations = @import("selection.zig").operations;
const replica = @import("replica.zig");

pub const Operation = enum(u8) {
    pulse = 0,
    print = 1,
    add = 2,
};

pub fn EventType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).event;
}

pub fn ResultType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).result;
}

pub fn CallType(comptime operation: Operation) fn (*EventType(operation), *ResultType(operation)) replica.Message_Status {
    return @field(operations, @tagName(operation)).call;
}

comptime {
    for (std.meta.fields(operations)) |field| {
        const TEvent = @field(operations, field.name).event;
        if (@alignOf(TEvent) != 16) {
            @compileError("event " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TEvent)));
        }

        const TResult = @field(operations, field.name).result;
        if (@alignOf(TResult) != 16) {
            @compileError("result " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TResult)));
        }
    }
}
