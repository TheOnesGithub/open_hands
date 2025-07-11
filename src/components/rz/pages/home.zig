const shared = @import("../../../shared.zig");
const BaseComponent = @import("../../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;

pub const Component = struct {
    const Self = @This();
    username: []const u8,
    display_name: []const u8,

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const file_content = @embedFile("home.html");
        const parts = comptime shared.splitOnMarkers(file_content);

        writer.write_to_body(parts[0]) catch {
            return error.ComponentError;
        };

        writer.write_to_body(self.username) catch {
            return error.ComponentError;
        };

        writer.write_to_body(parts[1]) catch {
            return error.ComponentError;
        };

        writer.write_to_body(self.display_name) catch {
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
