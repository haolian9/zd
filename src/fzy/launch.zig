const std = @import("std");
const builtin = @import("builtin");
const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();
const stdin = std.io.getStdIn();

const Options = @import("Options.zig");
const Choices = @import("Choices.zig");
const Tty = @import("Tty.zig");
const TtyInterface = @import("TtyInterface.zig").TtyInterface;

pub const OutputWriter = std.io.FixedBufferStream([]u8);

pub fn launch(base_allocator: std.mem.Allocator, options: *Options) anyerror![]const u8 {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var file = std.fs.cwd().openFile(options.input_file, .{}) catch |err| return err;

    var choices = try Choices.init(allocator, options, file);
    defer choices.deinit();

    if (stdin.isTty()) {
        try choices.readAll();
    }

    var tty = try Tty.init(options.tty_filename);

    const num_lines_adjustment: usize = if (options.show_info) 2 else 1;
    if (options.num_lines + num_lines_adjustment > tty.max_height) {
        options.num_lines = tty.max_height - num_lines_adjustment;
    }

    const output_buffer = try base_allocator.alloc(u8, std.fs.MAX_PATH_BYTES);
    errdefer base_allocator.free(output_buffer);

    var buffered_writer = OutputWriter{ .buffer = output_buffer, .pos = 0 };
    const output_writer = buffered_writer.writer();

    var tty_interface = try TtyInterface(OutputWriter.Writer).init(allocator, &tty, &choices, options, output_writer);
    defer tty_interface.deinit();

    try tty_interface.draw(true);
    if (tty_interface.run()) |rc| {
        if (rc != 0) return error.AbnormalExit;
        return base_allocator.shrink(output_buffer, try buffered_writer.getEndPos());
    } else |err| return err;
}
