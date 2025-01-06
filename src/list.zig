const std = @import("std");
const Command = @import("command.zig");
const lxc = @import("lxc.zig");

pub fn list(allocator: std.mem.Allocator, args: *const Command.ParseResult) !void {
    _ = args; // autofix

    var containers = try lxc.listAllContainers(allocator);
    defer containers.deinit();

    std.debug.print("Containers:\n", .{});
    var contIter = containers.iterator();
    while (contIter.next()) |entry| {
        const name = entry.key_ptr;
        const container = entry.value_ptr;
        _ = container; // autofix

        std.debug.print("  - {s}\n", .{name.*});
    }
}
