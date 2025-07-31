const shared = @import("../../../shared.zig");
const BaseComponent = @import("../../component.zig");
const component_error = BaseComponent.component_error;
const ComponentVTable = BaseComponent.ComponentVTable;
const timer = @import("../../tag/timer.zig");
const string_component = @import("../../string.zig");
const tag_component = @import("../../tag/tag.zig");

pub const Component = struct {
    const Self = @This();
    username: []const u8,
    display_name: []const u8,
    // timers: []*@import("../../../systems/gateway/gateway.zig").Timer,
    // timers: []*ComponentVTable,
    // active_tags: []*ComponentVTable,
    // saved_timers: []*ComponentVTable,

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

        writer.write_to_body(parts[2]) catch {
            return error.ComponentError;
        };

        var string_c = string_component.Component{
            .content = "this is a string",
        };
        var string_ptr = string_c.get_compenent();

        var timer_c = timer.Component{ .content = &string_ptr };
        var timer_ptr = timer_c.get_compenent();
        timer_ptr.render(writer) catch {
            return error.ComponentError;
        };

        var tag_string_c = string_component.Component{
            .content = "tag",
        };
        var tag_string_ptr = tag_string_c.get_compenent();
        var tag_c = tag_component.Component{ .content = &tag_string_ptr };
        var tag_ptr = tag_c.get_compenent();
        tag_ptr.render(writer) catch {
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
