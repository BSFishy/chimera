const std = @import("std");
pub const lxc = @cImport({
    @cInclude("lxc/lxccontainer.h");
});

pub fn getVersion() []const u8 {
    return std.mem.span(lxc.lxc_get_version());
}
