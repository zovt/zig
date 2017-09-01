const unzip = @import("index.zig");
const ZipFile = unzip.ZipFile;
const Entry = unzip.Entry;

const hexToBin = @import("test_util.zig").hexToBin;

const mem = @import("std").mem;
const assert = @import("std").debug.assert;

test "openRawReadStream" {
    @setEvalBranchQuota(100000);

    // zipfile obtained via:
    //  $ echo -n 'aaabaaabaaabaaab' > stored.txt
    //  $ cp stored.txt compressed.txt
    //  $ cp stored.txt encrypted.txt
    //  $ cp stored.txt encrypted-and-compressed.txt
    //  $ rm -f out.zip
    //  $ zip out.zip -0 stored.txt
    //  $ zip out.zip compressed.txt
    //  $ zip out.zip -e0 encrypted.txt
    //  $ zip out.zip -e encrypted-and-compressed.txt
    const zipfile_buffer = comptime hexToBin(
        "504b03040a00000000006a54954ab413389510000000100000000a001c007374" ++
        "6f7265642e7478745554090003d842fa5842c5f75875780b000104e803000004" ++
        "e803000061616162616161626161616261616162504b03041400000008007554" ++
        "954ab413389508000000100000000e001c00636f6d707265737365642e747874" ++
        "5554090003ed42fa58ed42fa5875780b000104e803000004e80300004b4c4c4c" ++
        "4a44c200504b03040a00090000008454954ab41338951c000000100000000d00" ++
        "1c00656e637279707465642e74787455540900030743fa580743fa5875780b00" ++
        "0104e803000004e8030000f72e7bb915142131c934f01b163fcadb2a8db7cdaf" ++
        "d0a6f4dd1694c0504b0708b41338951c00000010000000504b03041400090008" ++
        "008a54954ab413389514000000100000001c001c00656e637279707465642d61" ++
        "6e642d636f6d707265737365642e74787455540900031343fa581343fa587578" ++
        "0b000104e803000004e80300007c4d3ea0d9754b470d3eb32ada5741bfc848f4" ++
        "19504b0708b41338951400000010000000504b01021e030a00000000006a5495" ++
        "4ab413389510000000100000000a0018000000000000000000b4810000000073" ++
        "746f7265642e7478745554050003d842fa5875780b000104e803000004e80300" ++
        "00504b01021e031400000008007554954ab413389508000000100000000e0018" ++
        "000000000001000000b48154000000636f6d707265737365642e747874555405" ++
        "0003ed42fa5875780b000104e803000004e8030000504b01021e030a00090000" ++
        "008454954ab41338951c000000100000000d0018000000000000000000b481a4" ++
        "000000656e637279707465642e74787455540500030743fa5875780b000104e8" ++
        "03000004e8030000504b01021e031400090008008a54954ab413389514000000" ++
        "100000001c0018000000000001000000b48117010000656e637279707465642d" ++
        "616e642d636f6d707265737365642e74787455540500031343fa5875780b0001" ++
        "04e803000004e8030000504b0506000000000400040059010000910100000000" ++
    "");
    const entry_names = []const []const u8 {
        "stored.txt",
        "compressed.txt",
        "encrypted.txt",
        "encrypted-and-compressed.txt",
    };
    const entry_is_compressed = []const bool {
        false,
        true,
        false,
        true,
    };
    const entry_is_encrypted = []const bool {
        false,
        false,
        true,
        true,
    };
    const entry_raw_file_data = comptime []const []const u8 {
        hexToBin("61616162616161626161616261616162"),
        hexToBin("4b4c4c4c4a44c200"),
        hexToBin("f72e7bb915142131c934f01b163fcadb2a8db7cdafd0a6f4dd1694c0"),
        hexToBin("7c4d3ea0d9754b470d3eb32ada5741bfc848f419"),
    };

    var zipfile = %%unzip.fromBuffer(zipfile_buffer);
    assert(zipfile.entry_count == 4);

    var entries: [4]Entry = undefined;
    for (entries) |*entry, i| {
        *entry = %%zipfile.readEntry();
        testEntryName(zipfile, entry, entry_names[i]);
        testEntryAttributes(entry, entry_is_compressed[i], entry_is_encrypted[i]);
        testEntryRawFileData(&zipfile, entry, entry_raw_file_data[i]);
    }

    // This should still work after reading to the end
    for (entries) |*entry, i| {
        testEntryName(zipfile, entry, entry_names[i]);
        testEntryAttributes(entry, entry_is_compressed[i], entry_is_encrypted[i]);
        testEntryRawFileData(&zipfile, entry, entry_raw_file_data[i]);
    }
}

fn testEntryName(zipfile: &const ZipFile, entry: &const Entry, expected_name: []const u8) {
    var name_buffer = []u8{0} ** 0x100;
    %%zipfile.readRawEntryFileName(entry, name_buffer[0..entry.file_name_length]);
    assert(mem.eql(u8, name_buffer[0..entry.file_name_length], expected_name));
}
fn testEntryAttributes(entry: &const Entry, expected_compressed: bool, expected_encrypted: bool) {
    assert(entry.isCompressed() == expected_compressed);
    assert(entry.isEncrypted() == expected_encrypted);
}
fn testEntryRawFileData(zipfile: &ZipFile, entry: &const Entry, expected_contents: []const u8) {
    for ([]u64{0, 2}) |start| {
        for ([]u64{3, 5, expected_contents.len}) |end| {
            var stream = %%zipfile.openRawReadStream(entry, start, end);
            var buffer = []u8{0} ** 0x100;
            const expected_read_amount = end - start;
            assert(stream.read(buffer[0..]) == expected_read_amount);
            assert(mem.eql(u8, expected_contents[start .. end], buffer[0 .. expected_read_amount]));
        }
    }
}
