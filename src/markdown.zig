const std = @import("std");

pub const MarkdownParser = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Parse markdown text and return HTML
    pub fn parseToHtml(self: Self, markdown: []const u8) ![]const u8 {
        // Simple markdown parser for doc comments
        var result = try self.allocator.alloc(u8, markdown.len * 3); // generous buffer
        var result_len: usize = 0;

        // For now, just handle basic formatting
        var i: usize = 0;
        while (i < markdown.len) {
            // Handle bold **text**
            if (i + 1 < markdown.len and markdown[i] == '*' and markdown[i + 1] == '*') {
                const end = std.mem.indexOfPos(u8, markdown, i + 2, "**");
                if (end) |end_pos| {
                    const bold_html = "<strong>";
                    @memcpy(result[result_len..result_len + bold_html.len], bold_html);
                    result_len += bold_html.len;

                    const text = markdown[i + 2..end_pos];
                    @memcpy(result[result_len..result_len + text.len], text);
                    result_len += text.len;

                    const close_html = "</strong>";
                    @memcpy(result[result_len..result_len + close_html.len], close_html);
                    result_len += close_html.len;

                    i = end_pos + 2;
                    continue;
                }
            }

            // Handle italic *text*
            if (markdown[i] == '*') {
                const end = std.mem.indexOfPos(u8, markdown, i + 1, "*");
                if (end) |end_pos| {
                    const italic_html = "<em>";
                    @memcpy(result[result_len..result_len + italic_html.len], italic_html);
                    result_len += italic_html.len;

                    const text = markdown[i + 1..end_pos];
                    @memcpy(result[result_len..result_len + text.len], text);
                    result_len += text.len;

                    const close_html = "</em>";
                    @memcpy(result[result_len..result_len + close_html.len], close_html);
                    result_len += close_html.len;

                    i = end_pos + 1;
                    continue;
                }
            }

            // Handle inline code `text`
            if (markdown[i] == '`') {
                const end = std.mem.indexOfPos(u8, markdown, i + 1, "`");
                if (end) |end_pos| {
                    const code_html = "<code>";
                    @memcpy(result[result_len..result_len + code_html.len], code_html);
                    result_len += code_html.len;

                    const text = markdown[i + 1..end_pos];
                    @memcpy(result[result_len..result_len + text.len], text);
                    result_len += text.len;

                    const close_html = "</code>";
                    @memcpy(result[result_len..result_len + close_html.len], close_html);
                    result_len += close_html.len;

                    i = end_pos + 1;
                    continue;
                }
            }

            // Handle newlines as <br>
            if (markdown[i] == '\n') {
                const br_html = "<br>\n";
                @memcpy(result[result_len..result_len + br_html.len], br_html);
                result_len += br_html.len;
                i += 1;
                continue;
            }

            // Regular character
            result[result_len] = markdown[i];
            result_len += 1;
            i += 1;
        }

        // Resize result to actual length
        const final_result = try self.allocator.alloc(u8, result_len);
        @memcpy(final_result, result[0..result_len]);
        self.allocator.free(result);

        return final_result;
    }

};

test "basic markdown parsing" {
    const testing = std.testing;
    var parser = MarkdownParser.init(testing.allocator);

    const markdown = "This is **bold** and *italic* text.";
    const html = try parser.parseToHtml(markdown);
    defer testing.allocator.free(html);

    try testing.expect(std.mem.indexOf(u8, html, "<strong>bold</strong>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<em>italic</em>") != null);
}

test "inline code parsing" {
    const testing = std.testing;
    var parser = MarkdownParser.init(testing.allocator);

    const markdown = "Use `std.debug.print` for debugging.";
    const html = try parser.parseToHtml(markdown);
    defer testing.allocator.free(html);

    try testing.expect(std.mem.indexOf(u8, html, "<code>std.debug.print</code>") != null);
}