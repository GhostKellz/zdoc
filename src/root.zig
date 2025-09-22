//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn generateDocs(allocator: std.mem.Allocator, input_file: []const u8, output_dir: []const u8) !void {
    // Read file
    const file = try std.fs.cwd().openFile(input_file, .{});
    defer file.close();
    const max_size = 1024 * 1024; // 1MB
    var buffer = try allocator.alloc(u8, max_size);
    defer allocator.free(buffer);
    const bytes_read = try file.readAll(buffer);
    const source = try allocator.allocSentinel(u8, bytes_read, 0);
    defer allocator.free(source);
    std.mem.copyForwards(u8, source, buffer[0..bytes_read]);

    // Parse AST
    var ast = try std.zig.Ast.parse(allocator, source, .zig);
    defer ast.deinit(allocator);

    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    // Extract declarations
    var declarations: [10][]const u8 = undefined;
    var decl_count: usize = 0;

    for (ast.rootDecls()) |decl_idx| {
        if (decl_count >= 10) break;
        const idx = @intFromEnum(decl_idx);
        const decl = ast.nodes.items(.tag)[@as(usize, idx)];
        if (decl == .fn_decl or decl == .global_var_decl) {
            const main_token = ast.nodes.items(.main_token)[@as(usize, idx)];
            const name_token = main_token + 1; // Assume name is next token
            const name = ast.tokenSlice(name_token);
            declarations[decl_count] = name;
            decl_count += 1;
        }
    }

    // Generate HTML
    var html_buffer: [8192]u8 = undefined;
    var html_len: usize = 0;
    html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "<!DOCTYPE html>\n<html>\n<head><title>Zdoc Documentation</title></head>\n<body>\n<h1>API Documentation for {s}</h1>\n<ul>\n", .{input_file})).len;
    for (declarations[0..decl_count]) |name| {
        html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "<li>{s}</li>\n", .{name})).len;
    }
    html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "</ul>\n</body>\n</html>", .{})).len;

    // Write to file
    const output_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
    defer allocator.free(output_path);
    const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();
    try out_file.writeAll(html_buffer[0..html_len]);
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
