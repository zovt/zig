const unzip = @import("index.zig");

const hexToBin = @import("test_util.zig").hexToBin;

const assert = @import("std").debug.assert;
const mem = @import("std").mem;

test "readRawZipFileComment" {
    const zipfile_buffer = comptime hexToBin(
        "504b0506000000000000000000000000000000001400" ++
        "546869732069732074686520636f6d6d656e742e" ++
    "");
    var zipfile = %%unzip.fromBuffer(zipfile_buffer);

    const expected_comment = "This is the comment.";
    assert(zipfile.comment_length == expected_comment.len);

    var buffer = []u8{0} ** 0x100;
    zipfile.readRawZipFileComment(buffer[0..]);

    assert(mem.eql(u8, buffer[0..zipfile.comment_length], expected_comment));
}
