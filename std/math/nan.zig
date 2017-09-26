const math = @import("index.zig");

pub fn nan(comptime T: type) -> T {
    switch (T) {
        f32 => math.nan_f32,
        f64 => math.nan_f64,
        f128 => math.nan_f128,
        else => @compileError("nan not implemented for " ++ @typeName(T)),
    }
}

fn sigbits(comptime T: type) -> @typeOf(1) {
    switch (T) {
        f32 => 23,
        f64 => 52,
        f128 => 112,
        else => 0,  // Error is signalled at nanRepr
    }
}

pub fn nanRepr(comptime T: type, repr: @IntType(false, sigbits(T))) -> T {
    switch (T) {
        f32 => @bitCast(f32, math.nan_u32 | repr),
        f64 => @bitCast(f64, math.nan_u64 | repr),
        f128 => @bitCast(f128, math.nan_u128 | repr),
        else => @compileError("nanRepr not implemented for " ++ @typeName(T)),
    }
}

// TODO: nanRepr test

// Note: A signalling nan is identical to a standard right now by may have a different bit
// representation in the future when required.
pub fn snan(comptime T: type) -> T {
    switch (T) {
        f32 => math.nan_f32,
        f64 => math.nan_f64,
        f128 => math.nan_f128,
        else => @compileError("snan not implemented for " ++ @typeName(T)),
    }
}
