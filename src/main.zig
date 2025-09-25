const std = @import("std");
const zdoc = @import("zdoc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: zdoc <input_file_or_dir> <output_dir>\n", .{});
        std.debug.print("       zdoc file1.zig file2.zig ... <output_dir>\n", .{});
        return error.InvalidArguments;
    }

    const output_dir = args[args.len - 1];
    const inputs = args[1..args.len - 1];

    std.debug.print("Output directory: {s}\n", .{output_dir});
    for (inputs) |input| {
        std.debug.print("Input: {s}\n", .{input});
    }

    try zdoc.generateDocsMultiple(allocator, inputs, output_dir);
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
