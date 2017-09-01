const std = @import("std");
const assert = @import("std").debug.assert;

pub fn hexToBin(comptime hexString: []const u8) -> [@divExact(hexString.len, 2)]u8 {
    const finalLen = @divExact(hexString.len, 2);
    var result: [finalLen]u8 = undefined;
    {var i = 0; while (i < finalLen) : (i += 1) {
        result[i] = %%std.fmt.parseUnsigned(u8, hexString[i * 2 .. i * 2 + 2], 16);
    }}
    return result;
}

test "hexToBin" {
    assert((comptime hexToBin("")).len == 0);
    assert((comptime hexToBin("00"))[0] == 0x00);
    assert((comptime hexToBin("bc"))[0] == 0xbc);
    assert((comptime hexToBin("0123456789abcdef"))[2] == 0x45);
}
