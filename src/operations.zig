const std = @import("std");
const constants = @import("constants.zig");
const operations = @import("selection.zig").operations;
const replica = @import("replica.zig");
const main = @import("main.zig");

pub const Operation = enum(u8) {
    print = 0,
    add = 1,
    make_string = 2,
};

pub fn BodyType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).Body;
}

pub fn ResultType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).Result;
}

pub fn StateType(comptime operation: Operation) type {
    return @field(operations, @tagName(operation)).State;
}

pub fn CallType(comptime operation: Operation) fn (
    *main.Replica,
    *BodyType(operation),
    *ResultType(operation),
    *StateType(operation),
) replica.Handled_Status {
    return @field(operations, @tagName(operation)).call;
}

comptime {
    for (std.meta.fields(operations)) |field| {
        const TBody = @field(operations, field.name).Body;
        if (@alignOf(TBody) != 16) {
            @compileError("body " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TBody)));
        }

        const TResult = @field(operations, field.name).Result;
        if (@alignOf(TResult) != 16) {
            @compileError("result " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TResult)));
        }
        const TState = @field(operations, field.name).State;
        if (@alignOf(TState) != 16) {
            @compileError("state " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TState)));
        }
    }
}
