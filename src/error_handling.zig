const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const common = @import("common.zig");
const Span = common.Span;
const Position = common.Position;

/// The maximum number of errors to show to a user at once. Others will be supressed.
const MAX_DISPLAY_ERRORS: usize = 5;

/// ErrorMessage represents a complete error message with helpful information for the user to debug
/// the error.
const ErrorMessage = struct {
    /// An explicit message stating the problem with the start line and column numbers.
    message: []const u8,
    /// The line of code that contained the error with the line number prefixed to the front.
    line_of_code: []const u8,
    /// A line that should be printed beneath the line of code to indicate where the failure occurred.
    error_line: []const u8,

    const Self = @This();

    pub fn init(message: []const u8, line_of_code: []const u8, error_line: []const u8) Self {
        return ErrorMessage{
            .message = message,
            .line_of_code = line_of_code,
            .error_line = error_line,
        };
    }
};

/// ErrorHandler is used to collect build time errors during lexing,
/// parsing, and type checking. These errors can then be reported to the user
/// in a consistent way that shows the line number, the offending source code,
/// and exactly where in the code the error occurred.
pub const ErrorHandler = struct {
    /// The arena which is used for creating all the error strings. It owns the allocations
    /// for all created error messages.
    arena: std.heap.ArenaAllocator,
    /// The complete source code used to find the text to display to the user.
    source_code: []const u8,
    /// The collection of errors that have occurred during code processing.
    errors: [MAX_DISPLAY_ERRORS]ErrorMessage,
    /// The number of errors stored in the errors array.
    error_count: usize,
    /// The number of errors which are greater than MAX_DISPLAY_ERRORS.
    suppressed_error_count: usize,

    const Self = @This();

    /// Create a new error handler.
    ///
    /// Params:
    /// * allocator - The allocator that is used as the backing allocator for the arena.
    /// * source_code - The source code that is used to find the lines of code to display to the user.
    ///
    /// Returns:
    /// * Self - The new ErrorHandler instance.
    pub fn init(allocator: Allocator, source_code: []const u8) Self {
        return ErrorHandler{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .source_code = source_code,
            .errors = undefined,
            .error_count = 0,
            .suppressed_error_count = 0,
        };
    }

    /// Clean up allocations for the ErrorHandler.
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    /// The total number of errors that were discovered in the source code.
    pub fn totalErrorCount(self: *Self) usize {
        return self.error_count + self.suppressed_error_count;
    }

    /// Report an error to the error handler.
    ///
    /// Params:
    /// * span: The location in the code that triggered the error.
    /// * message_fmt: The formatting string used to format the error.
    /// * message_args: The arguments to supply to the formatter when creating the message.
    pub fn report(self: *Self, span: Span, comptime message_fmt: []const u8, message_args: anytype) !void {
        if (self.shouldSuppress()) {
            self.suppressError();
            return;
        }

        const message = try self.getErrorMessage(span, message_fmt, message_args);
        const line_of_offending_code = try self.getLineOfOffendingCode(span);
        const error_line = try self.getErrorLine(span);
        self.errors[self.error_count] = ErrorMessage.init(message, line_of_offending_code, error_line);
        self.error_count += 1;
    }

    /// Write all of the errors to the provided writer. If there are more than MAX_DISPLAY_ERRORS
    /// errors, only the first MAX_DISPLAY_ERRORS are printed to the writer, then additional error
    /// statistics will be printed to the writer to indicate the amount of errors which were
    /// suppressed to prevent information overload.
    ///
    /// Params:
    /// * writer - Any type that supports implements the std.io.AnyWriter interface.
    pub fn writeErrors(self: *Self, writer: std.io.AnyWriter) !void {
        for (0..self.error_count) |idx| {
            const err = self.errors[idx];
            try writer.print("\n", .{});
            try writer.print("{s}\n", .{err.message});
            try writer.print("{s}\n", .{err.line_of_code});
            try writer.print("{s}\n", .{err.error_line});
        }

        // We had extra errors, so add the suppression message.
        if (self.shouldSuppress()) {
            try writer.print("\nShowing {d} of {d} total errors.\n", .{ MAX_DISPLAY_ERRORS, self.totalErrorCount() });
            try writer.print("Recompile to see the rest.\n", .{});
        }

        try writer.print("\n", .{});
    }

    /// Returns true when enough errors have already been collected.
    fn shouldSuppress(self: *Self) bool {
        return self.error_count >= MAX_DISPLAY_ERRORS;
    }

    /// Increment the suppression count.
    fn suppressError(self: *Self) void {
        self.suppressed_error_count += 1;
    }

    /// Construct an error message that includes the line and column number.
    ///
    /// Params:
    /// * span - The location in the source code where the error occurred.
    /// * message_fmt - A format string for customized error text.
    /// * message_args - Any arguments that should be passed into the custom error text.
    ///
    /// Returns:
    /// * []u8 - An owned string with memory that is managed internally by the arena allocator.
    ///
    /// Example:
    ///
    /// ```text
    ///     [1:10] Error: You can't park that here mate!
    /// ```
    fn getErrorMessage(self: *Self, span: Span, comptime message_fmt: []const u8, message_args: anytype) ![]u8 {
        const complete_fmt = "[{d}:{d}] Error: " ++ message_fmt;
        const complete_args = .{ span.start.line, span.start.column } ++ message_args;
        return try std.fmt.allocPrint(self.arena.allocator(), complete_fmt, complete_args);
    }

    /// Collect the line of code from the source code which had the error for user error context.
    ///
    /// Params:
    /// * span - The location where the error occurred.
    ///
    /// Returns:
    /// * []u8 - An owned string with memory that is managed internally by the arena allocator.
    ///
    /// Example:
    ///
    /// ```text
    ///     1 | fun add(a, b) { return a + b; }
    /// ```
    fn getLineOfOffendingCode(self: *Self, span: Span) ![]u8 {
        const format_string = "{d} | {s}";
        const slice = span.sliceLine(self.source_code);
        return std.fmt.allocPrint(self.arena.allocator(), format_string, .{ span.start.line, slice });
    }

    /// Create a line that goes beneath the code line to point to the exact part of the source
    /// code where the error occurred.
    ///
    /// Params:
    /// * span - The location where the error occurred.
    ///
    /// Returns:
    /// * []u8 - An owned string mith memory that is managed internally by the arena allocator.
    ///
    /// Example:
    ///
    /// ```text
    ///           ^^^ <- Error Here
    /// ```
    fn getErrorLine(self: *Self, span: Span) ![]u8 {
        // create buffer
        const alloc = self.arena.allocator();
        var buf = ArrayList(u8).init(alloc);

        // how many spaces do we need?
        const line_number = try std.fmt.allocPrint(alloc, "{d} | ", .{span.start.line});
        const line_number_spaces = line_number.len;

        // spaces between the start of the line and the beginning of the offset
        const offset_spaces = span.start.offset - span.start.line_offset;
        try buf.appendNTimes(' ', line_number_spaces + offset_spaces);

        // How many arrows do we need?
        if (span.start.line != span.end.line) {
            // can only do carats for the stuff in the start line until we hit the end \n char
            const start = span.start.offset;
            var end = start;
            while (end < span.end.offset and self.source_code[end] != '\n') {
                end += 1;
            }

            const carat_count = (end - start) + 1;
            try buf.appendNTimes('^', carat_count);
        } else {
            // They're on the same line, so just go from start offset to end offset.
            const carat_count = (span.end.offset - span.start.offset) + 1;
            try buf.appendNTimes('^', carat_count);
        }

        // Add final error marker
        try buf.appendSlice(" <- Error Here");

        return buf.toOwnedSlice();
    }
};

