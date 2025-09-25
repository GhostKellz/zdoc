const std = @import("std");

/// A simple example struct
const Point = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Point {
        return Point{ .x = x, .y = y };
    }
};

/// An example enum
const Color = enum {
    red,
    green,
    blue,
};

/// Test function
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

const test_var: i32 = 42;