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
pub struct XmlToken {
    token_type: TokenType,
    start: isize,
    end: isize,
    is_partial: bool,
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
    token_start: isize,
    token_type: TokenType,

    pub fn init() -> XmlTokenizer {
        XmlTokenizer {
            .src_buf = []u8{},
            .is_eof = false,
            .src_buf_offset = 0,
            .cursor = 0,
            .mode = Mode.None,
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
        if (tokenizer.is_eof) {
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
        } else {
            switch (tokenizer.mode) {
                None, TagStart, InsideStartTag, TagSelfClose_0, InsideEndTag,
                SpecialTagStart, CommentStart_2, CommentEnd_0, CommentEnd_1 => {
                    // no partial tokens for these
                },
                Text, StartTagName, EndTagName, AttributeName, InsideComment,
                AttributeValueDoubleQuote, AttributeValueSingleQuote => {
                    // publish what we got so far
                    put_partial_token(a1, a2, tokenizer.token_type, tokenizer.token_start, tokenizer.cursor);
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
        const local_start = token.start + skip_start - tokenizer.src_buf_offset;
        const local_end = token.end - skip_end - tokenizer.src_buf_offset;
        const len = local_end - local_start;
        assert(output_buf.len >= len);
        @memcpy(&output_buf[0], &tokenizer.src_buf[local_start], len);
        return len;
    }
}
fn put_partial_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize) {
    put_exact_token(output_tokens, output_count, token_type, start, end, true);
}
fn put_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize) -> bool {
    return put_exact_token(output_tokens, output_count, token_type, start, end, false);
}
fn put_exact_token(output_tokens: &[]XmlToken, output_count: &isize, token_type: TokenType, start: isize, end: isize, is_partial: bool) -> bool {
    (*output_tokens)[*output_count] = XmlToken{
        .token_type = token_type,
        .start = start,
        .end = end,
        .is_partial = is_partial,
    };
    *output_count += 1;
    return *output_count >= output_tokens.len;
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
            .start = start,
            .end = end,
            .is_partial = false,
        },
        .text = text,
    }
}
fn token_equals(a: XmlToken, b: XmlToken) -> bool {
    a.token_type == b.token_type &&
    a.start      == b.start      &&
    a.end        == b.end        &&
    a.is_partial == b.is_partial &&
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
        }
    }
    const output_count = tokenizer.read_tokens(tokens);
    assert(output_count == 0);
}

fn test_chopped_input(source: []const u8, expected_tokens: []?ExpectedToken) {
    var tokens: [0x1000]XmlToken = undefined;
    var tokenizer = XmlTokenizer.init();
    var output_cursor: isize = 0;
    var input_cursor: isize = 0;
    while (input_cursor <= source.len; input_cursor += 1) {
        if (input_cursor < source.len) {
            tokenizer.load(source[input_cursor...input_cursor + 1], false);
        } else {
            tokenizer.load([]u8{}, true);
        }
        var output_tokens: [3]XmlToken = undefined;
        const output_count = tokenizer.read_tokens(output_tokens);
        switch (output_count) {
            0 => continue,
            1, 2 => {
                // 2 tokens is possible when feeding the ">" of "<a>"
                for (output_tokens[0...output_count]) |output_token| {
                    if (output_cursor > 0 && tokens[output_cursor - 1].is_partial) {
                        const tmp = tokens[output_cursor - 1].start;
                        tokens[output_cursor - 1] = output_token;
                        tokens[output_cursor - 1].start = tmp;
                    } else {
                        tokens[output_cursor] = output_token;
                        output_cursor += 1;
                    }
                }
            },
            3 => unreachable{},
        }
    }

    assert(output_cursor == expected_tokens.len);

    for (expected_tokens) |maybe_expected_token, i| {
        if (const expected_token ?= maybe_expected_token) {
            assert(token_equals(expected_token.token, tokens[i]));
        }
    }
}
