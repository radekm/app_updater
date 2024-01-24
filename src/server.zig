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

fn getHash(req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = httpz.ContentType.TEXT;
    const hex_hash = try shared.hashFile(req.arena, shared.publish_archive);
    std.debug.print("Computed hash {s}\n", .{hex_hash});
    try res.writer().writeAll(&hex_hash);
}

fn getFile(req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = httpz.ContentType.BINARY;
    const contents = try shared.readFile(req.arena, shared.publish_archive);
    std.debug.print("Sending file with {} bytes\n", .{contents.len});
    res.body = contents;
}
