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

    const verbose = args.get(bool, "verbose") orelse false;
    if (verbose) {
        try lxc.initLog();
    }
    defer if (verbose) {
        lxc.closeLog();
    };

    const container_name = extractContainerName(args);
    if (verbose) {
        std.debug.print("building container {s}\n", .{container_name});
    }

    var container = try Container.init(allocator, container_name);
    defer container.deinit();

    if (verbose) {
        try container.setConfigItem("lxc.log.level", "DEBUG");
        try container.setConfigItem("lxc.log.file", "/tmp/lxc-start.log");
    }

    try container.setConfigItem("lxc.apparmor.profile", "unconfined");

    try container.setConfigItem("lxc.net.0.type", "veth");
    try container.setConfigItem("lxc.net.0.link", "lxcbr0");
    try container.setConfigItem("lxc.net.0.flags", "up");

    if (!container.isDefined()) {
        if (verbose) {
            std.debug.print("creating container\n", .{});
        }

        const distro = args.get([]const u8, "distro") orelse "ubuntu";
        const release = getContainerRelease(args, distro);
        try container.create(distro, release);
    }

    if (!std.mem.eql(u8, container.state(), "RUNNING")) {
        if (verbose) {
            std.debug.print("starting container\n", .{});
        }

        try container.start();
    }

    try container.attach();
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

fn getContainerRelease(args: *const Command.ParseResult, distro: []const u8) []const u8 {
    const release = args.get([]const u8, "release");
    if (release) |out| {
        return out;
    }

    if (std.mem.eql(u8, distro, "ubuntu")) {
        return "oracular";
    }

    std.debug.print("unknown distro {s}, please specify a release: https://images.linuxcontainers.org/", .{distro});
    std.process.exit(1);
}
