pub const api_types = @import("api-types.zig");
const json = @import("json.zig");
const std = @import("std");
const hzzp = @import("hzzp");
const net = @import("zig-network");
const ssl = @import("bearssl");
const wz = @import("wz");

const user_agent = "ZigCord (github.com/Sobeston/zigcord, v0.0.0)";

pub const Snowflake = struct {
    data: u64,

    pub fn format(
        self: Snowflake,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{}", .{self.data});
    }

    pub const MentionKind = enum { user, role, channel };

    pub fn mention(self: Snowflake, kind: MentionKind, writer: anytype) !void {
        switch (kind) {
            .user => try writer.print("<@{}>", .{self.data}),
            .role => try writer.print("<@&{}>", .{self.data}),
            .channel => try writer.print("<#{}>", .{self.data}),
        }
    }

    /// nanosecond time
    pub fn milliTimestamp(self: @This()) i64 {
        return @intCast(i64, (self.data >> 22) + 1420070400000);
    }

    pub fn from(str: []const u8) Snowflake {
        return Snowflake{
            .data = std.fmt.parseInt(u64, str, 10) catch unreachable, // means discord gave us invalid data
        };
    }
};

pub const Timestamp = u64;
pub fn timestampFrom(str: []const u8) Timestamp {
    return 2; // TODO
}

pub const MessageType = enum(u32) {
    default,
    recipient_add,
    recipient_remove,
    call,
    channel_name_change,
    channel_icon_change,
    channel_pinned_message,
    guild_member_join,
    user_premium_guild_subscription,
    user_premium_guild_subscription_tier_1,
    user_premium_guild_subscription_tier_2,
    user_premium_guild_subscription_tier_3,
    channel_follow_add,
    guild_discovery_disqualified,
    guild_discovery_requalified,
    _,
};

pub const UserFlags = packed struct {
    discord_employee: u1,
    discord_partner: u1,
    hypesquad_events: u1,
    bug_hunter_level_1: u1,
    house_bravery: u1,
    house_brilliance: u1,
    house_balance: u1,
    early_supporter: u1,
    team_user: u1,
    system: u1,
    bug_hunter_level_2: u1,
    verified_bot: u1,
    verified_bot_developer: u1,
    pub fn from(flags: api_types.UInt) UserFlags {
        return @bitCast(UserFlags, @truncate(u13, flags));
    }
};

/// TODO
pub const WebhookUser = struct {};
pub const User = struct {
    username: []const u8,
    id: Snowflake,
    discriminator: []const u8,
    // avatar: union(enum) {custom: Avatar, default: Avatar}
    // default avatar is based on the discriminator or id or something

    pub fn from(user: api_types.PartialUser) User {
        // Auto.fill(User, user);
        return .{
            .username = user.username,
            .id = Snowflake.from(user.id),
            .discriminator = user.discriminator,
        };
    }
};
pub const GuildMember = struct {
    // roles: []Snowflake,
    // joined_at: Timestamp,
    pub fn from(member: api_types.PartialMember) GuildMember {
        return .{};
    }
};

/// https://discord.com/developers/docs/resources/channel#message-object-message-flags
pub const MessageFlags = packed struct {
    /// this message has been published to subscribed channels (via Channel Following)
    crossposted: u1 = 0,
    /// this message originated from a message in another channel (via Channel Following)
    is_crosspost: u1 = 0,
    ///	do not include any embeds when serializing this message
    supress_embeds: u1 = 0,
    /// the source message for this crosspost has been deleted (via Channel Following)
    source_message_deleted: u1 = 0,
    /// this message came from the urgent message system
    urgent: u1 = 0,

    pub fn from(flags: api_types.UInt) MessageFlags {
        return @bitCast(MessageFlags, @truncate(u5, flags));
    }
};

