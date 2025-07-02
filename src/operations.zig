const std = @import("std");
const constants = @import("constants.zig");
const project = @import("selection.zig");
const replica = @import("replica.zig");
const main = @import("main.zig");

pub fn BodyType(comptime Operations: type, comptime operation: Operations.Operation) type {
    return @field(Operations.operations, @tagName(operation)).Body;
}

pub fn ResultType(comptime Operations: type, comptime operation: Operations.Operation) type {
    return @field(Operations.operations, @tagName(operation)).Result;
}

pub fn StateType(comptime Operations: type, comptime operation: Operations.Operation) type {
    return @field(Operations.operations, @tagName(operation)).State;
}

pub fn CallType(comptime Operations: type, comptime operation: Operations.Operation) fn (
    *anyopaque,
    *BodyType(Operations, operation),
    *ResultType(Operations, operation),
    *StateType(Operations, operation),
) replica.Handled_Status {
    return @field(Operations.operations, @tagName(operation)).call;
}

comptime {
    // for (std.meta.fields(operations)) |field| {
    //     const TBody = @field(operations, field.name).Body;
    //     if (@alignOf(TBody) != 16) {
    //         @compileError("body " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TBody)));
    //     }
    //
    //     const TResult = @field(operations, field.name).Result;
    //     if (@alignOf(TResult) != 16) {
    //         @compileError("result " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TResult)));
    //     }
    //     const TState = @field(operations, field.name).State;
    //     if (@alignOf(TState) != 16) {
    //         @compileError("state " ++ field.name ++ " not aligned to 16, but to " ++ @tagName(@alignOf(TState)));
    //     }
    // }
}
