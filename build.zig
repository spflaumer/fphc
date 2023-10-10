const std = @import("std");

pub fn build(b: *std.Build) !void {
        // executable
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
        const exe = b.addExecutable(.{
                .name = "fphc",
                .root_source_file = .{ .path = "src/main.zig" },
                .target = target,
                .optimize = optimize,
        });
        b.installArtifact(exe);

        // modules
        const zig_clap = b.createModule(.{
                .source_file = .{ .path = "zig-clap/clap.zig" }
        });

        // add modules to exe
        exe.addModule("zig_clap", zig_clap);

        // steps
        const artifact_step = b.addRunArtifact(exe);
        if(b.args) |args| artifact_step.addArgs(args);

        const run_step = b.step("run", "run the app");
        run_step.dependOn(&artifact_step.step);
}