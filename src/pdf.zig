const std = @import("std");
const output = @import("output.zig");

/// PDF generation utilities for documentation
pub const PDFGenerator = struct {
    allocator: std.mem.Allocator,
    content: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !PDFGenerator {
        const content = try std.ArrayList(u8).initCapacity(allocator, 1024);
        return PDFGenerator{
            .allocator = allocator,
            .content = content,
        };
    }

    pub fn deinit(self: *PDFGenerator) void {
        self.content.deinit(self.allocator);
    }

    /// Generate PDF content from declarations
    pub fn generateFromDeclarations(self: *PDFGenerator, declarations: []const output.Declaration, source_file: []const u8) ![]const u8 {
        try self.writePDFHeader();
        try self.writeTitle(source_file);
        try self.writeTableOfContents(declarations);

        for (declarations) |decl| {
            try self.writeDeclaration(decl);
        }

        try self.writePDFFooter();

        return try self.content.toOwnedSlice(self.allocator);
    }

    fn writePDFHeader(self: *PDFGenerator) !void {
        // Basic PDF header with minimal structure
        const header =
            \\%PDF-1.4
            \\1 0 obj
            \\<<
            \\/Type /Catalog
            \\/Pages 2 0 R
            \\>>
            \\endobj
            \\
            \\2 0 obj
            \\<<
            \\/Type /Pages
            \\/Kids [3 0 R]
            \\/Count 1
            \\>>
            \\endobj
            \\
            \\3 0 obj
            \\<<
            \\/Type /Page
            \\/Parent 2 0 R
            \\/MediaBox [0 0 612 792]
            \\/Contents 4 0 R
            \\/Resources <<
            \\  /Font <<
            \\    /F1 5 0 R
            \\    /F2 6 0 R
            \\  >>
            \\>>
            \\>>
            \\endobj
            \\
            \\4 0 obj
            \\<<
            \\/Length
        ;
        try self.content.appendSlice(self.allocator, header);
    }

    fn writeTitle(self: *PDFGenerator, source_file: []const u8) !void {
        const title_text = try std.fmt.allocPrint(self.allocator, "API Documentation for {s}", .{source_file});
        defer self.allocator.free(title_text);

        const title_content = try std.fmt.allocPrint(self.allocator,
            \\BT
            \\/F1 16 Tf
            \\50 720 Td
            \\({s}) Tj
            \\ET
            \\
        , .{title_text});
        defer self.allocator.free(title_content);

        try self.content.appendSlice(self.allocator, title_content);
    }

    fn writeTableOfContents(self: *PDFGenerator, declarations: []const output.Declaration) !void {
        const toc_header =
            \\BT
            \\/F2 14 Tf
            \\50 680 Td
            \\(Table of Contents) Tj
            \\ET
            \\
        ;
        try self.content.appendSlice(self.allocator, toc_header);

        var y_pos: i32 = 650;
        for (declarations) |decl| {
            const line = try std.fmt.allocPrint(self.allocator,
                \\BT
                \\/F1 12 Tf
                \\60 {d} Td
                \\({s} - {s}) Tj
                \\ET
                \\
            , .{ y_pos, decl.name, @tagName(decl.kind) });
            defer self.allocator.free(line);

            try self.content.appendSlice(self.allocator, line);
            y_pos -= 20;
        }
    }

    fn writeDeclaration(self: *PDFGenerator, decl: output.Declaration) !void {
        const decl_text = try std.fmt.allocPrint(self.allocator,
            \\BT
            \\/F2 12 Tf
            \\50 500 Td
            \\({s}) Tj
            \\ET
            \\BT
            \\/F1 10 Tf
            \\50 480 Td
            \\(Kind: {s}) Tj
            \\ET
            \\
        , .{ decl.name, @tagName(decl.kind) });
        defer self.allocator.free(decl_text);

        try self.content.appendSlice(self.allocator, decl_text);

        if (decl.doc_comment) |doc| {
            const doc_text = try std.fmt.allocPrint(self.allocator,
                \\BT
                \\/F1 10 Tf
                \\50 460 Td
                \\({s}) Tj
                \\ET
                \\
            , .{doc});
            defer self.allocator.free(doc_text);

            try self.content.appendSlice(self.allocator, doc_text);
        }
    }

    fn writePDFFooter(self: *PDFGenerator) !void {
        // Calculate content length
        const content_start = std.mem.indexOf(u8, self.content.items, "BT").?;
        const content_length = self.content.items.len - content_start;

        // Insert content length
        const length_str = try std.fmt.allocPrint(self.allocator, "{d}", .{content_length});
        defer self.allocator.free(length_str);

        try self.content.appendSlice(self.allocator, length_str);
        try self.content.appendSlice(self.allocator,
            \\>>
            \\stream
            \\
        );

        // Add the content stream
        const footer =
            \\
            \\endstream
            \\endobj
            \\
            \\5 0 obj
            \\<<
            \\/Type /Font
            \\/Subtype /Type1
            \\/BaseFont /Helvetica-Bold
            \\>>
            \\endobj
            \\
            \\6 0 obj
            \\<<
            \\/Type /Font
            \\/Subtype /Type1
            \\/BaseFont /Helvetica
            \\>>
            \\endobj
            \\
            \\xref
            \\0 7
            \\0000000000 65535 f
            \\0000000010 00000 n
            \\0000000079 00000 n
            \\0000000173 00000 n
            \\0000000301 00000 n
            \\0000000380 00000 n
            \\0000000461 00000 n
            \\trailer
            \\<<
            \\/Size 7
            \\/Root 1 0 R
            \\>>
            \\startxref
            \\544
            \\%%EOF
        ;
        try self.content.appendSlice(self.allocator, footer);
    }
};

