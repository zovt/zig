const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

error NotAZipFile;
error MultiDiskArchivesNotSupported;

const eocdr_len = 22;
pub fn fromBuffer(buffer: []const u8) -> %ZipFile {
    if (buffer.len < eocdr_len) return error.NotAZipFile;
    const eocdr_buffer = buffer[buffer.len - eocdr_len ..];
    // TODO: search backward to skip any zipfile comment
    if (readInt32(eocdr_buffer, 0) != 0x06054b50) return error.NotAZipFile;

    // 0 - End of central directory signature = 0x06054b50
    // 4 - Number of this disk
    if (readInt16(eocdr_buffer, 4) != 0) return error.MultiDiskArchivesNotSupported;
    // 6 - Disk where central directory starts
    // 8 - Number of central directory records on this disk
    // 10 - Total number of central directory records
    const entry_count = readInt16(eocdr_buffer, 10);
    // 12 - Size of central directory (bytes)
    // 16 - Offset of start of central directory, relative to start of archive
    const central_directory_offset = readInt32(eocdr_buffer, 16);
    // 20 - Comment length
    // TODO: worry about comment length
    // 22 - Comment
    // (the encoding is always cp437.)

    // TODO: ZIP64 support

    var zipfile = ZipFile{
        .buffer = buffer,
        .entry_count = entry_count,
        .central_directory_cursor = central_directory_offset,
        .read_entry_counter = 0,
    };

    return zipfile;
}

error EndOfEntries;
error UnexpectedEof;
error InvalidCentralDirectoryRecordSignature;
error FileNameTooLong;
error InvalidLocalFileHeaderSignature;

const central_directory_record_fixed_size = 46;
const local_file_header_fixed_size = 30;

pub const ZipFile = struct {
    buffer: []const u8,
    entry_count : u32,
    read_entry_counter: u32,
    central_directory_cursor : u64,

    pub fn readEntry(self: &ZipFile) -> %Entry {
        if (self.read_entry_counter >= self.entry_count) return error.EndOfEntries;
        const entry_end = math.add(u64,
            self.central_directory_cursor,
            central_directory_record_fixed_size)
            %% return error.UnexpectedEof;
        if (entry_end > self.buffer.len) return error.UnexpectedEof;
        const entry_buffer = self.buffer[self.central_directory_cursor .. entry_end];

        // 0 - Central directory file header signature
        var signature = readInt32(entry_buffer, 0);
        if (signature != 0x02014b50) return error.InvalidCentralDirectoryRecordSignature;
        const entry = Entry{
            // save this so we can read the name later
            .central_directory_record_offset = self.central_directory_cursor,

            // 4 - Version made by
            .version_made_by = readInt16(entry_buffer, 4),
            // 6 - Version needed to extract (minimum)
            .version_needed_to_extract = readInt16(entry_buffer, 6),
            // 8 - General purpose bit flag
            .general_purpose_bit_flag = readInt16(entry_buffer, 8),
            // 10 - Compression method
            .compression_method = readInt16(entry_buffer, 10),
            // 12 - File last modification time
            .last_mod_file_time = readInt16(entry_buffer, 12),
            // 14 - File last modification date
            .last_mod_file_date = readInt16(entry_buffer, 14),
            // 16 - CRC-32
            .crc32 = readInt32(entry_buffer, 16),
            // 20 - Compressed size
            .compressed_size = readInt32(entry_buffer, 20),
            // 24 - Uncompressed size
            .uncompressed_size = readInt32(entry_buffer, 24),
            // 28 - File name length (n)
            .file_name_length = readInt16(entry_buffer, 28),
            // 30 - Extra field length (m)
            .extra_field_length = readInt16(entry_buffer, 30),
            // 32 - File comment length (k)
            .file_comment_length = readInt16(entry_buffer, 32),
            // 34 - Disk number where file starts
            // 36 - Internal file attributes
            .internal_file_attributes = readInt16(entry_buffer, 36),
            // 38 - External file attributes
            .external_file_attributes = readInt32(entry_buffer, 38),
            // 42 - Relative offset of local file header
            .relative_offset_of_local_header = readInt32(entry_buffer, 42),
        };

        // TODO: check for ZIP64 extended information extra field if necessary

        // advance the cursors
        const total_entry_size: u64 =
            central_directory_record_fixed_size +
            u64(entry.file_name_length) +
            u64(entry.extra_field_length) +
            u64(entry.file_comment_length);
        const next_entry_start = math.add(u64,
            self.central_directory_cursor,
            total_entry_size)
            %% return error.UnexpectedEof;
        if (next_entry_start > self.buffer.len) return error.UnexpectedEof;
        self.central_directory_cursor = next_entry_start;
        self.read_entry_counter += 1;

        return entry;
    }

    pub fn readEntryFileName(self: &const ZipFile, entry: &const Entry, output_buffer: []u8) -> %void {
        if (output_buffer.len < entry.file_name_length) return error.FileNameTooLong;
        // We already checked that this was in bounds when we read the entry.
        const file_name_start = entry.central_directory_record_offset + central_directory_record_fixed_size;
        mem.copy(u8, output_buffer, self.buffer[file_name_start .. file_name_start + entry.file_name_length]);
    }

    pub fn openRawReadStream(self: &ZipFile, entry: &const Entry, start: u64, end: u64) -> %Stream {
        assert(start <= end and end <= entry.compressed_size);

        const local_file_header_start = entry.relative_offset_of_local_header;
        const local_file_header_file_name_start = math.add(u64,
            local_file_header_start,
            local_file_header_fixed_size)
            %% return error.UnexpectedEof;
        if (local_file_header_file_name_start > self.buffer.len) return error.UnexpectedEof;
        const local_file_header_buffer = self.buffer[local_file_header_start .. local_file_header_file_name_start];

        // 0 - Local file header signature = 0x04034b50
        if (readInt32(local_file_header_buffer, 0) != 0x04034b50) return error.InvalidLocalFileHeaderSignature;

        // all this should be redundant
        // 4 - Version needed to extract (minimum)
        // 6 - General purpose bit flag
        // 8 - Compression method
        // 10 - File last modification time
        // 12 - File last modification date
        // 14 - CRC-32
        // 18 - Compressed size
        // 22 - Uncompressed size
        // 26 - File name length (n)
        const local_file_header_file_name_length = readInt16(local_file_header_buffer, 26);
        // 28 - Extra field length (m)
        const local_file_header_extra_field_length = readInt16(local_file_header_buffer, 28);
        // 30 - File name
        // 30+n - Extra field

        const raw_data_start = math.add(u64,
            local_file_header_file_name_start,
            u64(local_file_header_file_name_length) + u64(local_file_header_extra_field_length))
            %% return error.UnexpectedEof;

        const raw_data_end = math.add(u64,
            raw_data_start,
            entry.compressed_size)
            %% return error.UnexpectedEof;

        if (raw_data_end > self.buffer.len) return error.UnexpectedEof;

        return Stream{
            .zipfile = self,
            .cursor = raw_data_start + start,
            .end = raw_data_end - (entry.compressed_size - end),
        };
    }
};

