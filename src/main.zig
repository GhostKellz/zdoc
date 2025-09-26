const std = @import("std");
const zdoc = @import("zdoc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: zdoc [--format=<format>] <input_file_or_dir> <output_dir>\n", .{});
        std.debug.print("       zdoc [--format=<format>] file1.zig file2.zig ... <output_dir>\n", .{});
        std.debug.print("Formats: html, json, markdown\n", .{});
        return error.InvalidArguments;
    }

    // Parse format option
    var format = zdoc.OutputFormat.html; // default
    var arg_start: usize = 1;

    if (args.len > 1 and std.mem.startsWith(u8, args[1], "--format=")) {
        const format_str = args[1][9..]; // Skip "--format="
        if (zdoc.OutputFormat.fromString(format_str)) |fmt| {
            format = fmt;
        } else {
            std.debug.print("Error: Unknown format '{s}'. Available: html, json, markdown\n", .{format_str});
            return error.InvalidFormat;
        }
        arg_start = 2;
    }

    if (args.len < arg_start + 2) {
        std.debug.print("Error: Not enough arguments after format option\n", .{});
        return error.InvalidArguments;
    }

    const output_dir = args[args.len - 1];
    const inputs = args[arg_start..args.len - 1];

    std.debug.print("Output directory: {s}\n", .{output_dir});
    std.debug.print("Output format: {s}\n", .{@tagName(format)});
    for (inputs) |input| {
        std.debug.print("Input: {s}\n", .{input});
    }

    // Use optimized large project processing for many files
    if (inputs.len > 100) {
        std.debug.print("Using optimized large project processing...\n", .{});
        try zdoc.generateDocsLargeProject(allocator, inputs, output_dir, format);
    } else {
        try zdoc.generateDocsMultiple(allocator, inputs, output_dir, format);
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
