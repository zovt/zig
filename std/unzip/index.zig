// Much of this library is adapted from [yauzl](https://github.com/thejoshwolfe/yauzl)
const mem = @import("std").mem;
const math = @import("std").math;
const assert = @import("std").debug.assert;

error NotAZipFile;
error MultiDiskArchivesNotSupported;
error InvalidZipFileCommentLength;

const eocdr_fixed_size = 22;
pub fn fromBuffer(buffer: []const u8) -> %ZipFile {
    if (buffer.len < eocdr_fixed_size) return error.NotAZipFile;

    // search backward to skip any zipfile comment
    const max_possible_comment_length = 0xffff;
    const max_possible_eocdr_length = eocdr_fixed_size + max_possible_comment_length;
    const earliest_possible_eocdr_start =
        if  (buffer.len < max_possible_eocdr_length) 0
        else buffer.len - max_possible_eocdr_length;
    const eocdr_search_buffer = buffer[earliest_possible_eocdr_start..];
    var comment_length: u64 = 0;
    var eocdr_buffer: []const u8 = undefined;
    while (true) : (comment_length += 1) {
        const search_position = eocdr_search_buffer.len - comment_length - eocdr_fixed_size;
        eocdr_buffer = eocdr_search_buffer[search_position .. search_position + eocdr_fixed_size];
        if (readInt32(eocdr_buffer, 0) == 0x06054b50) break;
        if (comment_length == max_possible_comment_length) return error.NotAZipFile;
    }
    // found it

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
    const reported_comment_length = readInt16(eocdr_buffer, 20);
    // 22 - Comment

    if (comment_length != reported_comment_length) return error.InvalidZipFileCommentLength;

    // TODO: ZIP64 support

    var zipfile = ZipFile{
        .buffer = buffer,
        .entry_count = entry_count,
        .central_directory_cursor = central_directory_offset,
        .read_entry_counter = 0,
        .comment_length = reported_comment_length,
    };

    return zipfile;
}

error UnexpectedEof;
error InvalidCentralDirectoryRecordSignature;
error InvalidLocalFileHeaderSignature;

const central_directory_record_fixed_size = 46;
const local_file_header_fixed_size = 30;

pub const ZipFile = struct {
    buffer: []const u8,
    entry_count : u32,
    read_entry_counter: u32,
    central_directory_cursor : u64,
    comment_length : u16,

    pub fn readRawZipFileComment(self: &const ZipFile, output_buffer: []u8) {
        assert(output_buffer.len >= self.comment_length);
        mem.copy(u8, output_buffer, self.buffer[self.buffer.len - self.comment_length..]);
    }

    pub fn readEntry(self: &ZipFile) -> %Entry {
        assert(self.read_entry_counter < self.entry_count);
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

    pub fn readRawEntryFileName(self: &const ZipFile, entry: &const Entry, output_buffer: []u8) -> %void {
        assert(output_buffer.len >= entry.file_name_length);
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

pub const Entry = struct {
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

test "unzip" {
    _ = @import("test_empty.zig");
    _ = @import("test_readRawZipFileComment.zig");
    _ = @import("test_openRawReadStream.zig");
}
