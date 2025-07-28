const shared = @import("../../shared.zig");
const BaseComponent = @import("../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;

pub const Component = struct {
    const Self = @This();
    content: *ComponentVTable,

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const file_content = @embedFile("tag.html");
        const parts = comptime shared.splitOnMarkers(file_content);

        writer.write_to_body(parts[0]) catch {
            return error.ComponentError;
        };

        try self.content.render(writer);

        writer.write_to_body(parts[1]) catch {
            return error.ComponentError;
        };
    }

    pub fn get_compenent(self: *Self) ComponentVTable {
        return .{
            .ptr = self,
            .render_fn = Self.render,
        };
    }
};
