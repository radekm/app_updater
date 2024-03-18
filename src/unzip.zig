const std = @import("std");
const shared = @import("shared.zig");

const Allocator = std.mem.Allocator;

// Unzip implementation based on:
// - https://pkware.cachefly.net/webdocs/APPNOTE/APPNOTE-2.0.txt
// - https://users.cs.jmu.edu/buchhofp/forensics/formats/pkzip.html
//
// Implementation of `is_dir` comes from 7-Zip source code.

const Error = error{
    UnexpectedEndOfCentralDirRecord,
    UnexpectedCentralFileHeader,
    UnexpectedLocalFileHeader,
    MismatchBetweenFileHeaders,
    DangerousFilename, // TODO: Validate filenames.
    CorruptedData,
    EndOfStream,
};

fn readU16(reader: anytype) !u16 {
    return reader.readInt(u16, std.builtin.Endian.little);
}

fn readU32(reader: anytype) !u32 {
    return reader.readInt(u32, std.builtin.Endian.little);
}

// Returned slice is non-owned. It lies inside `fbs.buffer`.
fn getSlice(fbs: *std.io.FixedBufferStream([]const u8), len: u32) ![]const u8 {
    const remaining = fbs.buffer.len - fbs.pos;
    if (remaining < len)
        return Error.EndOfStream;
    const result = fbs.buffer[fbs.pos .. fbs.pos + len];
    try fbs.seekBy(len);
    return result;
}

// -----------------------------------------------------
// Reading End of central directory record

const CentralDir = struct {
    num_entries: u16,
    size: u32,
    offset: u32,
};

fn readEndOfCentralDirRecord(zip: []const u8) !CentralDir {
    const record_size = 22;
    // ZIP is so small that it can't contain End of central directory record.
    if (zip.len < record_size)
        return Error.UnexpectedEndOfCentralDirRecord;

    var fbs = std.io.fixedBufferStream(zip);
    // Comment at the end of the ZIP is not allowed. So we can start reading the record
    // at `zip.len - record_size`.
    const start = zip.len - record_size;
    // TODO: Error set is empty. Can we somehow shorten the code for error handling?
    fbs.seekTo(start) catch |e| switch (e) {};
    const reader = fbs.reader();

    const exp_signature = 0x06_05_4b_50; // "PK\x05\x06" in little endian (ie. reversed).
    if (try readU32(reader) != exp_signature)
        return Error.UnexpectedEndOfCentralDirRecord;
    // Number of this disk must be 0 - we don't support archives with multiple disks.
    if (try readU16(reader) != 0)
        return Error.UnexpectedEndOfCentralDirRecord;
    // Number of the disk where central directory starts must be 0 -
    // we don't support archives with multiple disks.
    if (try readU16(reader) != 0)
        return Error.UnexpectedEndOfCentralDirRecord;
    // Number of central directory entries on this disk.
    const num_entries = try readU16(reader);
    // Total number of entries in central directory must be same
    // as number of central directory entries on this disk -
    // because we don't support archives with multiple disks.
    if (try readU16(reader) != num_entries)
        return Error.UnexpectedEndOfCentralDirRecord;
    // Size of central directory.
    const size = try readU32(reader);
    // Offset where central directory starts.
    const offset = try readU32(reader);
    // Comment for ZIP is not allowed so its length must be 0.
    if (try readU16(reader) != 0)
        return Error.UnexpectedEndOfCentralDirRecord;

    // Central directory must start before End of central directory record and
    // must not overlap with it.
    // NOTE: We can't check this in `unzip` function because `unzip` doesn't know about `start`.
    if (offset < start and start - offset >= size) {
        return .{
            .num_entries = num_entries,
            .size = size,
            .offset = offset,
        };
    } else return Error.UnexpectedEndOfCentralDirRecord;
}

// -----------------------------------------------------
// Reading Central file header

const Compression = enum(u16) { uncompressed = 0, deflate = 8 };

// Ported from 7-Zip.
const OS = enum(u8) {
    fat = 0,
    amiga,
    vms,
    unix,
    vm_cms,
    atari,
    hpfs,
    mac,
    z_system,
    cpm,
    tops20,
    ntfs,
    qdos,
    acorn,
    vfat,
    mvs,
    beos,
    tandem,
    unknown = 255,
};

