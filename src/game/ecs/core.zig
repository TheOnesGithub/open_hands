// // the core of the ECS
// // entity
// // component
// // system
// // world
// // archetype
// // query
// // entity manager
// // component manager
// // system manager
//
// const std = @import("std");
//
// pub const World = struct {
//     var entity_manager: EntityManager = undefined;
//     var component_manager: ComponentManager = undefined;
//     var archetype_manager: ArchetypeManager = undefined;
// };
//
// pub const WorldManagerOptions = struct {
//     var world_capacity: u32 = undefined;
// };
//
// pub fn WorldManagerType(
//     comptime Options: WorldManagerOptions,
// ) type {
//     return struct {
//         var worlds: [Options.world_capacity]World = undefined;
//     };
// }
//
// pub const Entity = struct {
//     var index: u32 = undefined;
//     var generation: u32 = undefined;
// };
//
// pub const EntityManager = struct {
//     var entity_capacity: u32 = undefined;
//     var structure_generation: u32 = undefined;
//
//     pub fn createEntity() Entity {
//         const entity = Entity{
//             .index = entity_capacity,
//             .generation = structure_generation,
//         };
//         entity_capacity += 1;
//         structure_generation += 1;
//         return entity;
//     }
//
//     pub fn addComponent(entity: Entity, component_id: u32) void {}
// };
//
// pub const ComponentManager = struct {
//     var next_component_id: u32 = undefined;
//     // var component_capacity: u32 = undefined;
//     // var structure_generation: u32 = undefined;
//
//     // var map_component_id_to_name: std.StringArrayHashMap(u32) = undefined;
//     // var map_component_name_to_id: std.StringArrayHashMap(u32) = undefined;
//     // var map_component_id_to_type: std.StringArrayHashMap(u32) = undefined;
//
//     pub fn registerComponent(name: []const u8, comptime T: type) u32 {
//         // _ = name;
//         _ = T;
//         std.debug.print("register component {s}\r\n", .{name});
//         // map_component_id_to_type.put(next_component_id, T) catch undefined;
//         // map_component_id_to_name.put(next_component_id, name) catch undefined;
//         // map_component_name_to_id.put(name, next_component_id) catch undefined;
//         next_component_id += 1;
//         // structure_generation += 1;
//
//         return next_component_id - 1;
//     }
// };
//
// // can they be made at runtime or only compile time?
// // (defunition of the entity)
// pub const EntityArchetype = struct {
//     const id: u32 = undefined;
//     const size: u32 = undefined;
//     // map the component id to the offset
//     var map_components_offset: std.AutoHashMap(u32, u32) = undefined;
// };
//
// pub const ArchetypeManager = struct {
//     var archetype_capacity: u32 = undefined;
//     var structure_generation: u32 = undefined;
//     var map_archetype_uid_to_id: std.StringArrayHashMap(u32) = undefined;
//     var archetype_storage: std.map.AutoArrayHashMap(u32, ArchetypeStorage) = undefined;
// };
//
// pub const ArchetypeStorage = struct {
//     var archetype_capacity: u32 = undefined;
//     // get pages of memory
// };