pub const Message = struct {
    id: Snowflake,
    channel_id: Snowflake,
    guild_id: ?Snowflake,
    author: union(enum) { user: User, webhook_user: WebhookUser },
    member: ?GuildMember,
    flags: MessageFlags,

    content: []const u8,

    tts: bool,
    mention_everyone: bool,
    pinned: bool,
    kind: MessageType,

    pub fn from(msg: api_types.Message) Message {
        return Message{
            .id = Snowflake.from(msg.id),
            .channel_id = Snowflake.from(msg.channel_id),
            .guild_id = if (msg.guild_id) |guildid| Snowflake.from(guildid) else null,
            .author = if (msg.webhook_id) |whid| .{ .webhook_user = .{} } else .{ .user = User.from(msg.author) },
            .member = if (msg.member) |msgmem| GuildMember.from(msgmem) else null,
            .flags = if (msg.flags) |flags| MessageFlags.from(flags) else .{},

            .content = msg.content,
            .tts = msg.tts,
            .mention_everyone = msg.mention_everyone,
            .pinned = msg.pinned,
            .kind = @intToEnum(MessageType, @intCast(@TagType(MessageType), msg.@"type")),
        };
    }
};

pub const DiscordEvent = union(enum) {
    message_create: Message,
    unknown: []const u8,
};

pub const Event = struct {
    raw: []const u8,
    data: DiscordEvent,
};

fn heartbeatThread(session: *Session) void {
    while (true) {
        std.time.sleep(session.heartbeat_interval);
        session.sendHeartbeat() catch {};
    }
}

const SslSocket = ssl.Stream(*net.Socket.Reader, *net.Socket.Writer);

