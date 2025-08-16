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
    Nil,
    Break,
    Continue,
    Class,
    Super,
    This,

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
        .{ "nil", .Nil },
        .{ "break", .Break },
        .{ "continue", .Continue },
        .{ "class", .Class },
        .{ "super", .Super },
        .{ "this", .This },
    },
);
