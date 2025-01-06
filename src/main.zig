const std = @import("std");
const Command = @import("command.zig");
const connect = @import("connect.zig").connect;
const list = @import("list.zig").list;
const remove = @import("remove.zig").remove;

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
        .{ .short = 'v', .long = "verbose", .description = "enable verbose logging for lxc" },
        .{ .short = 'i', .long = "image", .description = "the image to use for the container", .type = .argument },
        .{ .short = 'd', .long = "distro", .description = "the distribution to start the container using", .type = .argument },
        .{ .short = 'r', .long = "release", .description = "the release of the distribution to use", .type = .argument },
    },
    .subcommands = &.{helpCommand},
};

const listCommand = Command{
    .name = "list",
    .help = "list all containers",
    .description = "List all containers in LXC.",

    .flags = &.{
        .{ .short = 'h', .long = "help", .description = "display help information" },
    },
    .subcommands = &.{helpCommand},
};

const removeCommand = Command{
    .name = "remove",
    .help = "delete containers",
    .description = "Delete one or more containers",

    .rest = true,
    .rest_placeholder = "container name",

    .flags = &.{
        .{ .short = 'h', .long = "help", .description = "display help information" },
        .{ .short = 'v', .long = "verbose", .description = "enable verbose logging for lxc" },
        .{ .short = 'a', .long = "all", .description = "delete all containers" },
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
    .subcommands = &.{ helpCommand, connectCommand, listCommand, removeCommand },
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

    const subcommand = args.subcommand orelse unreachable;
    if (std.mem.eql(u8, subcommand.name, "connect")) {
        try connect(allocator, subcommand.result);
    } else if (std.mem.eql(u8, subcommand.name, "list")) {
        try list(allocator, subcommand.result);
    } else if (std.mem.eql(u8, subcommand.name, "remove")) {
        try remove(allocator, subcommand.result);
    } else {
        @panic("this should never happen");
    }
}
