const std = @import("std");
const Self = @This();

const FlagType = enum {
    flag,
    argument,
};

const Flag = struct {
    long: ?[]const u8 = null,
    short: ?u8 = null,
    type: FlagType = .flag,
    default: ?[]const u8 = null,
    description: ?[]const u8 = null,

    fn len(self: *const Flag) usize {
        var l: usize = 0;
        if (self.short) |_| {
            l += 2;
        }

        if (self.long) |long| {
            l += long.len + 2;
        }

        if (self.short != null and self.long != null) {
            l += 2;
        }

        if (self.type == .argument) {
            l += 1 + 5;
        }

        return l;
    }
};

name: []const u8,
help: ?[]const u8 = null,
description: ?[]const u8 = null,
require_subcommand: bool = false,

flags: []const Flag = &.{},
subcommands: []const Self = &.{},

pub const SubcommandResult = struct {
    name: []const u8,
    result: *ParseResult,
};

pub const ParseResult = struct {
    flags: std.StringHashMap([]const u8),
    subcommand: ?SubcommandResult,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        self.flags.deinit();
        if (self.subcommand) |command| {
            command.result.deinit();

            self.allocator.destroy(command.result);
        }
    }

    pub fn get(self: *const ParseResult, key: []const u8) ?[]const u8 {
        return self.flags.get(key);
    }
};

pub fn parse(self: *const Self, allocator: std.mem.Allocator) !ParseResult {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    var argsIter = try std.process.argsWithAllocator(allocator);
    while (argsIter.next()) |arg| {
        try args.append(arg);
    }

    var parents = [_][]const u8{args.items[0]};
    return try self.parseInner(allocator, parents[0..], args.items[1..]);
}

fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) {
        return false;
    }

    for (b, 0..) |expected, i| {
        const actual = a[i];
        if (actual != expected) {
            return false;
        }
    }

    return true;
}

const FlagInstance = struct {
    flag: Flag,
    value: ?[]const u8 = null,
    consume: usize = 0,
};

fn findFlag(self: *const Self, args: [][]const u8) ?FlagInstance {
    const arg = args[0];
    if (startsWith(arg, "--")) {
        for (self.flags) |flag| {
            if (flag.long) |long| {
                if (startsWith(arg[2..], long)) {
                    if (arg.len > 2 + long.len) {
                        if (arg[2 + long.len] != '=') {
                            continue;
                        }

                        if (flag.type == .flag) {
                            std.debug.print("ermm no value for this flag: --{s}\n", .{long});
                            std.process.exit(1);
                        }

                        const value = arg[(2 + long.len + 1)..];
                        return FlagInstance{
                            .flag = flag,
                            .value = value,
                        };
                    }

                    if (flag.type == .argument) {
                        return FlagInstance{
                            .flag = flag,
                            .value = args[1],
                            .consume = 1,
                        };
                    }

                    return FlagInstance{
                        .flag = flag,
                    };
                }
            }
        }
    } else if (startsWith(arg, "-")) {
        for (self.flags) |flag| {
            if (flag.short) |short| {
                if (startsWith(arg[1..], &.{short})) {
                    if (arg.len > 2) {
                        if (arg[2] != '=') {
                            continue;
                        }

                        if (flag.type == .flag) {
                            std.debug.print("ermm no value for this flag: -{c}\n", .{short});
                            std.process.exit(1);
                        }

                        const value = arg[3..];
                        return FlagInstance{
                            .flag = flag,
                            .value = value,
                        };
                    }

                    if (flag.type == .argument) {
                        return FlagInstance{
                            .flag = flag,
                            .value = args[1],
                            .consume = 1,
                        };
                    }

                    return FlagInstance{
                        .flag = flag,
                    };
                }
            }
        }
    }

    return null;
}

