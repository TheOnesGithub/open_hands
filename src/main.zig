const std = @import("std");
pub const ReplicaZig = @import("replica.zig");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const message_header = @import("message_header.zig");

const global_constants = @import("constants.zig");
const Operations = @import("operations.zig");
const uuid = @import("uuid.zig");
const gateway = @import("gateway/gateway.zig");

pub const Replica = ReplicaZig.ReplicaType(gateway.system);

const AutoHashMap = std.AutoHashMap;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

var message_id_buffer: [global_constants.message_wait_on_map_buffer_size]u8 = undefined;
var message_id_map: AutoHashMap(uuid.UUID, Message_Request_Value) = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;

pub const Message_Request_Value = struct {
    client_message_id: uuid.UUID,
    conn: *httpz.websocket.Conn,
    only_return_body: bool,
};

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

    fba = FixedBufferAllocator.init(&message_id_buffer);
    const fixed_buffer_allocator = fba.allocator();
    message_id_map = AutoHashMap(uuid.UUID, Message_Request_Value).init(fixed_buffer_allocator);

    var app = App{};
    try app.replica.init(.{
        .temp_return = &temp_return,
    });
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
    router.get("/wasm.wasm", wasm, .{});
    router.get("/ws", ws, .{});

    server.listen() catch {
        return;
    };
}

fn index(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    _ = app;
    _ = req;
    std.debug.print("index \r\n", .{});
    res.status = 200;
    const file_content = @embedFile("index.html");
    res.body = file_content;
}

fn wasm(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    _ = app;
    _ = req;

    std.debug.print("wasm\r\n", .{});
    const wasm_path = "wasm.wasm";
    const file = try std.fs.cwd().openFile(wasm_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try res.arena.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    res.status = 200;
    res.content_type = httpz.ContentType.WASM; // ✅ This sets Content-Type header properly
    res.body = buffer;

    try res.write(); // Ensure headers and body are sent
}

fn ws(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    // Could do authentication or anything else before upgrading the connection
    // The context is any arbitrary data you want to pass to Client.init.
    const ctx = Client.Context{
        .user_id = 9001,
        .app = app,
    };

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
    app: *App,

    const Context = struct {
        user_id: u32,
        app: *App,
    };

    // context is any abitrary data that you want, you'll pass it to upgradeWebsocket
    pub fn init(conn: *websocket.Conn, ctx: *const Context) !Client {
        std.debug.print("init\r\n", .{});
        return .{
            .conn = conn,
            .user_id = ctx.user_id,
            .app = ctx.app,
        };
    }

    // at this point, it's safe to write to conn
    pub fn afterInit(self: *Client) !void {
        std.debug.print("afetrInit\r\n", .{});
        return self.conn.write("welcome!");
    }

    pub fn clientMessage(self: *Client, data: []const u8) !void {
        // std.debug.print("got message from client: {any}\r\n", .{data});
        // TODO: valadate data

        if (self.app.replica.resurveAvailableFiber()) |fiber_index| {
            const temp = &self.app.replica.messages[fiber_index];

            @memcpy(temp, data);

            // TODO: change the message id to a internal id
            const recived_message: *message_header.Header.Request(gateway.system.Operation) = @ptrCast(temp);
            // save the client message id
            const internal_message_id = uuid.UUID.v4();
            message_id_map.put(internal_message_id, Message_Request_Value{
                .client_message_id = recived_message.message_id,
                .conn = self.conn,
                .only_return_body = false,
            }) catch undefined;
            recived_message.message_id = internal_message_id;

            self.app.replica.message_statuses[fiber_index] = .Ready;
            try self.app.replica.push(fiber_index);
            std.debug.print("ran push \r\n", .{});
        }
    }
};

fn temp_return(message_id: uuid.UUID, message: []align(16) u8) void {
    if (message_id_map.get(message_id)) |value| {
        if (value.only_return_body) {
            const header: *message_header.Header.Reply(gateway.system.Operation) = @ptrCast(@constCast(message));
            value.conn.writeBin(message[@sizeOf(message_header.Header.Reply(gateway.system.Operation))..header.size]) catch {
                std.debug.assert(false);
            };
        } else {
            value.conn.writeBin(message) catch {
                std.debug.assert(false);
            };
        }
    }
}
