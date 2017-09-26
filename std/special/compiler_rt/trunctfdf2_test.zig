const __trunctfdf2 = @import("trunctfdf2.zig").__trunctfdf2;
const assert = @import("std").debug.assert;
const math = @import("../../math/index.zig");

fn test__trunctfdf2(a: f128, expected_q: u64) {
    const q = __trunctfdf2(a);
    if (@bitCast(u64, q) != expected_q) {
        _ = @import("std").debug.warn("have {} need {}, have {x} need {x}\n", q, @bitCast(f64, expected_q), @bitCast(u64, q), expected_q);
    }
    assert(@bitCast(u64, q) == expected_q);
}

test "trunctfdf2" {
    for (cases) |case| {
        test__trunctfdf2(case.a, case.q);
    }
}

const Case = struct {
    a: f128,
    q: u64,

    fn init(a: f128, q: u64) -> Case {
        Case {
            .a = a,
            .q = q,
        }
    }
};

const cases = []Case {
    Case.init(math.nanRepr(f128, 0x810000000000 << 64), 0x7ff8100000000000),
    Case.init(math.inf(f128), 0x7ff0000000000000),
    Case.init(0.0, 0x0),
    //Case.init(0x1.af23456789bbaaab347645365cdep+5, 0x404af23456789bbb),
    //Case.init(0x1.dedafcff354b6ae9758763545432p-9, 0x3f6dedafcff354b7),
    Case.init(0x1.2f34dd5f437e849b4baab754cdefp+4534, 0x7ff0000000000000),
    //Case.init(0x1.edcbff8ad76ab5bf46463233214fp-435, 0x24cedcbff8ad76ab),
};
