const std = @import("std");
const common = @import("common.zig");
const tokens = @import("tokens.zig");

const Token = tokens.Token;
const TokenKind = tokens.TokenKind;
const Position = common.Position;
const Span = common.Span;
const KEYWORDS = tokens.KEYWORDS;

const Allocator = std.mem.Allocator;

/// Lexer is a source code scanner/lexer implementation that produces
/// tokens used in the parsing stage.
pub const Lexer = struct {
    const Self = @This();

    /// The allocator used to allocate the token array.
    allocator: Allocator,
    /// The source code that lives at least as long as the lexer.
    source: []const u8,
    /// The current line of the source code that the lexer is on.
    line: usize,
    /// The current column of the current line of source code.
    column: usize,
    /// The number of characters from the start of the source code.
    offset: usize,
    /// The number of characters from the start of the source code to the start of the current line.
    line_offset: usize,
    /// The last location before advancing.
    previous_position: Position,

    /// Create a new Lexer.
    ///
    /// Params:
    /// * allocator - A memory allocator.
    /// * source - The source code that needs to be processed.
    ///
    /// Returns:
    /// * Self - A new Lexer.
    pub fn init(allocator: Allocator, source: []const u8) Self {
        return Lexer{
            .allocator = allocator,
            .source = source,
            .line = 1,
            .column = 1,
            .offset = 0,
            .line_offset = 0,
            .previous_position = Position.default(),
        };
    }

    /// Clean up the lexer.
    pub fn deinit(_: *Self) void {}

    /// Generate all of the tokens from the source code.
    ///
    /// Returns:
    /// * []Token - A slice of tokens that is owned by the caller.
    pub fn tokenize(self: *Self) ![]Token {
        var lexed_tokens = std.ArrayList(Token).init(self.allocator);

        while (true) {
            const token = self.nextToken();
            try lexed_tokens.append(token);

            if (token.kind == TokenKind.EOF) {
                break;
            }
        }

        return lexed_tokens.toOwnedSlice();
    }

    /// Get the next token from the source code.
    ///
    /// Returns:
    /// * Token - The token that was lexed from the source code.
    fn nextToken(self: *Self) Token {
        self.skipCommentsAndWhitespace();

        const start_position = self.currentPosition();

        const char = self.peek();
        if (char == 0) {
            return Token{ .kind = .EOF, .span = Span.init(start_position, start_position) };
        }

        if (std.ascii.isAlphabetic(char)) {
            return self.readIdentifier(start_position);
        }

        if (std.ascii.isDigit(char)) {
            return self.readNumber(start_position);
        }

        if (char == '"') {
            return self.readString(start_position);
        }

        return switch (char) {
            '+' => self.makeToken(.Plus, start_position),
            '-' => self.makeToken(.Minus, start_position),
            '*' => self.makeToken(.Star, start_position),
            '/' => self.makeToken(.Slash, start_position),
            '=' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    return self.makeToken(.EqualEqual, start_position);
                }

                return self.makeToken(.Equal, start_position);
            },
            '!' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    return self.makeToken(.BangEqual, start_position);
                }

                return self.makeToken(.Bang, start_position);
            },
            '<' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    return self.makeToken(.LessEqual, start_position);
                }

                return self.makeToken(.Less, start_position);
            },
            '>' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    return self.makeToken(.GreaterEqual, start_position);
                }

                return self.makeToken(.Greater, start_position);
            },
            ';' => self.makeToken(.Semicolon, start_position),
            ',' => self.makeToken(.Comma, start_position),
            '.' => self.makeToken(.Dot, start_position),
            ':' => self.makeToken(.Colon, start_position),
            '(' => self.makeToken(.LeftParen, start_position),
            ')' => self.makeToken(.RightParen, start_position),
            '[' => self.makeToken(.LeftBracket, start_position),
            ']' => self.makeToken(.RightBracket, start_position),
            '{' => self.makeToken(.LeftBrace, start_position),
            '}' => self.makeToken(.RightBrace, start_position),
            else => self.makeToken(.Error, start_position),
        };
    }

    /// Advance one position and make the token of the specified kind.
    ///
    /// Params:
    /// * kind - The kind of the token, e.g. TokenKind.LeftParen
    /// * start - The starting position.
    ///
    /// Returns:
    /// * Token - The created token.
    fn makeToken(self: *Self, kind: TokenKind, start: Position) Token {
        self.advance();
        return Token{ .kind = kind, .span = Span.init(start, self.previous_position) };
    }

    /// Read a number token.
    ///
    /// Params:
    /// * start - The starting position.
    ///
    /// Returns:
    /// * Token - The number token which may be an integer or decimal type number.
    fn readNumber(self: *Self, start: Position) Token {
        while (std.ascii.isDigit(self.peek())) {
            self.advance();
        }

        if (self.peek() == '.' and std.ascii.isDigit(self.peekNext())) {
            self.advance(); // consume '.'

            while (std.ascii.isDigit(self.peek())) {
                self.advance();
            }
        }

        return Token{ .kind = .Number, .span = Span.init(start, self.previous_position) };
    }

    /// Read an identifier token, which could be a keyword or a user defined identifier.
    ///
    /// Params:
    /// * start - The starting position.
    ///
    /// Returns:
    /// * A keyword token or an Identifier token.
    fn readIdentifier(self: *Self, start: Position) Token {
        while (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_') {
            self.advance();
        }

        const span = Span.init(start, self.previous_position);
        const lexeme = span.slice(self.source);

        if (KEYWORDS.get(lexeme)) |kw| {
            return Token{ .kind = kw, .span = span };
        }

        return Token{ .kind = .Identifier, .span = span };
    }

    /// Read a string literal token.
    ///
    /// Params:
    /// * start - The starting position.
    ///
    /// Returns:
    /// * Token - The string token or an error token if a string is unterminated.
    fn readString(self: *Self, start: Position) Token {
        self.advance(); // consume opening quote

        while (self.peek() != '"' and self.peek() != 0) {
            self.advance();
        }

        if (self.peek() == 0) {
            // Unterminated string - return error token
            return Token{ .kind = .Error, .span = Span.init(start, self.previous_position) };
        }

        self.advance(); // consume closing quote
        return Token{ .kind = .String, .span = Span.init(start, self.previous_position) };
    }

    /// Increment the lexer's position.
    fn advance(self: *Self) void {
        self.previous_position = self.currentPosition();
        const char = self.peek();

        if (char == 0) {
            return;
        } else if (char == '\n') {
            self.line += 1;
            self.column = 1;
            self.offset += 1;
            self.line_offset = self.offset;
        } else {
            self.offset += 1;
            self.column += 1;
        }
    }

    /// Peek at the character at the current offset.
    fn peek(self: *Self) u8 {
        return self.peekAt(self.offset);
    }

    /// Peek at the character at the current offset + 1.
    fn peekNext(self: *Self) u8 {
        return self.peekAt(self.offset + 1);
    }

    /// Find the character at the given offset. If the offset
    /// is beyond the end of the source, this function returns the null
    /// character. (0)
    fn peekAt(self: *Self, offset: usize) u8 {
        if (self.isAtEnd(offset)) {
            return 0;
        }

        return self.source[offset];
    }

    /// Check to see if the lexer is at the end of the source code.
    fn isAtEnd(self: *Self, offset: usize) bool {
        return offset >= self.source.len;
    }

    /// Get the current position of the lexer.
    fn currentPosition(self: *Self) Position {
        return Position{
            .offset = self.offset,
            .line_offset = self.line_offset,
            .line = self.line,
            .column = self.column,
        };
    }

    /// Check to see if the lexer is positioned at the start
    /// of a comment.
    fn isAtComment(self: *Self) bool {
        return self.peek() == '/' and self.peekNext() == '/';
    }

    /// Skip over comments and whitespace until meaningful
    /// source code is found.
    fn skipCommentsAndWhitespace(self: *Self) void {
        while (true) {
            self.skipWhitespace();
            if (self.isAtComment()) {
                self.skipComments();
            } else {
                return;
            }
        }
    }

    /// Skip over insignificant whitespace.
    fn skipWhitespace(self: *Self) void {
        while (std.ascii.isWhitespace(self.peek())) {
            self.advance();
        }
    }

    /// Skip over comments until a new line is found.
    fn skipComments(self: *Self) void {
        while (self.peek() != '\n' and self.peek() != 0) {
            self.advance();
        }
    }
};

