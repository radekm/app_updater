const std = @import("std");
const http = std.http;
const shared = @import("shared.zig");
const unzip = @import("unzip.zig");

const Allocator = std.mem.Allocator;

// Returns `false` iff remote hash can't be downloaded or both remote and local hashes are equal.
pub fn updateNeeded(allocator: Allocator, host: []const u8, port: u16, archive: []const u8) bool {
    const local_hex_hash = shared.hashFile(allocator, archive) catch |e| {
        std.debug.print("Can't compute local hash {} of {s}\n", .{ e, archive });
        return true;
    };

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const hash_url = std.fmt.allocPrint(
        allocator,
        "http://{s}:{}/hash?archive={s}",
        .{ host, port, archive },
    ) catch @panic("Can't format URL");
    defer allocator.free(hash_url);

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();
    const result = client.fetch(.{
        .location = .{ .url = hash_url },
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 2048, // Hash is short.
    }) catch |e| {
        std.debug.print("Can't fetch remote hash {}\n", .{e});
        return false;
    };
    if (result.status != std.http.Status.ok) {
        return false;
    }

    const remote_hex_hash = body.items;

    std.debug.print("Local hash {s}, remote hash {s}\n", .{ local_hex_hash, remote_hex_hash });
    return !std.mem.eql(u8, remote_hex_hash, &local_hex_hash);
}

const UpdateError = error{NotOkHttpStatus};

pub fn update(allocator: Allocator, host: []const u8, port: u16, archive: []const u8, executable: []const u8) !void {
    const new_publish_archive = try std.fmt.allocPrint(allocator, "new-{s}", .{archive});
    defer allocator.free(new_publish_archive);

    const temp_dir = "temp";

    std.debug.print("Deleting temporaries\n", .{});
    std.fs.cwd().deleteFile(new_publish_archive) catch |e| {
        // Ignore file not found error.
        if (e != std.fs.Dir.DeleteFileError.FileNotFound)
            return e;
    };
    try std.fs.cwd().deleteTree(temp_dir);

    std.debug.print("Downloading archive {s} as {s}\n", .{ archive, new_publish_archive });
    {
        var client = http.Client{ .allocator = allocator };
        defer client.deinit();
        const download_url = std.fmt.allocPrint(
            allocator,
            "http://{s}:{}/download?archive={s}",
            .{ host, port, archive },
        ) catch @panic("Can't format URL");
        defer allocator.free(download_url);

        var body = std.ArrayList(u8).init(allocator);
        defer body.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = download_url },
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 1024 * 1024 * 200,
        });
        if (result.status != std.http.Status.ok) {
            return UpdateError.NotOkHttpStatus;
        }

        const file = try std.fs.cwd().createFile(new_publish_archive, .{});
        defer file.close();
        try file.writeAll(body.items);
    }

    try unzip.unzip(allocator, new_publish_archive, temp_dir);

    std.debug.print("Making file executable\n", .{});
    {
        const path = try std.fs.path.join(allocator, &[_][]const u8{
            temp_dir,
            shared.publish_dir,
            executable,
        });
        defer allocator.free(path);

        // Opening the executable ensures that it exists.
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        if (std.fs.has_executable_bit) {
            const metadata = try file.metadata();
            var permissions = metadata.permissions();
            permissions.inner.unixSet(.user, .{ .execute = true });
            try file.setPermissions(permissions);
        }
    }

    std.debug.print("Replacing current version with new version\n", .{});
    {
        const temp_publish_dir = try std.fs.path.join(allocator, &[_][]const u8{
            temp_dir,
            shared.publish_dir,
        });
        defer allocator.free(temp_publish_dir);

        try std.fs.cwd().deleteTree(shared.publish_dir);
        try std.fs.cwd().rename(temp_publish_dir, shared.publish_dir);
        std.fs.cwd().deleteFile(archive) catch |e| {
            // Ignore file not found error.
            if (e != std.fs.Dir.DeleteFileError.FileNotFound)
                return e;
        };
        try std.fs.cwd().rename(new_publish_archive, archive);
    }

    std.debug.print("Deleting temporaries\n", .{});
    try std.fs.cwd().deleteTree(temp_dir);
}

const MainError = error{NotEnoughArguments};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 5) {
        return MainError.NotEnoughArguments;
    }
    const host = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);
    const archive = args[3];
    const executable = args[4]; // Program to run inside `publish_dir`.

    if (updateNeeded(allocator, host, port, archive)) {
        update(allocator, host, port, archive, executable) catch |e| {
            std.debug.print("Updating failed with {}\n", .{e});
        };
    }

    // Execute application.
    const app_path = try std.fs.path.join(allocator, &[_][]const u8{
        shared.publish_dir,
        executable,
    });
    defer allocator.free(app_path);
    std.debug.print("Executing {s}\n", .{app_path});
    var app = std.ChildProcess.init(&[_][]const u8{app_path}, allocator);
    if (app.spawnAndWait()) |term| {
        std.debug.print("Result: {}\n", .{term});
    } else |e| {
        std.debug.print("Cannot spawn process: {}\n", .{e});
    }
}