// Ported from 7-Zip.
fn is_dir(
    version_made_by: u16,
    compressed_size: u32,
    uncompressed_size: u32,
    external_file_attrs: u32,
    filename: []const u8,
) !bool {
    if (std.mem.endsWith(u8, filename, "/"))
        return true;

    const host_os = std.meta.intToEnum(OS, version_made_by >> 8) catch {
        return Error.UnexpectedCentralFileHeader;
    };
    if (compressed_size == 0 and uncompressed_size == 0 and std.mem.endsWith(u8, filename, "\\")) {
        switch (host_os) {
            OS.fat, OS.ntfs, OS.hpfs, OS.vfat => return true,
            else => {},
        }
    }

    const high_attrs = external_file_attrs >> 16;
    switch (host_os) {
        OS.amiga => {
            const amiga_file_type_mask = 0o06000;
            const amiga_dir = 0o04000;
            const amiga_file = 0o02000;
            switch (high_attrs & amiga_file_type_mask) {
                amiga_dir => return true,
                amiga_file => return false,
                else => return Error.UnexpectedCentralFileHeader,
            }
        },
        OS.fat, OS.ntfs, OS.hpfs, OS.vfat => {
            // This comes from DOS or Windows header files.
            const file_attribute_directory = 16;
            return external_file_attrs & file_attribute_directory != 0;
        },
        OS.atari,
        OS.mac,
        OS.vms,
        OS.vm_cms,
        OS.acorn,
        OS.mvs,
        => return Error.UnexpectedCentralFileHeader,
        OS.unix => {
            const unix_file_type_mask = 0o00170000; // S_IFMT
            const unix_dir = 0o0040000; // S_IFDIR
            return high_attrs & unix_file_type_mask == unix_dir;
        },
        else => return false,
    }
}

const CentralFileHeader = struct {
    compression: Compression,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    is_dir: bool,
    filename: []const u8,
    local_file_header_offset: u32,
};

fn readCentralFileHeader(fbs: *std.io.FixedBufferStream([]const u8)) !CentralFileHeader {
    const reader = fbs.reader();

    // "PK\x01\x02" in little endian (ie. reversed).
    const exp_signature = 0x02_01_4b_50;
    if (try readU32(reader) != exp_signature)
        return Error.UnexpectedCentralFileHeader;
    // Version made by is only used to extract host os.
    const version_made_by = try readU16(reader);
    // Ignore version needed to extract.
    _ = try readU16(reader);
    // General-purpose bit flag is not supported.
    if (try readU16(reader) != 0)
        return Error.UnexpectedCentralFileHeader;
    // Compression method.
    const compression = std.meta.intToEnum(Compression, try readU16(reader)) catch {
        return Error.UnexpectedCentralFileHeader;
    };
    if (compression != Compression.uncompressed and compression != Compression.deflate) {
        return Error.UnexpectedCentralFileHeader;
    }
    // Last modification time and date are ignored.
    _ = try readU16(reader);
    _ = try readU16(reader);

    const crc32 = try readU32(reader);
    const compressed_size = try readU32(reader);
    const uncompressed_size = try readU32(reader);

    const filename_len = try readU16(reader);
    const extra_field_len = try readU16(reader);
    const file_comment_len = try readU16(reader);

    // Disk number start must be 0 because archives with multiple disks are not supported.
    if (try readU16(reader) != 0)
        return Error.UnexpectedCentralFileHeader;
    // Ignore internal file attributes.
    _ = try readU16(reader);
    // External file attributes are only used to detect whether the item is a file or directory.
    const external_file_attrs = try readU32(reader);
    const local_file_header_offset = try readU32(reader);

    // Read variable length fields.
    const filename = try getSlice(fbs, filename_len);
    _ = try getSlice(fbs, extra_field_len);
    _ = try getSlice(fbs, file_comment_len);

    return .{
        .compression = compression,
        .crc32 = crc32,
        .compressed_size = compressed_size,
        .uncompressed_size = uncompressed_size,
        .is_dir = try is_dir(
            version_made_by,
            compressed_size,
            uncompressed_size,
            external_file_attrs,
            filename,
        ),
        .filename = filename,
        .local_file_header_offset = local_file_header_offset,
    };
}

// -----------------------------------------------------
// Reading Local file header

const LocalFileHeader = struct {
    compression: Compression,
    crc32: u32,
    uncompressed_size: u32,
    filename: []const u8,
    compressed_data: []const u8,
};

fn readLocalFileHeader(fbs: *std.io.FixedBufferStream([]const u8)) !LocalFileHeader {
    const reader = fbs.reader();

    // "PK\x03\x04" in little endian (ie. reversed).
    const exp_signature = 0x04_03_4b_50;
    if (try readU32(reader) != exp_signature)
        return Error.UnexpectedLocalFileHeader;
    // Ignore version needed to extract.
    _ = try readU16(reader);
    // General-purpose bit flag is not supported and must be 0.
    // This means that we don't support Data descriptor
    // (because that is indicated by non-zero bit 3 of general-purpose bit flag).
    if (try readU16(reader) != 0)
        return Error.UnexpectedLocalFileHeader;
    // Compression method.
    const compression = std.meta.intToEnum(Compression, try readU16(reader)) catch {
        return Error.UnexpectedLocalFileHeader;
    };
    if (compression != Compression.uncompressed and compression != Compression.deflate) {
        return Error.UnexpectedLocalFileHeader;
    }
    // Last modification time and date are ignored.
    _ = try readU16(reader);
    _ = try readU16(reader);

    const crc32 = try readU32(reader);
    const compressed_size = try readU32(reader);
    const uncompressed_size = try readU32(reader);

    const filename_len = try readU16(reader);
    const extra_field_len = try readU16(reader);

    // Read variable length fields.
    const filename = try getSlice(fbs, filename_len);
    _ = try getSlice(fbs, extra_field_len);
    const compressed_data = try getSlice(fbs, compressed_size);

    return .{
        .compression = compression,
        .crc32 = crc32,
        .uncompressed_size = uncompressed_size,
        .filename = filename,
        .compressed_data = compressed_data,
    };
}

