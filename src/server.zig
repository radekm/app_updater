const std = @import("std");
const httpz = @import("httpz");
const shared = @import("shared.zig");

const Error = error{NotEnoughArguments};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3) {
        return Error.NotEnoughArguments;
    }
    const address = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);

    var server = try httpz.Server().init(
        allocator,
        .{ .address = address, .port = port },
    );
    defer server.deinit();

    const router = server.router();
    router.get("/hash", getHash);
    router.get("/download", getFile);

    std.debug.print("Starting server\n", .{});

    // Start the server in the current thread, blocking.
    try server.listen();
}

// Either returns query parameter from `req` or `shared.default_publish_archive`.
fn getArchiveName(req: *httpz.Request) ![]const u8 {
    const query = try req.query();
    if (query.get("archive")) |archive| {
        var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and
                std.mem.endsWith(u8, entry.name, ".zip") and
                std.mem.eql(u8, entry.name, archive))
            {
                return archive;
            }
        }
    }

    return shared.default_publish_archive;
}

fn getHash(req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = httpz.ContentType.TEXT;
    const publish_archive = try getArchiveName(req);
    const hex_hash = try shared.hashFile(req.arena, publish_archive);
    std.debug.print("Computed hash {s} of file {s}\n", .{ hex_hash, publish_archive });
    try res.writer().writeAll(&hex_hash);
}

fn getFile(req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = httpz.ContentType.BINARY;
    const publish_archive = try getArchiveName(req);
    const contents = try shared.readFile(req.arena, publish_archive);
    std.debug.print("Sending file {s} with {} bytes\n", .{ publish_archive, contents.len });
    res.body = contents;
}
