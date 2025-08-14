const std = @import("std");
const ArrayList = std.ArrayList;
const common = @import("common.zig");
const Span = common.Span;
const Allocator = std.mem.Allocator;

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
const ErrorHandler = struct {
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
    fn init(allocator: Allocator, source_code: []const u8) Self {
        return ErrorHandler{
            .arena = std.heap.ArenaAllocator(allocator),
            .source_code = source_code,
            .errors = undefined,
            .error_count = 0,
            .suppressed_error_count = 0,
        };
    }

    /// Clean up allocations for the ErrorHandler.
    fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    /// Returns true when enough errors have already been collected.
    fn shouldSuppress(self: *Self) bool {
        return self.error_count >= MAX_DISPLAY_ERRORS;
    }

    /// Increment the suppression count.
    fn suppressError(self: *Self) void {
        self.suppressed_error_count += 1;
    }

    /// Report an error to the error handler.
    ///
    /// Params:
    /// * span: The location in the code that triggered the error.
    /// * message_fmt: The formatting string used to format the error.
    /// * message_args: The arguments to supply to the formatter when creating the message.
    ///
    /// Errors:
    /// * error.OutOfMemory - Produced when an allocator cannot reserve enough memory for the messages.
    fn report(self: *Self, span: Span, comptime message_fmt: []const u8, message_args: anytype) !void {
        if (self.shouldSuppress()) {
            self.suppressError();
            return;
        }

        _ = message_fmt;
        _ = message_args;
        _ = span;

        const allocator = self.arena.allocator();

        // TODO: implement the real messages, just placeholder for now.
        const message = try allocator.dupe(u8, "some error");
        const error_message = ErrorMessage.init(message, message, message);
        self.errors[self.error_count] = error_message;
    }

    /// The total number of errors that were discovered in the source code.
    fn total_error_count(self: *Self) usize {
        return self.error_count + self.suppressed_error_count;
    }
};
