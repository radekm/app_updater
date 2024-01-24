const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_client = b.addExecutable(.{
        .name = "app-updater",
        .root_source_file = .{ .path = "src/client.zig" },
        .target = target,
        .optimize = optimize,
    });

    const build_client_step = b.step("client", "Build client");
    build_client_step.dependOn(&b.addInstallArtifact(exe_client, .{}).step);

    const exe_server = b.addExecutable(.{
        .name = "server",
        .root_source_file = .{ .path = "src/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    const dep_opts = .{ .target = target, .optimize = optimize };
    exe_server.root_module.addImport("httpz", b.dependency("httpz", dep_opts).module("httpz"));

    const build_server_step = b.step("server", "Build server");
    build_server_step.dependOn(&b.addInstallArtifact(exe_server, .{}).step);
}
