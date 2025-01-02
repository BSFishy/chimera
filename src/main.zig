const std = @import("std");
const lxc = @import("lxc.zig");
const Command = @import("command.zig");

const helpCommand = Command{
    .name = "help",
    .help = "display help information",
};

const connectCommand = Command{
    .name = "connect",
    .help = "start and connect to a container",
    .description = "Start and connect to a container. If the container already exists, just connects to it.",
    .flags = &.{
        .{ .short = 'h', .long = "help", .description = "display help information" },
    },
    .subcommands = &.{helpCommand},
};

const command = Command{
    .name = "chimera",
    .description = "Simple LXC controller",
    .require_subcommand = true,
    .flags = &.{
        .{ .short = 'v', .long = "verbose", .description = "increase logging output" },
        .{ .short = 'h', .long = "help", .description = "display help information" },
        .{ .short = 'n', .long = "name", .description = "the name of the thing", .type = .argument },
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

    // const version = lxc.getVersion();
    // std.debug.print("LXC Version: {s}\n", .{version});
    var args = try command.parse(allocator);
    defer args.deinit();

    printArgs(0, &args);
}

fn prefix(n: usize) void {
    for (0..(n * 2)) |_| {
        std.debug.print(" ", .{});
    }
}

fn printArgs(n: usize, args: *const Command.ParseResult) void {
    var flagsIter = args.flags.iterator();
    while (flagsIter.next()) |flag| {
        prefix(n);
        std.debug.print("{s}: {s}\n", .{ flag.key_ptr.*, flag.value_ptr.* });
    }

    if (args.subcommand) |cmd| {
        prefix(n);
        std.debug.print("command - {s}\n", .{cmd.name});

        printArgs(n + 1, cmd.result);
    }
}
