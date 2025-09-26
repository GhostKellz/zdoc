const std = @import("std");
const zdoc = @import("zdoc");
const testing = std.testing;

test "JSON output format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "test_example.zig";
    const output_dir = "tests/output/json_format_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, test_file, output_dir, .json);

    // Verify JSON file exists
    const json_path = try std.fmt.allocPrint(allocator, "{s}/api.json", .{output_dir});
    defer allocator.free(json_path);

    const file = try std.fs.cwd().openFile(json_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Check JSON structure
    try testing.expect(std.mem.indexOf(u8, content, "\"source_file\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "\"declarations\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "\"generated_at\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "\"kind\"") != null);
}

test "Markdown output format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "test_example.zig";
    const output_dir = "tests/output/markdown_format_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, test_file, output_dir, .markdown_format);

    // Verify Markdown file exists
    const md_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{output_dir});
    defer allocator.free(md_path);

    const file = try std.fs.cwd().openFile(md_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Check Markdown structure
    try testing.expect(std.mem.indexOf(u8, content, "# API Documentation") != null);
    try testing.expect(std.mem.indexOf(u8, content, "## Table of Contents") != null);
    try testing.expect(std.mem.indexOf(u8, content, "## Functions") != null);
    try testing.expect(std.mem.indexOf(u8, content, "### add") != null);
}

test "parallel processing performance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{ "test_example.zig", "test2.zig" };
    const output_dir = "tests/output/parallel_performance_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    const start_time = std.time.milliTimestamp();
    try zdoc.generateDocsMultiple(allocator, &inputs, output_dir, .html);
    const end_time = std.time.milliTimestamp();

    const duration = end_time - start_time;
    std.debug.print("Parallel processing took {d}ms for {d} files\n", .{ duration, inputs.len });

    // Verify both files were processed
    var dir = try std.fs.cwd().openDir(output_dir, .{});
    defer dir.close();

    var test_example_dir = try dir.openDir("test_example", .{});
    defer test_example_dir.close();

    var test2_dir = try dir.openDir("test2", .{});
    defer test2_dir.close();

    // Performance should be reasonable (less than 5 seconds for small files)
    try testing.expect(duration < 5000);
}

test "cache functionality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "test_example.zig";
    const output_dir = "tests/output/cache_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    // First generation - should create files
    const start_time1 = std.time.milliTimestamp();
    try zdoc.generateDocs(allocator, test_file, output_dir, .html);
    const end_time1 = std.time.milliTimestamp();
    const duration1 = end_time1 - start_time1;

    // Verify file was created
    const html_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
    defer allocator.free(html_path);

    const stat1 = try std.fs.cwd().statFile(html_path);
    try testing.expect(stat1.size > 0);

    std.debug.print("First generation took {d}ms\n", .{duration1});
}

test "output format validation" {
    // Test format string conversion
    try testing.expect(zdoc.OutputFormat.fromString("html") == .html);
    try testing.expect(zdoc.OutputFormat.fromString("json") == .json);
    try testing.expect(zdoc.OutputFormat.fromString("markdown") == .markdown_format);
    try testing.expect(zdoc.OutputFormat.fromString("pdf") == .pdf);
    try testing.expect(zdoc.OutputFormat.fromString("invalid") == null);

    // Test file extensions
    try testing.expect(std.mem.eql(u8, zdoc.OutputFormat.html.getExtension(), ".html"));
    try testing.expect(std.mem.eql(u8, zdoc.OutputFormat.json.getExtension(), ".json"));
    try testing.expect(std.mem.eql(u8, zdoc.OutputFormat.markdown_format.getExtension(), ".md"));
    try testing.expect(std.mem.eql(u8, zdoc.OutputFormat.pdf.getExtension(), ".pdf"));
}

test "large project simulation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create multiple test files to simulate a larger project
    const test_files = [_][]const u8{ "test_example.zig", "test2.zig" };
    const output_dir = "tests/output/large_project_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    const start_time = std.time.milliTimestamp();
    try zdoc.generateDocsMultiple(allocator, &test_files, output_dir, .json);
    const end_time = std.time.milliTimestamp();

    const duration = end_time - start_time;
    std.debug.print("Large project simulation: {d} files in {d}ms\n", .{ test_files.len, duration });

    // Verify all outputs exist
    for (test_files) |test_file| {
        const basename = std.fs.path.basename(test_file);
        const name_without_ext = basename[0 .. basename.len - 4];
        const expected_path = try std.fmt.allocPrint(allocator, "{s}/{s}/api.json", .{ output_dir, name_without_ext });
        defer allocator.free(expected_path);

        const file = try std.fs.cwd().openFile(expected_path, .{});
        defer file.close();
    }

    // Performance should scale reasonably
    try testing.expect(duration < 10000); // Less than 10 seconds
}

test "PDF output format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_file = "test_example.zig";
    const output_dir = "tests/output/pdf_format_test";

    // Clean output directory
    std.fs.cwd().deleteTree(output_dir) catch {};

    try zdoc.generateDocs(allocator, test_file, output_dir, .pdf);

    // Verify PDF file exists
    const pdf_path = try std.fmt.allocPrint(allocator, "{s}/api.pdf", .{output_dir});
    defer allocator.free(pdf_path);

    const file = try std.fs.cwd().openFile(pdf_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Check PDF structure (basic PDF header)
    try testing.expect(std.mem.indexOf(u8, content, "%PDF-") != null);
    try testing.expect(std.mem.indexOf(u8, content, "API Documentation") != null);
}