const Entry = struct {
    central_directory_record_offset: u64,
    version_made_by: u16,
    version_needed_to_extract: u16,
    general_purpose_bit_flag: u16,
    compression_method: u16,
    last_mod_file_time: u16,
    last_mod_file_date: u16,
    crc32: u32,
    compressed_size: u64,
    uncompressed_size: u64,
    file_name_length: u16,
    extra_field_length: u16,
    file_comment_length: u16,
    internal_file_attributes: u16,
    external_file_attributes: u32,
    relative_offset_of_local_header: u64,

    pub fn isCompressed(self: &const Entry) -> bool {
        return self.compression_method == 8;
    }
    pub fn isEncrypted(self: &const Entry) -> bool {
        return self.general_purpose_bit_flag & 0x1 != 0;
    }
};

const Stream = struct {
    zipfile: &ZipFile,
    cursor: u64,
    end: u64,

    pub fn read(self: &Stream, buffer: []u8) -> usize {
        // this was checked before the stream was made
        assert(self.end <= self.zipfile.buffer.len);

        const remaining = self.end - self.cursor;
        const read_amount = math.min(buffer.len, remaining);
        mem.copy(u8, buffer, self.zipfile.buffer[self.cursor .. self.cursor + read_amount]);

        self.cursor += read_amount;
        return read_amount;
    }
};

fn readInt16(buffer: []const u8, offset: usize) -> u16 {
    mem.readInt(buffer[offset .. offset + 2], u16, false)
}
fn readInt32(buffer: []const u8, offset: usize) -> u32 {
    mem.readInt(buffer[offset .. offset + 4], u32, false)
}

test "openRawReadStream" {
    @setEvalBranchQuota(100000);

    // Thanks to https://github.com/thejoshwolfe/yauzl for this test data.
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
    assert(zipfile_buffer[0] == 0x50);
    assert(zipfile_buffer[2] == 0x03);
    const entry_names = []const []const u8{
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

    var zipfile = %%fromBuffer(zipfile_buffer);
    assert(zipfile.entry_count == 4);

    var entries: [4]Entry = undefined;
    for (entries) |*entry, i| {
        *entry = %%zipfile.readEntry();
        testEntryName(zipfile, entry, entry_names[i]);
        testEntryAttributes(entry, entry_is_compressed[i], entry_is_encrypted[i]);
        testEntryRawFileData(&zipfile, entry, entry_raw_file_data[i]);
    }

    for ([]void{{}} ** 2) |_| {
        // TODO: using _ twice shouldn't result in a redeclaration error
        if (zipfile.readEntry()) |_unused| unreachable
        else |e| assert(e == error.EndOfEntries);
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
    %%zipfile.readEntryFileName(entry, name_buffer[0..entry.file_name_length]);
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

fn hexToBin(comptime hexString: []const u8) -> [@divExact(hexString.len, 2)]u8 {
    const finalLen = @divExact(hexString.len, 2);
    var result: [finalLen]u8 = undefined;
    {var i = 0; while (i < finalLen) : (i += 1) {
        result[i] = %%std.fmt.parseUnsigned(u8, hexString[i * 2 .. i * 2 + 2], 16);
    }}
    return result;
}
