const assert = @import("std").assert;
const str_eql = @import("std").str.eql;

pub enum TokenType {
    Invalid,
    Text,                  // "text outside tags"
    StartTagStart,         // "<name"
    StartTagEnd,           // ("<name") ">"
    TagSelfClose,          // ("<name") "/>"
    EndTagStart,           // "</name"
    EndTagEnd,             // ("</name") ">"
    AttributeName,         // ("<name ") "name"
    AttributeEquals,       // ("<name ") "="
    AttributeValue,        // ("<name ") "'value'", '"value"'
    ProcessingInstruction, // '<%xml version="1.0">'
    Cdata,                 // "<![CDATA[text]]>"
    Comment,               // "<!--text-->"
}
pub const unfinished_flag: u8 = 1;
pub const continuation_flag: u8 = 2;
pub struct XmlToken {
    token_type: TokenType,
    flags: u8,
    start: isize,
    end: isize,

    pub fn is_unfinished(token: XmlToken) -> bool {
        token.flags & unfinished_flag != 0
    }
    pub fn is_continuation(token: XmlToken) -> bool {
        token.flags & continuation_flag != 0
    }
}

enum Mode {
    None,
    Text,           // "text outside tags"
    TagStart,       // "<"
    StartTagName,   // "<n", "<name"
    InsideStartTag, // "<name "
    TagSelfClose_0, // ("<name ") "/"
    EndTagName,     // "</", "</name"
    InsideEndTag,   // "</name "
    AttributeName,  // ("<name ") "a"
    AttributeValueDoubleQuote, // ("<name ") '"'
    AttributeValueSingleQuote, // ("<name ") "'"
    InsideProcessingInstruction, // "<%", "<%xml version="
    ProcessingInstructionEnd_0,  // "<% %"
    SectionStart,   // "<!"
    CdataStart_2,   // "<!["
    CdataStart_3,   // "<![C"
    CdataStart_4,   // "<![CD"
    CdataStart_5,   // "<![CDA"
    CdataStart_6,   // "<![CDAT"
    CdataStart_7,   // "<![CDATA"
    InsideCdata,    // "<![CDATA["
    CdataEnd_0,     // "<![CDATA[ ]"
    CdataEnd_1,     // "<![CDATA[ ]]"
    CommentStart_2, // "<!-"
    InsideComment,  // "<!--"
    CommentEnd_0,   // "<!-- -"
    CommentEnd_1,   // "<!-- --"
}
pub struct XmlTokenizer {
    src_buf: []const u8,
    is_eof: bool,
    src_buf_offset: isize,
    cursor: isize,
    mode: Mode,
    need_continuation: bool,
    token_start: isize,
    token_type: TokenType,

    pub fn init() -> XmlTokenizer {
        XmlTokenizer {
            .src_buf = []u8{},
            .is_eof = false,
            .src_buf_offset = 0,
            .cursor = 0,
            .mode = Mode.None,
            .need_continuation = false,
            .token_start = undefined,
            .token_type = undefined,
        }
    }

