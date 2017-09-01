const unzip = @import("index.zig");

const hexToBin = @import("test_util.zig").hexToBin;

const assert = @import("std").debug.assert;

test "empty" {
    const zipfile_buffer = comptime hexToBin("504b0506000000000000000000000000000000000000");
    var zipfile = %%unzip.fromBuffer(zipfile_buffer);

    assert(zipfile.entry_count == 0);
}
