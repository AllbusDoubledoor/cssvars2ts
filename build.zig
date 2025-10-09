const std = @import("std");

const NAME = "cssvars2ts";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Install
    const mainModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = NAME,
        .root_module = mainModule,
    });

    b.installDirectory(.{
        .source_dir = b.path("src/test/assets"),
        .install_dir = .{ .custom = "test" },
        .install_subdir = "assets",
    });

    b.installArtifact(exe);

    // Run
    const run_installed = b.addSystemCommand(&.{
        b.pathJoin(&.{ b.install_prefix, "bin", NAME }),
    });
    run_installed.step.dependOn(b.getInstallStep());

    b.step("run", "Build and run the program").dependOn(&run_installed.step);
}
