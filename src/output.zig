const std = @import("std");
const markdown = @import("markdown.zig");
const pdf = @import("pdf.zig");

pub const OutputFormat = enum {
    html,
    json,
    markdown_format,
    pdf,

    pub fn fromString(format_str: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, format_str, "html")) return .html;
        if (std.mem.eql(u8, format_str, "json")) return .json;
        if (std.mem.eql(u8, format_str, "markdown")) return .markdown_format;
        if (std.mem.eql(u8, format_str, "pdf")) return .pdf;
        return null;
    }

    pub fn getExtension(self: OutputFormat) []const u8 {
        return switch (self) {
            .html => ".html",
            .json => ".json",
            .markdown_format => ".md",
            .pdf => ".pdf",
        };
    }
};

pub const Declaration = struct {
    name: []const u8,
    kind: enum { function, variable, struct_type, enum_type, union_type },
    signature: ?[]const u8 = null,
    doc_comment: ?[]const u8 = null,

    pub fn toJson(self: Declaration, allocator: std.mem.Allocator) ![]const u8 {
        var json_obj = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer json_obj.deinit(allocator);

        try json_obj.appendSlice(allocator, "{\n");
        const basic_info = try std.fmt.allocPrint(allocator, "  \"name\": \"{s}\",\n  \"kind\": \"{s}\"", .{ self.name, @tagName(self.kind) });
        defer allocator.free(basic_info);
        try json_obj.appendSlice(allocator, basic_info);

        if (self.signature) |sig| {
            const signature = try std.fmt.allocPrint(allocator, ",\n  \"signature\": \"{s}\"", .{sig});
            defer allocator.free(signature);
            try json_obj.appendSlice(allocator, signature);
        }

        if (self.doc_comment) |doc| {
            // Escape JSON string
            try json_obj.appendSlice(allocator, ",\n  \"documentation\": \"");
            for (doc) |char| {
                switch (char) {
                    '"' => try json_obj.appendSlice(allocator, "\\\""),
                    '\\' => try json_obj.appendSlice(allocator, "\\\\"),
                    '\n' => try json_obj.appendSlice(allocator, "\\n"),
                    '\r' => try json_obj.appendSlice(allocator, "\\r"),
                    '\t' => try json_obj.appendSlice(allocator, "\\t"),
                    else => try json_obj.append(allocator, char),
                }
            }
            try json_obj.appendSlice(allocator, "\"");
        }

        try json_obj.appendSlice(allocator, "\n}");
        return json_obj.toOwnedSlice(allocator);
    }

    pub fn toMarkdown(self: Declaration, allocator: std.mem.Allocator) ![]const u8 {
        var md_content = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer md_content.deinit(allocator);

        // Header based on kind
        const header_level = switch (self.kind) {
            .function => "### ",
            .struct_type, .enum_type, .union_type => "## ",
            .variable => "#### ",
        };

        const title = try std.fmt.allocPrint(allocator, "{s}{s}\n\n", .{ header_level, self.name });
        defer allocator.free(title);
        try md_content.appendSlice(allocator, title);

        // Add signature if available
        if (self.signature) |sig| {
            const signature = try std.fmt.allocPrint(allocator, "**Signature:** `{s}`\n\n", .{sig});
            defer allocator.free(signature);
            try md_content.appendSlice(allocator, signature);
        }

        // Add documentation
        if (self.doc_comment) |doc| {
            const documentation = try std.fmt.allocPrint(allocator, "{s}\n\n", .{doc});
            defer allocator.free(documentation);
            try md_content.appendSlice(allocator, documentation);
        }

        return md_content.toOwnedSlice(allocator);
    }
};

