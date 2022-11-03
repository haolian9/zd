const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const EnvMap = std.process.EnvMap;
const Arg0Expand = std.os.Arg0Expand;
const ChildProcess = std.ChildProcess;
const builtin = std.builtin;
const os = std.os;

pub const ExecResult = struct {
    term: ChildProcess.Term,
    stdout: []u8,
};

pub fn stdoutonly(args: struct {
    allocator: mem.Allocator,
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    cwd_dir: ?fs.Dir = null,
    env_map: ?*const EnvMap = null,
    max_output_bytes: usize = 50 * 1024,
    expand_arg0: Arg0Expand = .no_expand,
}) !ExecResult {
    var child = ChildProcess.init(args.argv, args.allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.cwd = args.cwd;
    child.cwd_dir = args.cwd_dir;
    child.env_map = args.env_map;
    child.expand_arg0 = args.expand_arg0;

    try child.spawn();

    var stdout = std.ArrayList(u8).init(args.allocator);
    errdefer stdout.deinit();

    try collectOutputPosix(child, &stdout, args.max_output_bytes);

    return ExecResult{
        .term = try child.wait(),
        .stdout = stdout.toOwnedSlice(),
    };
}

fn collectOutputPosix(
    child: ChildProcess,
    stdout: *std.ArrayList(u8),
    max_output_bytes: usize,
) !void {
    var poll_fds = [_]os.pollfd{
        .{ .fd = child.stdout.?.handle, .events = os.POLL.IN, .revents = undefined },
    };

    var dead_fds: usize = 0;
    // We ask for ensureTotalCapacity with this much extra space. This has more of an
    // effect on small reads because once the reads start to get larger the amount
    // of space an ArrayList will allocate grows exponentially.
    const bump_amt = 512;

    const err_mask = os.POLL.ERR | os.POLL.NVAL | os.POLL.HUP;

    while (dead_fds < poll_fds.len) {
        const events = try os.poll(&poll_fds, std.math.maxInt(i32));
        if (events == 0) continue;

        var remove_stdout = false;
        // Try reading whatever is available before checking the error
        // conditions.
        // It's still possible to read after a POLL.HUP is received, always
        // check if there's some data waiting to be read first.
        if (poll_fds[0].revents & os.POLL.IN != 0) {
            // stdout is ready.
            const new_capacity = std.math.min(stdout.items.len + bump_amt, max_output_bytes);
            try stdout.ensureTotalCapacity(new_capacity);
            const buf = stdout.unusedCapacitySlice();
            if (buf.len == 0) return error.StdoutStreamTooLong;
            const nread = try os.read(poll_fds[0].fd, buf);
            stdout.items.len += nread;

            // Remove the fd when the EOF condition is met.
            remove_stdout = nread == 0;
        } else {
            remove_stdout = poll_fds[0].revents & err_mask != 0;
        }

        // Exclude the fds that signaled an error.
        if (remove_stdout) {
            poll_fds[0].fd = -1;
            dead_fds += 1;
        }
    }
}
