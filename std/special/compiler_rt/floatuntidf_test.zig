const __floatuntidf = @import("floatuntidf.zig").__floatuntidf;
const assert = @import("std").debug.assert;

fn test__floatuntidf(a: u128, expected_r: f64) {
    const r = __floatuntidf(a);
    assert(r == expected_r);
}

test "floatuntidf" {
    for (cases) |case| {
        test__floatuntidf(case.int, case.float);
    }
}

const u128_to_f64 = struct {
    int: u128,
    float: f64,
};

const cases = []u128_to_f64 {
    u128_to_f64 { .int = 0, .float = 0.0 },
    u128_to_f64 { .int = 1, .float = 1.0 },
    u128_to_f64 { .int = 2, .float = 2.0 },
    u128_to_f64 { .int = 20, .float = 20.0 },
    u128_to_f64 { .int = 0x7fffff8000000000, .float = 0x1.fffffep+62 },
};
