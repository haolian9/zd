const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const output_dir = b.pathJoin(&.{ b.env_map.get("HOME").?, "bin" });

    const enable_fzf = b.option(bool, "fzf", "enable fzf feature") orelse true;
    const single_threaded = true;
    const strip = mode == .Debug;

    const features = b.addOptions();
    features.addOption(bool, "fzf", enable_fzf);

    const exe = b.addExecutable("zd", "src/main.zig");

    {
        exe.setTarget(target);
        exe.addOptions("features", features);
        exe.setBuildMode(mode);
        exe.setOutputDir(output_dir);
        exe.single_threaded = single_threaded;
        exe.strip = strip;
        exe.install();
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(blk: {
        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        break :blk &run_cmd.step;
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(blk: {
        const exe_tests = b.addTest("src/main.zig");
        exe_tests.addOptions("features", features);
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        exe_tests.single_threaded = single_threaded;
        exe.strip = strip;
        break :blk &exe_tests.step;
    });
}
