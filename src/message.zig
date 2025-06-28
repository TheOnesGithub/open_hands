const std = @import("std");
const assert = std.debug.assert;
const stdx = @import("stdx.zig");
const Command = @import("command.zig").Command;
const Header = @import("message_header.zig");
const constants = @import("constants.zig");

pub const Message = extern struct {
    pub const Reserved = CommandMessageType(.reserved);
    pub const PingClient = CommandMessageType(.ping_client);
    pub const PongClient = CommandMessageType(.pong_client);
    pub const Request = CommandMessageType(.request);
    pub const Reply = CommandMessageType(.reply);
    pub const Headers = CommandMessageType(.headers);
    pub const Eviction = CommandMessageType(.eviction);

    // TODO Avoid the extra level of indirection.
    // (https://github.com/tigerbeetle/tigerbeetle/pull/1295#discussion_r1394265250)
    header: *Header,
    buffer: *align(constants.sector_size) [constants.message_size_max]u8,
    references: u32 = 0,

    pub fn body_used(message: *const Message) []align(@sizeOf(Header)) u8 {
        return message.buffer[@sizeOf(Header)..message.header.size];
    }

    /// NOTE: Does *not* alter the reference count.
    pub fn into(
        message: *Message,
        comptime command: Command,
    ) ?*CommandMessageType(command) {
        if (message.header.command != command) return null;
        return @ptrCast(message);
    }

    pub const AnyMessage = stdx.EnumUnionType(Command, MessagePointerType);

    fn MessagePointerType(comptime command: Command) type {
        return *CommandMessageType(command);
    }

    /// NOTE: Does *not* alter the reference count.
    pub fn into_any(message: *Message) AnyMessage {
        switch (message.header.command) {
            inline else => |command| {
                return @unionInit(AnyMessage, @tagName(command), message.into(command).?);
            },
        }
    }
};

fn CommandMessageType(comptime command: Command) type {
    const CommandHeaderUnified = Header.Type(command);

    return extern struct {
        const CommandMessage = @This();
        const CommandHeader = CommandHeaderUnified;

        // The underlying structure of Message and CommandMessage should be identical, so that their
        // memory can be cast back-and-forth.
        comptime {
            assert(@sizeOf(Message) == @sizeOf(CommandMessage));

            for (
                std.meta.fields(Message),
                std.meta.fields(CommandMessage),
            ) |message_field, command_message_field| {
                assert(std.mem.eql(u8, message_field.name, command_message_field.name));
                assert(@sizeOf(message_field.type) == @sizeOf(command_message_field.type));
                assert(@offsetOf(Message, message_field.name) ==
                    @offsetOf(CommandMessage, command_message_field.name));
            }
        }

        /// Points into `buffer`.
        header: *CommandHeader,
        buffer: *align(constants.sector_size) [constants.message_size_max]u8,
        references: u32,

        pub fn base(message: *CommandMessage) *Message {
            return @ptrCast(message);
        }

        pub fn base_const(message: *const CommandMessage) *const Message {
            return @ptrCast(message);
        }

        pub fn ref(message: *CommandMessage) *CommandMessage {
            return @ptrCast(message.base().ref());
        }

        pub fn body_used(message: *const CommandMessage) []align(@sizeOf(Header)) u8 {
            return message.base_const().body_used();
        }
    };
}