pub const Session = struct {
    ws: struct {
        x509: ssl.x509.Minimal,
        ssl_client: ssl.Client,
        socket: net.Socket,
        socket_reader: net.Socket.Reader,
        socket_writer: net.Socket.Writer,
        ssl_socket: SslSocket,
        buffer: [512]u8 = std.mem.zeroes([512]u8),
        client: wz.BaseClient.BaseClient(
            SslSocket.DstInStream,
            SslSocket.DstOutStream,
        ),
    },
    http: struct {
        x509: ssl.x509.Minimal,
        ssl_client: ssl.Client,
        socket: net.Socket,
        socket_reader: net.Socket.Reader,
        socket_writer: net.Socket.Writer,
        ssl_socket: SslSocket,
        buffer: [512]u8 = std.mem.zeroes([512]u8),
        client: hzzp.BaseClient.BaseClient(
            SslSocket.DstInStream,
            SslSocket.DstOutStream,
        ),
    },
    allocator: *std.mem.Allocator,
    trust_anchor: ssl.TrustAnchorCollection,
    token: []const u8,
    heartbeat_interval: u64, // nanoseconds
    last_received_sequence: u64,
    /// sets up ssl
    pub fn init(
        allocator: *std.mem.Allocator,
        gg_pem: []const u8,
        appcom_pem: []const u8,
    ) !Session {
        var trust_anchor = ssl.TrustAnchorCollection.init(allocator);
        try trust_anchor.appendFromPEM(gg_pem);
        try trust_anchor.appendFromPEM(appcom_pem);

        //ws ssl client setup
        var ws_x509 = ssl.x509.Minimal.init(trust_anchor);
        var ws_ssl_client = ssl.Client.init(ws_x509.getEngine());
        ws_ssl_client.relocate();
        try ws_ssl_client.reset("gateway.discord.gg", false);

        //http ssl client setup
        var http_x509 = ssl.x509.Minimal.init(trust_anchor);
        var http_ssl_client = ssl.Client.init(http_x509.getEngine());
        http_ssl_client.relocate();
        try http_ssl_client.reset("discordapp.com", false);

        return Session{
            .ws = .{
                .x509 = ws_x509,
                .ssl_client = ws_ssl_client,
                .socket = undefined,
                .socket_reader = undefined,
                .socket_writer = undefined,
                .ssl_socket = undefined,
                .client = undefined,
            },
            .http = .{
                .x509 = http_x509,
                .ssl_client = http_ssl_client,
                .socket = undefined,
                .socket_reader = undefined,
                .socket_writer = undefined,
                .ssl_socket = undefined,
                .client = undefined,
            },
            .token = undefined,
            .allocator = allocator,
            .trust_anchor = trust_anchor,
            .heartbeat_interval = undefined,
            .last_received_sequence = undefined,
        };
    }

    /// opens sockets to discord, initiates ssl sockets, initiates ws and http clients
    pub fn connect(self: *Session) !void {
        try net.init();

        // open sockets
        self.ws.socket = try net.connectToHost(self.allocator, "gateway.discord.gg", 443, .tcp);
        self.ws.socket_reader = self.ws.socket.reader();
        self.ws.socket_writer = self.ws.socket.writer();
        self.http.socket = try net.connectToHost(self.allocator, "discordapp.com", 443, .tcp);
        self.http.socket_reader = self.http.socket.reader();
        self.http.socket_writer = self.http.socket.writer();

        // initiate ssl sockets
        self.ws.ssl_socket = ssl.initStream(
            self.ws.ssl_client.getEngine(),
            &self.ws.socket_reader,
            &self.ws.socket_writer,
        );
        self.http.ssl_socket = ssl.initStream(
            self.http.ssl_client.getEngine(),
            &self.http.socket_reader,
            &self.http.socket_writer,
        );

        // setup ws and http clients
        self.ws.client = wz.BaseClient.create(
            &self.ws.buffer,
            self.ws.ssl_socket.inStream(),
            self.ws.ssl_socket.outStream(),
        );
        self.http.client = hzzp.BaseClient.create(
            &self.http.buffer,
            self.http.ssl_socket.inStream(),
            self.http.ssl_socket.outStream(),
        );
    }

    /// handshakes websocket, listens
    pub fn listen(self: *Session, token: []const u8, handler: fn (*Session, Event) anyerror!void) !void {
        self.token = token;

        //handshake with gateway
        var handshake_headers = std.http.Headers.init(self.allocator);
        defer handshake_headers.deinit();
        try handshake_headers.append("Host", "gateway.discord.gg", null);
        try self.ws.client.sendHandshake(&handshake_headers, "/?v=6&encoding=json");
        try self.ws.ssl_socket.flush();
        try self.ws.client.waitForHandshake();

        //listen for discord's "Hello", take heartbeat interval
        self.heartbeat_interval = blk: {
            var hb_ns: ?u64 = null;
            while (try self.ws.client.readEvent()) |event| {
                switch (event) {
                    .header => continue,
                    .chunk => {
                        var stream = std.json.TokenStream.init(event.chunk.data);
                        const hello = try std.json.parse(api_types.Hello, &stream, .{ .allocator = self.allocator });
                        defer std.json.parseFree(api_types.Hello, hello, .{ .allocator = self.allocator });
                        hb_ns = hello.d.heartbeat_interval * 1000 * 1000;
                        break;
                    },
                    .invalid => return error.InvalidEvent,
                    .closed => return error.Closed,
                    .end => break,
                }
            }
            break :blk hb_ns orelse return error.NoHeartbeatIntervalReceived;
        };

        //send identify to discord
        var identify_string = std.ArrayList(u8).init(self.allocator);
        defer identify_string.deinit();
        const identify = api_types.Identify{
            .d = .{
                .token = self.token,
                .properties = .{
                    .@"$os" = @tagName(std.Target.current.os.tag),
                    .@"$browser" = user_agent,
                    .@"$device" = user_agent,
                },
                .compress = false,
                .shard = .{ 0, 1 },
            },
        };
        try std.json.stringify(identify, .{}, identify_string.writer());
        try self.ws.client.writeMessageHeader(.{ .length = identify_string.items.len, .opcode = 1 });
        const mask_buf = try self.allocator.alloc(u8, identify_string.items.len);
        defer self.allocator.free(mask_buf);
        for (mask_buf) |*m| m.* = 0;
        self.ws.client.maskPayload(identify_string.items, mask_buf);
        try self.ws.client.writeMessagePayload(mask_buf);
        try self.ws.ssl_socket.flush();

        //listen for events
        var event_buf = std.ArrayList(u8).init(self.allocator);
        defer event_buf.deinit();

        _ = try std.Thread.spawn(self, heartbeatThread);

        while (true) {
            switch ((try self.ws.client.readEvent()).?) {
                .header => continue,
                .chunk => |chunk| {
                    try event_buf.appendSlice(chunk.data);
                    if (chunk.final) {
                        try self.handle(event_buf.items, handler);
                        event_buf.shrinkRetainingCapacity(0);
                    }
                },
                .end => return error.End,
                .invalid => return error.Invalid,
                .closed => return error.Closed,
            }
        }
    }

    fn sendHeartbeat(self: *Session) !void {
        var heartbeat_string = std.ArrayList(u8).init(self.allocator);
        defer heartbeat_string.deinit();

        try std.json.stringify(
            .{ .op = 1, .d = self.last_received_sequence },
            .{},
            heartbeat_string.writer(),
        );
        try self.ws.client.writeMessageHeader(.{ .length = heartbeat_string.items.len, .opcode = 1 });

        var mask_buf = try self.allocator.alloc(u8, heartbeat_string.items.len);
        defer self.allocator.free(mask_buf);
        for (mask_buf) |*m| m.* = 0;

        self.ws.client.maskPayload(heartbeat_string.items, mask_buf);
        try self.ws.client.writeMessagePayload(mask_buf);
        try self.ws.ssl_socket.flush();
    }

    /// converts raw json to an Event value, calls the user's handler function
    fn handle(self: *Session, raw: []const u8, handler: fn (*Session, Event) anyerror!void) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var unk_buffer: [1000]json.ExpectedEndToken = undefined;
        const options = .{
            .allocator = &arena.allocator,
            .unknown_field_buffer = &unk_buffer,
        };

        var stub_stream = json.TokenStream.init(raw);
        const stub = json.parse(api_types.Stub, &stub_stream, options) catch return;
        if (stub.s == null or stub.t == null) return;

        self.last_received_sequence = stub.s.?;
        const event_string = stub.t.?;

        var json_stream = json.TokenStream.init(raw);

        @setEvalBranchQuota(100_000);
        const event = Event{
            .raw = raw,
            .data = switch (std.hash.Crc32.hash(event_string)) {
                std.hash.Crc32.hash("MESSAGE_CREATE") => blk: {
                    const message = try json.parse(api_types.MessageCreate, &json_stream, options);

                    break :blk .{
                        .message_create = Message.from(message.d),
                    };
                },
                else => .{ .unknown = event_string },
            },
        };

        try handler(self, event);
    }

    pub fn sendMessage(self: *Session, channel: Snowflake, text: []const u8) !void {
        self.http.socket = try net.connectToHost(self.allocator, "discordapp.com", 443, .tcp);
        defer self.http.socket.close();

        var message_url = std.ArrayList(u8).init(self.allocator);
        defer message_url.deinit();
        try message_url.writer().print("/api/v6/channels/{}/messages", .{channel.data});

        try self.http.client.writeHead("POST", message_url.items);
        try self.http.client.writeHeader("Authorization", self.token);
        try self.http.client.writeHeader("Host", "discordapp.com");
        try self.http.client.writeHeader("User-Agent", user_agent);
        try self.http.client.writeHeader("Content-Type", "application/json");

        var response_body = std.ArrayList(u8).init(self.allocator);
        defer response_body.deinit();
        try std.json.stringify(.{ .content = text }, .{}, response_body.writer());

        const len_string = try std.fmt.allocPrint(self.allocator, "{}", .{response_body.items.len});
        defer self.allocator.free(len_string);

        try self.http.client.writeHeader("Content-length", len_string);
        try self.http.client.writeChunk(response_body.items);
        try self.http.ssl_socket.flush();
        self.http.client.reset();
    }
};
