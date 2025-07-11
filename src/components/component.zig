const shared = @import("../shared.zig");

pub const component_error = error{
    ComponentError,
};

pub const ComponentVTable = struct {
    ptr: *anyopaque,
    render_fn: *const fn (self: *anyopaque, writer: *shared.BufferWriter) component_error!void,

    pub fn render(self: *ComponentVTable, writer: *shared.BufferWriter) component_error!void {
        return self.render_fn(self.ptr, writer);
    }
};