test "ErrorHandler collects reported errors" {
    var handler = ErrorHandler.init(std.testing.allocator, "some source code");
    defer handler.deinit();

    const start = Position.default();
    const end = Position.init(5, 0, 1, 6);
    const span = Span.init(start, end);

    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(1, handler.error_count);
}

test "ErrorHandler stops collecting errors when limit reached" {
    var handler = ErrorHandler.init(std.testing.allocator, "some source code");
    defer handler.deinit();

    const start = Position.default();
    const end = Position.init(5, 0, 1, 6);
    const span = Span.init(start, end);

    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(1, handler.error_count);
    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(2, handler.error_count);
    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(3, handler.error_count);
    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(4, handler.error_count);
    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(5, handler.error_count);
    try handler.report(span, "Expected ';' but got {s}", .{"','"});
    try std.testing.expectEqual(5, handler.error_count);
    try std.testing.expectEqual(1, handler.suppressed_error_count);
}

// // Uncomment the two tests below to visually verify the error lines look right.
// test "ErrorHandler writes errors without overflow suppression" {
//     var handler = ErrorHandler.init(std.testing.allocator, "line 1 has some stuff here\nline 2 has some source code");
//     defer handler.deinit();

//     const start = Position.init(27, 27, 2, 1);
//     const end = Position.init(28, 27, 2, 2);
//     const span = Span.init(start, end);

//     try handler.report(span, "Expected ';' but got {s}", .{"','"});
//     try std.testing.expectEqual(1, handler.error_count);

//     try handler.writeErrors(std.io.getStdErr().writer().any());
// }

// test "ErrorHandler can write errors with overflow suppression" {
//     var handler = ErrorHandler.init(std.testing.allocator, "some source code");
//     defer handler.deinit();

//     const start = Position.default();
//     const end = Position.init(3, 0, 1, 4);
//     const span = Span.init(start, end);

//     for (0..6) |_| {
//         try handler.report(span, "Expected ';' but got {s}", .{"','"});
//     }

//     try handler.writeErrors(std.io.getStdErr().writer().any());
// }