fn parseInner(self: *const Self, allocator: std.mem.Allocator, parents: [][]const u8, args: [][]const u8) !ParseResult {
    var flags = std.StringHashMap([]const u8).init(allocator);

    // var i: usize = if (parents.len == 0) 1 else 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (self.findFlag(args[i..])) |flagInstance| {
            i += flagInstance.consume;

            const flag = flagInstance.flag;
            if (flag.long) |long| {
                if (std.mem.eql(u8, long, "help")) {
                    self.describe(parents);
                    std.process.exit(0);
                }
            }

            const flagName = flag.long orelse &.{flag.short orelse unreachable};
            try flags.put(flagName, flagInstance.value orelse "true");
            continue;
        }

        for (self.subcommands) |command| {
            if (std.mem.eql(u8, args[i], command.name)) {
                if (std.mem.eql(u8, command.name, "help")) {
                    self.describe(parents);
                    std.process.exit(0);
                }

                var childParents = std.ArrayList([]const u8).init(allocator);
                defer childParents.deinit();

                try childParents.appendSlice(parents);
                try childParents.append(command.name);

                const subcommandResult = try allocator.create(ParseResult);
                subcommandResult.* = try command.parseInner(allocator, childParents.items, args[(i + 1)..]);

                return .{
                    .allocator = allocator,
                    .flags = flags,
                    .subcommand = .{
                        .name = command.name,
                        .result = subcommandResult,
                    },
                };
            }
        }

        std.debug.print("failed to understand argument: {s}\n", .{args[i]});
        std.process.exit(1);
    }

    if (self.require_subcommand) {
        self.describe(parents);
        std.process.exit(1);
    }

    return .{
        .allocator = allocator,
        .flags = flags,
        .subcommand = null,
    };
}

pub fn describe(self: *const Self, parents: [][]const u8) void {
    std.debug.print("{s}", .{parents[0]});
    for (parents[1..]) |parent| {
        std.debug.print(" {s}", .{parent});
    }

    // if (parents.len == 0) {
    //
    // } else {
    //     std.debug.print("{s}", .{self.name});
    // }

    if (self.flags.len > 0) {
        std.debug.print(" [options]", .{});
    }

    if (self.subcommands.len > 0) {
        if (self.require_subcommand) {
            std.debug.print(" <command>", .{});
        } else {
            std.debug.print(" [command]", .{});
        }
    }

    std.debug.print("\n", .{});

    if (self.description) |description| {
        std.debug.print("\n{s}\n", .{description});
    }

    if (self.subcommands.len > 0) {
        self.describeCommands();
    }

    if (self.flags.len > 0) {
        self.describeFlags();
    }
}

fn describeFlags(self: *const Self) void {
    var max: usize = 0;
    for (self.flags) |flag| {
        const len = flag.len();
        if (len > max) {
            max = len;
        }
    }

    std.debug.print("\nOptions:\n", .{});
    for (self.flags) |flag| {
        std.debug.print("  ", .{});
        if (flag.short) |short| {
            std.debug.print("-{c}", .{short});
        }

        if (flag.short != null and flag.long != null) {
            std.debug.print(", ", .{});
        }

        if (flag.long) |long| {
            std.debug.print("--{s}", .{long});
        }

        if (flag.type == .argument) {
            std.debug.print(" value", .{});
        }

        if (flag.description) |description| {
            const paddingLen = max - flag.len() + 2;
            for (0..paddingLen) |_| {
                std.debug.print(" ", .{});
            }

            std.debug.print("{s}", .{description});
        }

        std.debug.print("\n", .{});
    }
}

fn describeCommands(self: *const Self) void {
    var max: usize = 0;
    for (self.subcommands) |command| {
        const len = command.name.len;
        if (len > max) {
            max = len;
        }
    }

    std.debug.print("\nSubcommands:\n", .{});
    for (self.subcommands) |command| {
        std.debug.print("  {s}", .{command.name});

        if (command.help) |help| {
            const padding = max - command.name.len + 2;
            for (0..padding) |_| {
                std.debug.print(" ", .{});
            }

            std.debug.print("{s}", .{help});
        }

        std.debug.print("\n", .{});
    }
}
