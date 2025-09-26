const std = @import("std");

//! This is a module-level doc comment
//! It describes the entire module

/// Generic Result type for error handling
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,

        /// Initialize a successful result
        pub fn success(value: T) Result(T, E) {
            return .{ .ok = value };
        }

        /// Initialize an error result
        pub fn failure(error_value: E) Result(T, E) {
            return .{ .err = error_value };
        }
    };
}

/// A point in 2D space with generic coordinate type
pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        /// Create a new point at the origin
        pub fn origin() Self {
            return Self{ .x = 0, .y = 0 };
        }

        /// Calculate the distance from origin
        pub fn magnitude(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y);
        }
    };
}

/// HTTP status codes
pub const HttpStatus = enum(u16) {
    ok = 200,
    not_found = 404,
    internal_server_error = 500,

    /// Check if status indicates success
    pub fn isSuccess(self: HttpStatus) bool {
        return @intFromEnum(self) >= 200 and @intFromEnum(self) < 300;
    }
};

/// Configuration union for different environments
pub const Config = union(enum) {
    development: struct {
        debug: bool,
        log_level: u8,
    },
    production: struct {
        optimize: bool,
        metrics_endpoint: []const u8,
    },
    testing: struct {
        mock_data: bool,
    },
};

/// Global application version
pub const VERSION: []const u8 = "1.0.0";

/// Maximum buffer size for operations
pub const MAX_BUFFER_SIZE: usize = 4096;

/// Test function for the documentation generator
pub fn testFunction(param1: i32, param2: []const u8, param3: ?bool) !void {
    _ = param1;
    _ = param2;
    _ = param3;
}

test "Point creation and methods" {
    const IntPoint = Point(i32);
    const point = IntPoint.origin();
    try std.testing.expect(point.x == 0);
    try std.testing.expect(point.y == 0);
}

test "Result type usage" {
    const IntResult = Result(i32, []const u8);
    const success = IntResult.success(42);
    try std.testing.expect(success == .ok);
}