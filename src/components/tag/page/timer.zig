const shared = @import("../../../shared.zig");
const BaseComponent = @import("../../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;
const Timer = @import("../timer.zig").Component;
const Tag = @import("../tag.zig").Component;

pub const Component = struct {
    const Self = @This();
    timers: []*ComponentVTable,
    active_tags: []*ComponentVTable,
    saved_timers: []*ComponentVTable,

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const file_content = @embedFile("timer.html");
        const parts = comptime shared.splitOnMarkers(file_content);

        writer.write_to_body(parts[0]) catch {
            return error.ComponentError;
        };

        for (self.timers) |timer| {
            // try Timer.render(timer, writer);
            try timer.render(writer);
        }

        writer.write_to_body(parts[1]) catch {
            return error.ComponentError;
        };

        for (self.active_tags) |timer| {
            // try Tag.render(timer, writer);
            try timer.render(writer);
        }

        writer.write_to_body(parts[2]) catch {
            return error.ComponentError;
        };

        for (self.saved_timers) |timer| {
            // try Timer.render(timer, writer);
            try timer.render(writer);
        }

        writer.write_to_body(parts[3]) catch {
            return error.ComponentError;
        };
    }

    pub fn get_compenent(self: *Self) ComponentVTable {
        return .{
            .ptr = self,
            .render_fn = Self.render,
        };
    }

    // pub fn click(self: *Button) void {
    // }
};
