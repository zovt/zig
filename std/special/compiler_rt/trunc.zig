const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const TypeId = builtin.TypeId;
const is_test = builtin.is_test;
const Log2Int = std.math.Log2Int;

fn sigbits(comptime T: type) -> @typeOf(1) {
    switch (@sizeOf(T)) {
        2 => 10,
        4 => 23,
        8 => 52,
        16 => 112,
        else => unreachable,
    }
}

pub fn trunc(comptime src_t: type, comptime dst_t: type, a: src_t) -> dst_t {
    @setDebugSafety(this, is_test);
    assert(@typeId(dst_t) == TypeId.Float);
    assert(@typeId(src_t) == TypeId.Float);
    assert(@sizeOf(dst_t) < @sizeOf(src_t));

    const src_rep_t = @IntType(false, src_t.bit_count);
    const dst_rep_t = @IntType(false, dst_t.bit_count);
    const log2_src_t = Log2Int(src_rep_t);
    const log2_dst_t = Log2Int(dst_rep_t);

    const src_sig_bits = sigbits(src_t);
    const src_exp_bits = src_t.bit_count - src_sig_bits - 1;
    const src_inf_exp = (1 << src_exp_bits) - 1;
    const src_exp_bias = src_inf_exp >> 1;

    const src_min_norm = src_rep_t(1) << src_sig_bits;
    const src_sig_mask = src_min_norm - 1;
    const src_infinity = src_rep_t(src_inf_exp) << src_sig_bits;
    const src_sign_mask = src_rep_t(1) << (src_sig_bits + src_exp_bits);
    const src_abs_mask = src_sign_mask - 1;
    const src_qnan = src_rep_t(1) << (src_sig_bits - 1);
    const src_nan = src_qnan - 1;

    const dst_sig_bits = sigbits(dst_t);
    const dst_exp_bits = dst_t.bit_count - dst_sig_bits - 1;
    const dst_inf_exp = (1 << dst_exp_bits) - 1;
    const dst_exp_bias = dst_inf_exp >> 1;

    const dst_qnan = dst_rep_t(1) << (dst_sig_bits - 1);
    const dst_nan = dst_qnan - 1;

    const round_mask = (src_rep_t(1) << (src_sig_bits - dst_sig_bits)) - 1;
    const halfway = src_rep_t(1) << (src_sig_bits - dst_sig_bits - 1);
    const underflow_exp = src_exp_bias + 1 - dst_exp_bias;
    const overflow_exp = src_exp_bias + dst_inf_exp - dst_exp_bias;
    const underflow = src_rep_t(underflow_exp) << src_sig_bits;
    const overflow = src_rep_t(overflow_exp) << src_sig_bits;

    const a_rep = @bitCast(src_rep_t, a);
    const a_abs = a_rep & src_abs_mask;
    const sign = a_rep & src_sign_mask;

    var abs_result: dst_rep_t = undefined;
    if (a_abs -% underflow < a_abs -% overflow) {
        // Pretty close here a bit off though!
        _ = @import("std").debug.warn("overflow case {x} {}\n", a_abs, u64(src_sig_bits - dst_sig_bits));
        // We do truncate, is this correct?
        abs_result = @truncate(dst_rep_t, a_abs >> (src_sig_bits - dst_sig_bits));
        abs_result -%= dst_rep_t(src_exp_bias - dst_exp_bias) << dst_sig_bits;

        const round_bits = a_abs & round_mask;
        if (round_bits > halfway) {
            abs_result += 1;
        } else if (round_bits == halfway) {
            abs_result += abs_result & 1;
        }
    } else if (a_abs > src_infinity) {
        abs_result = dst_rep_t(dst_inf_exp) << dst_sig_bits;
        abs_result |= dst_qnan;
        abs_result |= dst_rep_t((a_abs & src_nan) >> (src_sig_bits - dst_sig_bits)) & dst_nan;
    } else if (a_abs >= overflow) {
        abs_result = dst_rep_t(dst_inf_exp) << dst_sig_bits;
    } else {
        const a_exp = a_abs >> src_sig_bits;
        const shift = src_exp_bias - dst_exp_bias - a_exp + 1;
        const sig = (a_rep & src_sig_mask) | src_min_norm;

        if (shift > src_sig_bits) {
            abs_result = 0;
        } else {
            const sticky = std.math.shl(src_rep_t, sig, src_t.bit_count - shift) != 0;
            const denorm_sig = std.math.shr(src_rep_t, sig, shift) | (if (sticky) src_rep_t(1) else 0);
            abs_result = dst_rep_t(denorm_sig >> (src_sig_bits - dst_sig_bits));

            const round_bits = denorm_sig & round_mask;
            if (round_bits > halfway) {
                abs_result += 1;
            } else if (round_bits == halfway) {
                abs_result += abs_result & 1;
            }
        }
    }

    const result = abs_result | dst_rep_t(sign >> (src_t.bit_count - dst_t.bit_count));
    @bitCast(dst_t, result)
}
