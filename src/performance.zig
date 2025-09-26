const std = @import("std");

/// Performance monitoring and optimization utilities
pub const Performance = struct {
    start_time: i64,
    peak_memory: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Performance {
        return Performance{
            .start_time = std.time.milliTimestamp(),
            .peak_memory = 0,
            .allocator = allocator,
        };
    }

    pub fn recordMemoryUsage(self: *Performance, current_usage: usize) void {
        if (current_usage > self.peak_memory) {
            self.peak_memory = current_usage;
        }
    }

    pub fn getElapsedTime(self: Performance) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    pub fn printStats(self: Performance, file_count: usize) void {
        const elapsed = self.getElapsedTime();
        std.debug.print("Performance Stats:\n");
        std.debug.print("  Files processed: {d}\n", .{file_count});
        std.debug.print("  Time taken: {d}ms\n", .{elapsed});
        std.debug.print("  Peak memory: {d} KB\n", .{self.peak_memory / 1024});
        if (file_count > 0) {
            std.debug.print("  Avg time per file: {d}ms\n", .{elapsed / @as(i64, @intCast(file_count))});
        }
    }
};

/// Memory pool for efficient allocation of documentation objects
pub const MemoryPool = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: std.mem.Allocator,
    total_allocated: usize,

    pub fn init(base_allocator: std.mem.Allocator) MemoryPool {
        return MemoryPool{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
            .total_allocated = 0,
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *MemoryPool) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *MemoryPool) void {
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.base_allocator);
        self.total_allocated = 0;
    }

    pub fn getTotalAllocated(self: MemoryPool) usize {
        return self.total_allocated;
    }
};

/// Optimized string pool for reducing memory fragmentation
pub const StringPool = struct {
    strings: std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StringPool {
        return StringPool{
            .strings = std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StringPool) void {
        // Free all stored strings
        var iterator = self.strings.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.strings.deinit();
    }

    /// Interns a string, returning a reference to the pooled version
    pub fn intern(self: *StringPool, string: []const u8) ![]const u8 {
        const result = try self.strings.getOrPut(string);
        if (!result.found_existing) {
            const owned_string = try self.allocator.dupe(u8, string);
            result.key_ptr.* = owned_string;
        }
        return result.key_ptr.*;
    }
};

/// Batch processor for handling large numbers of files efficiently
pub const BatchProcessor = struct {
    batch_size: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, batch_size: usize) BatchProcessor {
        return BatchProcessor{
            .batch_size = batch_size,
            .allocator = allocator,
        };
    }

    /// Process files in batches to optimize memory usage
    pub fn processBatches(
        self: BatchProcessor,
        files: []const []const u8,
        processor_fn: *const fn (std.mem.Allocator, []const []const u8) anyerror!void,
    ) !void {
        var i: usize = 0;
        while (i < files.len) {
            const end = @min(i + self.batch_size, files.len);
            const batch = files[i..end];

            // Process this batch
            try processor_fn(self.allocator, batch);

            i = end;
        }
    }
};

/// Fast file reader with memory mapping for large files
pub const FastFileReader = struct {
    pub fn readFileOptimized(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();

        // For large files (>1MB), consider using different strategies
        if (file_size > 1024 * 1024) {
            // Use streaming read for very large files
            return try readLargeFile(allocator, file, file_size);
        } else {
            // Use simple allocation for smaller files
            const contents = try allocator.alloc(u8, file_size);
            _ = try file.readAll(contents);
            return contents;
        }
    }

    fn readLargeFile(allocator: std.mem.Allocator, file: std.fs.File, file_size: u64) ![]u8 {
        const contents = try allocator.alloc(u8, file_size);
        var total_read: usize = 0;
        const chunk_size = 64 * 1024; // 64KB chunks

        while (total_read < file_size) {
            const remaining = file_size - total_read;
            const to_read = @min(chunk_size, remaining);
            const bytes_read = try file.readAll(contents[total_read..total_read + to_read]);
            total_read += bytes_read;

            if (bytes_read == 0) break; // EOF
        }

        return contents;
    }
};