const std = @import("std");
const assert = std.debug.assert;
const linux = std.os.linux;
const os = std.os;
const fs = std.fs;
const exec = @import("exec.zig");

var facts: Facts = undefined;

const Facts = struct {
    allocator: std.mem.Allocator,
    dbpath: []const u8,
    lockpath: []const u8,

    const appname = "zd";
    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
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

    const fd = try os.open(facts.dbpath, linux.O.WRONLY | linux.O.CREAT | linux.O.APPEND, linux.S.IRUSR | linux.S.IWUSR);
    defer os.close(fd);

    const file = fs.File{ .handle = fd };

    try file.writeAll(path);
    try file.writeAll("\n");
}

fn cmdDiscardOne(path: []const u8) !void {
    _ = path;
}

fn cmdClear() !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.EX);
    defer lock.deinit();

    return os.unlink(facts.dbpath) catch |err| switch (err) {
        error.FileNotFound => {},
        else => err,
    };
}

fn cmdFzf(allocator: std.mem.Allocator) !void {
    const lock = try Lock.init(facts.lockpath, linux.LOCK.SH);
    defer lock.deinit();

    const result = try exec.stdoutonly(.{
        .allocator = allocator,
        .argv = &.{ "fzf", "--layout=reverse", "--height=30%", "--min-height=5", "--input-file", facts.dbpath },
    });
    defer allocator.free(result.stdout);

    const stdout = std.io.getStdOut().writer();
    switch (result.term) {
        .Exited => |exited| switch (exited) {
            0 => try std.fmt.format(stdout, "cd {s}", .{result.stdout}),
            1 => try std.fmt.format(stdout, "echo no match", .{}),
            else => {},
        },
        else => unreachable,
    }
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
        if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, ".")) {
            if (args.next()) |path| {
                if (std.mem.eql(u8, path, "/")) {
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
        } else if (std.mem.eql(u8, subcmd, "discard")) {
            if (args.next()) |path| {
                try cmdDiscardOne(path);
            } else {
                var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                const path = try os.getcwd(&buf);
                try cmdDiscardOne(path);
            }
        } else if (std.mem.eql(u8, subcmd, "clear")) {
            try cmdClear();
        } else if (std.mem.eql(u8, subcmd, "fzf")) {
            try cmdFzf(allocator);
        } else if (std.mem.eql(u8, subcmd, "list")) {
            try cmdListAll();
        } else {
            std.log.warn("unknown subcmd: {s}", .{subcmd});
        }
    } else {
        try cmdFzf(allocator);
    }
}
