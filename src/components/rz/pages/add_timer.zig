const shared = @import("../../../shared.zig");
const BaseComponent = @import("../../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;

pub const Component = struct {
    const Self = @This();

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        _ = ptr;
        const file_content = @embedFile("add_timer.html");
        writer.write_to_body(file_content) catch {
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
