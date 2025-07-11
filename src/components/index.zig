const shared = @import("../shared.zig");
const Component = @import("component.zig");
const component_error = Component.component_error;
const ComponentVTable = Component.ComponentVTable;

pub const Index = struct {
    const Self = @This();
    content: *ComponentVTable,

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const file_content = @embedFile("index.html");
        const parts = comptime shared.splitOnMarkers(file_content);

        writer.write_to_body(parts[0]) catch {
            return;
        };

        try self.content.render(writer);

        writer.write_to_body(parts[1]) catch {
            return;
        };
    }

    pub fn get_compenent(self: *Self) ComponentVTable {
        return .{
            .ptr = self,
            .render_fn = Self.render,
        };
    }
};
