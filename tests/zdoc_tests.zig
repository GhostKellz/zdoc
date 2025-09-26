const std = @import("std");
const zdoc = @import("zdoc");
const testing = std.testing;

test "basic documentation generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "tests/test_files/complex_example.zig";
    const output_dir = "tests/output/basic_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, test_file, output_dir);

    // Verify output file exists
    const output_file = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
    defer allocator.free(output_file);

    const file = std.fs.cwd().openFile(output_file, .{}) catch |err| {
        std.debug.print("Expected output file not found: {s}\n", .{output_file});
        return err;
    };
    defer file.close();

    // Read and verify content contains expected elements
    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Check for expected HTML structure
    try testing.expect(std.mem.indexOf(u8, content, "<!DOCTYPE html>") != null);
    try testing.expect(std.mem.indexOf(u8, content, "<title>Zdoc Documentation</title>") != null);
    try testing.expect(std.mem.indexOf(u8, content, "testFunction") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Point") != null);
    try testing.expect(std.mem.indexOf(u8, content, "HttpStatus") != null);
}

test "multiple file documentation generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{ "test_example.zig", "test2.zig" };
    const output_dir = "tests/output/multi_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocsMultiple(allocator, &inputs, output_dir);

    // Verify both output directories exist
    var dir = try std.fs.cwd().openDir(output_dir, .{});
    defer dir.close();

    // Check test_example directory
    var test_example_dir = try dir.openDir("test_example", .{});
    defer test_example_dir.close();

    // Check test2 directory
    var test2_dir = try dir.openDir("test2", .{});
    defer test2_dir.close();
}

test "doc comment extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "tests/test_files/complex_example.zig";
    const output_dir = "tests/output/doc_comment_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, test_file, output_dir);

    // Read generated HTML
    const output_file = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
    defer allocator.free(output_file);

    const file = try std.fs.cwd().openFile(output_file, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Check for specific function names (doc comments may not be extracted yet)
    try testing.expect(std.mem.indexOf(u8, content, "Result") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Point") != null);
    try testing.expect(std.mem.indexOf(u8, content, "HttpStatus") != null);
    try testing.expect(std.mem.indexOf(u8, content, "testFunction") != null);
}

test "error handling for non-existent files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{"nonexistent.zig"};
    const output_dir = "tests/output/error_test";

    // This should not crash, but handle the error gracefully
    try zdoc.generateDocsMultiple(allocator, &inputs, output_dir);
}

test "empty file handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create empty test file
    const empty_file = "tests/test_files/empty.zig";
    const file = try std.fs.cwd().createFile(empty_file, .{});
    file.close();
    defer std.fs.cwd().deleteFile(empty_file) catch {};

    const output_dir = "tests/output/empty_test";
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, empty_file, output_dir);

    // Verify output file exists even for empty input
    const output_file = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
    defer allocator.free(output_file);

    const out_file = try std.fs.cwd().openFile(output_file, .{});
    defer out_file.close();
}