// -----------------------------------------------------
// Unzipping

fn crc32File(allocator: Allocator, dest_dir: std.fs.Dir, sub_path: []const u8) !u32 {
    // TODO: There's no need to read whole contents into memory.
    const file = try dest_dir.openFile(sub_path, .{});
    defer file.close();

    const max_size = 1024 * 1024 * 200;
    const contents = try file.reader().readAllAlloc(allocator, max_size);
    defer allocator.free(contents);

    return std.hash.Crc32.hash(contents);
}

// TODO: Ensure that file data and local file headers don't overlap.
// TODO: We should check that paths and filenames are reasonable.
//       Currently this program can be probably manipulated to unzip files into weird places.
// NOTE: We don't intentionally check for duplicate files or directories.
//       The reason is that it's hard because differences in operating systems.
pub fn unzip(
    allocator: Allocator,
    archive_sub_path: []const u8,
    dest_dir_sub_path: []const u8,
) !void {
    const zip: []const u8 = try shared.readFile(allocator, archive_sub_path);
    defer allocator.free(zip);

    const central_dir = try readEndOfCentralDirRecord(zip);
    std.debug.print("Central directory has size {}, starts at {} and contains {} entries\n", .{
        central_dir.size,
        central_dir.offset,
        central_dir.num_entries,
    });

    // Central directory is read sequentially.
    var central_dir_fbs = std.io.fixedBufferStream(
        zip[central_dir.offset .. central_dir.offset + central_dir.size],
    );

    const dest_dir = try std.fs.cwd().makeOpenPath(dest_dir_sub_path, .{});

    for (0..central_dir.num_entries) |_| {
        const central_header = try readCentralFileHeader(&central_dir_fbs);
        // Ensure that Local file header is before Central directory.
        // NOTE: We can't check it in `readCentralFileHeader` because
        //       `readCentralFileHeader` doesn't know where Central directory starts.
        if (central_header.local_file_header_offset >= central_dir.offset)
            return Error.UnexpectedCentralFileHeader;
        var local_fbs = std.io.fixedBufferStream(
            zip[central_header.local_file_header_offset..central_dir.offset],
        );

        // TODO: Check whether filename is dangerous/suspicious.

        const local_header = try readLocalFileHeader(&local_fbs);

        if (central_header.compression != local_header.compression or
            central_header.crc32 != local_header.crc32 or
            central_header.compressed_size != local_header.compressed_data.len or
            central_header.uncompressed_size != central_header.uncompressed_size or
            !std.mem.eql(u8, central_header.filename, local_header.filename))
        {
            return Error.MismatchBetweenFileHeaders;
        }

        if (central_header.is_dir) {
            std.debug.print("Creating directory {s}\n", .{central_header.filename});
            try dest_dir.makePath(central_header.filename);
        } else {
            std.debug.print("Decompressing file {s} (compression {})\n", .{
                central_header.filename,
                central_header.compression,
            });
            // Ensure that parent directory exists.
            if (std.fs.path.dirname(central_header.filename)) |dir| {
                try dest_dir.makePath(dir);
            }

            // After this block file is written and flushed to disk and we can check CRC-32.
            {
                const dest_file = try dest_dir.createFile(central_header.filename, .{});
                defer dest_file.close();

                switch (central_header.compression) {
                    Compression.uncompressed => {
                        var fbs = std.io.fixedBufferStream(local_header.compressed_data);
                        const reader = fbs.reader();
                        // TODO: Can we reuse `LinearFifo`? If so do it.
                        var fifo = std.fifo.LinearFifo(u8, .Dynamic).init(allocator);
                        defer fifo.deinit();
                        try fifo.ensureTotalCapacity(4096);
                        try fifo.pump(reader, dest_file.writer());
                    },
                    Compression.deflate => {
                        var fbs = std.io.fixedBufferStream(local_header.compressed_data);
                        try std.compress.flate.decompress(fbs.reader(), dest_file.writer());
                    },
                }
            }

            const crc32 = try crc32File(allocator, dest_dir, central_header.filename);
            if (crc32 != central_header.crc32)
                return Error.CorruptedData;
        }
    }
    std.debug.print("{} entries decompressed\n", .{central_dir.num_entries});
}
