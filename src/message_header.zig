const std = @import("std");
const assert = std.debug.assert;
const maybe = stdx.maybe;

const constants = @import("constants.zig");
const stdx = @import("stdx.zig");
// const vsr = @import("../vsr.zig");
const Command = @import("command.zig").Command;
const Operation = @import("operations.zig").Operation;
// const schema = @import("../lsm/schema.zig");

const uuid = @import("uuid.zig");

pub const checksum = @import("checksum.zig").checksum;
const checksum_body_empty = checksum(&.{});

const Release = u32;
pub const Version: u16 = 0;

pub const RegisterRequest = extern struct {
    /// When command=request, batch_size_limit = 0.
    /// When command=prepare, batch_size_limit > 0 and batch_size_limit ≤ message_body_size_max.
    /// (Note that this does *not* include the `@sizeOf(Header)`.)
    batch_size_limit: u32,
    reserved: [252]u8 = [_]u8{0} ** 252,

    comptime {
        assert(@sizeOf(RegisterRequest) == 256);
        assert(@sizeOf(RegisterRequest) <= constants.message_body_size_max);
        assert(stdx.no_padding(RegisterRequest));
    }
};

pub const UpgradeRequest = extern struct {
    release: Release,
    reserved: [12]u8 = [_]u8{0} ** 12,

    comptime {
        assert(@sizeOf(UpgradeRequest) == 16);
        assert(@sizeOf(UpgradeRequest) <= constants.message_body_size_max);
        assert(stdx.no_padding(UpgradeRequest));
    }
};

