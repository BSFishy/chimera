const std = @import("std");
const config = @import("config");
pub const lxc = @import("lxc_translate.zig");
const uid = @import("uid.zig");

pub fn getVersion() []const u8 {
    return std.mem.span(lxc.lxc_get_version());
}

pub fn initLog() !void {
    var log = lxc.lxc_log{};
    if (lxc.lxc_log_init(&log) != 0) {
        return error.lxcError;
    }
}

pub fn closeLog() void {
    lxc.lxc_log_close();
}

fn getAppConfigDir(allocator: std.mem.Allocator, appname: []const u8) ![]u8 {
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fs.path.join(allocator, &[_][]const u8{ xdg, appname });
    }

    const home_dir = std.posix.getenv("HOME") orelse {
        return error.AppDataDirUnavailable;
    };
    return std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".config", appname });
}

fn getConfigFile(allocator: std.mem.Allocator) ![]const u8 {
    const app_data_dir = try getAppConfigDir(allocator, "lxc");
    var app_dir = std.fs.openDirAbsolute(app_data_dir, .{}) catch |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }

        try std.fs.makeDirAbsolute(app_data_dir);
        break :blk try std.fs.openDirAbsolute(app_data_dir, .{});
    };
    defer app_dir.close();

    const euid = std.os.linux.geteuid();
    if (euid == 0) {
        return app_data_dir;
    }

    var config_file = try app_dir.createFile("default.conf", .{
        .read = true,
        .truncate = false,
    });
    defer config_file.close();

    const size = try config_file.getEndPos();
    if (size == 0) {
        const include_config = try std.fs.path.join(allocator, &.{ config.lxc_sys_confdir, "default.conf" });
        defer allocator.free(include_config);

        var writer = config_file.writer();
        try writer.print("lxc.include = {s}\n", .{include_config});

        const username = try uid.getUsername(allocator);
        defer allocator.free(username);

        const subuid = (try uid.getSubuid(allocator, username)) orelse @panic("no user in /etc/subuid");
        try writer.print("lxc.idmap = u 0 {d} {d}\n", .{ subuid.subid, subuid.range });

        const subgid = (try uid.getSubgid(allocator, username)) orelse @panic("no user in /etc/subgid");
        try writer.print("lxc.idmap = g 0 {d} {d}\n", .{ subgid.subid, subgid.range });

        try config_file.sync();
    }

    return app_data_dir;
}

pub const Container = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    inner: [*c]lxc.struct_lxc_container,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Self {
        const config_path = try getConfigFile(allocator);
        defer allocator.free(config_path);

        const name_ptr = try allocator.dupeZ(u8, name);
        const config_path_ptr = try allocator.dupeZ(u8, config_path);
        defer allocator.free(name_ptr);
        defer allocator.free(config_path_ptr);

        std.debug.print("name: {s}, config path: {s}\n", .{ name_ptr, config_path_ptr });

        const inner = lxc.lxc_container_new(name_ptr.ptr, null);
        if (inner == null) {
            return error.lxcError;
        }

        return Self{
            .allocator = allocator,
            .inner = inner,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = lxc.lxc_container_put(self.inner);
    }

    fn printError(self: *const Self) void {
        const err = self.inner.*.error_string;
        const err_code = self.inner.*.error_num;
        std.debug.print("LXC ERROR: {*} ({})\n", .{ err, err_code });
    }

    pub fn isDefined(self: *const Self) bool {
        const func = self.inner.*.is_defined orelse unreachable;

        return func(self.inner);
    }

    pub fn create(self: *const Self) !void {
        const func = self.inner.*.create;

        const args = try toArgs(self.allocator, &.{
            "-d", "ubuntu",
            "-r", "oracular",
            "-a", "amd64",
        });
        defer freeArgs(self.allocator, args);

        const rt = func(self.inner, "download", null, null, 0, @ptrCast(args.ptr));
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
    }
};

fn toArgs(allocator: std.mem.Allocator, args: []const []const u8) ![:null]?[*:0]const u8 {
    var out = try allocator.allocSentinel(?[*:0]const u8, args.len, null);
    for (args, 0..) |arg, i| {
        out[i] = try allocator.dupeZ(u8, arg);
    }

    return out;
}

fn freeArgs(allocator: std.mem.Allocator, args: [:null]?[*:0]const u8) void {
    for (args) |arg| {
        allocator.free(std.mem.span(arg orelse unreachable));
    }

    allocator.free(args);
}
