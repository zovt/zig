const __floatunditf = @import("floatunditf.zig").__floatunditf;
const assert = @import("std").debug.assert;

fn test__floatunditf(a: u64, expected_bits: u128) {
    const r = __floatunditf(a);
    assert(@bitCast(u128, r) == expected_bits);
}

test "floatuntidf" {
    for (cases) |case| {
        test__floatunditf(case.int, case.float);
    }
}

const u64_to_f128 = struct {
    int: u64,
    float: u128,
};

const cases = []u64_to_f128 {
    u64_to_f128 { .int = 0x0, .float = 0 },
    u64_to_f128 { .int = 0x1, .float = 0x3fff0000000000000000000000000000 },
    u64_to_f128 { .int = 0x2, .float = 0x40000000000000000000000000000000 },
    u64_to_f128 { .int = 0x123456789abcdef1, .float = 0x403b23456789abcdef10000000000000 },

    u64_to_f128 { .int = 0xffffffffffffffff, .float = 0x403efffffffffffffffe000000000000 },
    u64_to_f128 { .int = 0xfffffffffffffffe, .float = 0x403efffffffffffffffc000000000000 },
    u64_to_f128 { .int = 0x8000000000000000, .float = 0x403e0000000000000000000000000000 },
    u64_to_f128 { .int = 0x7fffffffffffffff, .float = 0x403dfffffffffffffffc000000000000 },
};
