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
const kv = @import("systems/kv/kv.zig");
const shared = @import("shared.zig");

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

var client_db: *websocket.Client = undefined;

pub fn call_kv(ptr: [*]const u8, len: usize) void {
    std.debug.print("call kv in gateway\r\n", .{});
    // print the message id
    const header: *message_header.Header.Request(gateway.system) = @constCast(@ptrCast(@alignCast(ptr[0..len])));
    const message_id = header.message_id;
    std.debug.print("message id: {any}\n", .{message_id});
    client_db.writeBin(@constCast(ptr[0..len])) catch undefined;
}

pub fn startKVServerClient(passed_client_db: *websocket.Client, replica: *Replica) !void {
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
                if (message.data.len < @sizeOf(message_header.Header.Reply(kv.system))) {
                    std.debug.print("recieved message is too small\n", .{});
                    continue;
                }

                // copy the data to a buffer that is aligned
                var buffer: [global_constants.message_size_max]u8 align(16) = undefined;
                const temp = buffer[0..message.data.len];
                @memcpy(temp, message.data);

                std.debug.print("received from kv: {any}\n", .{message.data});
                // cast data to a recieved header
                const header: *message_header.Header.Reply(kv.system) = @ptrCast(&buffer);
                // get the message id
                const message_id = header.message_id;
                std.debug.print("message id: {any}\n", .{message_id});

                // TODO:
                // route the reply to the corrent message based on the message id
                // this needs to be able to interact with the replica
                // this needs to be made thread safe
                if (replica.message_wait_on_map.get(message_id)) |value| {
                    if (value.is_fiber_waiting) {
                        replica.message_waiting_on_count[value.waiting_index] = replica.message_waiting_on_count[value.waiting_index] - 1;
                    }
                    //TODO: check that size of the data received matches the size of the data expected

                    // std.debug.assert(value.reply_size < @sizeOf(Operations.ResultType(kv.system, header.operation)) + 1);
                    // const casted_reply: *Operations.ResultType(kv.system, header.operation) = @alignCast(@ptrCast(&replica.messages_state[value.waiting_index][value.reply_offset]));

                    // casted_reply.* = buffer[@sizeOf(message_header.Header.Reply(kv.system))..header.size];
                    // @memcpy(casted_reply, buffer[@sizeOf(message_header.Header.Reply(kv.system))..header.size]);
                    // @memcpy(std.mem.asBytes(casted_reply), buffer[@sizeOf(message_header.Header.Reply(kv.system.Operation))..header.size]);
                    @memcpy(
                        replica.messages_state[value.waiting_index][value.reply_offset .. value.reply_offset + (header.size - @sizeOf(message_header.Header.Reply(kv.system)))],
                        buffer[@sizeOf(message_header.Header.Reply(kv.system))..header.size],
                    );

                    std.debug.print("got vk reply chcek\r\n", .{});
                }
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
    var app = App{};

    var system_instance: gateway.system = gateway.system{};
    try app.replica.init(
        &system_instance,
        .{ .temp_return = &temp_return },
    );

    var client_db_src: websocket.Client = undefined;
    client_db = &client_db_src;
    const KV_thread = try std.Thread.spawn(.{}, startKVServerClient, .{ client_db, &app.replica });
    _ = KV_thread;

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

    const BufferSize = 50000;
    // var buffer: [BufferSize]u8 = undefined; // fixed-size backing buffer

    const slice_ptr = try res.arena.alloc(u8, BufferSize);
    var fba2 = std.heap.FixedBufferAllocator.init(slice_ptr);

    const allocator = fba2.allocator();

    var writer = shared.BufferWriter.init(&allocator, BufferSize) catch {
        return;
    };

    const file_content = @embedFile("index.html");
    const parts = comptime shared.splitOnMarkers(file_content);

    writer.set_lens();
    writer.write_to_header("this is the header") catch {
        return;
    };

    writer.set_lens();

    writer.write_to_body(parts[0]) catch {
        return;
    };

    writer.write_to_body(@embedFile("components/auth/signup.html")) catch {
        return;
    };

    writer.write_to_body(parts[1]) catch {
        return;
    };

    writer.set_lens();

    // res.body = file_content;

    res.body = writer.buffer[4 + writer.position_header .. writer.position_body];
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
            const recived_message: *message_header.Header.Request(gateway.system) = @ptrCast(temp);
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
        const header: *message_header.Header.Reply(gateway.system) = @ptrCast(@constCast(message));
        app_state.conn.writeBin(message[@sizeOf(message_header.Header.Reply(gateway.system))..header.size]) catch {
            std.debug.assert(false);
        };
    } else {
        app_state.conn.writeBin(message) catch {
            std.debug.assert(false);
        };
    }
}
