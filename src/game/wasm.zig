const std = @import("std");
const ecs = @import("ecs/core.zig");
const components = @import("ecs/components.zig");
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

const vertices: []const f32 = &.{ // x,    y,   z,    u,   v
    -0.5, -0.5, 0.0, 0.0, 1.0,
    0.5,  -0.5, 0.0, 1.0, 1.0,
    0.5,  0.5,  0.0, 1.0, 0.0,

    -0.5, -0.5, 0.0, 0.0, 1.0,
    0.5,  0.5,  0.0, 1.0, 0.0,
    -0.5, 0.5,  0.0, 0.0, 0.0,
};

pub export fn get_vertex_data() [*]const f32 {
    return vertices.ptr;
}

pub export fn get_vertex_data_len() usize {
    return vertices.len;
}

pub export fn init() void {
    // const str = "hello from wasm\r\n";
    // print_wasm(str.ptr, str.len);
    // const world_manager = ecs.WorldManagerType(.{
    //     .world_capacity = 1,
    // }){};
    //
    // const world = world_manager.worlds[0];
    // var entity_manager = world.entity_manager;
    // var component_manager = world.component_manager;
    //
    // const entity = entity_manager.createEntity();
    // const transform_id = component_manager.registerComponent("Transform", components.Transform);
    // entity_manager.addComponent(entity, transform_id);
}
