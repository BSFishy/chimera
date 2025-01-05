const std = @import("std");
const Command = @import("command.zig");
const Container = @import("lxc.zig").Container;
const lxc = @import("lxc.zig");

pub fn connect(allocator: std.mem.Allocator, args: *Command.ParseResult) !void {
    const euid = std.os.linux.geteuid();
    if (euid != 0) {
        std.debug.print("must be run as root\n", .{});
        std.process.exit(1);
    }

    const container_name = extractContainerName(args);
    std.debug.print("building container {s}\n", .{container_name});

    try lxc.initLog();
    defer lxc.closeLog();

    var container = try Container.init(allocator, container_name);
    defer container.deinit();

    const config_item = container.getConfigItem("include") catch blk: {
        break :blk try allocator.dupe(u8, "nuffin");
    };
    defer allocator.free(config_item);
    std.debug.print("config: {s}\n", .{config_item});

    const keys = container.getKeys("lxc.") catch blk: {
        break :blk try allocator.dupe(u8, "nada");
    };
    defer allocator.free(keys);
    std.debug.print("keys: {s}\n", .{keys});

    std.debug.print("config filename: {s}\n", .{try container.getConfigFilename()});
    std.debug.print("container exists\n", .{});
    std.debug.print("container defined: {}\n", .{container.isDefined()});

    if (!container.isDefined()) {
        try container.create();
        std.debug.print("container created\n", .{});
    }
}

fn extractContainerName(args: *const Command.ParseResult) []const u8 {
    const args_rest: [][]const u8 = args.rest orelse {
        std.debug.print("you need to provide a container name\n", .{});
        std.process.exit(1);
    };

    if (args_rest.len != 1) {
        std.debug.print("invalid input: {s}", .{args_rest[0]});
        for (args_rest[1..]) |rest| {
            std.debug.print(" {s}", .{rest});
        }

        std.debug.print("\n", .{});
        std.process.exit(1);
    }

    return args_rest[0];
}
