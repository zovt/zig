const builtin = @import("builtin");
const linkage = @import("index.zig").linkage;

export fn __floatunditf(a: u64) -> f128 {
    @setGlobalLinkage(__floatunditf, linkage);
    @setDebugSafety(this, builtin.is_test);

    if (a == 0) {
        return @bitCast(f128, u128(0));
    }

    const size_in_bits = @typeOf(a).bit_count;
    const significand_bit_count = 112;
    const exponent = (size_in_bits - 1) - @clz(a);
    const shift = significand_bit_count - exponent;
    const implicit_bit = u128(1) << shift;
    const exponent_bias = size_in_bits - significand_bit_count - 1;

    const significand_bits = (u128(a) << shift) ^ implicit_bit;
    const exponent_bits = u128(exponent + exponent_bias) << significand_bits;

    @bitCast(f128, exponent_bits | significand_bits)
}
