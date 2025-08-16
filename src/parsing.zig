const std = @import("std");
const token_file = @import("tokens.zig");

const Allocator = std.mem.Allocator;
const Token = token_file.Token;
const TokenKind = token_file.TokenKind;

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    tokens: []const Token,

    pub fn init(allocator: Allocator, source: []const u8, tokens: []const Token) Self {
        return Parser{
            .allocator = allocator,
            .source = source,
            .tokens = tokens,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};
