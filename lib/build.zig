const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("hecl_gterm.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ghostty-vt dependency
    if (b.lazyDependency("ghostty", .{
        .@"emit-xcframework" = false,
        .@"emit-macos-app" = false,
        .@"emit-exe" = false,
    })) |dep| {
        lib_mod.addImport("ghostty-vt", dep.module("ghostty-vt"));
    }

    const lib = b.addLibrary(.{
        .name = "hecl-gterm",
        .linkage = .dynamic,
        .root_module = lib_mod,
    });

    b.installArtifact(lib);
}
