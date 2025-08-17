const std = @import("std");
const common = @import("common.zig");

const Span = common.Span;

pub const TokenKind = enum {
    // Literals
    Number,
    String,
    Identifier,

    // Keywords
    Let,
    If,
    Else,
    While,
    For,
    Fun,
    Return,
    True,
    False,
    None,
    Break,
    Continue,
    Class,
    Super,
    This,
    New,

    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    Equal,
    EqualEqual,
    Bang,
    BangEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    And,
    Or,
    Not,

    // Punctuation
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Comma,
    Dot,
    Semicolon,
    Colon,

    // Special
    EOF,
    Error,
    Print,
};

pub const Token = struct {
    kind: TokenKind,
    span: Span,
};

pub const KEYWORDS = std.StaticStringMap(TokenKind).initComptime(
    .{
        .{ "let", .Let },
        .{ "if", .If },
        .{ "else", .Else },
        .{ "while", .While },
        .{ "for", .For },
        .{ "fun", .Fun },
        .{ "return", .Return },
        .{ "true", .True },
        .{ "false", .False },
        .{ "none", .None },
        .{ "break", .Break },
        .{ "continue", .Continue },
        .{ "class", .Class },
        .{ "super", .Super },
        .{ "this", .This },
        .{ "not", .Not },
        .{ "new", .New },
        .{ "print", .Print },
    },
);
