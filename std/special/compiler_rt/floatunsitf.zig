export fn __floatunsitf(a: u32) -> f128 {
    @setGlobalLinkage(__floatunsitf, @import("builtin").GlobalLinkage.LinkOnce);

    const a_width = @sizeOf(a) * 8;

    if (a == 0) {
        return @bitCast(f128, 0);
    }

    const exp = (a_width - 1) - @clz(a);

    const shift = significand_bits - exp;
    var result = (f32(a) << shift) ^ implicit_bit;
}

test "import floatunsitf" {
    _ = @import("floatunsitf_test.zig");
}

