const std = @import("std");

/// # Mathematical Functions
///
/// This module provides **basic mathematical operations**.
///
/// ## Usage
///
/// ```zig
/// const result = add(2, 3); // returns 5
/// ```
///
/// *Note*: All functions are `pub` and can be used externally.
///
/// For more info, see [Zig documentation](https://ziglang.org/documentation/).
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

/// Subtract two numbers
///
/// **Parameters:**
/// - `a`: First number
/// - `b`: Second number
///
/// **Returns:** The difference `a - b`
pub fn subtract(a: i32, b: i32) i32 {
    return a - b;
}

/// A simple data structure
///
/// This struct contains:
/// 1. An `x` coordinate
/// 2. A `y` coordinate
/// 3. Helper methods for manipulation
const Point = struct {
    x: f32,
    y: f32,
};