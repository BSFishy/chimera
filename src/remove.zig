const std = @import("std");
const Command = @import("command.zig");
const lxc = @import("lxc.zig");

pub fn remove(allocator: std.mem.Allocator, args: *const Command.ParseResult) !void {
    const verbose = args.get(bool, "verbose") orelse false;
    if (verbose) {
        try lxc.initLog();
    }
    defer if (verbose) {
        lxc.closeLog();
    };

    const all = args.get(bool, "all") orelse false;
    if (all) {
        return removeAll(allocator);
    }

    const rest = args.rest orelse {
        std.debug.print("either specify a container to delete or -a\n", .{});
        std.process.exit(1);
    };

    for (rest) |container_name| {
        try removeContainer(allocator, container_name);
    }
}

fn removeAll(allocator: std.mem.Allocator) !void {
    var containers = try lxc.listAllContainers(allocator);
    defer containers.deinit();

    var iter = containers.iterator();
    while (iter.next()) |entry| {
        try removeContainer(allocator, entry.key_ptr.*);
    }
}

fn removeContainer(allocator: std.mem.Allocator, container_name: []const u8) !void {
    var container = try lxc.Container.init(allocator, container_name);
    defer container.deinit();

    if (!std.mem.eql(u8, container.state(), "STOPPED")) {
        try container.stop();
    }

    try container.destroy();

    std.debug.print("Removed {s}\n", .{container_name});
}
