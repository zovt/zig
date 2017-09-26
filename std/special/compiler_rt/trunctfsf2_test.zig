const __trunctfsf2 = @import("trunctfsf2.zig").__trunctfsf2;
const assert = @import("std").debug.assert;
const math = @import("../../math/index.zig");

fn test__trunctfsf2(a: f128, expected_q: u32) {
    const q = __trunctfsf2(a);
    if (@bitCast(u32, q) != expected_q) {
        _ = @import("std").debug.warn("have {} need {}, have {x} need {x}\n",
            q, @bitCast(f32, expected_q), @bitCast(u32, q), expected_q);
    }
    assert(@bitCast(u32, q) == expected_q);
}

test "trunctfsf2" {
    for (cases) |case| {
        test__trunctfsf2(case.a, case.q);
    }
}

const Case = struct {
    a: f128,
    q: u32,

    fn init(a: f128, q: u32) -> Case {
        Case {
            .a = a,
            .q = q,
        }
    }
};

const cases = []Case {
    // TODO nanq:
    // TODO nan:
    //Case.init(math.inf(f128), 0x7f800000),
    //Case.init(0.0, 0x0),
    //Case.init(0x1.af23456789bbaaab347645365cdep+5, 0x4211d156),
    //Case.init(0x1.dedafcff354b6ae9758763545432p-9, 0x3b71e9e2),
    //Case.init(0x1.2f34dd5f437e849b4baab754cdefp+4534, 0x7f800000),
    //Case.init(0x1.edcbff8ad76ab5bf46463233214fp-435, 0x0),
};
