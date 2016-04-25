const assert = @import("std").assert;

pub enum TokenType {
    Invalid,
    StartTagStart,   // "<name"
    StartTagEnd,     // ("<name") ">"
    TagSelfClose,    // ("<name") "/>"
    EndTagStart,     // "</name"
    EndTagEnd,       // ("</name") ">"
    AttributeName,   // ("<name ") "name"
    AttributeEquals, // ("<name ") "="
    AttributeValue,  // ("<name ") "'value'", '"value"'
}
pub struct XmlToken {
    token_type: TokenType,
    start: isize,
    end: isize,
}

enum Mode {
    None,
    TagStart,       // "<"
    StartTagName,   // "<n", "<name"
    InsideStartTag, // "<name "
    TagSelfClose_0, // ("<name ") "/"
    EndTagName,     // "</", "</name"
    InsideEndTag,   // "</name "
    AttributeName,  // ("<name ") "a"
    AttributeValueDoubleQuote, // ("<name ") '"'
    AttributeValueSingleQuote, // ("<name ") "'"
}
pub struct XmlTokenizer {
    src_buf: []const u8,
    cursor: isize,
    mode: Mode,

    pub fn init() -> XmlTokenizer {
        XmlTokenizer {
            .src_buf = []u8{},
            .cursor = 0,
            .mode = Mode.None,
        }
    }

    pub fn is_eof_acceptible(tokenizer: &XmlTokenizer) -> bool {
        tokenizer.cursor == tokenizer.src_buf.len &&
        tokenizer.mode == Mode.None
    }

    pub fn load(tokenizer: &XmlTokenizer, source_buffer: []const u8) {
        tokenizer.src_buf = source_buffer;
    }
    pub fn read_tokens(tokenizer: &XmlTokenizer, output_tokens: []XmlToken) -> isize {
        assert(output_tokens.len > 0);
        var output_count: isize = 0;
        var token_start: isize = undefined;
        while (tokenizer.cursor < tokenizer.src_buf.len) {
            const c = tokenizer.src_buf[tokenizer.cursor];
            switch (tokenizer.mode) {
                None => {
                    switch (c) {
                        '<' => {
                            tokenizer.mode = Mode.TagStart;
                            token_start = tokenizer.cursor;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // TODO: text
                            unreachable{};
                            //tokenizer.mode = Mode.Text;
                            //tokenizer.cursor += 1;
                        },
                    }
                },
                TagStart => {
                    // we have a "<"
                    switch (c) {
                        '/' => {
                            tokenizer.mode = Mode.EndTagName;
                            tokenizer.cursor += 1;
                        },
                        // TODO: '?', '!'
                        else => {
                            tokenizer.mode = Mode.StartTagName;
                        },
                    }
                },
                StartTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '/', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.StartTagStart,
                                .start = token_start,
                                .end = tokenizer.cursor,
                            };
                            output_count += 1;
                            if (output_count >= output_tokens.len) return output_count;
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
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.StartTagEnd,
                                .start = tokenizer.cursor,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        '/' => {
                            tokenizer.mode = Mode.TagSelfClose_0;
                            tokenizer.cursor += 1;
                        },
                        '=' => {
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.AttributeEquals,
                                .start = tokenizer.cursor,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        '"' => {
                            tokenizer.mode = Mode.AttributeValueDoubleQuote;
                            token_start = tokenizer.cursor;
                            tokenizer.cursor += 1;
                        },
                        '\'' => {
                            tokenizer.mode = Mode.AttributeValueSingleQuote;
                            token_start = tokenizer.cursor;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            tokenizer.mode = Mode.AttributeName;
                            token_start = tokenizer.cursor;
                        },
                    }
                },
                TagSelfClose_0 => {
                    switch (c) {
                        '>' => {
                            tokenizer.mode = Mode.None;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.TagSelfClose,
                                .start = tokenizer.cursor - 1,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        else => {
                            // invalid '/'
                            tokenizer.mode = Mode.InsideStartTag;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.Invalid,
                                .start = tokenizer.cursor,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                    }
                },
                EndTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideEndTag;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.EndTagStart,
                                .start = token_start,
                                .end = tokenizer.cursor,
                            };
                            output_count += 1;
                            if (output_count >= output_tokens.len) return output_count;
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
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.EndTagEnd,
                                .start = tokenizer.cursor,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        ' ', '\t', '\n', '\r' => {
                            // skip
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // invalid characters between "</name" and ">"
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.Invalid,
                                .start = tokenizer.cursor,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                    }
                },
                AttributeName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '=', '/', '>', '"', '\'' => {
                            // done
                            tokenizer.mode = Mode.InsideStartTag;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.AttributeName,
                                .start = token_start,
                                .end = tokenizer.cursor,
                            };
                            output_count += 1;
                            if (output_count >= output_tokens.len) return output_count;
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
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.AttributeValue,
                                .start = token_start,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
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
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.AttributeValue,
                                .start = token_start,
                                .end = tokenizer.cursor + 1,
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        else => {
                            // not done
                            tokenizer.cursor += 1;
                        },
                    }
                },
            }
        }
        return output_count;
    }
}