    pub fn load(tokenizer: &XmlTokenizer, source_buffer: []const u8, is_eof: bool) {
        assert(tokenizer.cursor - tokenizer.src_buf_offset == tokenizer.src_buf.len);
        assert(!tokenizer.is_eof);
        tokenizer.src_buf_offset += tokenizer.src_buf.len;
        tokenizer.src_buf = source_buffer;
        tokenizer.is_eof = is_eof;
    }
    pub fn read_tokens(tokenizer: &XmlTokenizer, output_tokens: []XmlToken) -> isize {
        assert(output_tokens.len > 0);
        var output_count: isize = 0;
        // these aliases make calls to put_token() look shorter
        const a1 = &output_tokens;
        const a2 = &output_count;
        const a3 = &tokenizer.need_continuation;
        while (tokenizer.cursor - tokenizer.src_buf_offset < tokenizer.src_buf.len) {
            const c = tokenizer.src_buf[tokenizer.cursor - tokenizer.src_buf_offset];
            switch (tokenizer.mode) {
                None => {
                    switch (c) {
                        '<' => {
                            tokenizer.mode = Mode.TagStart;
                            tokenizer.token_start = tokenizer.cursor;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.Text;
                            tokenizer.token_start = tokenizer.cursor;
                            tokenizer.token_type = TokenType.Text;
                            tokenizer.cursor += 1;
                        },
                    }
                },
                Text => {
                    switch (c) {
                        '<' => {
                            // done
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                TagStart => {
                    // we have a "<"
                    switch (c) {
                        '/' => {
                            tokenizer.mode = Mode.EndTagName;
                            tokenizer.token_type = TokenType.EndTagStart;
                            tokenizer.cursor += 1;
                        },
                        '!' => {
                            tokenizer.mode = Mode.SectionStart;
                            tokenizer.cursor += 1;
                        },
                        '?' => {
                            tokenizer.mode = Mode.InsideProcessingInstruction;
                            tokenizer.token_type = TokenType.ProcessingInstruction;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.StartTagName;
                            tokenizer.token_type = TokenType.StartTagStart;
                        },
                    }
                },
                StartTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '/', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                InsideStartTag => {
                    switch (c) {
                        ' ', '\t', '\n', '\r' => {
                            // skip
                            tokenizer.cursor += 1;
                        },
                        '>' => {
                            tokenizer.mode = Mode.None;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, TokenType.StartTagEnd, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                        '/' => {
                            tokenizer.mode = Mode.TagSelfClose_0;
                            tokenizer.cursor += 1;
                        },
                        '=' => {
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, TokenType.AttributeEquals, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                        '"' => {
                            tokenizer.mode = Mode.AttributeValueDoubleQuote;
                            tokenizer.token_start = tokenizer.cursor;
                            tokenizer.token_type = TokenType.AttributeValue;
                            tokenizer.cursor += 1;
                        },
                        '\'' => {
                            tokenizer.mode = Mode.AttributeValueSingleQuote;
                            tokenizer.token_start = tokenizer.cursor;
                            tokenizer.token_type = TokenType.AttributeValue;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.AttributeName;
                            tokenizer.token_type = TokenType.AttributeName;
                            tokenizer.token_start = tokenizer.cursor;
                        },
                    }
                },
                TagSelfClose_0 => {
                    switch (c) {
                        '>' => {
                            tokenizer.mode = Mode.None;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, TokenType.TagSelfClose, tokenizer.cursor - 1, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // invalid '/'
                            tokenizer.mode = Mode.InsideStartTag;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.cursor - 1, tokenizer.cursor)) goto done;
                        },
                    }
                },
                EndTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideEndTag;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                InsideEndTag => {
                    switch (c) {
                        '>' => {
                            // done
                            tokenizer.mode = Mode.None;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, TokenType.EndTagEnd, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                        ' ', '\t', '\n', '\r' => {
                            // skip
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // invalid characters between "</name" and ">"
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                    }
                },
                AttributeName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '=', '/', '>', '"', '\'' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                AttributeValueDoubleQuote => {
                    switch (c) {
                        '"' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                AttributeValueSingleQuote => {
                    switch (c) {
                        '\'' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                InsideProcessingInstruction => {
                    switch (c) {
                        '?' => {
                            tokenizer.mode = Mode.ProcessingInstructionEnd_0;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.cursor += 1;
                        },
                    }
                },
                ProcessingInstructionEnd_0 => {
                    switch (c) {
                        '>' => {
                            // done
                            tokenizer.mode = Mode.None;
                            tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        '?' => {
                            // keep hoping
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // false alarm
                            tokenizer.mode = Mode.InsideProcessingInstruction;
                            tokenizer.cursor += 1;
                        },
                    }
                },
                SectionStart => {
                    // we have "<!"
                    switch (c) {
                        '-' => {
                            tokenizer.mode = Mode.CommentStart_2;
                            tokenizer.token_type = TokenType.Comment;
                            tokenizer.cursor += 1;
                        },
                        '[' => {
                            tokenizer.mode = Mode.CdataStart_2;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // TODO: dtd stuff
                            unreachable{};
                        },
                    }
                },
                CdataStart_2 => {
                    switch (c) {
                        'C' => {
                            tokenizer.mode = Mode.CdataStart_3;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                CdataStart_3 => {
                    switch (c) {
                        'D' => {
                            tokenizer.mode = Mode.CdataStart_4;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                CdataStart_4 => {
                    switch (c) {
                        'A' => {
                            tokenizer.mode = Mode.CdataStart_5;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                CdataStart_5 => {
                    switch (c) {
                        'T' => {
                            tokenizer.mode = Mode.CdataStart_6;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                CdataStart_6 => {
                    switch (c) {
                        'A' => {
                            tokenizer.mode = Mode.CdataStart_7;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                CdataStart_7 => {
                    switch (c) {
                        '[' => {
                            tokenizer.mode = Mode.InsideCdata;
                            tokenizer.token_type = TokenType.Cdata;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                InsideCdata => {
                    switch (c) {
                        ']' => {
                            tokenizer.mode = Mode.CdataEnd_0;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.cursor += 1;
                        },
                    }
                },
                CdataEnd_0 => {
                    switch (c) {
                        ']' => {
                            tokenizer.mode = Mode.CdataEnd_1;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.InsideCdata;
                            tokenizer.cursor += 1;
                        },
                    }
                },
                CdataEnd_1 => {
                    switch (c) {
                        '>' => {
                            tokenizer.mode = Mode.None;
                            tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                        ']' => {
                            // keep hoping
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.InsideCdata;
                            tokenizer.cursor += 1;
                        },
                    }
                },
                CommentStart_2 => {
                    switch (c) {
                        '-' => {
                            tokenizer.mode = Mode.InsideComment;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // "<!-x"
                            tokenizer.mode = Mode.None;
                            if (put_token(a1, a2, a3, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
                        },
                    }
                },
                InsideComment => {
                    switch (c) {
                        '-' => {
                            tokenizer.mode = Mode.CommentEnd_0;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.cursor += 1;
                        },
                    }
                },
                CommentEnd_0 => {
                    switch (c) {
                        '-' => {
                            tokenizer.mode = Mode.CommentEnd_1;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.InsideComment;
                            tokenizer.cursor += 1;
                        },
                    }
                },
                CommentEnd_1 => {
                    switch (c) {
                        '>' => {
                            tokenizer.mode = Mode.None;
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // technically an error, but we tolerate it.
                            tokenizer.cursor += 1;
                        },
                    }
                },
            }
        }

        // the input buffer has been exhausted
        if (!tokenizer.is_eof) {
            // flush any partial content spanning chunk boundaries
            const trailing_uncertainty = get_unfinished_token_trailing_uncertainty(tokenizer.mode);
            if (trailing_uncertainty != -1) {
                const token_end = tokenizer.cursor - trailing_uncertainty;
                if (tokenizer.token_start != token_end) {
                    // publish what we got so far
                    put_unfinished_token(a1, a2, a3, tokenizer.token_type, tokenizer.token_start, token_end);
                    tokenizer.token_start = token_end;
                }
            } else {
                // no partial tokens for these
            }
        } else {
            // the is the end
            switch (tokenizer.mode) {
                None => {
                    // all good
                },
                Text => {
                    // flush the last text
                    tokenizer.mode = Mode.None;
                    if (put_token(a1, a2, a3, TokenType.Text, tokenizer.token_start, tokenizer.cursor)) goto done;
                },
                else => {
                    // TODO: report early EOF
                    unreachable{};
                },
            }
        }
        done:
        return output_count;
    }
    pub fn copy_content(tokenizer: &XmlTokenizer, token: XmlToken, output_buf: []u8) -> isize {
        var skip_start: isize = undefined;
        var skip_end: isize = 0;
        switch (token.token_type) {
            Invalid, StartTagEnd, TagSelfClose, EndTagEnd, AttributeEquals => {
                // no text content at all
                return 0;
            },
            Text, AttributeName => {
                skip_start = 0;
            },
            StartTagStart => {
                skip_start = 1;
            },
            AttributeValue => {
                skip_start = 1;
                skip_end = 1;
            },
            EndTagStart => {
                skip_start = 2;
            },
            ProcessingInstruction => {
                skip_start = 2;
                skip_end = 2;
            },
            Cdata => {
                skip_start = 9;
                skip_end = 3;
            },
            Comment => {
                skip_start = 4;
                skip_end = 3;
            },
        };
        if (token.is_continuation()) {
            skip_start = 0;
        }
        if (token.is_unfinished()) {
            skip_end = 0;
        }
        var local_start = token.start + skip_start - tokenizer.src_buf_offset;
        var local_end = token.end - skip_end - tokenizer.src_buf_offset;
        var len = local_end - local_start;
        const return_len = len;
        var output_cursor: isize = 0;
        while (local_start < 0 && len > 0; {local_start += 1; len -= 1}) {
            // backfill the output buffer with whatever character was leading us to believe
            // it was going to terminate this token, but really didn't.
            const tease_char: u8 = switch (token.token_type) {
                Comment => '-',
                Cdata => ']',
                ProcessingInstruction => '?',
                else => unreachable{},
            };
            assert(output_buf.len >= output_cursor + 1);
            output_buf[output_cursor] = tease_char;
            output_cursor += 1;
        }
        if (len != 0) {
            assert(output_buf.len >= output_cursor + len);
            @memcpy(&output_buf[output_cursor], &tokenizer.src_buf[local_start], len);
        }
        return return_len;
    }
}
fn put_unfinished_token(output_tokens: &[]XmlToken, output_count: &isize, need_continuation: &bool, token_type: TokenType, start: isize, end: isize) {
    put_exact_token(output_tokens, output_count, need_continuation, token_type, start, end, true);
}
fn put_token(output_tokens: &[]XmlToken, output_count: &isize, need_continuation: &bool, token_type: TokenType, start: isize, end: isize) -> bool {
    return put_exact_token(output_tokens, output_count, need_continuation, token_type, start, end, false);
}
fn put_exact_token(output_tokens: &[]XmlToken, output_count: &isize, need_continuation: &bool, token_type: TokenType, start: isize, end: isize, is_unfinished: bool) -> bool {
    const flags =
        (if (is_unfinished) unfinished_flag else 0) |
        (if (*need_continuation) continuation_flag else 0);
    *need_continuation = is_unfinished;
    (*output_tokens)[*output_count] = XmlToken{
        .token_type = token_type,
        .flags = flags,
        .start = start,
        .end = end,
    };
    *output_count += 1;
    return *output_count >= output_tokens.len;
}
fn get_unfinished_token_trailing_uncertainty(mode: Mode) -> isize {
    return switch (mode) {
        // no text content to publish
        None, TagStart, InsideStartTag, TagSelfClose_0, InsideEndTag,
        SectionStart, CommentStart_2,
        CdataStart_2,
        CdataStart_3,
        CdataStart_4,
        CdataStart_5,
        CdataStart_6,
        CdataStart_7 => -1,

        // publish right up to the cursor
        Text, StartTagName, EndTagName, AttributeName, InsideCdata, InsideComment,
        InsideProcessingInstruction, AttributeValueDoubleQuote, AttributeValueSingleQuote => 0,

        // hesitate on the last characters, because it might be the start of the terminator
        ProcessingInstructionEnd_0 => 1,
        CommentEnd_0 => 1,
        CommentEnd_1 => 2,
        CdataEnd_0 => 1,
        CdataEnd_1 => 2,
    }
}

#attribute("test")
fn xml_tag_test() {
    const source = "<a><b/></a>";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.StartTagStart, 0, 2, "a"),
        make_token(TokenType.StartTagEnd, 2, 3, ""),
        make_token(TokenType.StartTagStart, 3, 5, "b"),
        make_token(TokenType.TagSelfClose, 5, 7, ""),
        make_token(TokenType.EndTagStart, 7, 10, "a"),
        make_token(TokenType.EndTagEnd, 10, 11, ""),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_attribute_test() {
    const source = r"XML(<b a="c" de='fg'/>)XML";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.StartTagStart, 0, 2, "b"),
        make_token(TokenType.AttributeName, 3, 4, "a"),
        make_token(TokenType.AttributeEquals, 4, 5, ""),
        make_token(TokenType.AttributeValue, 5, 8, "c"),
        make_token(TokenType.AttributeName, 9, 11, "de"),
        make_token(TokenType.AttributeEquals, 11, 12, ""),
        make_token(TokenType.AttributeValue, 12, 16, "fg"),
        make_token(TokenType.TagSelfClose, 16, 18, ""),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_simple_text_test() {
    const source = "text";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.Text, 0, 4, "text"),
    };
    test_every_which_way(source, expected_tokens);
}
#attribute("test")
fn xml_tags_and_text_test() {
    const source = "a <b/> c";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.Text, 0, 2, "a "),
        make_token(TokenType.StartTagStart, 2, 4, "b"),
        make_token(TokenType.TagSelfClose, 4, 6, ""),
        make_token(TokenType.Text, 6, 8, " c"),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_simple_comment_test() {
    const source = "<!-- comment -->";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.Comment, 0, source.len, " comment "),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_cdata_test() {
    const source = "<![CDATA[a<b>c]]>";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.Cdata, 0, source.len, "a<b>c"),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_tricky_tokenizer_test() {
    const source = "<![CDATA[]]]]]]>";
    const expected_tokens = []?ExpectedToken{
        make_token(TokenType.Cdata, 0, source.len, "]]]]"),
    };
    test_every_which_way(source, expected_tokens);
}

#attribute("test")
fn xml_processing_instruction_test() {
    const s1 = "xml version=\"1.0\"";
    const s2 = "name";
    const s3 = "actually-fine ?\"?";
    const source =
        "<?" ++ s1 ++ "?>" ++
        "<?" ++ s2 ++ "?>" ++
        "<?" ++ s3 ++ "?>";
    var cursor: isize = 0;
    const t1 = make_token(TokenType.ProcessingInstruction, cursor, {cursor += s1.len + 4; cursor}, s1);
    const t2 = make_token(TokenType.ProcessingInstruction, cursor, {cursor += s2.len + 4; cursor}, s2);
    const t3 = make_token(TokenType.ProcessingInstruction, cursor, {cursor += s3.len + 4; cursor}, s3);
    const expected_tokens = []?ExpectedToken{t1, t2, t3};
    test_every_which_way(source, expected_tokens);
}

//TODO: #attribute("test")
fn xml_complex_test() {
    const source = r"XML(
<?xml version="1.0"?>
<?processing-instruction?>
<!DOCTYPE an-internal-dtd [
  <!-- comment inside internal DTD ]> -->
  <%dont-look-here ]>%>
  <!ENTITY % not-this ']>'>
  <!ENTITY or-this "]>">
] >
<root>
  <group name="Group 1" type="Normal">
    <Prime frame="1" alive="true"/>
    <secondary x="176" y="608" frame="0">
      Text <i>and </i>  stuff.
    </secondary>
  </group>
  <group name="Group 2" type="Crazy">
    <a-:_2. quot='"' apos="'"
        characters="&#9;, &#x10FFFF;, &#1114111;"
        elements="&amp;&lt;&gt;&apos;&quot;"/>
    <![CDATA[<literal text="in">a &quot;<![CDATA[>/literal>]]>
    <!--
      comment <contains> &apos; </stuff>
    -->
  </group>
</root>
)XML";
    const expected_tokens = []?ExpectedToken{
        // TODO
    };
    test_every_which_way(source, expected_tokens);
}

struct ExpectedToken {
    token: XmlToken,
    text: []const u8,
}
fn make_token(token_type: TokenType, start: isize, end: isize, text: []const u8) -> ExpectedToken {
    ExpectedToken{
        .token = XmlToken{
            .token_type = token_type,
            .flags = 0,
            .start = start,
            .end = end,
        },
        .text = text,
    }
}
fn token_equals(a: XmlToken, b: XmlToken) -> bool {
    a.token_type == b.token_type &&
    a.flags      == b.flags      &&
    a.start      == b.start      &&
    a.end        == b.end        &&
    true
}
fn test_every_which_way(source: []const u8, expected_tokens: []const ?ExpectedToken) {
    test_all_at_once(source, expected_tokens);
    test_constrained_output(source, expected_tokens);

    // 1 byte at a time
    {
        var sources_array: [0x1000][]const u8 = undefined;
        for (source) |_, i| {
            sources_array[i] = source[i...i + 1];
        }
        test_streaming_input(sources_array[0...source.len], expected_tokens);
    }

    // test every possible seam
    {
        var cut_offset: isize = 0;
        while (cut_offset < source.len + 1; cut_offset += 1) {
            var sources_array = [][]const u8{
                source[0...cut_offset],
                source[cut_offset...],
            };
            test_streaming_input(sources_array, expected_tokens);
        }
    }
}

fn test_all_at_once(source: []const u8, expected_tokens: []const ?ExpectedToken) {
    var tokens: [0x1000]XmlToken = undefined;
    var tokenizer = XmlTokenizer.init();
    tokenizer.load(source, true);
    const output_count = tokenizer.read_tokens(tokens);
    assert(output_count == expected_tokens.len);
    for (expected_tokens) |maybe_expected_token, i| {
        if (const expected_token ?= maybe_expected_token) {
            assert(token_equals(expected_token.token, tokens[i]));

            var buf: [0x1000]u8 = undefined;
            const text = buf[0...tokenizer.copy_content(tokens[i], buf)];
            assert(str_eql(expected_token.text, text));
        }
    }
}

fn test_constrained_output(source: []const u8, expected_tokens: []const ?ExpectedToken) {
    var tokens: [1]XmlToken = undefined;
    var tokenizer = XmlTokenizer.init();
    tokenizer.load(source, true);
    for (expected_tokens) |maybe_expected_token| {
        const output_count = tokenizer.read_tokens(tokens);
        assert(output_count == 1);
        if (const expected_token ?= maybe_expected_token) {
            assert(token_equals(expected_token.token, tokens[0]));

            var buf: [0x1000]u8 = undefined;
            const text = buf[0...tokenizer.copy_content(tokens[0], buf)];
            assert(str_eql(expected_token.text, text));
        }
    }
    const output_count = tokenizer.read_tokens(tokens);
    assert(output_count == 0);
}

fn test_streaming_input(sources: []const[]const u8, expected_tokens: []const ?ExpectedToken) {
    var tokenizer = XmlTokenizer.init();
    var scratch_token: XmlToken = undefined;
    scratch_token.flags = 0;
    var text_buf: [0x1000]u8 = undefined;
    var text_len: isize = 0;

    var complete_output_count: isize = 0;
    var input_cursor: isize = 0;
    while (input_cursor < sources.len + 1; input_cursor += 1) {
        if (input_cursor < sources.len) {
            tokenizer.load(sources[input_cursor], false);
        } else {
            tokenizer.load([]u8{}, true);
        }
        while (true) {
            var output_tokens: [1]XmlToken = undefined;
            const output_count = tokenizer.read_tokens(output_tokens);
            if (output_count == 0) break;

            assert(output_count == 1);
            const output_token = output_tokens[0];
            if (scratch_token.is_unfinished()) {
                assert(output_token.is_continuation());
                // extend partial scratch token
                const true_start = scratch_token.start;
                scratch_token = output_token;
                scratch_token.start = true_start;
                scratch_token.flags &= ~continuation_flag;
            } else {
                assert(!output_token.is_continuation());
                scratch_token = output_token;
                text_len = 0;
            }
            text_len += tokenizer.copy_content(output_token, text_buf[text_len...]);
            if (!output_token.is_unfinished()) {
                assert(complete_output_count < expected_tokens.len);
                if (const expected_token ?= expected_tokens[complete_output_count]) {
                    assert(token_equals(expected_token.token, scratch_token));
                    assert(str_eql(expected_token.text, text_buf[0...text_len]));
                }
                complete_output_count += 1;
            }
        }
    }

    assert(complete_output_count == expected_tokens.len);
}
