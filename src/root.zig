//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

fn extractFunctionSignature(ast: *std.zig.Ast, fn_proto: std.zig.Ast.full.FnProto, buffer: []u8) ![]const u8 {
    _ = ast;
    // For now, return basic parameter count info
    const param_count = fn_proto.ast.params.len;
    return try std.fmt.bufPrint(buffer, "({d} parameters)", .{param_count});
}

fn extractDocComment(ast: *std.zig.Ast, token_idx: std.zig.Ast.TokenIndex, allocator: std.mem.Allocator) !?[]const u8 {
    // Look backwards from the given token to find doc comments
    var current_token = token_idx;
    var doc_comments: std.ArrayListUnmanaged([]const u8) = .{};
    defer doc_comments.deinit(allocator);

    // Search backwards for doc comments
    while (current_token > 0) : (current_token -= 1) {
        const token = ast.tokenSlice(current_token - 1);

        if (std.mem.startsWith(u8, token, "///")) {
            // Regular doc comment - extract the text after ///
            const comment_text = std.mem.trim(u8, token[3..], " \t");
            try doc_comments.insert(allocator, 0, comment_text);
        } else if (std.mem.startsWith(u8, token, "//!")) {
            // Top-level doc comment - extract the text after //!
            const comment_text = std.mem.trim(u8, token[3..], " \t");
            try doc_comments.insert(allocator, 0, comment_text);
        } else if (std.mem.eql(u8, token, "\n") or std.mem.eql(u8, token, "") or
                  std.mem.startsWith(u8, token, "//") and !std.mem.startsWith(u8, token, "///") and !std.mem.startsWith(u8, token, "//!")) {
            // Continue searching - whitespace or non-doc comments
            if (current_token < token_idx - 10) break; // Don't search too far back
        } else {
            // Hit non-comment, non-whitespace token - stop searching
            break;
        }
    }

    if (doc_comments.items.len == 0) return null;

    // Join the comments with newlines
    var total_len: usize = 0;
    for (doc_comments.items, 0..) |comment, i| {
        total_len += comment.len;
        if (i > 0) total_len += 1; // for newline
    }

    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (doc_comments.items, 0..) |comment, i| {
        if (i > 0) {
            result[pos] = '\n';
            pos += 1;
        }
        @memcpy(result[pos..pos + comment.len], comment);
        pos += comment.len;
    }

    return result;
}

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

pub fn generateDocsMultiple(allocator: std.mem.Allocator, inputs: []const []const u8, output_dir: []const u8) !void {
    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    for (inputs) |input| {
        const stat = std.fs.cwd().statFile(input) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Error: File not found: {s}\n", .{input});
                continue;
            },
            else => return err,
        };

        if (stat.kind == .directory) {
            try processDirectory(allocator, input, output_dir);
        } else {
            // Generate docs for single file
            const basename = std.fs.path.basename(input);
            const name_without_ext = if (std.mem.endsWith(u8, basename, ".zig"))
                basename[0 .. basename.len - 4]
            else
                basename;

            const file_output_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, name_without_ext });
            defer allocator.free(file_output_dir);

            try generateDocs(allocator, input, file_output_dir);
        }
    }
}


