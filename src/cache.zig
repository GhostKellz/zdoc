const std = @import("std");

pub const CacheEntry = struct {
    source_path: []const u8,
    source_mtime: i128,
    output_path: []const u8,
    output_mtime: i128,

    pub fn isValid(self: CacheEntry) bool {
        // Cache is valid if source file hasn't been modified since output was generated
        return self.source_mtime <= self.output_mtime;
    }
};

pub const Cache = struct {
    allocator: std.mem.Allocator,
    entries: std.HashMap([]const u8, CacheEntry, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) Cache {
        return Cache{
            .allocator = allocator,
            .entries = std.HashMap([]const u8, CacheEntry, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Cache) void {
        // Free all stored keys and values
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.source_path);
            self.allocator.free(entry.value_ptr.output_path);
        }
        self.entries.deinit();
    }

    pub fn shouldRegenerate(self: *Cache, source_path: []const u8, output_path: []const u8) !bool {
        // Get file modification times
        const source_stat = std.fs.cwd().statFile(source_path) catch |err| switch (err) {
            error.FileNotFound => return true, // Source doesn't exist, can't generate
            else => return err,
        };

        const output_stat = std.fs.cwd().statFile(output_path) catch |err| switch (err) {
            error.FileNotFound => return true, // Output doesn't exist, need to generate
            else => return err,
        };

        // Check cache
        if (self.entries.get(source_path)) |entry| {
            if (entry.isValid() and entry.source_mtime == source_stat.mtime and entry.output_mtime == output_stat.mtime) {
                return false; // Cache hit, no need to regenerate
            }
        }

        // Update cache entry
        const key = try self.allocator.dupe(u8, source_path);
        const source_path_owned = try self.allocator.dupe(u8, source_path);
        const output_path_owned = try self.allocator.dupe(u8, output_path);

        const new_entry = CacheEntry{
            .source_path = source_path_owned,
            .source_mtime = source_stat.mtime,
            .output_path = output_path_owned,
            .output_mtime = output_stat.mtime,
        };

        // Clean up old entry if exists
        if (self.entries.fetchRemove(source_path)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value.source_path);
            self.allocator.free(old.value.output_path);
        }

        try self.entries.put(key, new_entry);

        // Source is newer than output, need to regenerate
        return source_stat.mtime > output_stat.mtime;
    }

    pub fn loadFromFile(self: *Cache, cache_file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(cache_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // No cache file, start fresh
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Simple line-based format: source_path|source_mtime|output_path|output_mtime
        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.split(u8, trimmed, "|");
            const source_path = parts.next() orelse continue;
            const source_mtime_str = parts.next() orelse continue;
            const output_path = parts.next() orelse continue;
            const output_mtime_str = parts.next() orelse continue;

            const source_mtime = std.fmt.parseInt(i128, source_mtime_str, 10) catch continue;
            const output_mtime = std.fmt.parseInt(i128, output_mtime_str, 10) catch continue;

            const key = try self.allocator.dupe(u8, source_path);
            const source_path_owned = try self.allocator.dupe(u8, source_path);
            const output_path_owned = try self.allocator.dupe(u8, output_path);

            const entry = CacheEntry{
                .source_path = source_path_owned,
                .source_mtime = source_mtime,
                .output_path = output_path_owned,
                .output_mtime = output_mtime,
            };

            try self.entries.put(key, entry);
        }
    }

    pub fn saveToFile(self: *Cache, cache_file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(cache_file_path, .{});
        defer file.close();

        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            const line = try std.fmt.allocPrint(self.allocator, "{s}|{d}|{s}|{d}\n", .{
                entry.value_ptr.source_path,
                entry.value_ptr.source_mtime,
                entry.value_ptr.output_path,
                entry.value_ptr.output_mtime,
            });
            defer self.allocator.free(line);

            try file.writeAll(line);
        }
    }
};

test "cache basic functionality" {
    const testing = std.testing;
    var cache = Cache.init(testing.allocator);
    defer cache.deinit();

    // Create test files
    const test_source = "test_cache_source.zig";
    const test_output = "test_cache_output.html";

    {
        const source_file = try std.fs.cwd().createFile(test_source, .{});
        defer source_file.close();
        try source_file.writeAll("const x = 42;");
    }

    // First check should indicate regeneration needed
    const should_regen1 = try cache.shouldRegenerate(test_source, test_output);
    try testing.expect(should_regen1 == true);

    // Create output file
    {
        const output_file = try std.fs.cwd().createFile(test_output, .{});
        defer output_file.close();
        try output_file.writeAll("<html>test</html>");
    }

    // Now check should indicate no regeneration needed (assuming output is newer)
    std.time.sleep(1000000); // Sleep 1ms to ensure different mtime
    const should_regen2 = try cache.shouldRegenerate(test_source, test_output);
    try testing.expect(should_regen2 == false);

    // Cleanup
    std.fs.cwd().deleteFile(test_source) catch {};
    std.fs.cwd().deleteFile(test_output) catch {};
}