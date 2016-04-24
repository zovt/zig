const assert = @import("std").assert;

pub enum TokenType {
    Invalid,
    StartTagStart,   // "<name"
    StartTagEnd,     // ("<name") ">"
    TagSelfClose,    // ("<name") "/>"
    EndTagStart,     // "</name"
    EndTagEnd,       // ("</name") ">"
}
pub struct XmlToken {
    token_type: TokenType,
    src: []const u8,
}

enum Mode {
    None,
    TagStart,       // "<"
    StartTagName,   // "<n", "<name"
    InsideStartTag, // "<name "
    TagSelfClose_0, // ("<name ") "/"
    EndTagName,     // "</", "</name"
    InsideEndTag,   // "</name "
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
        var tag_start = tokenizer.cursor;
        while (tokenizer.cursor < tokenizer.src_buf.len) {
            const c = tokenizer.src_buf[tokenizer.cursor];
            switch (tokenizer.mode) {
                None => {
                    switch (c) {
                        '<' => {
                            tokenizer.mode = Mode.TagStart;
                            tag_start = tokenizer.cursor;
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
                                .src = tokenizer.src_buf[tag_start...tokenizer.cursor],
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
                                .src = tokenizer.src_buf[tokenizer.cursor...tokenizer.cursor + 1],
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                        '/' => {
                            tokenizer.mode = Mode.TagSelfClose_0;
                            tokenizer.cursor += 1;
                        },
                        else => {
                            // TODO: attribute name
                            unreachable{};
                        },
                    }
                },
                TagSelfClose_0 => {
                    if (c == '>') {
                        tokenizer.mode = Mode.None;
                        output_tokens[output_count] = XmlToken{
                            .token_type = TokenType.TagSelfClose,
                            .src = tokenizer.src_buf[tokenizer.cursor - 1...tokenizer.cursor + 1],
                        };
                        output_count += 1;
                        tokenizer.cursor += 1;
                        if (output_count >= output_tokens.len) return output_count;
                    } else {
                        // invalid '/'
                        tokenizer.mode = Mode.InsideStartTag;
                        output_tokens[output_count] = XmlToken{
                            .token_type = TokenType.Invalid,
                            .src = tokenizer.src_buf[tokenizer.cursor...tokenizer.cursor + 1],
                        };
                        output_count += 1;
                        if (output_count >= output_tokens.len) return output_count;
                    }
                },
                EndTagName => {
                    switch (c) {
                        ' ', '\t', '\n', '\r', '>' => {
                            // done
                            tokenizer.mode = Mode.InsideEndTag;
                            output_tokens[output_count] = XmlToken{
                                .token_type = TokenType.EndTagStart,
                                .src = tokenizer.src_buf[tag_start...tokenizer.cursor],
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
                                .src = tokenizer.src_buf[tokenizer.cursor...tokenizer.cursor + 1],
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
                                .src = tokenizer.src_buf[tokenizer.cursor...tokenizer.cursor + 1],
                            };
                            output_count += 1;
                            tokenizer.cursor += 1;
                            if (output_count >= output_tokens.len) return output_count;
                        },
                    }
                },
            }
        }
        return output_count;
    }
}

#attribute("test")
fn xml_test() {
    const simple_source = "<a><b/></a>";
    const simple_tokens = []?XmlToken{
        XmlToken{
            .token_type = TokenType.StartTagStart,
            .src = simple_source[0...2], // "<a"
        },
        XmlToken{
            .token_type = TokenType.StartTagEnd,
            .src = simple_source[2...3], // ">"
        },
        XmlToken{
            .token_type = TokenType.StartTagStart,
            .src = simple_source[3...5], // "<b"
        },
        XmlToken{
            .token_type = TokenType.TagSelfClose,
            .src = simple_source[5...7], // "/>"
        },
        XmlToken{
            .token_type = TokenType.EndTagStart,
            .src = simple_source[7...10], // "</a"
        },
        XmlToken{
            .token_type = TokenType.EndTagEnd,
            .src = simple_source[10...11], // ">"
        },
    };
    test_all_at_once(simple_source, simple_tokens);

    const complex_source = r"XML(
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
    const complex_tokens = []XmlToken{};

    //test_all_at_once(complex_source, complex_tokens);
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
    // a.src.ptr    == b.src.ptr    &&
    a.src.len    == b.src.len    &&
    true
}