/// Network message, prepare, and grid block header:
/// We reuse the same header for both so that prepare messages from the primary can simply be
/// journalled as is by the backups without requiring any further modification.
pub const Header = extern struct {
    /// A checksum covering only the remainder of this header.
    /// This allows the header to be trusted without having to recv() or read() the associated body.
    /// This checksum is enough to uniquely identify a network message or prepare.
    checksum: u128,

    // TODO(zig): When Zig supports u256 in extern-structs, merge this into `checksum`.
    checksum_padding: u128,

    /// A checksum covering only the associated body after this header.
    checksum_body: u128,

    // TODO(zig): When Zig supports u256 in extern-structs, merge this into `checksum_body`.
    checksum_body_padding: u128,

    /// Reserved for future use by AEAD.
    nonce_reserved: u128,

    /// The cluster number binds intention into the header, so that a client or replica can indicate
    /// the cluster it believes it is speaking to, instead of accidentally talking to the wrong
    /// cluster (for example, staging vs production).
    cluster: u128,

    /// The size of the Header structure (always), plus any associated body.
    size: u32,

    /// The cluster reconfiguration epoch number (for future use).
    epoch: u32,

    /// Every message sent from one replica to another contains the sending replica's current view.
    /// A `u32` allows for a minimum lifetime of 136 years at a rate of one view change per second.
    view: u32,

    /// The release version set by the state machine.
    /// (This field is not set for all message types.)
    release: Release,

    /// The version of the protocol implementation that originated this message.
    protocol: u16,

    /// The Viewstamped Replication protocol command for this message.
    command: Command,

    /// The index of the replica in the cluster configuration array that authored this message.
    /// This identifies only the ultimate author because messages may be forwarded amongst replicas.
    replica: u8,

    /// Reserved for future use by the header frame (i.e. to be shared by all message types).
    reserved_frame: [12]u8,

    /// This data's schema is different depending on the `Header.command`.
    /// (No default value – `Header`s should not be constructed directly.)
    reserved_command: [128]u8,

    comptime {
        assert(@sizeOf(Header) == 256);
        assert(stdx.no_padding(Header));
        assert(@offsetOf(Header, "reserved_command") % @sizeOf(u256) == 0);
    }

    pub fn Type(comptime command: Command) type {
        return switch (command) {
            .reserved => Reserved,
            .ping_client => PingClient,
            .pong_client => PongClient,
            .request => Request,
            .reply => Reply,
            .headers => Headers,
            .eviction => Eviction,
            // .future_deprected_thing => Deprecated,
        };
    }

    pub fn calculate_checksum(self: *const Header) u128 {
        const checksum_size = @sizeOf(@TypeOf(self.checksum));
        assert(checksum_size == 16);
        const checksum_value = checksum(std.mem.asBytes(self)[checksum_size..]);
        assert(@TypeOf(checksum_value) == @TypeOf(self.checksum));
        return checksum_value;
    }

    pub fn calculate_checksum_body(self: *const Header, body: []const u8) u128 {
        assert(self.size == @sizeOf(Header) + body.len);
        const checksum_size = @sizeOf(@TypeOf(self.checksum_body));
        assert(checksum_size == 16);
        const checksum_value = checksum(body);
        assert(@TypeOf(checksum_value) == @TypeOf(self.checksum_body));
        return checksum_value;
    }

    /// This must be called only after set_checksum_body() so that checksum_body is also covered:
    pub fn set_checksum(self: *Header) void {
        self.checksum = self.calculate_checksum();
    }

    pub fn set_checksum_body(self: *Header, body: []const u8) void {
        self.checksum_body = self.calculate_checksum_body(body);
    }

    pub fn valid_checksum(self: *const Header) bool {
        return self.checksum == self.calculate_checksum();
    }

    pub fn valid_checksum_body(self: *const Header, body: []const u8) bool {
        return self.checksum_body == self.calculate_checksum_body(body);
    }

    pub const AnyHeaderPointer = stdx.EnumUnionType(Command, struct {
        fn PointerForCommandType(comptime variant: Command) type {
            return *const Type(variant);
        }
    }.PointerForCommandType);

    pub fn into_any(self: *const Header) AnyHeaderPointer {
        switch (self.command) {
            inline else => |command| {
                return @unionInit(AnyHeaderPointer, @tagName(command), self.into_const(command).?);
            },
        }
    }

    pub fn into(self: *Header, comptime command: Command) ?*Type(command) {
        if (self.command != command) return null;
        return std.mem.bytesAsValue(Type(command), std.mem.asBytes(self));
    }

    pub fn into_const(self: *const Header, comptime command: Command) ?*const Type(command) {
        if (self.command != command) return null;
        return std.mem.bytesAsValue(Type(command), std.mem.asBytes(self));
    }

    /// Returns null if all fields are set correctly according to the command, or else a warning.
    /// This does not verify that checksum is valid, and expects that this has already been done.
    pub fn invalid(self: *const Header) ?[]const u8 {
        if (self.checksum_padding != 0) return "checksum_padding != 0";
        if (self.checksum_body_padding != 0) return "checksum_body_padding != 0";
        if (self.nonce_reserved != 0) return "nonce_reserved != 0";
        if (self.size < @sizeOf(Header)) return "size < @sizeOf(Header)";
        if (self.size > constants.message_size_max) return "size > message_size_max";
        if (self.epoch != 0) return "epoch != 0";
        if (!stdx.zeroed(&self.reserved_frame)) return "reserved_frame != 0";

        // if (self.command == .block) {
        //     if (self.protocol > vsr.Version) return "block: protocol > Version";
        // } else {
        //     if (self.protocol != vsr.Version) return "protocol != Version";
        // }

        switch (self.into_any()) {
            inline else => |command_header| return command_header.invalid_header(),
            // The `Command` enum is exhaustive, so we can't write an "else" branch here. An unknown
            // command is a possibility, but that means that someone has send us a message with
            // matching cluster, matching version, correct checksum, and a command we don't know
            // about. Ignoring unknown commands might be unsafe, so the replica intentionally
            // crashes here, which is guaranteed by Zig's ReleaseSafe semantics.
            //
            // _ => unreachable
        }
    }

    /// Returns whether the immediate sender is a replica or client (if this can be determined).
    /// Some commands such as .request or .prepare may be forwarded on to other replicas so that
    /// Header.replica or Header.client only identifies the ultimate origin, not the latest peer.
    // pub fn peer_type(self: *const Header) vsr.Peer {
    //     switch (self.into_any()) {
    //         .reserved => unreachable,
    //         // TODO: replicas used to forward requests. They no longer do, and can always return
    //         // request.client starting with the next release.
    //         .request => |request| {
    //             switch (request.operation) {
    //                 // However, we do not forward the first .register request sent by a client:
    //                 .register => return .{ .client = request.client },
    //                 else => return .unknown,
    //             }
    //         },
    //         .reply => return .unknown,
    //         .future_deprected_thing => return .unknown,
    //         // These messages identify the peer as either a replica or a client:
    //         .ping_client => |ping| return .{ .client = ping.client },
    //         // All other messages identify the peer as a replica:
    //         .pong_client,
    //         .headers,
    //         .eviction,
    //         => return .{ .replica = self.replica },
    //     }
    // }

    pub fn format(
        self: *const Header,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.into_any()) {
            inline else => |header| return try std.fmt.formatType(
                header,
                fmt,
                options,
                writer,
                std.options.fmt_max_depth,
            ),
        }
    }

    fn HeaderFunctionsType(comptime CommandHeader: type) type {
        return struct {
            pub fn frame(header: *CommandHeader) *Header {
                return std.mem.bytesAsValue(Header, std.mem.asBytes(header));
            }

            pub fn frame_const(header: *const CommandHeader) *const Header {
                return std.mem.bytesAsValue(Header, std.mem.asBytes(header));
            }

            pub fn invalid(self: *const CommandHeader) ?[]const u8 {
                return self.frame_const().invalid();
            }

            pub fn calculate_checksum(self: *const CommandHeader) u128 {
                return self.frame_const().calculate_checksum();
            }

            pub fn calculate_checksum_body(self: *const CommandHeader, body: []const u8) u128 {
                return self.frame_const().calculate_checksum_body(body);
            }

            pub fn set_checksum(self: *CommandHeader) void {
                self.frame().set_checksum();
            }

            pub fn set_checksum_body(self: *CommandHeader, body: []const u8) void {
                self.frame().set_checksum_body(body);
            }

            pub fn valid_checksum(self: *const CommandHeader) bool {
                return self.frame_const().valid_checksum();
            }

            pub fn valid_checksum_body(self: *const CommandHeader, body: []const u8) bool {
                return self.frame_const().valid_checksum_body(body);
            }
        };
    }

    /// This type isn't ever actually a constructed, but makes Type() simpler by providing a header
    /// type for each command.
    pub const Reserved = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128,
        checksum_padding: u128 = 0,
        checksum_body: u128,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128,
        cluster: u128,
        size: u32,
        epoch: u32 = 0,
        view: u32 = 0,
        release: Release = 0, // vsr.Release.zero, // Always 0.
        protocol: u16 = Version,
        command: Command,
        replica: u8 = 0,
        reserved_frame: [12]u8,

        reserved: [128]u8 = [_]u8{0} ** 128,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .reserved);
            return "reserved is invalid";
        }
    };

    /// This type isn't ever actually a constructed, but makes Type() simpler by providing a header
    /// type for each command.
    pub const Deprecated = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128,
        checksum_padding: u128 = 0,
        checksum_body: u128,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128,
        cluster: u128,
        size: u32,
        epoch: u32 = 0,
        view: u32 = 0,
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8 = 0,
        reserved_frame: [12]u8,

        reserved: [128]u8 = [_]u8{0} ** 128,

        fn invalid_header(_: *const @This()) ?[]const u8 {
            return "deprecated message type";
        }
    };

    pub const PingClient = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32 = 0, // Always 0.
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8 = 0, // Always 0.
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        client: u128,
        ping_timestamp_monotonic: u64,
        reserved: [104]u8 = [_]u8{0} ** 104,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .ping_client);
            if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
            if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
            if (self.release.value == 0) return "release == 0";
            if (self.replica != 0) return "replica != 0";
            if (self.view != 0) return "view != 0";
            if (self.client == 0) return "client == 0";
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";
            return null;
        }
    };

    pub const PongClient = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32,
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8,
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        ping_timestamp_monotonic: u64,
        reserved: [120]u8 = [_]u8{0} ** 120,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .pong_client);
            if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
            if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
            if (self.release.value == 0) return "release == 0";
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";
            return null;
        }
    };

    pub const Request = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32 = 0,
        /// The client's release version.
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8 = 0, // Always 0.
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        /// Clients hash-chain their requests to verify linearizability:
        /// - A session's first request (operation=register) sets `parent=0`.
        /// - A session's subsequent requests (operation≠register) set `parent` to the checksum of
        ///   the preceding reply.
        parent: u128 = 0,
        parent_padding: u128 = 0,
        /// Each client process generates a unique, random and ephemeral client ID at
        /// initialization. The client ID identifies connections made by the client to the cluster
        /// for the sake of routing messages back to the client.
        ///
        /// With the client ID in hand, the client then registers a monotonically increasing session
        /// number (committed through the cluster) to allow the client's session to be evicted
        /// safely from the client table if too many concurrent clients cause the client table to
        /// overflow. The monotonically increasing session number prevents duplicate client requests
        /// from being replayed.
        ///
        /// The problem of routing is therefore solved by the 128-bit client ID, and the problem of
        /// detecting whether a session has been evicted is solved by the session number.
        client: u128,
        /// When operation=register, this is zero.
        /// When operation≠register, this is the commit number of register.
        session: u64 = 0,
        /// Only nonzero during AOF recovery.
        /// TODO: Use this for bulk-import to state machine?
        timestamp: u64 = 0,
        /// Each request is given a number by the client and later requests must have larger numbers
        /// than earlier ones. The request number is used by the replicas to avoid running requests
        /// more than once; it is also used by the client to discard duplicate replies to its
        /// requests.
        ///
        /// A client is allowed to have at most one request inflight at a time.
        request: u32,
        operation: Operation,
        message_id: uuid.UUID,
        reserved: [43]u8 = [_]u8{0} ** 43,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .request);
            if (self.release.value == 0) return "release == 0";
            if (self.parent_padding != 0) return "parent_padding != 0";
            if (self.timestamp != 0 and !constants.aof_recovery) return "timestamp != 0";
            switch (self.operation) {
                // .reserved => return "operation == .reserved",
                // .root => return "operation == .root",
                // .register => {
                //     // The first request a client makes must be to register with the cluster:
                //     if (self.replica != 0) return "register: replica != 0";
                //     if (self.client == 0) return "register: client == 0";
                //     if (self.parent != 0) return "register: parent != 0";
                //     if (self.session != 0) return "register: session != 0";
                //     if (self.request != 0) return "register: request != 0";
                //     // Support `register` requests without the body to correctly
                //     // reply with `client_release_too_low` for clients <= v0.15.3.
                //     if (self.size != @sizeOf(Header) and self.size != @sizeOf(Header) + @sizeOf(RegisterRequest)) {
                //         return "register: size != @sizeOf(Header) [+ @sizeOf(RegisterRequest)]";
                //     }
                // },
                .pulse => {
                    // These requests don't originate from a real client or session.
                    if (self.client != 0) return "pulse: client != 0";
                    if (self.parent != 0) return "pulse: parent != 0";
                    if (self.session != 0) return "pulse: session != 0";
                    if (self.request != 0) return "pulse: request != 0";
                    if (self.size != @sizeOf(Header)) return "pulse: size != @sizeOf(Header)";
                },
                // .upgrade => {
                //     // These requests don't originate from a real client or session.
                //     if (self.client != 0) return "upgrade: client != 0";
                //     if (self.parent != 0) return "upgrade: parent != 0";
                //     if (self.session != 0) return "upgrade: session != 0";
                //     if (self.request != 0) return "upgrade: request != 0";
                //
                //     if (self.size != @sizeOf(Header) + @sizeOf(UpgradeRequest)) {
                //         return "upgrade: size != @sizeOf(Header) + @sizeOf(UpgradeRequest)";
                //     }
                // },
                else => {
                    // if (self.operation == .reconfigure) {
                    //     if (self.size != @sizeOf(Header) + @sizeOf(vsr.ReconfigurationRequest)) {
                    //         return "size != @sizeOf(Header) + @sizeOf(ReconfigurationRequest)";
                    //     }
                    // } else if (self.operation == .noop) {
                    //     if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
                    // } else if (@intFromEnum(self.operation) < constants.vsr_operations_reserved) {
                    //     return "operation is reserved";
                    // }
                    if (self.replica != 0) return "replica != 0";
                    if (self.client == 0) return "client == 0";
                    // Thereafter, the client must provide the session number:
                    // These requests should set `parent` to the `checksum` of the previous reply.
                    if (self.session == 0) return "session == 0";
                    if (self.request == 0) return "request == 0";
                    // The Replica is responsible for checking the `Operation` is a valid variant –
                    // the check requires the StateMachine type.
                },
            }
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";
            return null;
        }
    };

    pub const Reply = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32,
        /// The corresponding Request's (and Prepare's, and client's) release version.
        /// `Reply.release` matches `Request.release` (rather than the cluster release):
        /// - to serve as an escape hatch if state machines ever need to branch on client release.
        /// - to emphasize that the reply's format must be compatible with the client's version –
        ///   which is potentially behind the cluster's version when the prepare commits.
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8,
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        /// The checksum of the corresponding Request.
        request_checksum: u128,
        request_checksum_padding: u128 = 0,
        /// The checksum to be included with the next request as parent checksum.
        /// It's almost exactly the same as entire header's checksum, except that it is computed
        /// with a fixed view and remains stable if reply is retransmitted in a newer view.
        /// This allows for strong guarantees beyond request, op, and commit numbers, which
        /// have low entropy and may otherwise collide in the event of any correctness bugs.
        context: u128 = 0,
        context_padding: u128 = 0,
        client: u128,
        op: u64,
        commit: u64,
        /// The corresponding `prepare`'s timestamp.
        /// This allows the test workload to verify transfer timeouts.
        timestamp: u64,
        request: u32,
        // operation: Operation = .reserved,
        // TODO: change op
        operation: Operation = .print,
        message_id: uuid.UUID,
        reserved: [3]u8 = [_]u8{0} ** 3,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .reply);
            if (self.release.value == 0) return "release == 0";
            // Initialization within `client.zig` asserts that client `id` is greater than zero:
            if (self.client == 0) return "client == 0";
            if (self.request_checksum_padding != 0) return "request_checksum_padding != 0";
            if (self.context_padding != 0) return "context_padding != 0";
            if (self.op != self.commit) return "op != commit";
            if (self.timestamp == 0) return "timestamp == 0";
            // if (self.operation == .register) {
            //     if (self.size != @sizeOf(Header) + @sizeOf(vsr.RegisterResult)) {
            //         return "register: size != @sizeOf(Header) + @sizeOf(vsr.RegisterResult)";
            //     }
            //     // In this context, the commit number is the newly registered session number.
            //     // The `0` commit number is reserved for cluster initialization.
            //     if (self.commit == 0) return "commit == 0";
            //     if (self.request != 0) return "request != 0";
            // } else {
            if (self.commit == 0) return "commit == 0";
            if (self.request == 0) return "request == 0";
            // }
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";
            return null;
        }
    };

    pub const Headers = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32,
        release: Release = 0, // vsr.Release.zero, // Always 0.
        protocol: u16 = Version,
        command: Command,
        replica: u8,
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        reserved: [128]u8 = [_]u8{0} ** 128,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .headers);
            if (self.size == @sizeOf(Header)) return "size == @sizeOf(Header)";
            if (self.release.value != 0) return "release != 0";
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";
            return null;
        }
    };

    pub const Eviction = extern struct {
        pub usingnamespace HeaderFunctionsType(@This());

        checksum: u128 = 0,
        checksum_padding: u128 = 0,
        checksum_body: u128 = 0,
        checksum_body_padding: u128 = 0,
        nonce_reserved: u128 = 0,
        cluster: u128,
        size: u32 = @sizeOf(Header),
        epoch: u32 = 0,
        view: u32,
        release: Release,
        protocol: u16 = Version,
        command: Command,
        replica: u8,
        reserved_frame: [12]u8 = [_]u8{0} ** 12,

        client: u128,
        reserved: [111]u8 = [_]u8{0} ** 111,
        reason: Reason,

        fn invalid_header(self: *const @This()) ?[]const u8 {
            assert(self.command == .eviction);
            if (self.size != @sizeOf(Header)) return "size != @sizeOf(Header)";
            if (self.checksum_body != checksum_body_empty) return "checksum_body != expected";
            if (self.release.value == 0) return "release == 0";
            if (self.client == 0) return "client == 0";
            if (!stdx.zeroed(&self.reserved)) return "reserved != 0";

            const reasons = comptime std.enums.values(Reason);
            inline for (reasons) |reason| {
                if (@intFromEnum(self.reason) == @intFromEnum(reason)) break;
            } else return "reason invalid";
            if (self.reason == .reserved) return "reason == reserved";
            return null;
        }

        pub const Reason = enum(u8) {
            reserved = 0,
            no_session = 1,
            client_release_too_low = 2,
            client_release_too_high = 3,
            invalid_request_operation = 4,
            invalid_request_body = 5,
            invalid_request_body_size = 6,
            session_too_low = 7,
            session_release_mismatch = 8,

            comptime {
                for (std.enums.values(Reason), 0..) |reason, index| {
                    assert(@intFromEnum(reason) == index);
                }
            }
        };
    };
};

// Verify each Command's header type.
comptime {
    @setEvalBranchQuota(20_000);

    for (std.enums.values(Command)) |command| {
        const CommandHeader = Header.Type(command);
        assert(@sizeOf(CommandHeader) == @sizeOf(Header));
        assert(@alignOf(CommandHeader) == @alignOf(Header));
        assert(@typeInfo(CommandHeader) == .@"struct");
        assert(@typeInfo(CommandHeader).@"struct".layout == .@"extern");
        assert(stdx.no_padding(CommandHeader));

        // Verify that the command's header's frame is identical to Header's.
        for (std.meta.fields(Header)) |header_field| {
            if (std.mem.eql(u8, header_field.name, "reserved_command")) {
                assert(std.meta.fieldIndex(CommandHeader, header_field.name) == null);
            } else {
                const command_field_index = std.meta.fieldIndex(CommandHeader, header_field.name).?;
                const command_field = std.meta.fields(CommandHeader)[command_field_index];
                assert(command_field.type == header_field.type);
                assert(command_field.alignment == header_field.alignment);
                assert(@offsetOf(CommandHeader, command_field.name) ==
                    @offsetOf(Header, header_field.name));
            }
        }
    }
}
