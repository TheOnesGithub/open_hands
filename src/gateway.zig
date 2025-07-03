const std = @import("std");
pub const ReplicaZig = @import("replica.zig");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const message_header = @import("message_header.zig");

const global_constants = @import("constants.zig");
const Operations = @import("operations.zig");
const uuid = @import("uuid.zig");
const gateway = @import("systems/gateway/gateway.zig");
const AppState = @import("systems/gateway/gateway.zig").AppState;

pub const Replica = ReplicaZig.ReplicaType(
    gateway.system,
    AppState,
    &gateway.remote_services,
);

const AutoHashMap = std.AutoHashMap;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

var message_id_buffer: [global_constants.message_wait_on_map_buffer_size]u8 = undefined;
// var message_id_map: AutoHashMap(uuid.UUID, Message_Request_Value) = undefined;
var fba: std.heap.FixedBufferAllocator = undefined;
const IO = @import("io.zig");

// pub const Message_Request_Value = struct {
//     client_message_id: uuid.UUID,
//     conn: *httpz.websocket.Conn,
//     only_return_body: bool,
// };

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

var client_db: *websocket.Client = undefined;

pub fn call_kv(ptr: [*]const u8, len: usize) void {
    std.debug.print("call kv in gateway\r\n", .{});
    client_db.writeBin(@constCast(ptr[0..len])) catch undefined;
}

pub fn startKVServerClient(passed_client_db: *websocket.Client) !void {
    client_db = passed_client_db;
    var gpa_db = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator_db = gpa_db.allocator();

    // create the client
    client_db.* = try websocket.Client.init(allocator_db, .{
        .port = 9224,
        .host = "0.0.0.0",
    });
    defer client_db.deinit();

    // send the initial handshake request
    const request_path = "/ws";
    try client_db.handshake(request_path, .{
        .timeout_ms = 1000,
        // Raw headers to send, if any.
        // A lot of servers require a Host header.
        // Separate multiple headers using \r\n
        .headers = "Host: localhost:9224",
    });

    // optional, read will return null after 1 second
    try client_db.readTimeout(std.time.ms_per_s * 1);

    // echo messages back to the server until the connection is closed
    while (true) {
        // since we didn't set a timeout, client.read() will either
        // return a message or an error (i.e. it won't return null)
        const message = (try client_db.read()) orelse {
            // no message after our 1 second
            std.debug.print(".", .{});
            continue;
        };

        // must be called once you're done processing the request
        defer client_db.done(message);

        switch (message.type) {
            .text, .binary => {
                std.debug.print("received from kv: {s}\n", .{message.data});
            },
            .ping => try client_db.writePong(message.data),
            .pong => {},
            .close => {
                try client_db.close(.{});
                break;
            },
        }
    }
}

pub fn start() !void {
    var client_db_src: websocket.Client = undefined;
    client_db = &client_db_src;
    const KV_thread = try std.Thread.spawn(.{}, startKVServerClient, .{client_db});
    _ = KV_thread;

    /////////////////

    // fba = FixedBufferAllocator.init(&message_id_buffer);
    // const fixed_buffer_allocator = fba.allocator();
    // message_id_map = AutoHashMap(uuid.UUID, Message_Request_Value).init(fixed_buffer_allocator);

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
            self.app.replica.app_state_data[fiber_index] = AppState{
                .client_message_id = recived_message.message_id,
                .conn = self.conn,
                .only_return_body = false,
            };
            // message_id_map.put(internal_message_id, Message_Request_Value{
            //     .client_message_id = recived_message.message_id,
            //     .conn = self.conn,
            //     .only_return_body = false,
            // }) catch undefined;
            recived_message.message_id = internal_message_id;

            self.app.replica.message_statuses[fiber_index] = .Ready;
            try self.app.replica.push(fiber_index);
            std.debug.print("ran push \r\n", .{});
        }
    }
};

fn temp_return(app_state: AppState, message: []align(16) u8) void {
    if (app_state.only_return_body) {
        const header: *message_header.Header.Reply(gateway.system.Operation) = @ptrCast(@constCast(message));
        app_state.conn.writeBin(message[@sizeOf(message_header.Header.Reply(gateway.system.Operation))..header.size]) catch {
            std.debug.assert(false);
        };
    } else {
        app_state.conn.writeBin(message) catch {
            std.debug.assert(false);
        };
    }
}
