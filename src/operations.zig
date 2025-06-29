const std = @import("std");
const constants = @import("constants.zig");
const operations = @import("selection.zig").operations;
const replica = @import("replica.zig");
const main = @import("main.zig");

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

pub fn CacheType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).cache;
}

pub fn CallType(comptime operation: Operation) fn (
    *main.Replica,
    *EventType(operation),
    *ResultType(operation),
    *CacheType(operation),
) replica.Handled_Status {
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
        const TCache = @field(operations, field.name).cache;
        if (@alignOf(TCache) != 16) {
            @compileError("cache " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TCache)));
        }
    }
}
