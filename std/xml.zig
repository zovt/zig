const assert = @import("std").assert;
const str_eql = @import("std").str.eql;

pub enum TokenType {
    Invalid,
    Text,            // "text outside tags"
    StartTagStart,   // "<name"
    StartTagEnd,     // ("<name") ">"
    TagSelfClose,    // ("<name") "/>"
    EndTagStart,     // "</name"
    EndTagEnd,       // ("</name") ">"
    AttributeName,   // ("<name ") "name"
    AttributeEquals, // ("<name ") "="
    AttributeValue,  // ("<name ") "'value'", '"value"'
    Comment,         // "<!--text-->"
}
pub const continuation_flag = 1;
pub const unfinished_flag = 2;
pub struct XmlToken {
    token_type: TokenType,
    flags: u8,
    start: isize,
    end: isize,

    pub fn is_continuation(token: XmlToken) -> bool {
        token.flags & continuation_flag != 0
    }
    pub fn is_unfinished(token: XmlToken) -> bool {
        token.flags & unfinished_flag != 0
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
    SpecialTagStart,// "<!"
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
        const a3 = tokenizer.need_continuation;
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
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
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
                            tokenizer.mode = Mode.SpecialTagStart;
                            tokenizer.cursor += 1;
                        },
                        // TODO: '?'
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
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
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
                            if (put_token(a1, a2, TokenType.StartTagEnd, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                        '/' => {
                            tokenizer.mode = Mode.TagSelfClose_0;
                            tokenizer.cursor += 1;
                        },
                        '=' => {
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, TokenType.AttributeEquals, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
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
                            if (put_token(a1, a2, TokenType.TagSelfClose, tokenizer.cursor - 1, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // invalid '/'
                            tokenizer.mode = Mode.InsideStartTag;
                            if (put_token(a1, a2, TokenType.Invalid, tokenizer.cursor - 1, tokenizer.cursor)) goto done;
                        },
                    }
                },
                EndTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideEndTag;
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
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
                            if (put_token(a1, a2, TokenType.EndTagEnd, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                        ' ', '\t', '\n', '\r' => {
                            // skip
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // invalid characters between "</name" and ">"
                            defer tokenizer.cursor += 1;
                            if (put_token(a1, a2, TokenType.Invalid, tokenizer.cursor, tokenizer.cursor + 1)) goto done;
                        },
                    }
                },
                AttributeName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '=', '/', '>', '"', '\'' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor)) goto done;
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
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
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
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
                SpecialTagStart => {
                    // we have "<!"
                    switch (c) {
                        '-' => {
                            tokenizer.mode = Mode.CommentStart_2;
                            tokenizer.token_type = TokenType.Comment;
                            tokenizer.cursor += 1;
                        },
                        // TODO: '['
                        else => {
                            // TODO: dtd stuff
                            unreachable{};
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
                            if (put_token(a1, a2, TokenType.Invalid, tokenizer.token_start, tokenizer.cursor)) goto done;
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
                            if (put_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor + 1)) goto done;
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
            if (mode_has_text_content(tokenizer.mode)) {
                // publish what we got so far
                put_unfinished_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor);
                tokenizer.need_continuation = true;
            } else {
                // no partial tokens for these
                tokenizer.need_continuation = false;
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
                    if (put_token(a1, a2, TokenType.Text, tokenizer.token_start, tokenizer.cursor)) goto done;
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
        const local_start = token.start + skip_start - tokenizer.src_buf_offset;
        const local_end = token.end - skip_end - tokenizer.src_buf_offset;
        const len = local_end - local_start;
        assert(output_buf.len >= len);
        @memcpy(&output_buf[0], &tokenizer.src_buf[local_start], len);
        return len;
    }
}
fn put_unfinished_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize) {
    put_exact_token(output_tokens, output_count, token_type, start, end, unfinished_flag);
}
fn put_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize) -> bool {
    return put_exact_token(output_tokens, output_count, token_type, start, end, 0);
}
fn put_exact_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize, flags: u8) -> bool {
    (*output_tokens)[*output_count] = XmlToken{
        .token_type = token_type,
        .flags = flags,
        .start = start,
        .end = end,
    };
    *output_count += 1;
    return *output_count >= output_tokens.len;
}
fn mode_has_text_content(mode: Mode) -> bool {
    return switch (mode) {
        None, TagStart, InsideStartTag, TagSelfClose_0, InsideEndTag,
        SpecialTagStart, CommentStart_2, CommentEnd_0, CommentEnd_1 => false,

        Text, StartTagName, EndTagName, AttributeName, InsideComment,
        AttributeValueDoubleQuote, AttributeValueSingleQuote => true,
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

//TODO: #attribute("test")
fn xml_complex_test() {
    const source = r"XML(
<?xml version="1.0"?>
<?processing-instruction?>
<!-- TODO: internal dtd craziness -->
<root>
  <group name="Group 1" type="Normal">
    <Prime frame="1" alive="true"/>
    <secondary x="176" y="608" frame="0">
      Text <i>and </i>  stuff.
    </secondary>
  </group>
  <group name="Group 2" type="Crazy">
    <a-:_2. quot='"' apos="'"
        elements="&amp;&lt;&gt;&apos;&quot;"/>
        characters="&#9;, &#x10FFFF;, &#1114111;"
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
fn test_every_which_way(source: []const u8, expected_tokens: []?ExpectedToken) {
    test_all_at_once(source, expected_tokens);
    test_constrained_output(source, expected_tokens);
    test_chopped_input(source, expected_tokens);
}

fn test_all_at_once(source: []const u8, expected_tokens: []?ExpectedToken) {
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

fn test_constrained_output(source: []const u8, expected_tokens: []?ExpectedToken) {
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

fn test_chopped_input(source: []const u8, expected_tokens: []?ExpectedToken) {
    var tokenizer = XmlTokenizer.init();
    var scratch_token: XmlToken = undefined;
    scratch_token.flags = 0;
    var text_buf: [0x1000]u8 = undefined;
    var text_len: isize = 0;

    var complete_output_count: isize = 0;
    var input_cursor: isize = 0;
    while (input_cursor <= source.len; input_cursor += 1) {
        if (input_cursor < source.len) {
            tokenizer.load(source[input_cursor...input_cursor + 1], false);
        } else {
            tokenizer.load([]u8{}, true);
        }
        var output_tokens: [3]XmlToken = undefined;
        const output_count = tokenizer.read_tokens(output_tokens);
        // 2 tokens is possible when feeding the ">" of "<a>"
        // 3 tokens is not possible
        assert(output_count < 3);
        for (output_tokens[0...output_count]) |output_token| {
            if (scratch_token.is_unfinished()) {
                assert(output_token.is_continuation());
                // extend partial scratch token
                const true_start = scratch_token.start;
                scratch_token = output_token;
                scratch_token.start = true_start;
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
