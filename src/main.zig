const std = @import("std");

const ArenaAlloc = std.heap.ArenaAllocator;
const page_alloc = std.heap.page_allocator;
const sha512 = std.crypto.hash.sha3.Sha3_512;
const Thread = std.Thread;
const ArrayList = std.ArrayList;

/// print a string with formatting to stdout
fn print(comptime format: []const u8, args: anytype) !void {
        // get a handle to stdout
        var sout = std.io.getStdOut();
        // initialize a buffered writer
        var sout_buffered = std.io.bufferedWriter(sout.writer());
        // print to stdout
        try sout_buffered.writer().print(format, args);
        // flush the buffer completing the print operation
        try sout_buffered.flush();
}

/// read and store an entire file
/// caller owns returned memory
fn readFile(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        // get a handle to the current working directory
        const cwd = std.fs.cwd();

        // verify that that is infact a file
        const stat = try cwd.statFile(path);
        if(stat.kind != .file) {
                std.debug.print("{s} isn't a file!\n", .{path});
                return error.NotAFile;
        }

        // open the file
        const file = try cwd.openFile(path, .{ .mode = .read_only });
        defer file.close();

        // read the entire file
        var result = try file.readToEndAlloc(allocator, stat.size + 1);

        return result;
}

const FPHCConf = struct {
        threads: u16,
        input: [][]u8,
        output: []u8,
        stdout: bool,

        const Self = @This();

        pub fn fromJSON(json_str: []const u8, allocator: std.mem.Allocator) !FPHCConf {
                // create a json object from the input json string
                const conf_json = try std.json.parseFromSlice(Self, allocator, json_str, .{});
                defer conf_json.deinit();

                // initialize and return the config struct
                return .{
                        .threads = conf_json.value.threads,
                        .input = conf_json.value.input,
                        .output = conf_json.value.output,
                        .stdout = conf_json.value.stdout,
                };
        }
};

