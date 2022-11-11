pub const Options = @import("fzy/Options.zig");

const std = @import("std");
const builtin = @import("builtin");

const Choices = @import("fzy/Choices.zig");
const Tty = @import("fzy/Tty.zig");
const TtyInterface = @import("fzy/TtyInterface.zig").TtyInterface;

const OutputWriter = std.io.FixedBufferStream([]u8);

pub fn launch(base_allocator: std.mem.Allocator, options: *Options) anyerror![]const u8 {
    var backing_allocator = if (builtin.mode == .Debug)
        std.heap.GeneralPurposeAllocator(.{}){}
    else
        std.heap.ArenaAllocator.init(base_allocator);

    defer if (builtin.mode == .Debug)
        std.debug.assert(!backing_allocator.deinit())
    else
        backing_allocator.deinit();

    const allocator = backing_allocator.allocator();

    const file = std.fs.cwd().openFile(options.input_file, .{}) catch |err| return err;
    var choices = try Choices.init(allocator, options, file);
    defer choices.deinit();

    try choices.readAll();

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

    switch (try tty_interface.run()) {
        0 => return base_allocator.shrink(output_buffer, try buffered_writer.getEndPos()),
        1 => return error.NoMatch,
        else => unreachable,
    }
}
