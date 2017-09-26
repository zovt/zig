const trunc = @import("trunc.zig").trunc;
const linkage = @import("index.zig").linkage;

export fn __trunctfsf2(a: f128) -> f32 {
    @setGlobalLinkage(__trunctfsf2, linkage);
    trunc(f128, f32, a)
}

test "import trunctfsf2" {
    _ = @import("trunctfsf2_test.zig");
}

