const std = @import("../index.zig");
const assert = std.debug.assert;
const mem = std.mem;
const ast = std.zig.ast;
const Tokenizer = std.zig.Tokenizer;
const Token = std.zig.Token;
const TokenIndex = ast.TokenIndex;
const Error = ast.Error;

pub const Error = error {
    /// Ran out of memory allocating call stack frames to complete parsing.
    /// Or, ran out of memory allocating AST nodes.
    OutOfMemory,
};

/// Result should be freed with tree.deinit() when there are
/// no more references to any of the tokens or nodes.
pub fn parse(allocator: &mem.Allocator, source: []const u8) Error!ast.Tree {
    var tree = ast.Tree {
        .source = source,
        .root_node = undefined,
        .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        .tokens = undefined,
        .errors = undefined,
    };
    errdefer tree.arena_allocator.deinit();

    const arena = &tree.arena_allocator.allocator;

    tree.tokens = ast.Tree.TokenList.init(arena),
    tree.errors = ast.Tree.ErrorList.init(arena),
    tree.root_node = try arena.construct(ast.Node.Root {
        .base = ast.Node { .id = ast.Node.Id.Root },
        .decls = ast.Node.Root.DeclList.init(arena),
        .doc_comments = null,
        // initialized when we get the eof token
        .eof_token = undefined,
    });

    var tokenizer = Tokenizer.init(tree.source);
    while (true) {
        const token_ptr = try tree.tokens.addOne();
        *token_ptr = tokenizer.next();
        if (token_ptr.id == Token.Id.Eof)
            break;
    }
    var tok_it = tree.tokens.iterator(0);

    const ctx = Context {
        .stack_allocator = allocator,
        .arena = arena,
        .tok_it = &tok_it,
        .tree = &tree,
    };

    if (parseTopLevelDecls(ctx)) {
        tree.root_node.eof_token = mustEatToken(ctx, Token.Id.Eof) catch |e| switch (e) { error.ParseFailure => undefined };
        return tree;
    } else |err| switch (err) {
        error.ParseFailure => return tree,
        else => return err, // TODO error.ParseFailure should be excluded from the returning error set
    }
}

const Context = struct {
    stack_allocator: &mem.Allocator, // for recursive calls
    arena: &mem.Allocator, // for AST nodes
    tok_it: &ast.Tree.TokenList.Iterator,
    tree: &ast.Tree,
};

