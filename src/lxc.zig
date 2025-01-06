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

    pub fn create(self: *const Self, distro: []const u8, release: []const u8) !void {
        const func = self.inner.create;

        const args = try toArgs(self.allocator, &.{
            "-d", distro,
            "-r", release,
            "-a", "amd64",
        });
        defer freeArgs(self.allocator, args);

        const rt = func(self.inner, "download", null, null, 0, @ptrCast(args.ptr));
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
    }

    pub fn start(self: *const Self) !void {
        const func = self.inner.start;

        const rt = func(self.inner, 0, null);
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
    }

    pub fn destroy(self: *const Self) !void {
        const rt = self.inner.destroy(self.inner);
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
    }

    pub fn stop(self: *const Self) !void {
        const rt = self.inner.stop(self.inner);
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
    }

    pub fn state(self: *const Self) []const u8 {
        return std.mem.span(self.inner.state(self.inner));
    }

    pub fn getConfigFilename(self: *const Self) ![]const u8 {
        return std.mem.span(self.inner.config_file_name(self.inner));
    }

    // TODO: this doesnt work c pointer boundary?
    pub fn getConfigItem(self: *const Self, key: []const u8) ![:0]const u8 {
        const key_ptr = try self.allocator.dupeZ(u8, key);
        defer self.allocator.free(key_ptr);

        const len = self.inner.get_config_item(self.inner, key_ptr.ptr, null, 0);
        if (len < 0) {
            self.printError();
            return error.lxcError;
        }

        const out = try self.allocator.allocSentinel(u8, @intCast(len), 0);
        const rt = self.inner.get_config_item(self.inner, key_ptr.ptr, out.ptr, @intCast(out.len));
        if (rt < 0) {
            self.printError();
            return error.lxcError;
        }

        return out;
    }

    pub fn setConfigItem(self: *Self, key: []const u8, value: []const u8) !void {
        const key_ptr = try self.allocator.dupeZ(u8, key);
        const value_ptr = try self.allocator.dupeZ(u8, value);

        defer self.allocator.free(key_ptr);
        defer self.allocator.free(value_ptr);

        const rt = self.inner.set_config_item(self.inner, key_ptr.ptr, value_ptr.ptr);
        if (!rt) {
            self.printError();
            return error.lxcError;
        }
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

    pub fn attach(self: *const Self) !void {
        var options: lxc.lxc_attach_options_t = .{
            .attach_flags = lxc.LXC_ATTACH_DEFAULT,
            .namespaces = -1,
            .personality = lxc.LXC_ATTACH_DETECT_PERSONALITY,
            .initial_cwd = null,
            .uid = 0,
            .gid = 0,
            .env_policy = lxc.LXC_ATTACH_KEEP_ENV,
            .extra_env_vars = null,
            .extra_keep_env = null,
            .stdin_fd = 0,
            .stdout_fd = 1,
            .stderr_fd = 2,
            .log_fd = -1,
            .lsm_label = null,
            .groups = .{},
        };
        var pid: lxc.pid_t = undefined;

        const rt = self.inner.attach(self.inner, lxc.lxc_attach_run_shell, null, &options, &pid);
        if (rt != 0) {
            self.printError();
            return error.lxcError;
        }

        var status: u32 = undefined;
        _ = std.os.linux.waitpid(pid, &status, 0);
    }
};

pub fn listAllContainers(allocator: std.mem.Allocator) !std.StringArrayHashMap(Container) {
    // so this will allocate inside of the function (what the fuck). i dont
    // really care about that so just wanted to call out we leak here
    var names: [*][*:0]u8 = undefined;
    var containers: [*]*lxc.lxc_container = undefined;
    const len = lxc.list_all_containers(null, &names, &containers);
    if (len < 0) {
        return error.lxcError;
    }

    var out = std.StringArrayHashMap(Container).init(allocator);
    for (0..@intCast(len)) |i| {
        const name = names[i];
        const container = containers[i];

        try out.put(std.mem.span(name), Container{
            .allocator = allocator,
            .inner = container,
        });
    }

    return out;
}

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
