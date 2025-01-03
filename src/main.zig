const std = @import("std");
const Command = @import("command.zig");
const connect = @import("connect.zig").connect;

const helpCommand = Command{
    .name = "help",
    .help = "display help information",
};

const connectCommand = Command{
    .name = "connect",
    .help = "start and connect to a container",
    .description = "Start and connect to a container. If the container already exists, just connects to it.",

    .rest = true,
    .rest_placeholder = "container name",

    .flags = &.{
        .{ .short = 'h', .long = "help", .description = "display help information" },
        .{ .short = 'i', .long = "image", .description = "the image to use for the container", .type = .argument },
    },
    .subcommands = &.{helpCommand},
};

const command = Command{
    .name = "chimera",
    .description = "Simple LXC controller",
    .require_subcommand = true,
    .flags = &.{
        .{ .short = 'h', .long = "help", .description = "display help information" },
    },
    .subcommands = &.{ helpCommand, connectCommand },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.process.exit(1);
        }
    }

    var args = try command.parse(allocator);
    defer args.deinit();

    const Subcommand = enum { connect };
    const subcommand = args.subcommand orelse unreachable;
    switch (std.meta.stringToEnum(Subcommand, subcommand.name) orelse unreachable) {
        .connect => {
            try connect(allocator, subcommand.result);
        },
    }
}
