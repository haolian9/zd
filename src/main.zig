const std = @import("std");
const assert = std.debug.assert;
const linux = std.os.linux;
const os = std.os;
const fs = std.fs;
const mem = std.mem;

const exec = @import("exec.zig");
const fzy = @import("fzy.zig");

var facts: Facts = undefined;

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

fn cmdListAll() !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.SH);
    defer lock.deinit();

    var file = fs.openFileAbsolute(facts.dbpath, .{}) catch |err| switch (err) {
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

fn cmdAddOne(path: []const u8) !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.EX);
    defer lock.deinit();

    const fd = try os.open(facts.dbpath, linux.O.RDWR | linux.O.CREAT, linux.S.IRUSR | linux.S.IWUSR);
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

fn cmdClear() !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.EX);
    defer lock.deinit();

    return os.unlink(facts.dbpath) catch |err| switch (err) {
        error.FileNotFound => {},
        else => err,
    };
}

fn cmdFzf(allocator: mem.Allocator) !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.SH);
    defer lock.deinit();

    const result = try exec.stdoutonly(.{
        .allocator = allocator,
        .argv = &.{ "fzf", "--layout=reverse", "--height=30%", "--min-height=5", "--input-file", facts.dbpath },
    });
    defer allocator.free(result.stdout);

    switch (result.term) {
        .Exited => |exited| switch (exited) {
            0 => try std.fmt.format(std.io.getStdOut().writer(), "cd {s}", .{result.stdout}),
            1 => {},
            else => {},
        },
        else => unreachable,
    }
}

fn cmdFzy(allocator: mem.Allocator) !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.SH);
    defer lock.deinit();
    var options = fzy.Options{
        .input_file = facts.dbpath,
    };
    const output = fzy.launch(allocator, &options) catch |err| switch (err) {
        error.NoMatch => return {},
        else => return err,
    };
    defer allocator.free(output);
    try std.fmt.format(std.io.getStdOut().writer(), "cd {s}", .{output});
}

pub fn main() !void {
    var args = std.process.ArgIteratorPosix.init();
    assert(args.skip());

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    facts = try Facts.init(allocator);
    defer facts.deinit();

    if (args.next()) |subcmd| {
        if (mem.eql(u8, subcmd, "add") or mem.eql(u8, subcmd, ".")) {
            if (args.next()) |path| {
                if (mem.eql(u8, path, "/")) {
                    try cmdAddOne(path);
                } else {
                    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                    try cmdAddOne(try os.realpath(path, &buf));
                }
            } else {
                var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                const path = try os.getcwd(&buf);
                try cmdAddOne(path);
            }
        } else if (mem.eql(u8, subcmd, "clear")) {
            try cmdClear();
        } else if (mem.eql(u8, subcmd, "fzf")) {
            try cmdFzf(allocator);
        } else if (mem.eql(u8, subcmd, "fzy")) {
            try cmdFzy(allocator);
        } else if (mem.eql(u8, subcmd, "list")) {
            try cmdListAll();
        } else {
            std.log.warn("unknown subcmd: {s}", .{subcmd});
        }
    } else {
        try cmdFzf(allocator);
    }
}
