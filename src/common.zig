const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

/// Position is a location in the source code.
pub const Position = struct {
    /// The number of chars since the start of the source code. (0-based)
    offset: usize,
    /// The number of chars since the start of the current line. (0-based)
    line_offset: usize,
    /// The line number in the source code. (1-based)
    line: usize,
    /// The column in the current line. (1-based)
    column: usize,

    const Self = @This();

    /// Create a new position.
    ///
    /// Params:
    /// * offset - The number of chars since the start of the source code. (0-based)
    /// * line_offset - The number of chars since the start of the current line. (0-based)
    /// * line - The line number in the source code. (1-based)
    /// * column - The column in the current line. (1-based)
    ///
    /// Returns:
    /// * Self - A new Position
    pub fn init(offset: usize, line_offset: usize, line: usize, column: usize) Self {
        std.debug.assert(offset >= line_offset); // Invariant: The offset must always be greater or equal to the line offset.
        std.debug.assert(column == (offset - line_offset) + 1); // Invariant: The column is always 1-based from the start of the line offset.

        return Position{
            .offset = offset,
            .line_offset = line_offset,
            .line = line,
            .column = column,
        };
    }

    /// Create a default position that starts from the beginning of the source code.
    pub fn default() Self {
        return Position{
            .offset = 0,
            .line_offset = 0,
            .line = 1,
            .column = 1,
        };
    }
};

/// Span is a grouping of source code over a given range.
pub const Span = struct {
    /// The starting point for the portion of source code.
    start: Position,
    /// The ending point for the portion of source code.
    end: Position,

    const Self = @This();

    /// Create a new Span.
    ///
    /// Params:
    /// * start - The starting point for the given source code.
    /// * end - The ending point for the given source code.
    ///
    /// Returns:
    /// * Self - A new Span.
    pub fn init(start: Position, end: Position) Self {
        std.debug.assert(start.offset <= end.offset); // Invariant: The start should always come before the end.
        std.debug.assert(start.line <= end.line); // Invariant: The start line must be less than or equal to the end line.

        return Span{
            .start = start,
            .end = end,
        };
    }

    /// Slice into the source code and return the lexeme represented by the span.
    ///
    /// Params:
    /// * source - The source code that is being compiled.
    ///
    /// Returns:
    /// * []const u8 - The lexeme of the source code for the given span.
    pub fn slice(self: Self, source: []const u8) []const u8 {
        std.debug.assert(self.end.offset < source.len); // Invariant: The span end offset must never be greater or equal to the source code length.
        return source[self.start.offset .. self.end.offset + 1];
    }

    /// Slice into the source code and return the entire line of source code starting
    /// from the span's start line number. For example, if the span starts at line 3,
    /// get all of line 3 and return it.
    ///
    /// Params:
    /// * source - The source code that is being compiled.
    ///
    /// Returns:
    /// * []const u8 - The line of source code at the span's start line.
    pub fn sliceLine(self: Self, source: []const u8) []const u8 {
        const start = self.start.line_offset;
        var end = start;

        while (end < source.len and source[end] != '\n') {
            end += 1;
        }

        return source[start..end];
    }
};

test "Span can slice source code from start" {
    const source = "fun add(a, b) { return a + b; }";
    var mySpan = Span.init(Position.default(), Position.init(6, 0, 1, 7));
    const sliced = mySpan.slice(source);
    try testing.expectEqualStrings("fun add", sliced);
}

test "Span can slice source code from end" {
    const source = "fun add(a, b) { return a + b; }";
    var mySpan = Span.init(Position.init(14, 0, 1, 15), Position.init(30, 0, 1, 31));
    const sliced = mySpan.slice(source);
    try testing.expectEqualStrings("{ return a + b; }", sliced);
}