test "lexer can produce string tokens" {
    const source = "\"hello world\"";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(2, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.String, lexed_tokens[0].kind);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[1].kind);
    try std.testing.expectEqualStrings("\"hello world\"", lexed_tokens[0].span.slice(source));
}

test "lexer can handle escaped strings" {
    const source = "\"hello\\nworld\\\"";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(2, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.String, lexed_tokens[0].kind);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[1].kind);
}

test "lexer detects unterminated strings" {
    const source = "\"unterminated";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(2, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.Error, lexed_tokens[0].kind);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[1].kind);
}

test "lexer with empty source doesn't fail" {
    const source = "";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(1, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[0].kind);
}

test "lexer can produce number tokens" {
    const source = "1.2";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(2, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.Number, lexed_tokens[0].kind);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[1].kind);
    try std.testing.expectEqualStrings("1.2", lexed_tokens[0].span.slice(source));
}

test "lexer can produce identifier tokens" {
    const source = "let thing = 3;";
    var lexer = Lexer.init(std.testing.allocator, source);
    defer lexer.deinit();

    const lexed_tokens = try lexer.tokenize();
    defer std.testing.allocator.free(lexed_tokens);

    try std.testing.expectEqual(6, lexed_tokens.len);
    try std.testing.expectEqual(TokenKind.Let, lexed_tokens[0].kind);
    try std.testing.expectEqual(TokenKind.Identifier, lexed_tokens[1].kind);
    try std.testing.expectEqual(TokenKind.Equal, lexed_tokens[2].kind);
    try std.testing.expectEqual(TokenKind.Number, lexed_tokens[3].kind);
    try std.testing.expectEqual(TokenKind.Semicolon, lexed_tokens[4].kind);
    try std.testing.expectEqual(TokenKind.EOF, lexed_tokens[5].kind);
}
