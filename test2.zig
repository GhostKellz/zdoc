const std = @import("std");

/// A utility struct for mathematical operations
const Math = struct {
    /// Calculate the square of a number
    pub fn square(x: f64) f64 {
        return x * x;
    }
};

/// Status enumeration
const Status = enum {
    ok,
    err,
    pending,
};

/// Global constant
const PI: f64 = 3.14159;