fn parseTopLevelDecls(ctx: &const Context) !void {
    while (true) {
        if (try eatLineComment(ctx)) |line_comment| {
            try tree.root_node.decls.push(&line_comment.base);
            continue;
        }

        if (try parseTestDecl(ctx)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        if (try parseComptime(ctx, true)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        const doc_comments = try eatDocComments(ctx.arena);
        const pub_token = eatToken(ctx, Token.Id.Keyword_pub);

        if (try parseUseDecl(ctx, pub_token, doc_comments)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        if (try parseVarDeclTopLevel(ctx, pub_token, doc_comments)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        if (try parseFnDef(ctx, pub_token, doc_comments)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        if (try parseExternDecl(ctx, pub_token, doc_comments)) |node| {
            try tree.root_node.decls.push(node);
            continue;
        }

        if (pub_token) |token| {
            *(try tree.errors.addOne()) = Error {
                .InvalidToken = Error.InvalidToken { .token = token },
            };
        }

        if (doc_comments) |comments| {
            ctx.tree.root_node.doc_comments = comments;
        }

        return;
}

fn parseTestDecl(ctx: &const Context) !?&ast.Node {
    const test_token = eatToken(ctx, Token.Id.Keyword_test) ?? return null;
    const name_token = try mustEatToken(ctx, Token.Id.StringLiteral);

    const body_node = try parseBlock(ctx);

    const arena = &tree.arena_allocator.allocator;
    return arena.construct(ast.Node.TestDecl {
        .base = ast.Node { .id = ast.Node.Id.TestDecl },
        .test_token = test_token,
        .name_token = name_token,
        .body_node = body_node,
    });
}

fn parseComptime(ctx: &const Context, require_block_body: bool) !?&ast.Node {
    const comptime_token = eatToken(ctx, Token.Id.Keyword_comptime) ?? return null;
    const body_node = if (require_block_body) try parseBlock(ctx) else try parseBlockOrExpr(ctx);

    return arena.construct(ast.Node.Comptime {
        .base = ast.Node { .id = ast.Node.Id.Comptime },
        .comptime_token = comptime_token,
        .expr = body_node,
    });
}

fn parseUseDecl(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment) !?&ast.Node {
    const use_token = eatToken(ctx, Token.Id.Keyword_use) ?? return null;
    const expr = try parseExpression(ctx);
    const semicolon_token = try mustEatToken(ctx, Token.Id.Semicolon);

    return arena.construct(ast.Node.Use {
        .base = ast.Node { .id = ast.Node.Id.Use },
        .doc_comments = doc_comments,
        .pub_token = pub_token,
        .expr = expr,
        .semicolon_token = semicolon_token,
    });
}

fn parseExternDecl(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment) !?&ast.Node {
    const extern_token = eatToken(ctx, Token.Id.Keyword_extern) ?? return null;
    const lib_name_token = eatToken(ctx, Token.Id.StringLiteral);

    if (try parseFnProto(ctx, pub_token, doc_comments)) |fn_proto| {
        const semicolon_token = try mustEatToken(ctx, Token.Id.Semicolon);

        return arena.construct(ast.Node.ExternDecl {
            .base = ast.Node { .id = ast.Node.Id.ExternDecl },
            .extern_token = extern_token,
            .lib_name_token = lib_name_token,
            .decl = fn_proto,
            .semicolon_token = semicolon_token,
        });
    }

    if (try parseVarDecl(ctx, pub_token, doc_comments)) |var_decl| {
        const semicolon_token = try mustEatToken(ctx, Token.Id.Semicolon);

        return arena.construct(ast.Node.ExternDecl {
            .base = ast.Node { .id = ast.Node.Id.ExternDecl },
            .extern_token = extern_token,
            .lib_name_token = lib_name_token,
            .decl = var_decl,
            .semicolon_token = semicolon_token,
        });
    }

    return parseError(ctx, Error {
        .ExpectedVarDeclOrFn = Error.ExpectedVarDeclOrFn { .token = ctx.tok_it.index },
    });
}

fn parseVarDeclTopLevel(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment) !?&ast.Node {
    const orig_index = ctx.tok_it.index;
    const export_token = eatToken(ctx, Token.Id.Keyword_export);
    return parseVarDecl(ctx, pub_token, doc_comments, export_token, null) ?? {
        ctx.tok_it.set(orig_index);
        return null;
    };
}

fn parseVarDecl(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment, export_token: ?TokenIndex, comptime_token: ?TokenIndex) !?&ast.Node {
    const mut_token = switch ((??ctx.tok_it.peek()).id) {
        Token.Id.Var, Token.Id.Const => blk: {
            _ = ctx.tok_it.next();
            break :blk ctx.tok_it.index;
        },
        else => return null,
    };

    const name_token = try mustEatToken(ctx, Token.Id.Identifier);

    const type_node = if (eatToken(ctx, Token.Id.Colon)) |_| try parseTypeExpr(ctx) else null;
    const align_node = if (eatToken(ctx, Token.Id.Keyword_align)) |_| blk: {
        _ = try mustEatToken(ctx, Token.Id.LParen);
        const node = try parseExpression(ctx);
        _ = try mustEatToken(ctx, Token.Id.RParen);
        break :blk node;
    } else null;

    const section_node = if (eatToken(ctx, Token.Id.Keyword_section)) |_| blk: {
        _ = try mustEatToken(ctx, Token.Id.LParen);
        const node = try parseExpression(ctx);
        _ = try mustEatToken(ctx, Token.Id.RParen);
        break :blk node;
    } else null;

    const init_node = if (eatToken(ctx, Token.Id.Eq)) |_| try parseExpression(ctx) else null;

    return ctx.arena.construct(ast.Node.VarDecl {
        .pub_token = pub_token,
        .doc_comments = doc_comments,
        .export_token = export_token,
        .comptime_token = comptime_token,
        .mut_token = mut_token,
        .name_token = name_token,
        .type_node = type_node,
        .align_node = align_node,
        .section_node = section_node,
        .init_node = init_node,
    });
}

fn parseFnDef(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment) !?&ast.Node {
    aoeu
}

fn parseFnProto(ctx: &const Context, pub_token: ?TokenIndex, doc_comments: ?&ast.Node.DocComment) !?&ast.Node {
    aoeu
}

fn parseExpression(ctx: &const Context) !?&ast.Node {
    aoeu
}

fn eatDocComments(arena: &mem.Allocator, tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree) !?&ast.Node.DocComment {
    var result: ?&ast.Node.DocComment = null;
    while (true) {
        if (eatToken(tok_it, tree, Token.Id.DocComment)) |line_comment| {
            const node = blk: {
                if (result) |comment_node| {
                    break :blk comment_node;
                } else {
                    const comment_node = try arena.construct(ast.Node.DocComment {
                        .base = ast.Node {
                            .id = ast.Node.Id.DocComment,
                        },
                        .lines = ast.Node.DocComment.LineList.init(arena),
                    });
                    result = comment_node;
                    break :blk comment_node;
                }
            };
            try node.lines.push(line_comment);
            continue;
        }
        break;
    }
    return result;
}

fn eatLineComment(arena: &mem.Allocator, tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree) !?&ast.Node.LineComment {
    const token = eatToken(tok_it, tree, Token.Id.LineComment) ?? return null;
    return try arena.construct(ast.Node.LineComment {
        .base = ast.Node {
            .id = ast.Node.Id.LineComment,
        },
        .token = token,
    });
}

fn parseStringLiteral(ctx: &const Context) !?&ast.Node {
    const token = ??ctx.tok_it.peek();
    switch (token_ptr.id) {
        Token.Id.StringLiteral => {
            return &(try createLiteral(ctx.arena, ast.Node.StringLiteral, token_index)).base;
        },
        Token.Id.MultilineStringLiteralLine => {
            const node = try arena.construct(ast.Node.MultilineStringLiteral {
                .base = ast.Node { .id = ast.Node.Id.MultilineStringLiteral },
                .lines = ast.Node.MultilineStringLiteral.LineList.init(arena),
            });
            try node.lines.push(token_index);
            while (true) {
                const multiline_str = nextToken(tok_it, tree);
                const multiline_str_index = multiline_str.index;
                const multiline_str_ptr = multiline_str.ptr;
                if (multiline_str_ptr.id != Token.Id.MultilineStringLiteralLine) {
                    putBackToken(tok_it, tree);
                    break;
                }

                try node.lines.push(multiline_str_index);
            }

            return &node.base;
        },
        // TODO: We shouldn't need a cast, but:
        // zig: /home/jc/Documents/zig/src/ir.cpp:7962: TypeTableEntry* ir_resolve_peer_types(IrAnalyze*, AstNode*, IrInstruction**, size_t): Assertion `err_set_type != nullptr' failed.
        else => return (?&ast.Node)(null),
    }
}

fn parseBlockExpr(stack: &std.ArrayList(State), arena: &mem.Allocator, ctx: &const OptionalCtx,
    token_ptr: &const Token, token_index: TokenIndex) !bool {
    switch (token_ptr.id) {
        Token.Id.Keyword_suspend => {
            const node = try arena.construct(ast.Node.Suspend {
                .base = ast.Node {.id = ast.Node.Id.Suspend },
                .label = null,
                .suspend_token = token_index,
                .payload = null,
                .body = null,
            });
            ctx.store(&node.base);

            stack.append(State { .SuspendBody = node }) catch unreachable;
            try stack.append(State { .Payload = OptionalCtx { .Optional = &node.payload } });
            return true;
        },
        Token.Id.Keyword_if => {
            const node = try arena.construct(ast.Node.If {
                .base = ast.Node {.id = ast.Node.Id.If },
                .if_token = token_index,
                .condition = undefined,
                .payload = null,
                .body = undefined,
                .@"else" = null,
            });
            ctx.store(&node.base);

            stack.append(State { .Else = &node.@"else" }) catch unreachable;
            try stack.append(State { .Expression = OptionalCtx { .Required = &node.body } });
            try stack.append(State { .PointerPayload = OptionalCtx { .Optional = &node.payload } });
            try stack.append(State { .ExpectToken = Token.Id.RParen });
            try stack.append(State { .Expression = OptionalCtx { .Required = &node.condition } });
            try stack.append(State { .ExpectToken = Token.Id.LParen });
            return true;
        },
        Token.Id.Keyword_while => {
            stack.append(State {
                .While = LoopCtx {
                    .label = null,
                    .inline_token = null,
                    .loop_token = token_index,
                    .opt_ctx = *ctx,
                }
            }) catch unreachable;
            return true;
        },
        Token.Id.Keyword_for => {
            stack.append(State {
                .For = LoopCtx {
                    .label = null,
                    .inline_token = null,
                    .loop_token = token_index,
                    .opt_ctx = *ctx,
                }
            }) catch unreachable;
            return true;
        },
        Token.Id.Keyword_switch => {
            const node = try arena.construct(ast.Node.Switch {
                .base = ast.Node {
                    .id = ast.Node.Id.Switch,
                },
                .switch_token = token_index,
                .expr = undefined,
                .cases = ast.Node.Switch.CaseList.init(arena),
                .rbrace = undefined,
            });
            ctx.store(&node.base);

            stack.append(State {
                .SwitchCaseOrEnd = ListSave(@typeOf(node.cases)) {
                    .list = &node.cases,
                    .ptr = &node.rbrace,
                },
            }) catch unreachable;
            try stack.append(State { .ExpectToken = Token.Id.LBrace });
            try stack.append(State { .ExpectToken = Token.Id.RParen });
            try stack.append(State { .Expression = OptionalCtx { .Required = &node.expr } });
            try stack.append(State { .ExpectToken = Token.Id.LParen });
            return true;
        },
        Token.Id.Keyword_comptime => {
            const node = try arena.construct(ast.Node.Comptime {
                .base = ast.Node {.id = ast.Node.Id.Comptime },
                .comptime_token = token_index,
                .expr = undefined,
                .doc_comments = null,
            });
            ctx.store(&node.base);

            try stack.append(State { .Expression = OptionalCtx { .Required = &node.expr } });
            return true;
        },
        Token.Id.LBrace => {
            const block = try arena.construct(ast.Node.Block {
                .base = ast.Node {.id = ast.Node.Id.Block },
                .label = null,
                .lbrace = token_index,
                .statements = ast.Node.Block.StatementList.init(arena),
                .rbrace = undefined,
            });
            ctx.store(&block.base);
            stack.append(State { .Block = block }) catch unreachable;
            return true;
        },
        else => {
            return false;
        }
    }
}

const ExpectCommaOrEndResult = union(enum) {
    end_token: ?TokenIndex,
    parse_error: Error,
};

fn expectCommaOrEnd(tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree, end: @TagType(Token.Id)) ExpectCommaOrEndResult {
    const token = nextToken(tok_it, tree);
    const token_index = token.index;
    const token_ptr = token.ptr;
    switch (token_ptr.id) {
        Token.Id.Comma => return ExpectCommaOrEndResult { .end_token = null},
        else => {
            if (end == token_ptr.id) {
                return ExpectCommaOrEndResult { .end_token = token_index };
            }

            return ExpectCommaOrEndResult {
                .parse_error = Error {
                    .ExpectedCommaOrEnd = Error.ExpectedCommaOrEnd {
                        .token = token_index,
                        .end_id = end,
                    },
                },
            };
        },
    }
}

fn tokenIdToAssignment(id: &const Token.Id) ?ast.Node.InfixOp.Op {
    // TODO: We have to cast all cases because of this:
    // error: expected type '?InfixOp', found '?@TagType(InfixOp)'
    return switch (*id) {
        Token.Id.AmpersandEqual => ast.Node.InfixOp.Op { .AssignBitAnd = {} },
        Token.Id.AngleBracketAngleBracketLeftEqual => ast.Node.InfixOp.Op { .AssignBitShiftLeft = {} },
        Token.Id.AngleBracketAngleBracketRightEqual => ast.Node.InfixOp.Op { .AssignBitShiftRight = {} },
        Token.Id.AsteriskEqual => ast.Node.InfixOp.Op { .AssignTimes = {} },
        Token.Id.AsteriskPercentEqual => ast.Node.InfixOp.Op { .AssignTimesWarp = {} },
        Token.Id.CaretEqual => ast.Node.InfixOp.Op { .AssignBitXor = {} },
        Token.Id.Equal => ast.Node.InfixOp.Op { .Assign = {} },
        Token.Id.MinusEqual => ast.Node.InfixOp.Op { .AssignMinus = {} },
        Token.Id.MinusPercentEqual => ast.Node.InfixOp.Op { .AssignMinusWrap = {} },
        Token.Id.PercentEqual => ast.Node.InfixOp.Op { .AssignMod = {} },
        Token.Id.PipeEqual => ast.Node.InfixOp.Op { .AssignBitOr = {} },
        Token.Id.PlusEqual => ast.Node.InfixOp.Op { .AssignPlus = {} },
        Token.Id.PlusPercentEqual => ast.Node.InfixOp.Op { .AssignPlusWrap = {} },
        Token.Id.SlashEqual => ast.Node.InfixOp.Op { .AssignDiv = {} },
        else => null,
    };
}

fn tokenIdToUnwrapExpr(id: @TagType(Token.Id)) ?ast.Node.InfixOp.Op {
    return switch (id) {
        Token.Id.Keyword_catch => ast.Node.InfixOp.Op { .Catch = null },
        Token.Id.QuestionMarkQuestionMark => ast.Node.InfixOp.Op { .UnwrapMaybe = void{} },
        else => null,
    };
}

fn tokenIdToComparison(id: @TagType(Token.Id)) ?ast.Node.InfixOp.Op {
    return switch (id) {
        Token.Id.BangEqual => ast.Node.InfixOp.Op { .BangEqual = void{} },
        Token.Id.EqualEqual => ast.Node.InfixOp.Op { .EqualEqual = void{} },
        Token.Id.AngleBracketLeft => ast.Node.InfixOp.Op { .LessThan = void{} },
        Token.Id.AngleBracketLeftEqual => ast.Node.InfixOp.Op { .LessOrEqual = void{} },
        Token.Id.AngleBracketRight => ast.Node.InfixOp.Op { .GreaterThan = void{} },
        Token.Id.AngleBracketRightEqual => ast.Node.InfixOp.Op { .GreaterOrEqual = void{} },
        else => null,
    };
}

fn tokenIdToBitShift(id: @TagType(Token.Id)) ?ast.Node.InfixOp.Op {
    return switch (id) {
        Token.Id.AngleBracketAngleBracketLeft => ast.Node.InfixOp.Op { .BitShiftLeft = void{} },
        Token.Id.AngleBracketAngleBracketRight => ast.Node.InfixOp.Op { .BitShiftRight = void{} },
        else => null,
    };
}

fn tokenIdToAddition(id: @TagType(Token.Id)) ?ast.Node.InfixOp.Op {
    return switch (id) {
        Token.Id.Minus => ast.Node.InfixOp.Op { .Sub = void{} },
        Token.Id.MinusPercent => ast.Node.InfixOp.Op { .SubWrap = void{} },
        Token.Id.Plus => ast.Node.InfixOp.Op { .Add = void{} },
        Token.Id.PlusPercent => ast.Node.InfixOp.Op { .AddWrap = void{} },
        Token.Id.PlusPlus => ast.Node.InfixOp.Op { .ArrayCat = void{} },
        else => null,
    };
}

fn tokenIdToMultiply(id: @TagType(Token.Id)) ?ast.Node.InfixOp.Op {
    return switch (id) {
        Token.Id.Slash => ast.Node.InfixOp.Op { .Div = void{} },
        Token.Id.Asterisk => ast.Node.InfixOp.Op { .Mult = void{} },
        Token.Id.AsteriskAsterisk => ast.Node.InfixOp.Op { .ArrayMult = void{} },
        Token.Id.AsteriskPercent => ast.Node.InfixOp.Op { .MultWrap = void{} },
        Token.Id.Percent => ast.Node.InfixOp.Op { .Mod = void{} },
        Token.Id.PipePipe => ast.Node.InfixOp.Op { .MergeErrorSets = void{} },
        else => null,
    };
}

fn tokenIdToPrefixOp(id: @TagType(Token.Id)) ?ast.Node.PrefixOp.Op {
    return switch (id) {
        Token.Id.Bang => ast.Node.PrefixOp.Op { .BoolNot = void{} },
        Token.Id.Tilde => ast.Node.PrefixOp.Op { .BitNot = void{} },
        Token.Id.Minus => ast.Node.PrefixOp.Op { .Negation = void{} },
        Token.Id.MinusPercent => ast.Node.PrefixOp.Op { .NegationWrap = void{} },
        Token.Id.Asterisk, Token.Id.AsteriskAsterisk => ast.Node.PrefixOp.Op { .Deref = void{} },
        Token.Id.Ampersand => ast.Node.PrefixOp.Op {
            .AddrOf = ast.Node.PrefixOp.AddrOfInfo {
                .align_expr = null,
                .bit_offset_start_token = null,
                .bit_offset_end_token = null,
                .const_token = null,
                .volatile_token = null,
            },
        },
        Token.Id.QuestionMark => ast.Node.PrefixOp.Op { .MaybeType = void{} },
        Token.Id.QuestionMarkQuestionMark => ast.Node.PrefixOp.Op { .UnwrapMaybe = void{} },
        Token.Id.Keyword_await => ast.Node.PrefixOp.Op { .Await = void{} },
        Token.Id.Keyword_try => ast.Node.PrefixOp.Op { .Try = void{ } },
        else => null,
    };
}

fn createLiteral(arena: &mem.Allocator, comptime T: type, token_index: TokenIndex) !&T {
    return arena.construct(T {
        .base = ast.Node {.id = ast.Node.typeToId(T)},
        .token = token_index,
    });
}

fn createToCtxLiteral(arena: &mem.Allocator, opt_ctx: &const OptionalCtx, comptime T: type, token_index: TokenIndex) !&T {
    const node = try createLiteral(arena, T, token_index);
    opt_ctx.store(&node.base);

    return node;
}

fn eatToken(tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree, id: @TagType(Token.Id)) ?TokenIndex {
    const token = nextToken(tok_it, tree);

    if (token.ptr.id == id)
        return token.index;

    putBackToken(tok_it, tree);
    return null;
}

fn mustEatToken(tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree, id: @TagType(Token.Id)) !TokenIndex {
    return eatToken(tok_it, tree, id) ?? {
        *(try tree.errors.addOne()) = Error {
            .ExpectedToken = Error.ExpectedToken {
                .token = tok_it.index,
                .expected_id = id,
            },
        };
        return error.ParseFailure;
    };
}

fn nextToken(tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree) AnnotatedToken {
    const result = AnnotatedToken {
        .index = tok_it.index,
        .ptr = ??tok_it.next(),
    };
    // possibly skip a following same line token
    const token = tok_it.next() ?? return result;
    if (token.id != Token.Id.LineComment) {
        putBackToken(tok_it, tree);
        return result;
    }
    const loc = tree.tokenLocationPtr(result.ptr.end, token);
    if (loc.line != 0) {
        putBackToken(tok_it, tree);
    }
    return result;
}

fn putBackToken(tok_it: &ast.Tree.TokenList.Iterator, tree: &ast.Tree) void {
    const prev_tok = ??tok_it.prev();
    if (prev_tok.id == Token.Id.LineComment) {
        const minus2_tok = tok_it.prev() ?? return;
        const loc = tree.tokenLocationPtr(minus2_tok.end, prev_tok);
        if (loc.line != 0) {
            _ = tok_it.next();
        }
    }
}

fn parseError(ctx: &const Context, ast_error: &const ast.Error) (error{ParseFailure, OutOfMemory}) {
    *(try ctx.tree.errors.addOne()) = *ast_error;
    return error.ParseFailure;
}



test "std.zig.parser" {
    _ = @import("parser_test.zig");
}
