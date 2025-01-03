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
