const std = @import("std");
const assert = std.debug.assert;
const linux = std.os.linux;
const fs = std.fs;
const mem = std.mem;
const builtin = @import("builtin");
const posix = std.posix;

const exec = @import("exec.zig");

const Facts = struct {
    allocator: mem.Allocator,
    dbpath: []const u8,
    lockpath: []const u8,

    const appname = "zd";
    const Self = @This();

    fn init(allocator: mem.Allocator) !Self {
        const home_dir = std.posix.getenv("HOME") orelse {
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
    file: fs.File = undefined,
    /// lastQuery: 0..1024
    data: [1 << 10]u8 = undefined,

    const Self = @This();

    fn init(self: *Self, path: []const u8, op: i32) !void {
        const file = try fs.createFileAbsolute(path, .{ .read = true, .truncate = false });
        errdefer file.close();

        posix.flock(file.handle, op | linux.LOCK.NB) catch |err| return err;
        errdefer posix.flock(file.handle, linux.LOCK.UN) catch unreachable;

        try file.seekTo(0);
        for (&self.data) |*char| char.* = 0;
        _ = try file.readAll(&self.data);

        self.file = file;
    }

    fn deinit(self: Self) void {
        defer self.file.close();
        defer posix.flock(self.file.handle, linux.LOCK.UN) catch unreachable;

        self.file.seekTo(0) catch unreachable;
        self.file.writeAll(&self.data) catch unreachable;
    }

    fn getLastQuery(self: *Self) []const u8 {
        const end: usize = blk: {
            for (self.data[0..1024], 0..) |*char, ix| {
                if (char.* == 0) break :blk ix;
            }
            unreachable;
        };

        return self.data[0..end];
    }

    fn setLastQuery(self: *Self, query: []const u8) !void {
        if (query.len > 1024) return error.QueryTooLong;

        mem.copyForwards(u8, self.data[0..query.len], query);
        for (self.data[query.len..1024]) |*char| {
            if (char.* == 0) break;
            char.* = 0;
        }
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
        var lock = Lock{};
        try lock.init(self.facts.lockpath, linux.LOCK.SH);
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
        var lock = Lock{};
        try lock.init(self.facts.lockpath, linux.LOCK.EX);
        defer lock.deinit();

        var file = try fs.createFileAbsolute(self.facts.dbpath, .{ .read = true, .truncate = false });
        defer file.close();

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
        var lock = Lock{};
        try lock.init(self.facts.lockpath, linux.LOCK.EX);
        defer lock.deinit();

        return posix.unlink(self.facts.dbpath) catch |err| switch (err) {
            error.FileNotFound => {},
            else => err,
        };
    }

    fn tidy(self: Self) !void {
        var lock = Lock{};
        try lock.init(self.facts.lockpath, linux.LOCK.EX);
        defer lock.deinit();

        const src_path = self.facts.dbpath;
        var dest_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const dest_path = try std.fmt.bufPrint(&dest_buf, "{s}.bak", .{src_path});

        {
            var src_file = fs.openFileAbsolute(src_path, .{}) catch |err| switch (err) {
                error.FileNotFound => return,
                else => return err,
            };
            defer src_file.close();

            var dest_file = try fs.createFileAbsolute(dest_path, .{});
            defer dest_file.close();

            var reader = src_file.reader();
            var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
            while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |entry| {
                var ent_file = fs.openDirAbsolute(entry, .{ .access_sub_paths = false }) catch |err| {
                    std.log.warn("discarded: {s}; {any}", .{ entry, err });
                    continue;
                };
                defer ent_file.close();

                try dest_file.writeAll(entry);
                try dest_file.writeAll("\n");
            }
        }

        try fs.renameAbsolute(dest_path, src_path);
    }

    fn fzf(self: Self) !void {
        var lock = Lock{};
        try lock.init(self.facts.lockpath, linux.LOCK.SH);
        defer lock.deinit();

        const result = try exec.stdoutonly(.{
            .allocator = self.allocator,
            .argv = &.{
                "fzf",
                "--ansi",
                "--print-query",
                "--layout=reverse",
                "--height=30%",
                "--min-height=5",
                "--bind",
                "char:unbind(char)+clear-query+put", // placeholder&clear
                "--bind",
                "space:accept", // space is handy than <cr>/<c-m>
                "--input-file",
                self.facts.dbpath,
                "--query",
                lock.getLastQuery(),
            },
        });
        defer self.allocator.free(result.stdout);

        switch (result.term) {
            .Exited => |exited| switch (exited) {
                0 => {
                    assert(mem.endsWith(u8, result.stdout, "\n"));
                    var iter = mem.split(u8, result.stdout[0 .. result.stdout.len - 1], "\n");
                    if (iter.next()) |query| {
                        if (query.len > 0) try lock.setLastQuery(query);
                    } else return error.expectQuery;
                    if (iter.next()) |matched| {
                        try std.fmt.format(std.io.getStdOut().writer(), "cd {s}", .{matched});
                    } else return error.expectMatch;
                },
                1 => {},
                else => {},
            },
            else => unreachable,
        }
    }

    fn edit(self: Self) !void {
        const editor = posix.getenv("EDITOR") orelse "vi";
        return std.process.execv(self.allocator, &.{ editor, self.facts.dbpath });
    }
};

fn dispatchRun(allocator: mem.Allocator) !void {
    var args = std.process.ArgIteratorPosix.init();
    assert(args.skip());

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
                    try cmds.addOne(try posix.realpath(path, &buf));
                }
            } else {
                var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                const path = try posix.getcwd(&buf);
                try cmds.addOne(path);
            }
        } else if (mem.eql(u8, subcmd, "clear")) {
            try cmds.clear();
        } else if (mem.eql(u8, subcmd, "fzf")) {
            try cmds.fzf();
        } else if (mem.eql(u8, subcmd, "list")) {
            try cmds.listAll();
        } else if (mem.eql(u8, subcmd, "tidy")) {
            try cmds.tidy();
        } else if (mem.eql(u8, subcmd, "edit")) {
            try cmds.edit();
        } else {
            std.log.err("unknown subcmd: {s}", .{subcmd});
        }
    } else {
        try cmds.fzf();
    }
}

pub fn main() !void {
    if (builtin.mode == .Debug) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer assert(gpa.deinit() != .leak);
        const allocator = gpa.allocator();
        try dispatchRun(allocator);
    } else {
        try dispatchRun(std.heap.page_allocator);
    }
}
