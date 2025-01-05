const std = @import("std");
pub const lxc = @import("lxc_translate.zig");

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

pub const Container = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    inner: *lxc.struct_lxc_container,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Self {
        const name_ptr = try allocator.dupeZ(u8, name);
        defer allocator.free(name_ptr);

        const inner = lxc.lxc_container_new(name_ptr.ptr, null);
        if (inner == null) {
            return error.lxcError;
        }

        return Self{
            .allocator = allocator,
            .inner = inner orelse unreachable,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = lxc.lxc_container_put(self.inner);
    }

    fn printError(self: *const Self) void {
        const err = self.inner.error_string orelse "invalid error";
        const err_code = self.inner.error_num;
        std.debug.print("LXC ERROR: {s} ({})\n", .{ err, err_code });
    }

    pub fn isDefined(self: *const Self) bool {
        return self.inner.is_defined(self.inner);
    }

    pub fn create(self: *const Self) !void {
        const func = self.inner.create;

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

    pub fn getConfigFilename(self: *const Self) ![]const u8 {
        return std.mem.span(self.inner.config_file_name(self.inner));
    }

    pub fn getConfigItem(self: *const Self, key: []const u8) ![]const u8 {
        const key_ptr = try self.allocator.dupeZ(u8, key);
        defer self.allocator.free(key_ptr);

        const len = self.inner.get_config_item(self.inner, key_ptr.ptr, null, 0);
        if (len < 0) {
            self.printError();
            return error.lxcError;
        }

        const out = try self.allocator.allocSentinel(u8, @intCast(len), 0);
        _ = self.inner.get_config_item(self.inner, key_ptr.ptr, out.ptr, @intCast(out.len));

        return out;
    }

    pub fn getKeys(self: *const Self, prefix: []const u8) ![]const u8 {
        const prefix_ptr = try self.allocator.dupeZ(u8, prefix);
        defer self.allocator.free(prefix_ptr);

        const len = self.inner.get_keys(self.inner, prefix_ptr.ptr, null, 0);
        if (len < 0) {
            self.printError();
            return error.lxcError;
        }

        const out = try self.allocator.allocSentinel(u8, @intCast(len), 0);
        _ = self.inner.get_keys(self.inner, prefix_ptr.ptr, out.ptr, @intCast(out.len));

        return out;
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
