// modules import
const std = @import("std");
const zig_clap = @import("zig_clap");

// "shortcuts"
const sha = std.crypto.hash.sha3.Sha3_512;

/// commandline arguments atructure
const cmdArgs = struct {
        output: []const u8,
        input: []const u8,
};

/// parse given commandline arguments
fn parseArgs(allocator: std.mem.Allocator) !cmdArgs {
        // create help/argument description
        const help = 
                \\-h, --help                    Display this help message and exit
                \\-o, --output  <str>           Specify the output: filename. otherwise stdout is used (no conversion to hex is done and no newline is used)
                \\-i, --input   <str>           Input filename (later on optionally multiple and/or foldername; all files within the folder would then be parsed recursively)
                \\
        ;

        // parse argument description
        const params = comptime zig_clap.parseParamsComptime(help);

        // parse the arguments given
        var res = try zig_clap.parse(zig_clap.Help, &params, zig_clap.parsers.default, .{});
        defer res.deinit();

        // print the help and exit with status SUCCESS
        if(res.args.help != 0) {
                std.debug.print("{s}", .{help});
                std.os.exit(0);
        }

        // allocate either an array of length of the `output` given
        // or with the length of "stdout"
        var output: []u8 = try allocator.alloc(u8, if(res.args.output) |out| out.len else 6);
        if(res.args.output) |out| {
                // copy the output filename
                @memcpy(output, out);
        } else {
                // set output to "stdout"
                @memcpy(output, "stdout");
        }

        // same as above, except exit when no input filename was provided
        var input: []u8 = try allocator.alloc(u8, if(res.args.input) |in| in.len else {
                std.debug.print("No input filename was supplied!\n", .{});
                std.os.exit(1);
        });
        if(res.args.input) |in| {
                @memcpy(input, in);
        }

        return cmdArgs {
                .input = input,
                .output = output,
        };
}

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

        // parse the arguments given
        var args = try parseArgs(arena.allocator());

        // read the input of the file
        var file_contents = try readFileAlloc(args.input, arena.allocator());

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

        if(std.mem.eql(u8, args.output, "stdout")){
                try print("{s}", .{final_hash});
        } else {
                try writeFile(args.output, @as([]const u8, &final_hash));
        }
}