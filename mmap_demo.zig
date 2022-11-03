// ref
// * https://ravendb.net/articles/implementing-a-file-pager-in-zig-using-mmap
// * https://stackoverflow.com/questions/4991533/sharing-memory-between-processes-through-the-use-of-mmap
//

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const linux = std.os.linux;

pub fn main() !void {
    const path = "/dev/shm/zig-demo";
    const max_size = 64;

    const fd = try std.os.open(path, linux.O.RDWR | linux.O.CREAT | linux.O.TRUNC, linux.S.IRUSR | linux.S.IWUSR);
    // fixme
    try std.os.ftruncate(fd, 1024);
    var mem = try std.os.mmap(null, max_size, linux.PROT.READ | linux.PROT.WRITE, linux.MAP.SHARED, fd, 0);
    defer std.os.close(fd);
    defer std.os.munmap(mem);

    var arg_iter = std.process.ArgIteratorPosix.init();
    _ = arg_iter.skip();

    if (arg_iter.next()) |words| {
        // sender
        assert(words.len <= max_size);
        std.mem.copy(u8, mem[0..words.len], words);
    } else {
        // receiver
        while (true) {
            std.time.sleep(std.time.ns_per_s * 10);
            print("got {any}, {s}\n", .{ @TypeOf(mem), mem[0..5] });
        }
    }
}