pub const OutputGenerator = struct {
    allocator: std.mem.Allocator,
    format: OutputFormat,

    pub fn init(allocator: std.mem.Allocator, format: OutputFormat) OutputGenerator {
        return OutputGenerator{
            .allocator = allocator,
            .format = format,
        };
    }

    pub fn generateOutput(self: OutputGenerator, declarations: []Declaration, input_file: []const u8, output_path: []const u8) !void {
        switch (self.format) {
            .html => try self.generateHtml(declarations, input_file, output_path),
            .json => try self.generateJson(declarations, input_file, output_path),
            .markdown_format => try self.generateMarkdown(declarations, input_file, output_path),
            .pdf => try self.generatePdf(declarations, input_file, output_path),
        }
    }

    fn generateJson(self: OutputGenerator, declarations: []Declaration, input_file: []const u8, output_path: []const u8) !void {
        var json_content = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        defer json_content.deinit(self.allocator);

        try json_content.appendSlice(self.allocator, "{\n");

        const header = try std.fmt.allocPrint(self.allocator, "  \"source_file\": \"{s}\",\n  \"generated_at\": \"{d}\",\n  \"declarations\": [\n", .{ input_file, std.time.timestamp() });
        defer self.allocator.free(header);
        try json_content.appendSlice(self.allocator, header);

        for (declarations, 0..) |decl, i| {
            const decl_json = try decl.toJson(self.allocator);
            defer self.allocator.free(decl_json);

            const json_entry = try std.fmt.allocPrint(self.allocator, "    {s}", .{decl_json});
            defer self.allocator.free(json_entry);
            try json_content.appendSlice(self.allocator, json_entry);
            if (i < declarations.len - 1) {
                try json_content.appendSlice(self.allocator, ",");
            }
            try json_content.appendSlice(self.allocator, "\n");
        }

        try json_content.appendSlice(self.allocator, "  ]\n}");

        // Write to file
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        try file.writeAll(json_content.items);
    }

    fn generateMarkdown(self: OutputGenerator, declarations: []Declaration, input_file: []const u8, output_path: []const u8) !void {
        var md_content = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        defer md_content.deinit(self.allocator);

        // Header
        const header = try std.fmt.allocPrint(self.allocator, "# API Documentation for {s}\n\nGenerated on {d}\n\n", .{ input_file, std.time.timestamp() });
        defer self.allocator.free(header);
        try md_content.appendSlice(self.allocator, header);

        // Table of contents
        try md_content.appendSlice(self.allocator, "## Table of Contents\n\n");

        // Group declarations by kind
        const kind_names = [_][]const u8{ "Functions", "Structs", "Enums", "Unions", "Variables" };
        const kinds = [_]@TypeOf(declarations[0].kind){ .function, .struct_type, .enum_type, .union_type, .variable };

        for (kinds, 0..) |kind, kind_idx| {
            var has_items = false;
            for (declarations) |decl| {
                if (decl.kind == kind) {
                    if (!has_items) {
                        const toc_item = try std.fmt.allocPrint(self.allocator, "- [{s}](#{s})\n", .{ kind_names[kind_idx], kind_names[kind_idx] });
                        defer self.allocator.free(toc_item);
                        try md_content.appendSlice(self.allocator, toc_item);
                        has_items = true;
                    }
                }
            }
        }

        try md_content.appendSlice(self.allocator, "\n");

        // Generate content by sections
        for (kinds, 0..) |kind, kind_idx| {
            var has_items = false;
            for (declarations) |decl| {
                if (decl.kind == kind) {
                    if (!has_items) {
                        const section_header = try std.fmt.allocPrint(self.allocator, "## {s}\n\n", .{kind_names[kind_idx]});
                        defer self.allocator.free(section_header);
                        try md_content.appendSlice(self.allocator, section_header);
                        has_items = true;
                    }

                    const decl_md = try decl.toMarkdown(self.allocator);
                    defer self.allocator.free(decl_md);
                    try md_content.appendSlice(self.allocator, decl_md);
                }
            }
        }

        // Write to file
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        try file.writeAll(md_content.items);
    }

    fn generatePdf(self: OutputGenerator, declarations: []Declaration, input_file: []const u8, output_path: []const u8) !void {
        var pdf_writer = try pdf.SimplePDFWriter.init(self.allocator, output_path);
        defer pdf_writer.deinit();

        try pdf_writer.writeDeclarations(declarations, input_file);
    }

    fn generateHtml(self: OutputGenerator, declarations: []Declaration, input_file: []const u8, output_path: []const u8) !void {
        // This will delegate to the existing HTML generation logic
        // For now, we'll implement a basic version and integrate with the existing system later
        _ = self;
        _ = declarations;
        _ = input_file;
        _ = output_path;
        // TODO: Integrate with existing HTML generation
    }
};

test "JSON export functionality" {
    const testing = std.testing;

    const decl = Declaration{
        .name = "testFunction",
        .kind = .function,
        .signature = "(2 parameters)",
        .doc_comment = "A test function",
    };

    const json = try decl.toJson(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "testFunction") != null);
    try testing.expect(std.mem.indexOf(u8, json, "function") != null);
    try testing.expect(std.mem.indexOf(u8, json, "A test function") != null);
}

test "Markdown export functionality" {
    const testing = std.testing;

    const decl = Declaration{
        .name = "testFunction",
        .kind = .function,
        .signature = "(2 parameters)",
        .doc_comment = "A test function",
    };

    const md = try decl.toMarkdown(testing.allocator);
    defer testing.allocator.free(md);

    try testing.expect(std.mem.indexOf(u8, md, "### testFunction") != null);
    try testing.expect(std.mem.indexOf(u8, md, "**Signature:**") != null);
    try testing.expect(std.mem.indexOf(u8, md, "A test function") != null);
}