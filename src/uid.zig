const std = @import("std");
const linux = std.os.linux;

pub fn getUsername(allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    return try allocator.dupe(u8, env_map.get("USER") orelse @panic("USER environment variable doesn't exist"));
}

pub const Subid = struct {
    subid: u32,
    range: u32,
};

pub fn getSubuid(allocator: std.mem.Allocator, username: []const u8) !?Subid {
    return getSubid(allocator, username, "/etc/subuid");
}

pub fn getSubgid(allocator: std.mem.Allocator, username: []const u8) !?Subid {
    return getSubid(allocator, username, "/etc/subgid");
}

pub fn getSubid(allocator: std.mem.Allocator, username: []const u8, path: []const u8) !?Subid {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = file.reader();
    while (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |line| {
        defer allocator.free(line);

        var tokens = std.mem.split(u8, line, ":");
        const first = tokens.next() orelse continue;
        if (std.mem.eql(u8, first, username)) {
            const subuid = try std.fmt.parseInt(u32, tokens.next() orelse continue, 10);
            const range = try std.fmt.parseInt(u32, tokens.next() orelse continue, 10);

            return .{
                .subid = subuid,
                .range = range,
            };
        }
    }

    return null;
}