/// the state of the program
const FPHC = struct {
        const Self = @This();

        _threads: u16,
        _input: ArrayList([]u8),
        _output: []const u8,
        _stdout: bool,
        _arena: ArenaAlloc,
        // only used once
        _alloc: std.mem.Allocator,

        /// allocator should NOT be from an ArenaAllocator
        /// instead call deinit() afterwards
        pub fn init(conf: *FPHCConf, allocator: std.mem.Allocator) !Self {
                // arena is stored within the struct
                var arena = ArenaAlloc.init(allocator);
                var input = ArrayList([]u8).init(arena.allocator());
                try input.appendSlice(conf.input);

                return .{
                        ._threads = conf.threads,
                        ._input = input,
                        ._output = conf.output,
                        ._stdout = conf.stdout,
                        ._arena = arena,
                        ._alloc = allocator,
                };
        }

        /// a wrapper around input_files.popOrNull() using mutexes
        inline fn ___input_files_popOrNull_wrapper(input_files: *ArrayList([]u8), mutex_input: *Thread.Mutex) ?[]u8 {
                mutex_input.lock();
                defer mutex_input.unlock();
                return input_files.popOrNull();
        }

        /// used by Self.hashFiles() for multi-threading
        /// allocator should NOT be an ArenaAllocator
        fn __hashInput(allocator: std.mem.Allocator, input_files: *ArrayList([]u8), mutex_input: *Thread.Mutex, hash_files: *ArrayList([64]u8)) !void {
                while(___input_files_popOrNull_wrapper(input_files, mutex_input)) |path| {
                        // allocate the file only to hash it
                        // deallocate immediately after the same iteration of the loop to avoid memory hogging
                        var content_file = try readFile(path, allocator);
                        defer allocator.free(content_file);

                        // the digest length of sha512 is 512bit * (1 / 8)byte = 64 bytes
                        var out_hash: [64]u8 = .{0}**64;
                        // hash the file
                        sha512.hash(content_file, &out_hash, .{});
                        try hash_files.append(out_hash);
                }
        }

        /// hash the input files using threads
        ///! upgrade this to use Thread.Pool sometime later
        fn _hashFiles(self: *Self) ![64]u8 {
                // the hash of input files
                // freed by Self.deinit()
                var hash_files = ArrayList([64]u8).init(self._arena.allocator());

                // get the core count
                const count_cpu = try Thread.getCpuCount();

                // allocatoe a list of threads
                var threads = ArrayList(Thread).init(self._arena.allocator());

                // input_files mutex
                var input_mutex = std.Thread.Mutex{};

                // create and allocate threads
                for (0..count_cpu) |_| {
                        try threads.append(try Thread.spawn(.{}, __hashInput, .{self._alloc, &self._input, &input_mutex, &hash_files}));
                }

                // wait for the threads to finish
                while (threads.popOrNull()) |thread| {
                        thread.join();
                }

                // concatenate all the hashes to rehash them
                var hashes_combined = try self._arena.allocator().alloc(u8, hash_files.items.len * 64);

                var res_hash: [64]u8 = .{0}**64;
                // hash the concatenated hashes
                sha512.hash(hashes_combined, &res_hash, .{});

                return res_hash;
        }

        /// gets user input and hashes it
        ///!! need to find a way to hide the password/turn off character echo on input
        ///!! or replace them with asterisks or the like
        fn _hashPwd(self: *Self) ![64]u8 {
                // get a handle to stdin
                const stdin = std.io.getStdIn();

                // create an ArrayList to store the input
                var input = std.ArrayList(u8).init(self._arena.allocator());
                defer input.deinit();  // technically a no-op considering .toOwnedSlice() is used

                // prompt for the password
                try print("Please enter your password:\n", .{});

                // read from stdin
                try stdin.reader().streamUntilDelimiter(input.writer(), '\n', null);
                // convert the ArrayList to a slice
                const slice_input = try input.toOwnedSlice();

                // hash the input
                var hash_input: [64]u8 = .{0}**64;
                sha512.hash(slice_input, &hash_input, .{});

                return hash_input;
        }

        /// combine both sha3_512 hashes into one sha3_512 hash
        fn __combineHash(self: *Self, hash_a: *[64]u8, hash_b: *[64]u8) ![]u8 {
                var hash_combined = try self._arena.allocator().alloc(u8, 128);
                std.mem.copy(u8, hash_combined[0..64], hash_a);
                std.mem.copy(u8, hash_combined[64..], hash_b);
                return hash_combined;
        }

        /// writes the key to stdout or to a file
        fn _writeKey(self: *Self, key: [64]u8) !void {
                if(self._stdout) {
                        // if the config demands stdout
                        // print to stdout
                        try print("{s}\n", .{key});
                } else {
                        // open a handle to the cwd
                        const cwd = std.fs.cwd();

                        // create a file and truncate if it exists
                        _ = try cwd.createFile(self._output, .{ .truncate = true });

                        // open the file with write_only permission
                        var file = try cwd.openFile(self._output, .{ .mode = .write_only });
                        defer file.close();

                        // write to the file
                        try file.writer().writeAll(&key);
                }
        }

        /// get the key from specified files and the password of the user
        pub fn getKey(self: *Self) !void {
                // get the hash of the users password first
                // the user won't have to wait for the files to finish hashing
                var hash_user = try self._hashPwd();

                // get the hash of the files specified within fphc.json
                var hash_files = try self._hashFiles();

                // combine/concatenate the hashes
                var hash_combined = try self.__combineHash(&hash_user, &hash_files);

                // rehash the hashes
                var hash_final: [64]u8 = .{0}**64;
                sha512.hash(hash_combined, &hash_final, .{});

                // create the key
                try self._writeKey(hash_final);
        }

        pub fn deinit(self: *Self) void {
                self._arena.allocator().free(self._output);
                self._input.deinit();
                self._arena.deinit();
        }
};

pub fn main() !void {
        // initialize an ArenaAllocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        // read the config file
        const fphc_conf = try FPHCConf.fromJSON(try readFile("fphc.json", arena.allocator()), arena.allocator());
        // initialize program state
        var fphc = try FPHC.init(@constCast(&fphc_conf), std.heap.page_allocator);
        defer fphc.deinit();

        try fphc.getKey();
}