/// Simple PDF writer for basic documentation
pub const SimplePDFWriter = struct {
    file: std.fs.File,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !SimplePDFWriter {
        const file = try std.fs.cwd().createFile(file_path, .{});
        return SimplePDFWriter{
            .file = file,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimplePDFWriter) void {
        self.file.close();
    }

    pub fn writeDeclarations(self: *SimplePDFWriter, declarations: []const output.Declaration, source_file: []const u8) !void {
        var generator = try PDFGenerator.init(self.allocator);
        defer generator.deinit();

        const pdf_content = try generator.generateFromDeclarations(declarations, source_file);
        defer self.allocator.free(pdf_content);

        try self.file.writeAll(pdf_content);
    }
};

/// Alternative: HTML to PDF conversion (simpler approach)
pub fn generatePDFFromHTML(allocator: std.mem.Allocator, html_content: []const u8, output_path: []const u8) !void {
    // This is a simplified approach - in a real implementation, you might use:
    // 1. wkhtmltopdf command line tool
    // 2. Puppeteer/Chrome headless
    // 3. A proper PDF library

    // For now, create a simple text-based PDF representation
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var generator = try PDFGenerator.init(allocator);
    defer generator.deinit();

    // Basic conversion: extract text content from HTML and format as PDF
    const text_content = try extractTextFromHTML(allocator, html_content);
    defer allocator.free(text_content);

    const pdf_header =
        \\%PDF-1.4
        \\1 0 obj
        \\<< /Type /Catalog /Pages 2 0 R >>
        \\endobj
        \\2 0 obj
        \\<< /Type /Pages /Kids [3 0 R] /Count 1 >>
        \\endobj
        \\3 0 obj
        \\<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
        \\endobj
        \\4 0 obj
        \\<< /Length
    ;

    const pdf_content = try std.fmt.allocPrint(allocator,
        \\{s}{d} >>
        \\stream
        \\BT
        \\/F1 12 Tf
        \\50 720 Td
        \\({s}) Tj
        \\ET
        \\endstream
        \\endobj
        \\xref
        \\0 5
        \\0000000000 65535 f
        \\0000000010 00000 n
        \\0000000079 00000 n
        \\0000000173 00000 n
        \\0000000301 00000 n
        \\trailer
        \\<< /Size 5 /Root 1 0 R >>
        \\startxref
        \\380
        \\%%EOF
    , .{ pdf_header, text_content.len + 50, text_content });
    defer allocator.free(pdf_content);

    try file.writeAll(pdf_content);
}

fn extractTextFromHTML(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    // Simple HTML tag removal for basic text extraction
    var result = try std.ArrayList(u8).initCapacity(allocator, html.len);
    defer result.deinit(allocator);

    var in_tag = false;
    for (html) |char| {
        switch (char) {
            '<' => in_tag = true,
            '>' => in_tag = false,
            else => if (!in_tag) try result.append(allocator, char),
        }
    }

    return try result.toOwnedSlice(allocator);
}