// modules import
const std = @import("std");

// "shortcuts"
const sha = std.crypto.hash.sha3.Sha3_512;

/// read the entire file into one allocated buffer
/// caller owns the memory
fn readFileAlloc(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
        // open the file
        var file = try std.fs.cwd().openFile(filename, .{});
        // get file statistics
        var stat = try file.stat();
        // read everything from the file
        return try file.readToEndAlloc(allocator, stat.size + 1);
}

/// print implementation
/// does not return bytes written/printed
fn print(comptime format: []const u8, args: anytype) !void {
        var buffered_stdout = std.io.getStdOut();
        try buffered_stdout.writer().print(format, args);
}

/// get maximum of 255 characters of user input, or until '\n'
fn getUserIn(prompt: ?[]const u8, allocator: std.mem.Allocator) !?[]u8 {
        // print the prompt
        if(prompt) |p| try print("{s}", .{p});

        // get handle to stdin
        var stdin = std.io.getStdIn();
        return try stdin.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 255);
}

/// overwrites an existing file with new file contents
/// clears the file when contents are null
/// bytes written are not returned
fn writeFile(filename: []const u8, contents: []const u8) !void {
        var cwd = std.fs.cwd();
        _ = cwd.statFile(filename) catch |err| {
                try switch (err) {
                        error.FileNotFound => _ = try cwd.createFile(filename, .{}),
                        else => err,
                };
        };

        var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_write });
        _ = try file.writer().writeAll(contents);
}

pub fn main() !void {
        // initialize the arenaallocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        // read the input of the file
        var file_contents = try readFileAlloc("testfile.txt", arena.allocator());

        // create the hash
        var file_hash: [64]u8 = .{0}**64;
        sha.hash(file_contents, &file_hash, .{});

        // get user input
        var userin = try getUserIn("enter your password: ", arena.allocator());

        // hash user input
        var userin_hash: [64]u8 = .{0}**64;
        if(userin) |ui| sha.hash(ui, &userin_hash, .{});

        // combine both hashes
        var combined_hash: [128]u8 = .{0}**128;
        for (0..64) |i| {
                combined_hash[i] = userin_hash[i];
        }
        for (64..128) |i| {
                combined_hash[i] = file_hash[i-64];
        }

        // hash the combined hash
        var final_hash: [64]u8 = .{0}**64;
        sha.hash(@as([]const u8, &combined_hash), &final_hash, .{});

        try writeFile("key", @as([]const u8, &final_hash));
}