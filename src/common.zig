const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const PositionError = error{};

/// Position is a location in the source code.
pub const Position = struct {
    /// The number of chars since the start of the source code. (0-based)
    offset: u32,
    /// The number of chars since the start of the current line. (0-based)
    line_offset: u32,
    /// The line number in the source code. (1-based)
    line: u32,
    /// The column in the current line. (1-based)
    column: u32,

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
    pub fn init(offset: u32, line_offset: u32, line: u32, column: u32) PositionError!Self {
        // TODO: ensure column number is (offset - lineoffset) + 1
        // TODO: ensure that offset >= lineoffset

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

pub const SpanError = error{
    InvalidSpan,
    OutOfOrder,
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
    pub fn init(start: Position, end: Position) SpanError!Self {
        if (start.offset > end.offset) {
            return SpanError.OutOfOrder;
        }

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
    pub fn slice(self: *Self, source: []const u8) SpanError![]const u8 {
        if (self.end.offset >= source.len) {
            return SpanError.InvalidSpan;
        }

        return source[self.start.offset .. self.end.offset + 1];
    }
};

test "Span with backwards positions produces error" {
    try testing.expectError(SpanError.OutOfOrder, Span.init(try Position.init(1, 0, 1, 2), Position.default()));
}

test "Span can slice source code from start" {
    const source = "fun add(a, b) { return a + b; }";
    var mySpan = try Span.init(Position.default(), try Position.init(6, 0, 1, 7));
    const sliced = try mySpan.slice(source);
    try testing.expectEqualStrings("fun add", sliced);
}

test "Span can slice source code from end" {
    const source = "fun add(a, b) { return a + b; }";
    var mySpan = try Span.init(try Position.init(14, 0, 1, 15), try Position.init(30, 0, 1, 31));
    const sliced = try mySpan.slice(source);
    try testing.expectEqualStrings("{ return a + b; }", sliced);
}

test "Span returns error when slicing beyond end" {
    const source = "fun add(a, b) { return a + b; }";
    var mySpan = try Span.init(try Position.init(14, 0, 1, 15), try Position.init(31, 0, 1, 32));
    try testing.expectError(SpanError.InvalidSpan, mySpan.slice(source));
}

test "fail" {
    try testing.expectEqual(1, 2);
}
