const std = @import("std");
const assert = std.debug.assert;
const linux = std.os.linux;
const os = std.os;
const fs = std.fs;
const mem = std.mem;

const exec = @import("exec.zig");
const fzylib = @import("fzy.zig");

const Facts = struct {
    allocator: mem.Allocator,
    dbpath: []const u8,
    lockpath: []const u8,

    const appname = "zd";
    const Self = @This();

    fn init(allocator: mem.Allocator) !Self {
        const home_dir = os.getenv("HOME") orelse {
            return error.AppCacheDirUnavailable;
        };

        const cache_dir = try fs.path.join(allocator, &[_][]const u8{ home_dir, ".cache", appname });
        defer allocator.free(cache_dir);

        fs.makeDirAbsolute(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const dbpath = try fs.path.join(allocator, &[_][]const u8{ cache_dir, "data" });
        const lockpath = try fs.path.join(allocator, &[_][]const u8{ cache_dir, "lock" });

        return Self{ .allocator = allocator, .dbpath = dbpath, .lockpath = lockpath };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.dbpath);
        self.allocator.free(self.lockpath);
    }
};

const Lock = struct {
    fd: os.fd_t,

    const Self = @This();

    fn init(path: []const u8, op: i32) !Self {
        const fd = os.open(path, linux.O.RDWR | linux.O.CREAT, linux.S.IRUSR | linux.S.IWUSR) catch |err| return err;
        os.flock(fd, op | linux.LOCK.NB) catch |err| return err;

        return Self{ .fd = fd };
    }

    fn deinit(self: Self) void {
        defer os.close(self.fd);
        os.flock(self.fd, linux.LOCK.UN) catch unreachable;
    }
};

/// contains cmd used in main()
/// all cmds should return `anyerror!void` for now
/// todo: exit code
const Cmds = struct {
    allocator: mem.Allocator,
    facts: Facts,

    const Self = @This();

    fn listAll(self: Self) !void {
        const lock = try Lock.init(self.facts.lockpath, linux.LOCK.SH);
        defer lock.deinit();

        var file = fs.openFileAbsolute(self.facts.dbpath, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        {
            const stdout = std.io.getStdOut().writer();
            const reader = file.reader();
            var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
            while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
                try stdout.writeAll(line);
                try stdout.writeAll("\n");
            }
        }
    }

    fn addOne(self: Self, path: []const u8) !void {
        const lock = try Lock.init(self.facts.lockpath, linux.LOCK.EX);
        defer lock.deinit();

        const fd = try os.open(self.facts.dbpath, linux.O.RDWR | linux.O.CREAT, linux.S.IRUSR | linux.S.IWUSR);
        defer os.close(fd);

        const file = fs.File{ .handle = fd };

        var found = false;

        {
            var reader = file.reader();
            var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
            while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
                found = mem.eql(u8, line, path);
                if (found) break;
            }
        }

        if (found) return;

        const stat = try file.stat();
        try file.seekTo(stat.size);
        try file.writeAll(path);
        try file.writeAll("\n");
    }

    fn clear(self: Self) !void {
        const lock = try Lock.init(self.facts.lockpath, linux.LOCK.EX);
        defer lock.deinit();

        return os.unlink(self.facts.dbpath) catch |err| switch (err) {
            error.FileNotFound => {},
            else => err,
        };
    }

    fn fzf(self: Self) !void {
        const lock = try Lock.init(self.facts.lockpath, linux.LOCK.SH);
        defer lock.deinit();

        const result = try exec.stdoutonly(.{
            .allocator = self.allocator,
            .argv = &.{ "fzf", "--layout=reverse", "--height=30%", "--min-height=5", "--input-file", self.facts.dbpath },
        });
        defer self.allocator.free(result.stdout);

        switch (result.term) {
            .Exited => |exited| switch (exited) {
                0 => try std.fmt.format(std.io.getStdOut().writer(), "cd {s}", .{result.stdout}),
                1 => {},
                else => {},
            },
            else => unreachable,
        }
    }

    fn fzy(self: Self) !void {
        const lock = try Lock.init(self.facts.lockpath, linux.LOCK.SH);
        defer lock.deinit();
        var options = fzylib.Options{
            .input_file = self.facts.dbpath,
        };
        const output = fzylib.launch(self.allocator, &options) catch |err| switch (err) {
            error.NoMatch => return {},
            else => return err,
        };
        defer self.allocator.free(output);
        try std.fmt.format(std.io.getStdOut().writer(), "cd {s}", .{output});
    }
};

pub fn main() !void {
    var args = std.process.ArgIteratorPosix.init();
    assert(args.skip());

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    const facts = try Facts.init(allocator);
    defer facts.deinit();

    const cmds = Cmds{ .allocator = allocator, .facts = facts };

    if (args.next()) |subcmd| {
        if (mem.eql(u8, subcmd, "add") or mem.eql(u8, subcmd, ".")) {
            if (args.next()) |path| {
                if (mem.eql(u8, path, "/")) {
                    try cmds.addOne(path);
                } else {
                    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                    try cmds.addOne(try os.realpath(path, &buf));
                }
            } else {
                var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                const path = try os.getcwd(&buf);
                try cmds.addOne(path);
            }
        } else if (mem.eql(u8, subcmd, "clear")) {
            try cmds.clear();
        } else if (mem.eql(u8, subcmd, "fzf")) {
            try cmds.fzf();
        } else if (mem.eql(u8, subcmd, "fzy")) {
            try cmds.fzy();
        } else if (mem.eql(u8, subcmd, "list")) {
            try cmds.listAll();
        } else {
            std.log.err("unknown subcmd: {s}", .{subcmd});
        }
    } else {
        try cmds.fzf();
    }
}
