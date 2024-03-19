const std = @import("std");

const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

// Each archive must contain directory `publish_dir`.
pub const publish_dir = "publish";

pub fn readFile(allocator: Allocator, sub_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(sub_path, .{});
    defer file.close();

    const max_size = 1024 * 1024 * 200;
    const contents = try file.reader().readAllAlloc(allocator, max_size);
    return contents;
}

pub fn hashFile(allocator: Allocator, sub_path: []const u8) ![Sha256.digest_length * 2]u8 {
    // TODO: There's no need to read whole contents into memory.
    const contents = try readFile(allocator, sub_path);
    defer allocator.free(contents);

    var hash: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(contents, &hash, .{});

    var hex_hash: [Sha256.digest_length * 2]u8 = undefined;
    _ = std.fmt.bufPrint(&hex_hash, "{s}", .{std.fmt.fmtSliceHexLower(&hash)}) catch {
        @panic("Absurd");
    };

    return hex_hash;
}
