const trunc = @import("trunc.zig").trunc;
const linkage = @import("index.zig").linkage;

export fn __trunctfdf2(a: f128) -> f64 {
    @setGlobalLinkage(__trunctfdf2, linkage);
    trunc(f128, f64, a)
}

test "import trunctfdf2" {
    _ = @import("trunctfdf2_test.zig");
}