#attribute("test")
fn xml_tag_test() {
    const source = "<a><b/></a>";
    const expected_tokens = []?XmlToken{
        XmlToken{ // "<a"
            .token_type = TokenType.StartTagStart,
            .start = 0, .end = 2,
        },
        XmlToken{ // ">"
            .token_type = TokenType.StartTagEnd,
            .start = 2, .end = 3,
        },
        XmlToken{ // "<b"
            .token_type = TokenType.StartTagStart,
            .start = 3, .end = 5,
        },
        XmlToken{ // "/>"
            .token_type = TokenType.TagSelfClose,
            .start = 5, .end = 7,
        },
        XmlToken{ // "</a"
            .token_type = TokenType.EndTagStart,
            .start = 7, .end = 10,
        },
        XmlToken{ // ">"
            .token_type = TokenType.EndTagEnd,
            .start = 10, .end = 11,
        },
    };
    test_all_at_once(source, expected_tokens);
}

#attribute("test")
fn xml_attribute_test() {
    const source = r"XML(<b a="c" de='fg'/>)XML";
    const expected_tokens = []?XmlToken{
        XmlToken{ // "<b"
            .token_type = TokenType.StartTagStart,
            .start = 0, .end = 2,
        },
        XmlToken{ // "a"
            .token_type = TokenType.AttributeName,
            .start = 3, .end = 4,
        },
        XmlToken{ // "="
            .token_type = TokenType.AttributeEquals,
            .start = 4, .end = 5,
        },
        XmlToken{ // "\"c\""
            .token_type = TokenType.AttributeValue,
            .start = 5, .end = 8,
        },
        XmlToken{ // "de"
            .token_type = TokenType.AttributeName,
            .start = 9, .end = 11,
        },
        XmlToken{ // "="
            .token_type = TokenType.AttributeEquals,
            .start = 11, .end = 12,
        },
        XmlToken{ // "'fg'"
            .token_type = TokenType.AttributeValue,
            .start = 12, .end = 16,
        },
        XmlToken{ // "/>"
            .token_type = TokenType.TagSelfClose,
            .start = 16, .end = 18,
        },
    };
    test_all_at_once(source, expected_tokens);
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
    <a-:_2 x='"' y="'" frame="&amp;&lt;&gt;&apos;&quot;"/>
    <![CDATA[<literal text="in">a &quot;<![CDATA[>/literal>]]>
    <!--
      comment <contains> &apos; </stuff>
    -->
  </group>
</root>
)XML";
    const expected_tokens = []?XmlToken{
        // TODO
    };
    test_all_at_once(source, expected_tokens);
}

fn test_all_at_once(source: []const u8, expected_tokens: []?XmlToken) {
    var tokens: [0x1000]XmlToken = undefined;
    var tokenizer = XmlTokenizer.init();
    tokenizer.load(source);
    const read_count = tokenizer.read_tokens(tokens);
    assert(tokenizer.is_eof_acceptible());
    assert(read_count == expected_tokens.len);
    for (expected_tokens) |maybe_expected_token, i| {
        if (const expected_token ?= maybe_expected_token) {
            assert(token_equals(expected_token, tokens[i]));
        }
    }
}
fn token_equals(a: XmlToken, b: XmlToken) -> bool {
    a.token_type == b.token_type &&
    a.start      == b.start      &&
    a.end        == b.end        &&
    true
}
