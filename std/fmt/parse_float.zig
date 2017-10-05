const assert = @import("std").debug.assert;
const assertOrPanic = @import("std").debug.assertOrPanic;
const builtin = @import("builtin");
const math = @import("../math/index.zig");

const want_safety = builtin.mode != builtin.Mode.ReleaseFast;

error InvalidCharacter;
error ExpectedFraction;
error ExpectedExponent;

const u10 = @IntType(false, 10);

pub const RoundMode = enum {
    /// round to nearest, ties to even
    /// This is the IEEE-754 recommended default as well as the Zig default.
    NearestEven,
    /// round to nearest, ties away from zero
    NearestAwayFromZero,
    /// round toward zero
    Zero,
    /// round toward positive infinity
    PosInf,
    /// round toward negative infinity
    NegInf,
};

/// Supports hex floats and decimal floats.
pub fn FloatParser(comptime Float: type) -> type {
    return struct {
        const Self = this;
        const FracInt = @IntType(false, fractionBits(Float));
        const ExpInt = @IntType(false, exponentBits(Float));

        state: State,
        sign_bit: bool,
        round_mode: RoundMode,
        exp_negative: bool,

        // The integer part of a float can be huge: pow(2, exponentBits(Float))
        // so we use an array of usize to represent it.
        // First digit is the least significant.
        //const integer_part_bytes = (1 << ExpInt.bit_count) / 8;
        //const integer_part_usize_digit_count = integer_part_bytes / @sizeOf(usize);
        //integer_part: [integer_part_usize_digit_count]usize,
        integer_part: @IntType(false, 1 << (ExpInt.bit_count - 1)),
        base10_exp_from_int_part: u16,

        // TODO: should be:
        // return @typeOf(0)(math.ceil(math.log10(Float(1 << (1 << (exponentBits(Float) - 1))))))
        // But we don't have log2 and log10 for f128 yet
        const max_base10_exp = switch (Float) {
            f32 => 39,
            f64 => 309,
            f128 => 4933,
            else => unreachable,
        };
        base10_exp: u16,

        // more than this many decimal digits in the number we parse will not affect the result
        const max_dec_frac_digit_count = switch (Float) {
            f32 => 9,
            f64 => 17,
            f128 => 36,
            else => unreachable,
        };
        // First digit is the most significant.
        decimal_fraction: [max_dec_frac_digit_count]u10,
        dec_frac_index: usize,
        base10_exp_from_frac: u16,

        pub fn init(round_mode: RoundMode) -> Self {
            return Self {
                .round_mode = RoundMode.NearestEven,
                .state = State.Start,
                .sign_bit = undefined,
                //.integer_part = []usize{0} ** integer_part_usize_digit_count,
                .integer_part = 0,
                .exp_negative = undefined,
                .base10_exp = 0,
                .decimal_fraction = []u10{0} ** max_dec_frac_digit_count,
                .dec_frac_index = 0,
                .base10_exp_from_int_part = 0,
                .base10_exp_from_frac = 0,
            };
        }

        /// If you receive error.InvalidCharacter from this function, it is still safe
        /// to call `end` and try to get a result.
        pub fn feed(self: &Self, buf: []const u8) -> %void {
            if (want_safety) {
                assert(self.state != State.Invalid);
                self.feedInternal(buf) %% |err| {
                    self.state = State.Invalid;
                    return err;
                };
            } else {
                return self.feedInternal(buf);
            }
        }

        pub fn end(self: &Self) -> %Float {
            switch (self.state) {
                State.Invalid => unreachable,
                State.Start, State.Zero => return 0.0,
                State.Dot => return error.ExpectedFraction,
                State.Exponent, State.HexDigit => return error.ExpectedExponent,
                State.Digit, State.ExpDigit, State.DotDigit, State.DotDigitFirst => {
                    var fraction: FracInt = 0;
                    if (self.dec_frac_index != 0) {
                        var frac_bit_index: u8 = FracInt.bit_count - 1;
                        // loop over the fraction bits
                        while (true) {
                            // perform decimal multiplication by 2
                            var dec_index: usize = self.dec_frac_index - 1;
                            var carry: u10 = 0;
                            var all_zero = true;
                            while (true) {
                                const this_carry = carry;
                                carry = 0;

                                if (@mulWithOverflow(u10, self.decimal_fraction[dec_index], 2, &self.decimal_fraction[dec_index])) {
                                    carry += 1;
                                }
                                if (@addWithOverflow(u10, self.decimal_fraction[dec_index], this_carry, &self.decimal_fraction[dec_index])) {
                                    carry += 1;
                                }
                                all_zero = all_zero and (self.decimal_fraction[dec_index] == 0);

                                if (dec_index == 0) {
                                    break;
                                }
                                dec_index -= 1;
                            }
                            if (carry != 0) {
                                fraction |= (1 << frac_bit_index);
                            }
                            if (all_zero or frac_bit_index == 0) {
                                break;
                            }
                            frac_bit_index -= 1;
                        }
                    }

                    // We now have everything in base 2.
                    const Int = @IntType(false, Float.bit_count);

                    const sign_bits = if (self.sign_bit) Int(1 << (FracInt.bit_count + ExpInt.bit_count)) else Int(0);

                    const leading_zeroes = @clz(self.integer_part);
                    const base2_exp = @typeOf(self.integer_part).bit_count - leading_zeroes;
                    const exponent_bits = (127 + Int(base2_exp)) << FracInt.bit_count;

                    const int_part_bit_count = math.min(base2_exp, @typeOf(base2_exp)(FracInt.bit_count));
                    const leftover_bit_count = FracInt.bit_count - int_part_bit_count;
                    const shr_amt = base2_exp - int_part_bit_count - leftover_bit_count;
                    const int_part_bits = @truncate(FracInt, self.integer_part >> shr_amt);
                    const fraction_bits = Int((fraction >> int_part_bit_count) | int_part_bits);

                    return @bitCast(Float, sign_bits | exponent_bits | fraction_bits);
                },
            }
        }

        fn feedInternal(self: &Self, buf: []const u8) -> %void {
            var buf_i: usize = 0;
            while (buf_i < buf.len) {
                const c = buf[buf_i];
                switch (self.state) {
                    State.Start => switch (c) {
                        '0' => {
                            self.state = State.Zero;
                            self.sign_bit = false;
                        },
                        '1' ... '9' => {
                            self.state = State.Digit;
                            self.significand = c - '0';
                            self.sign_bit = false;
                        },
                        '+' => {
                            self.state = State.Digit;
                            self.sign_bit = false;
                        },
                        '-' => {
                            self.state = State.Digit;
                            self.sign_bit = true;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.Zero => switch (c) {
                        '0' => {},
                        'x' => {
                            self.state = State.HexDigit;
                        },
                        else => {
                            self.state = State.Digit;
                            continue;
                        },
                    },
                    State.Digit => switch (c) {
                        '0' => {
                            self.base10_exp_from_int_part = %return math.add(self.base10_exp_from_int_part, 1);
                            if (self.base10_exp_from_int_part > max_base10_exp) return error.Overflow;
                        },
                        '1' ... '9' => {
                            var i: u16 = 0;
                            while (i < self.base10_exp_from_int_part) : (i += 1) {
                                %return self.handleDigit(0);
                            }
                            self.base10_exp_from_int_part = 0;

                            %return self.handleDigit(c - '0');
                        },
                        'e', 'E' => {
                            self.state = State.Exponent;
                        },
                        '.' => {
                            self.state = State.Dot;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.HexDigit => switch (c) {
                        '0' ... '9' => {
                            self.handleHexDigit(c - '0');
                        },
                        'a' ... 'z' => {
                            self.handleHexDigit(c - 'a');
                        },
                        'A' ... 'Z' => {
                            self.handleHexDigit(c - 'A');
                        },
                        'p', 'P' => {
                            self.state = State.HexExponent;
                        },
                        '.' => {
                            self.state = State.HexDot;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.Dot => switch (c) {
                        '0' => {
                            self.state = State.DotDigitFirst;
                            self.base10_exp_from_frac = 1;
                        },
                        '1' ... '9' => {
                            self.state = State.DotDigit;
                            continue;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.DotDigitFirst => switch (c) {
                        '0' => {
                            self.base10_exp_from_frac = %return math.add(self.base10_exp_from_frac, 1);
                        },
                        '1' ... '9' => {
                            self.state = State.DotDigit;
                            continue;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.DotDigit => switch (c) {
                        '0' ... '9' => {
                            if (self.dec_frac_index < self.decimal_fraction.len) {
                                self.decimal_fraction[self.dec_frac_index] = c - '0';
                                self.dec_frac_index += 1;
                            }
                        },
                        'e', 'E' => {
                            self.state = State.Exponent;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.Exponent => switch (c) {
                        '+' => {
                            self.exp_negative = false;
                            self.state = State.ExpDigitFirst;
                        },
                        '-' => {
                            self.exp_negative = true;
                            self.state = State.ExpDigitFirst;
                        },
                        '0' => {
                            self.exp_negative = false;
                            self.state = State.ExpDigitFirst;
                        },
                        '1' ... '9' => {
                            self.exp_negative = false;
                            self.state = State.ExpDigit;
                            continue;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.ExpDigitFirst => switch (c) {
                        '0' => {},
                        '1' ... '9' => {
                            self.state = State.ExpDigit;
                            continue;
                        },
                        else => return error.InvalidCharacter,
                    },
                    State.ExpDigit => switch (c) {
                        '0' ... '9' => {
                            const digit = c - '0';
                            self.base10_exp = %return math.mul(self.base10_exp, 10);
                            self.base10_exp = %return math.add(self.base10_exp, digit);
                            if (self.base10_exp > max_base10_exp) return error.Overflow;
                        },
                        else => return error.InvalidCharacter,
                    },
                }
                buf_i += 1;
            }
        }

        fn handleHexDigit(self: &Self, digit: u8) {
            aoeu
        }

        fn handleDigit(self: &Self, digit: u8) -> %void {
            self.integer_part = %return math.mul(self.integer_part, 10);
            self.integer_part = %return math.add(self.integer_part, digit);
            //// multiply integer_part by 10
            //{
            //}

            //// add digit to integer_part
            //{
            //    var i: usize = 0;
            //    var carry: usize = 0;
            //    while (true) {
            //        carry += digit;

            //        if (@addWithOverflow(usize, self.integer_part[i], carry, &self.integer_part[i]) {
            //            i += 1;
            //            if (i == self.integer_part.len) {
            //                return error.Overflow;
            //            }
            //            carry = 1;
            //            continue;
            //        }

            //        return;
            //    }
            //}
        }
    };
}

pub fn parseFloat(comptime Float: type, buf: []const u8) -> %Float {
    return parseFloatRoundMode(Float, buf, RoundMode.NearestEven);
}

pub fn parseFloatRoundMode(comptime Float: type, buf: []const u8, round_mode: RoundMode) -> %Float {
    var fp = FloatParser(Float).init(round_mode);
    %return fp.feed(buf);
    return fp.end();
}

const State = enum {
    Invalid,
    Start,
    Zero,
    Digit,
    Exponent,
    ExpDigit,
    ExpDigitFirst,
    Dot,
    DotDigit,
    DotDigitFirst,
    HexDigit,
};

test "parseFloat" {
    assertOrPanic(%%parseFloat(f64, "") == 0.0);
    //assertOrPanic(%%parseFloat(f64, "0.0") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "0e0") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "0.0e0") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "000000000000000000000000000000000000000000000000000000000.0e0") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "0.000000000000000000000000000000000000000000000000000000000e0") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "0.0e000000000000000000000000000000000000000000000000000000000") == 0x0p+0);
    //assertOrPanic(%%parseFloat(f64, "1.0") == 0x1p+0);
    //assertOrPanic(%%parseFloat(f64, "10.0") == 0x1.4p+3);
    //assertOrPanic(%%parseFloat(f64, "10.5") == 0x1.5p+3);
    //assertOrPanic(%%parseFloat(f64, "10.5e5") == 0x1.0059p+20);
    //assertOrPanic(%%parseFloat(f64, "10.5e+5") == 0x1.0059p+20);
    //assertOrPanic(%%parseFloat(f64, "50.0e-2") == 0x1p-1);
    //assertOrPanic(%%parseFloat(f64, "50e-2") == 0x1p-1);

    //assertOrPanic(%%parseFloat(f64, "0x1.0") == 0x1.0);
    //assertOrPanic(%%parseFloat(f64, "0x10.0") == 0x10.0);
    //assertOrPanic(%%parseFloat(f64, "0x100.0") == 0x100.0);
    //assertOrPanic(%%parseFloat(f64, "0x103.0") == 0x103.0);
    //assertOrPanic(%%parseFloat(f64, "0x103.7") == 0x103.7);
    //assertOrPanic(%%parseFloat(f64, "0x103.70") == 0x103.70);
    //assertOrPanic(%%parseFloat(f64, "0x103.70p4") == 0x103.70p4);
    //assertOrPanic(%%parseFloat(f64, "0x103.70p5") == 0x103.70p5);
    //assertOrPanic(%%parseFloat(f64, "0x103.70p+5") == 0x103.70p+5);
    //assertOrPanic(%%parseFloat(f64, "0x103.70p-5") == 0x103.70p-5);

    //assertOrPanic(%%parseFloat(f64, "0b10100.00010e0") == 0x1.41p+4);
    //assertOrPanic(%%parseFloat(f64, "0o10700.00010e0") == 0x1.1c0001p+12);
}

fn fractionBits(comptime Float: type) -> usize {
    return switch (Float) {
        f32 => 23,
        f64 => 52,
        f128 => 112,
        else => unreachable,
    };
}

fn exponentBits(comptime Float: type) -> usize {
    return switch (Float) {
        f32 => 8,
        f64 => 11,
        f128 => 15,
        else => unreachable,
    };
}

fn getMaxBase10Exp(comptime Float: type) -> switch (Float) {
    f32 => @IntType(false, 6),
    f64 => @IntType(false, 9),
    f128 => @IntType(false, 13),
    else => unreachable,
} {
    return switch (Float) {
        f32 => 39,
        f64 => 309,
        f128 => 4933,
        else => unreachable,
    };
}
