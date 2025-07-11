const shared = @import("../../shared.zig");
const BaseComponent = @import("../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;

pub const Component = struct {
    const Self = @This();

    pub fn render(ptr: *anyopaque, writer: *shared.BufferWriter) component_error!void {
        _ = ptr;
        // const self: *Self = @ptrCast(@alignCast(ptr));
        writer.write_to_body(@embedFile("signup.html")) catch {
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
