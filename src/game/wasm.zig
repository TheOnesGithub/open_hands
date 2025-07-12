const std = @import("std");
const allocator = std.heap.wasm_allocator;

pub extern fn print_wasm(ptr: [*]const u8, len: usize) void;

pub export fn alloc(size: usize) ?[*]u8 {
    return if (allocator.alloc(u8, size)) |slice|
        slice.ptr
    else |_|
        null;
}

pub export fn free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

pub export fn tick() void {}
