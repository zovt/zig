const builtin = @import("builtin");
const is_test = builtin.is_test;
const linkage = @import("index.zig").linkage;

const low = if (builtin.is_big_endian) 1 else 0;
const high = 1 - low;

export fn __floatuntidf(a_: u128) -> f64 {
    @setGlobalLinkage(__floatuntidf, linkage);
    @setDebugSafety(this, is_test);

    var a = a_;
    if (a == 0) {
        return 0.0;
    }

    const N = @sizeOf(u128) * 8;
    const sd = N - @clz(a);
    var e = sd - 1;

    // TODO: Where is DBL_MANT_DIG equiv
    const DBL_MANT_DIG = 16;
    if (DBL_MANT_DIG > 16) {
        switch (sd) {
            DBL_MANT_DIG + 1 => {
                a <<= 1;
            },
            DBL_MANT_DIG + 2 => {
                // empty
            },
            else => {
                const hl1 = (a >> (sd - DBL_MANT_DIG + 2));
                const hl2 = a & (@maxValue(128) >> ((N + DBL_MANT_DIG + 2) - sd));
                a = if ((hl1 | hl2) != 0) 1 else 0;
            },
        }

        a |= (a & 4) != 0;
        a += 1;
        a >>= 2;

        if (a & (u128(1) << DBL_MANT_DIG) != 0) {
            a >>= 1;
            e += 1;
        }
    } else {
        a <<= u7(DBL_MANT_DIG - sd);
    }

    // TODO: Get proper cast working here
    //var f64_bits: [2]u32 = undefined;
    //f64_bits[high] = ((u32(e) + 1023) << 20) | u32((a >> 32) & 0x00FFFFF);
    //f64_bits[low]  = @truncate(u32, a);
    //*@ptrCast(&f64, &f64_bits)
}
