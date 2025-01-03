const std = @import("std");
const linux = std.os.linux;

pub fn ensurePermissions(allocator: std.mem.Allocator) !void {
    const euid = linux.geteuid();
    if (euid == 0) {
        return;
    }

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("CHIMERA_WRAPPED")) |_| {
        return;
    }

    // Build the systemd-run command
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    try args.appendSlice(&.{
        "systemd-run",
        "--unit=chimera",
        "--user",
        "--scope",
        "--quiet",
        "-p",
        "Delegate=yes",
        "--setenv=CHIMERA_WRAPPED=1",
        "--",
    });

    var argIter = try std.process.argsWithAllocator(allocator);
    defer argIter.deinit();

    while (argIter.next()) |arg| {
        try args.append(arg);
    }

    return std.process.execve(allocator, args.items, null);
}
