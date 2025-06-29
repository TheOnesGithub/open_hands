const std = @import("std");
pub const StateMachineZig = @import("state_machine.zig");
pub const ReplicaZig = @import("replica.zig");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const message_header = @import("message_header.zig");

const global_constants = @import("constants.zig");
const Operations = @import("operations.zig");

pub const StateMachine =
    StateMachineZig.StateMachineType(global_constants.state_machine_config);
pub const Replica = ReplicaZig.ReplicaType(StateMachine);

const App = struct {
    pub const WebsocketHandler = Client;
    replica: Replica = undefined,
};

pub fn main() !void {
    try start();
}

pub fn replica_start(replica: *Replica) void {
    // var replica: Replica = undefined;
    // try replica.init(.{});
    while (true) {
        replica.tick();
    }
}

pub fn start() !void {
    // var replica: Replica = undefined;
    // try replica.init(.{});

    var app = App{};
    try app.replica.init(.{});
    _ = std.Thread.spawn(.{}, replica_start, .{&app.replica}) catch |err| {
        return err;
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator_check = gpa.allocator();

    var server = httpz.Server(*App).init(allocator_check, .{
        .port = 8801,
        .address = "0.0.0.0",
    }, &app) catch {
        return;
    };
    defer {
        // clean shutdown, finishes serving any live request
        server.stop();
        server.deinit();
    }

    var router = server.router(.{}) catch {
        return;
    };

    router.get("/", index, .{});
    router.get("/ws", ws, .{});

    server.listen() catch {
        return;
    };
}

fn index(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    // _ = app;
    _ = req;
    std.debug.print("index \r\n", .{});
    if (app.replica.resurveAvailableFiber()) |fiber_index| {
        const temp = &app.replica.messages[fiber_index][0];
        std.debug.print("size: {}\r\n", .{@sizeOf(message_header.Header.Request)});
        std.debug.print("addr: {*}\r\n", .{temp});
        const t2: *message_header.Header.Request = @ptrCast(temp);
        t2.* = message_header.Header.Request{
            .request = 0,
            .command = .request,
            .client = 0,
            .operation = .print,
            .cluster = 0,
            .release = 0,
        };
        // const header_size = @sizeOf(message_header.Header.Request);
        // const Event = Operations.EventType(.print);
        // var ptr_as_int = @intFromPtr(temp);
        // ptr_as_int = ptr_as_int + header_size;
        // const operation_struct: *Event = @ptrFromInt(ptr_as_int);
        // operation_struct.a = 1;
        // operation_struct.b = 2;

        app.replica.message_statuses[fiber_index] = .Ready;
        try app.replica.push(fiber_index);
        std.debug.print("ran push \r\n", .{});
    }
    res.status = 200;
    const file_content = @embedFile("index.html");
    res.body = file_content;
}

fn ws(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    _ = app;
    // Could do authentication or anything else before upgrading the connection
    // The context is any arbitrary data you want to pass to Client.init.
    const ctx = Client.Context{ .user_id = 9001 };

    // The first parameter, Client, ***MUST*** be the same as Handler.WebSocketHandler
    // I'm sorry about the awkwardness of that.
    // It's undefined behavior if they don't match, and it _will_ behave weirdly/crash.
    if (try httpz.upgradeWebsocket(Client, req, res, &ctx) == false) {
        res.status = 500;
        res.body = "invalid websocket";
    }
    // unsafe to use req or res at this point!
}

const Client = struct {
    user_id: u32,
    conn: *websocket.Conn,

    const Context = struct {
        user_id: u32,
    };

    // context is any abitrary data that you want, you'll pass it to upgradeWebsocket
    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        std.debug.print("init\r\n", .{});
        return .{
            .conn = conn,
            .user_id = ctx.user_id,
        };
    }

    // at this point, it's safe to write to conn
    pub fn afterInit(self: *Client) !void {
        std.debug.print("afetrInit\r\n", .{});
        return self.conn.write("welcome!");
    }

    pub fn clientMessage(self: *Client, data: []const u8) !void {
        std.debug.print("got message from client: {any}\r\n", .{data});

        return self.conn.write("clientMessage return");
    }
};
