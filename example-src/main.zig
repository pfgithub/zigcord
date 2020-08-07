const std = @import("std");
const zigcord = @import("zigcord");
const token = "Bot " ++ @embedFile("token");

fn handler(session: *zigcord.Session, event: zigcord.Event) !void {
    switch (event.data) {
        .message_create => |msg| {
            std.debug.warn("Message: {}\n", .{msg});
            if (std.mem.eql(u8, msg.content, "ping")) {
                // const response = try fmtAlloc(.{fmt.call(msg.author.user, msg.author.user.mention, .{.user}), ", ", "pong!"});
                // kind of bad
                try session.sendMessage(msg.channel_id, "pong!");
                // session.sendMessage() catch |e| switch(e) {
                //     error.NetworkError => return e,
                //     error.DiscordAPIError => ... uh oh we need more information oh no
                // }
            }
            if (std.mem.eql(u8, msg.content, "restart")) {
                return error.RequestedRestart;
            }
        },
        else => {},
    }
}

pub fn main() !void {
    var discord = try zigcord.Session.init(
        std.heap.c_allocator,
        @embedFile("../discordgg.pem"),
        @embedFile("../discordappcom.pem"),
    );
    try discord.connect();
    std.debug.warn("Discord started\n", .{});
    discord.listen(token, handler) catch |e| switch(e) {
        error.RequestedRestart => {
            std.debug.warn("Restart requested\n", .{});
            return;
        },
        else => return e,
    };
}