const std = @import("std");
pub const ReplicaZig = @import("replica.zig");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const message_header = @import("message_header.zig");

const global_constants = @import("constants.zig");
const Operations = @import("operations.zig");
const uuid = @import("uuid.zig");
const kv = @import("systems/kv/kv.zig");
const AppState = @import("systems/kv/kv.zig").AppState;

pub const Replica = ReplicaZig.ReplicaType(
    kv.system,
    AppState,
    &kv.remote_services,
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
    // backoff in nothing is ran
    var backoff: u64 = 0;
    while (true) {
        if (replica.tick()) {
            std.debug.print("backoff: {}\r\n", .{backoff});
            backoff = 0;
        } else {
            backoff += 10;
            if (backoff > 10) {
                // sleep based on the backoff
                // set a a max of half a second
                if (backoff > std.time.ns_per_s / 10) {
                    backoff = std.time.ns_per_s / 10;
                }
                std.time.sleep(backoff);
            }
        }
    }
}

pub fn start() !void {

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
        .port = 9224,
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
        _ = self;
        std.debug.print("afetrInit\r\n", .{});
        // return self.conn.write("welcome!");
    }

    pub fn clientMessage(self: *Client, data: []const u8) !void {
        // std.debug.print("got message from client: {any}\r\n", .{data});
        // TODO: valadate data

        if (self.app.replica.resurveAvailableFiber()) |fiber_index| {
            const temp = &self.app.replica.messages[fiber_index];

            @memcpy(temp, data);

            self.app.replica.app_state_data[fiber_index] = AppState{
                .conn = self.conn,
            };
            // message_id_map.put(internal_message_id, Message_Request_Value{
            //     .client_message_id = recived_message.message_id,
            //     .conn = self.conn,
            //     .only_return_body = false,
            // }) catch undefined;

            self.app.replica.message_statuses[fiber_index] = .Ready;
            try self.app.replica.push(fiber_index);
            std.debug.print("ran push \r\n", .{});
        }
    }
};

fn temp_return(app_state: AppState, message: []align(16) u8) void {
    app_state.conn.writeBin(message) catch {
        std.debug.assert(false);
    };
}