fn processDirectory(allocator: std.mem.Allocator, dir_path: []const u8, output_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(full_path);

            const name_without_ext = entry.name[0 .. entry.name.len - 4];
            const file_output_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, name_without_ext });
            defer allocator.free(file_output_dir);

            try generateDocs(allocator, full_path, file_output_dir);
        }
    }
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
    const Declaration = struct {
        name: []const u8,
        kind: enum { function, variable, struct_type, enum_type, union_type },
        signature: ?[]const u8 = null,
        doc_comment: ?[]const u8 = null,
    };

    var declarations = std.ArrayListUnmanaged(Declaration){};
    defer declarations.deinit(allocator);

    for (ast.rootDecls()) |decl_idx| {
        const idx = @intFromEnum(decl_idx);
        const decl = ast.nodes.items(.tag)[@as(usize, idx)];
        const main_token = ast.nodes.items(.main_token)[@as(usize, idx)];

        switch (decl) {
            .fn_decl => {
                const name_token = main_token + 1;
                const name = ast.tokenSlice(name_token);

                // Extract function signature
                var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
                const fn_proto = ast.fullFnProto(&fn_buffer, decl_idx);

                // Extract doc comment
                const doc_comment = try extractDocComment(&ast, main_token, allocator);

                if (fn_proto) |proto| {
                    var sig_buffer: [256]u8 = undefined;
                    const sig = try extractFunctionSignature(&ast, proto, sig_buffer[0..]);
                    try declarations.append(allocator, .{ .name = name, .kind = .function, .signature = sig, .doc_comment = doc_comment });
                } else {
                    try declarations.append(allocator, .{ .name = name, .kind = .function, .doc_comment = doc_comment });
                }
            },
            .global_var_decl => {
                const name_token = main_token + 1;
                const name = ast.tokenSlice(name_token);

                // Extract doc comment
                const doc_comment = try extractDocComment(&ast, main_token, allocator);

                try declarations.append(allocator, .{ .name = name, .kind = .variable, .doc_comment = doc_comment });
            },
            .simple_var_decl => {
                const name_token = main_token + 1;
                const name = ast.tokenSlice(name_token);

                // Look ahead to see if this is a type declaration
                var token_idx = name_token + 1;
                var kind: @TypeOf(@as(Declaration, undefined).kind) = .variable;

                while (token_idx < ast.tokens.len and token_idx < name_token + 15) : (token_idx += 1) {
                    const token = ast.tokenSlice(token_idx);
                    if (std.mem.eql(u8, token, "struct")) {
                        kind = .struct_type;
                        break;
                    } else if (std.mem.eql(u8, token, "enum")) {
                        kind = .enum_type;
                        break;
                    } else if (std.mem.eql(u8, token, "union")) {
                        kind = .union_type;
                        break;
                    } else if (std.mem.eql(u8, token, ";") and !std.mem.eql(u8, token, "=")) {
                        // If we hit semicolon without equals, it's likely just a variable declaration
                        break;
                    }
                }

                // Extract doc comment
                const doc_comment = try extractDocComment(&ast, main_token, allocator);

                try declarations.append(allocator, .{ .name = name, .kind = kind, .doc_comment = doc_comment });
            },
            else => {},
        }
    }

    // Generate HTML
    var html_buffer: [16384]u8 = undefined;
    var html_len: usize = 0;
    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\<meta charset="UTF-8">
        \\<meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\<title>Zdoc Documentation</title>
        \\<style>
        \\body {{ font-family: Arial, sans-serif; margin: 0; padding: 0; }}
        \\h1 {{ color: #333; margin: 0 0 20px 0; }}
        \\h2 {{ color: #666; border-bottom: 1px solid #ddd; margin: 30px 0 15px 0; }}
        \\.container {{ display: flex; min-height: 100vh; }}
        \\.sidebar {{ width: 250px; background: #f8f9fa; border-right: 1px solid #ddd; padding: 20px; overflow-y: auto; }}
        \\.content {{ flex: 1; padding: 40px; }}
        \\.nav-section {{ margin-bottom: 20px; }}
        \\.nav-title {{ font-weight: bold; color: #666; margin-bottom: 8px; text-transform: uppercase; font-size: 0.9em; }}
        \\.nav-item {{ display: block; color: #007acc; text-decoration: none; padding: 4px 8px; border-radius: 3px; margin-bottom: 2px; }}
        \\.nav-item:hover {{ background: #e9ecef; }}
        \\.nav-function {{ border-left: 3px solid #28a745; }}
        \\.nav-struct {{ border-left: 3px solid #dc3545; }}
        \\.nav-enum {{ border-left: 3px solid #ffc107; }}
        \\.nav-union {{ border-left: 3px solid #17a2b8; }}
        \\.nav-variable {{ border-left: 3px solid #6c757d; }}
        \\.declaration {{ margin: 10px 0; padding: 10px; background: #f8f9fa; border-left: 3px solid #007acc; }}
        \\.function {{ border-left-color: #28a745; }}
        \\.struct {{ border-left-color: #dc3545; }}
        \\.enum {{ border-left-color: #ffc107; }}
        \\.union {{ border-left-color: #17a2b8; }}
        \\.variable {{ border-left-color: #6c757d; }}
        \\.name {{ font-weight: bold; }}
        \\.kind {{ color: #666; font-size: 0.8em; text-transform: uppercase; }}
        \\.signature {{ font-family: monospace; color: #333; }}
        \\.doc-comment {{ color: #555; font-style: italic; margin-top: 5px; padding: 5px; background: #f0f0f0; border-radius: 3px; }}
        \\
        \\/* Mobile responsive design */
        \\@media (max-width: 768px) {{
        \\  .container {{ flex-direction: column; }}
        \\  .sidebar {{ width: 100%; border-right: none; border-bottom: 1px solid #ddd; padding: 15px; }}
        \\  .content {{ padding: 20px; }}
        \\  .nav-section {{ display: inline-block; margin-right: 20px; vertical-align: top; }}
        \\  .nav-title {{ margin-bottom: 5px; }}
        \\  .nav-item {{ display: inline-block; margin-right: 10px; margin-bottom: 5px; }}
        \\  h1 {{ font-size: 1.8em; }}
        \\  h2 {{ font-size: 1.4em; }}
        \\  .declaration {{ margin: 8px 0; padding: 8px; }}
        \\}}
        \\
        \\@media (max-width: 480px) {{
        \\  .content {{ padding: 15px; }}
        \\  .sidebar {{ padding: 10px; }}
        \\  h1 {{ font-size: 1.6em; }}
        \\  h2 {{ font-size: 1.2em; }}
        \\  .nav-section {{ display: block; margin-bottom: 15px; }}
        \\  .declaration {{ margin: 6px 0; padding: 6px; }}
        \\}}
        \\</style>
        \\</head>
        \\<body>
        \\<div class="container">
        \\<div class="sidebar">
        \\<h3>Navigation</h3>
        \\<div style="margin-bottom: 15px;">
        \\<input type="text" id="search" placeholder="Search declarations..." style="width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px;">
        \\</div>
        \\
    , .{})).len;

    // Group by kind
    const kind_names = [_][]const u8{ "Functions", "Structs", "Enums", "Unions", "Variables" };
    const kinds = [_]@TypeOf(declarations.items[0].kind){ .function, .struct_type, .enum_type, .union_type, .variable };
    const css_classes = [_][]const u8{ "function", "struct", "enum", "union", "variable" };
    const nav_classes = [_][]const u8{ "nav-function", "nav-struct", "nav-enum", "nav-union", "nav-variable" };

    // Generate sidebar navigation
    for (kinds, 0..) |kind, kind_idx| {
        var has_nav_items = false;
        for (declarations.items) |decl| {
            if (decl.kind == kind) {
                if (!has_nav_items) {
                    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
                        \\<div class="nav-section">
                        \\<div class="nav-title">{s}</div>
                    , .{kind_names[kind_idx]})).len;
                    has_nav_items = true;
                }
                html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
                    \\<a href="#{s}" class="nav-item {s}">{s}</a>
                , .{ decl.name, nav_classes[kind_idx], decl.name })).len;
            }
        }
        if (has_nav_items) {
            html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "</div>\n", .{})).len;
        }
    }

    // End sidebar and start content
    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
        \\</div>
        \\<div class="content">
        \\<h1>API Documentation for {s}</h1>
    , .{input_file})).len;

    for (kinds, 0..) |kind, kind_idx| {
        var has_items = false;
        for (declarations.items) |decl| {
            if (decl.kind == kind) {
                if (!has_items) {
                    html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "<h2>{s}</h2>\n", .{kind_names[kind_idx]})).len;
                    has_items = true;
                }
                html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
                    \\<div class="declaration {s}" id="{s}">
                    \\<span class="name">{s}</span> <span class="kind">{s}</span>
                , .{ css_classes[kind_idx], decl.name, decl.name, kind_names[kind_idx] })).len;

                if (decl.signature) |sig| {
                    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
                        \\<br><span class="signature">{s}</span>
                    , .{sig})).len;
                }

                if (decl.doc_comment) |doc| {
                    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
                        \\<br><div class="doc-comment">{s}</div>
                    , .{doc})).len;
                }

                html_len += (try std.fmt.bufPrint(html_buffer[html_len..], "</div>\n", .{})).len;
            }
        }
    }

    html_len += (try std.fmt.bufPrint(html_buffer[html_len..],
        \\</div>
        \\</div>
        \\<script>
        \\document.getElementById('search').addEventListener('input', function(e) {{
        \\  const query = e.target.value.toLowerCase();
        \\  const navItems = document.querySelectorAll('.nav-item');
        \\  const declarations = document.querySelectorAll('.declaration');
        \\  const sections = document.querySelectorAll('.nav-section');
        \\
        \\  navItems.forEach(function(item) {{
        \\    const text = item.textContent.toLowerCase();
        \\    item.style.display = text.includes(query) ? 'block' : 'none';
        \\  }});
        \\
        \\  declarations.forEach(function(decl) {{
        \\    const name = decl.querySelector('.name').textContent.toLowerCase();
        \\    decl.style.display = name.includes(query) ? 'block' : 'none';
        \\  }});
        \\
        \\  sections.forEach(function(section) {{
        \\    const visibleItems = section.querySelectorAll('.nav-item[style*="block"], .nav-item:not([style])');
        \\    section.style.display = (query === '' || visibleItems.length > 0) ? 'block' : 'none';
        \\  }});
        \\}});
        \\</script>
        \\</body>
        \\</html>
    , .{})).len;

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
