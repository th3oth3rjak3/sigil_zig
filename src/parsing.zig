const std = @import("std");
const token_file = @import("tokens.zig");
const error_handling = @import("error_handling.zig");
const ast_file = @import("ast.zig");

const Allocator = std.mem.Allocator;
const Token = token_file.Token;
const TokenKind = token_file.TokenKind;
const ErrorHandler = error_handling.ErrorHandler;
const Stmt = ast_file.Stmt;
const Parameter = ast_file.Parameter;
const Expr = ast_file.Expr;

const ParseError = error{ParseError};

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    tokens: []const Token,
    error_handler: *ErrorHandler,
    current: usize,

    pub fn init(allocator: Allocator, source: []const u8, tokens: []const Token, error_handler: *ErrorHandler) Self {
        return Parser{
            .allocator = allocator,
            .source = source,
            .tokens = tokens,
            .current = 0,
            .error_handler = error_handler,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // Main parsing entry point
    pub fn parse(self: *Self) ![]Stmt {
        var statements = std.ArrayList(Stmt).init(self.allocator);

        while (!self.isAtEnd()) {
            // Check for error tokens from lexer
            if (self.peek().kind == .Error) {
                const error_token = self.advance();
                const lexeme = error_token.span.slice(self.source);
                try self.error_handler.report(error_token.span, "Unexpected token '{s}'", .{lexeme});
                self.synchronize();
                continue;
            }

            if (self.parseStatement()) |stmt| {
                try statements.append(stmt);
            } else {
                // Parse error occurred, synchronize and continue
                self.synchronize();
            }
        }

        return statements.toOwnedSlice();
    }

    // Statement parsing - returns null on error (malformed statements are skipped)
    fn parseStatement(self: *Self) ?Stmt {
        if (self.match(&[_]TokenKind{.If})) return self.parseIfStatement();
        if (self.match(&[_]TokenKind{.While})) return self.parseWhileStatement();
        if (self.match(&[_]TokenKind{.For})) return self.parseForStatement();
        if (self.match(&[_]TokenKind{.Print})) return self.parsePrintStmt();
        if (self.match(&[_]TokenKind{.Return})) return self.parseReturnStatement();
        if (self.match(&[_]TokenKind{.Class})) return self.parseClassDeclaration();
        if (self.match(&[_]TokenKind{.LeftBrace})) return self.parseBlockStatement();

        return self.parseExpressionStatement();
    }

    fn parseIfStatement(self: *Self) ?Stmt {
        _ = self.consume(.LeftParen, "'('") orelse return null;
        const condition = self.parseExpression() orelse return null;
        _ = self.consume(.RightParen, "')'") orelse return null;

        const then_branch = self.allocator.create(Stmt) catch return null;
        then_branch.* = self.parseStatement() orelse return null;

        var else_branch: ?*Stmt = null;
        if (self.match(&[_]TokenKind{.Else})) {
            const else_stmt = self.allocator.create(Stmt) catch return null;
            else_stmt.* = self.parseStatement() orelse return null;
            else_branch = else_stmt;
        }

        const if_stmt = self.allocator.create(Stmt.IfStmt) catch return null;
        if_stmt.* = .{ .condition = condition, .then_branch = then_branch, .else_branch = else_branch };
        return Stmt{ .if_stmt = if_stmt };
    }

    fn parseWhileStatement(self: *Self) ?Stmt {
        _ = self.consume(.LeftParen, "'('") orelse return null;
        const condition = self.parseExpression() orelse return null;
        _ = self.consume(.RightParen, "')'") orelse return null;

        const body = self.allocator.create(Stmt) catch return null;
        body.* = self.parseStatement() orelse return null;

        const while_stmt = self.allocator.create(Stmt.WhileStmt) catch return null;
        while_stmt.* = .{ .condition = condition, .body = body };
        return Stmt{ .while_stmt = while_stmt };
    }

    fn parseForStatement(self: *Self) ?Stmt {
        _ = self.consume(.LeftParen, "'('") orelse return null;

        var initializer: ?Expr = null;
        if (!self.check(.Semicolon)) {
            initializer = self.parseExpression();
            if (initializer == null) return null;
        }
        _ = self.consume(.Semicolon, "';'") orelse return null;

        var condition: ?Expr = null;
        if (!self.check(.Semicolon)) {
            condition = self.parseExpression();
            if (condition == null) return null;
        }
        _ = self.consume(.Semicolon, "';'") orelse return null;

        var increment: ?Expr = null;
        if (!self.check(.RightParen)) {
            increment = self.parseExpression();
            if (increment == null) return null;
        }
        _ = self.consume(.RightParen, "')'") orelse return null;

        const body = self.allocator.create(Stmt) catch return null;
        body.* = self.parseStatement() orelse return null;

        const for_stmt = self.allocator.create(Stmt.ForStmt) catch return null;
        for_stmt.* = .{ .initializer = initializer, .condition = condition, .increment = increment, .body = body };
        return Stmt{ .for_stmt = for_stmt };
    }

    fn parseReturnStatement(self: *Self) ?Stmt {
        const value = self.parseExpression() orelse return null;
        _ = self.consume(.Semicolon, "';'") orelse return null;

        const return_stmt = self.allocator.create(Stmt.ReturnStmt) catch return null;
        return_stmt.* = .{ .value = value };
        return Stmt{ .return_stmt = return_stmt };
    }

    fn parseClassDeclaration(self: *Self) ?Stmt {
        const name_token = self.consume(.Identifier, "class name") orelse return null;
        const name = name_token.span.slice(self.source);

        _ = self.consume(.LeftBrace, "'{'") orelse return null;

        var constructor: ?Stmt.Constructor = null;
        var methods = std.ArrayList(Stmt.Method).init(self.allocator);

        while (!self.check(.RightBrace) and !self.isAtEnd()) {
            _ = self.consume(.Fun, "'fun'") orelse return null;

            if (self.match(&[_]TokenKind{.New})) {
                // Constructor
                _ = self.consume(.LeftParen, "'('") orelse return null;
                const params = self.parseParameterList() orelse return null;
                _ = self.consume(.RightParen, "')'") orelse return null;
                const body = self.parseBlock() orelse return null;
                constructor = .{ .parameters = params, .body = body };
            } else {
                // Method
                const method_name_token = self.consume(.Identifier, "method name") orelse return null;
                const method_name = method_name_token.span.slice(self.source);
                _ = self.consume(.LeftParen, "'('") orelse return null;
                const params = self.parseParameterList() orelse return null;
                _ = self.consume(.RightParen, "')'") orelse return null;
                const body = self.parseBlock() orelse return null;
                methods.append(.{ .name = method_name, .parameters = params, .body = body }) catch return null;
            }
        }

        _ = self.consume(.RightBrace, "'}'") orelse return null;

        const class_decl = self.allocator.create(Stmt.ClassDecl) catch return null;
        const methods_slice = methods.toOwnedSlice() catch return null;
        class_decl.* = .{ .name = name, .constructor = constructor, .methods = methods_slice };
        return Stmt{ .class_decl = class_decl };
    }

    fn parseBlockStatement(self: *Self) ?Stmt {
        const statements = self.parseBlock() orelse return null;
        return Stmt{ .block = statements };
    }

    fn parseBlock(self: *Self) ?[]Stmt {
        var statements = std.ArrayList(Stmt).init(self.allocator);

        while (!self.check(.RightBrace) and !self.isAtEnd()) {
            if (self.parseStatement()) |stmt| {
                statements.append(stmt) catch return null;
            } else {
                // Skip malformed statement and try to recover
                self.synchronize();
            }
        }

        _ = self.consume(.RightBrace, "'}'") orelse return null;
        return statements.toOwnedSlice() catch null;
    }

    fn parseExpressionStatement(self: *Self) ?Stmt {
        const expr = self.parseExpression() orelse return null;
        _ = self.consume(.Semicolon, "';'") orelse return null;
        return Stmt{ .expression = expr };
    }

    // Expression parsing - returns null on error (expressions must be complete)
    fn parseExpression(self: *Self) ?Expr {
        return self.parseAssignment();
    }

    fn parseAssignment(self: *Self) ?Expr {
        const expr = self.parseLogicOr() orelse return null;

        if (self.match(&[_]TokenKind{.Equal})) {
            const value = self.parseAssignment() orelse return null;

            // Check if left side is a valid assignment target
            switch (expr) {
                .identifier => |name| {
                    // Create an assignment expression
                    const assignment = self.allocator.create(Expr.Assignment) catch return null;
                    assignment.* = .{ .name = name, .value = value };
                    return Expr{ .assignment = assignment };
                },
                else => {
                    const current_token = self.previous();
                    self.error_handler.report(current_token.span, "Invalid assignment target", .{}) catch {};
                    return null;
                },
            }
        }

        return expr;
    }

    fn parsePrintStmt(self: *Parser) ?Stmt {
        const expr = self.parseExpression() orelse return null;
        _ = self.consume(.Semicolon, "Expect ';' after value");
        return Stmt{ .print = expr };
    }

    fn parseLogicOr(self: *Self) ?Expr {
        var expr = self.parseLogicAnd() orelse return null;

        while (self.match(&[_]TokenKind{.Or})) {
            const operator = self.previous();
            const right = self.parseLogicAnd() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseLogicAnd(self: *Self) ?Expr {
        var expr = self.parseEquality() orelse return null;

        while (self.match(&[_]TokenKind{.And})) {
            const operator = self.previous();
            const right = self.parseEquality() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseEquality(self: *Self) ?Expr {
        var expr = self.parseComparison() orelse return null;

        while (self.match(&[_]TokenKind{ .BangEqual, .EqualEqual })) {
            const operator = self.previous();
            const right = self.parseComparison() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseComparison(self: *Self) ?Expr {
        var expr = self.parseTerm() orelse return null;

        while (self.match(&[_]TokenKind{ .Greater, .GreaterEqual, .Less, .LessEqual })) {
            const operator = self.previous();
            const right = self.parseTerm() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseTerm(self: *Self) ?Expr {
        var expr = self.parseFactor() orelse return null;

        while (self.match(&[_]TokenKind{ .Minus, .Plus })) {
            const operator = self.previous();
            const right = self.parseFactor() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseFactor(self: *Self) ?Expr {
        var expr = self.parseUnary() orelse return null;

        while (self.match(&[_]TokenKind{ .Slash, .Star })) {
            const operator = self.previous();
            const right = self.parseUnary() orelse return null;
            const binary = self.allocator.create(Expr.Binary) catch return null;
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = Expr{ .binary = binary };
        }

        return expr;
    }

    fn parseUnary(self: *Self) ?Expr {
        if (self.match(&[_]TokenKind{ .Bang, .Minus, .Not })) {
            const operator = self.previous();
            const right = self.parseUnary() orelse return null;
            const unary = self.allocator.create(Expr.Unary) catch return null;
            unary.* = .{ .operator = operator, .right = right };
            return Expr{ .unary = unary };
        }

        return self.parseCall();
    }

    fn parseCall(self: *Self) ?Expr {
        var expr = self.parsePrimary() orelse return null;

        while (true) {
            if (self.match(&[_]TokenKind{.LeftParen})) {
                expr = self.finishCall(expr) orelse return null;
            } else {
                break;
            }
        }

        return expr;
    }

    fn finishCall(self: *Self, callee: Expr) ?Expr {
        var arguments = std.ArrayList(Expr).init(self.allocator);

        if (!self.check(.RightParen)) {
            while (true) {
                const arg = self.parseExpression() orelse return null;
                arguments.append(arg) catch return null;
                if (!self.match(&[_]TokenKind{.Comma})) break;
            }
        }

        _ = self.consume(.RightParen, "')'") orelse return null;

        const call = self.allocator.create(Expr.Call) catch return null;
        const args_slice = arguments.toOwnedSlice() catch return null;
        call.* = .{ .callee = callee, .arguments = args_slice };
        return Expr{ .call = call };
    }

    fn parsePrimary(self: *Self) ?Expr {
        if (self.match(&[_]TokenKind{.True})) {
            return Expr{ .literal = .{ .boolean = true } };
        }

        if (self.match(&[_]TokenKind{.False})) {
            return Expr{ .literal = .{ .boolean = false } };
        }

        if (self.match(&[_]TokenKind{.None})) {
            return Expr{ .literal = .{ .none = {} } };
        }

        if (self.match(&[_]TokenKind{.Number})) {
            const value = self.previous().span.slice(self.source);
            return Expr{ .literal = .{ .number = value } };
        }

        if (self.match(&[_]TokenKind{.String})) {
            const value = self.previous().span.slice(self.source);
            return Expr{ .literal = .{ .string = value[1 .. value.len - 1] } };
        }

        if (self.match(&[_]TokenKind{.Identifier})) {
            const name = self.previous().span.slice(self.source);
            return Expr{ .identifier = name };
        }

        if (self.match(&[_]TokenKind{.This})) {
            _ = self.consume(.Dot, "'.'") orelse return null;
            const property_token = self.consume(.Identifier, "property name") orelse return null;
            const property = property_token.span.slice(self.source);

            const prop_access = self.allocator.create(Expr.PropertyAccess) catch return null;
            prop_access.* = .{ .object = "this", .property = property };
            return Expr{ .property_access = prop_access };
        }

        if (self.match(&[_]TokenKind{.LeftParen})) {
            const expr = self.parseExpression() orelse return null;
            _ = self.consume(.RightParen, "')'") orelse return null;
            const grouping = self.allocator.create(Expr) catch return null;
            grouping.* = expr;
            return Expr{ .grouping = grouping };
        }

        if (self.match(&[_]TokenKind{.Fun})) {
            return self.parseFunctionExpression();
        }

        const current_token = self.peek();
        const lexeme = current_token.span.slice(self.source);
        self.error_handler.report(current_token.span, "Expected expression but got '{s}'", .{lexeme}) catch {};
        return null;
    }

    fn parseFunctionExpression(self: *Self) ?Expr {
        _ = self.consume(.LeftParen, "'('") orelse return null;
        const parameters = self.parseParameterList() orelse return null;
        _ = self.consume(.RightParen, "')'") orelse return null;
        const body = self.parseBlock() orelse return null;

        const func_expr = self.allocator.create(Expr.FunctionExpr) catch return null;
        func_expr.* = .{ .parameters = parameters, .body = body };
        return Expr{ .function_expr = func_expr };
    }

    fn parseParameterList(self: *Self) ?[]Parameter {
        var parameters = std.ArrayList(Parameter).init(self.allocator);

        if (!self.check(.RightParen)) {
            while (true) {
                const name_token = self.consume(.Identifier, "parameter name") orelse return null;
                const name = name_token.span.slice(self.source);

                var type_annotation: ?[]const u8 = null;
                if (self.match(&[_]TokenKind{.Colon})) {
                    const type_token = self.consume(.Identifier, "type name") orelse return null;
                    type_annotation = type_token.span.slice(self.source);
                }

                parameters.append(.{ .name = name, .type_annotation = type_annotation }) catch return null;

                if (!self.match(&[_]TokenKind{.Comma})) break;
            }
        }

        return parameters.toOwnedSlice() catch null;
    }

    // Core utility methods
    fn peek(self: *Self) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn isAtEnd(self: *Self) bool {
        return self.peek().kind == TokenKind.EOF;
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.previous();
    }

    fn check(self: *Self, kind: TokenKind) bool {
        if (self.isAtEnd()) return false;
        return self.peek().kind == kind;
    }

    fn match(self: *Self, kinds: []const TokenKind) bool {
        for (kinds) |kind| {
            if (self.check(kind)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn consume(self: *Self, kind: TokenKind, expected: []const u8) ?Token {
        if (self.check(kind)) {
            return self.advance();
        }

        const current_token = self.peek();
        const lexeme = current_token.span.slice(self.source);
        self.error_handler.report(current_token.span, "Expected {s} but got '{s}'", .{ expected, lexeme }) catch {};
        return null;
    }

    fn synchronize(self: *Self) void {
        _ = self.advance();

        while (!self.isAtEnd()) {
            if (self.previous().kind == .Semicolon) return;

            switch (self.peek().kind) {
                .Class, .Fun, .If, .While, .For, .Return => return,
                else => {},
            }

            _ = self.advance();
        }
    }
};

// Tests
test "parser can parse simple expression" {
    // Mock tokens for "42;"
    const tokens = [_]Token{
        .{ .kind = .Number, .span = undefined },
        .{ .kind = .Semicolon, .span = undefined },
        .{ .kind = .EOF, .span = undefined },
    };

    var error_handler = ErrorHandler.init(std.testing.allocator, "42;");
    defer error_handler.deinit();

    var parser = Parser.init(std.testing.allocator, "42;", &tokens, &error_handler);
    defer parser.deinit();

    const statements = try parser.parse();
    defer std.testing.allocator.free(statements);

    try std.testing.expectEqual(1, statements.len);
    try std.testing.expectEqual(Stmt.expression, std.meta.activeTag(statements[0]));
    try std.testing.expectEqual(0, error_handler.totalErrorCount());
}

test "parser skips malformed statements" {
    // Mock tokens for "1 + ; 42;"
    const tokens = [_]Token{
        .{ .kind = .Number, .span = undefined },
        .{ .kind = .Plus, .span = undefined },
        .{ .kind = .Semicolon, .span = undefined },
        .{ .kind = .Number, .span = undefined },
        .{ .kind = .Semicolon, .span = undefined },
        .{ .kind = .EOF, .span = undefined },
    };

    var error_handler = ErrorHandler.init(std.testing.allocator, "1 + ; 42;");
    defer error_handler.deinit();

    var parser = Parser.init(std.testing.allocator, "1 + ; 42;", &tokens, &error_handler);
    defer parser.deinit();

    const statements = try parser.parse();
    defer std.testing.allocator.free(statements);

    // Should have skipped the malformed statement but parsed the valid one
    try std.testing.expectEqual(1, statements.len);
    try std.testing.expect(error_handler.totalErrorCount() > 0);
}

test "parser handles error tokens from lexer" {
    // Mock tokens including an error token
    const tokens = [_]Token{
        .{ .kind = .Error, .span = undefined },
        .{ .kind = .Number, .span = undefined },
        .{ .kind = .Semicolon, .span = undefined },
        .{ .kind = .EOF, .span = undefined },
    };

    var error_handler = ErrorHandler.init(std.testing.allocator, "@ 42;");
    defer error_handler.deinit();

    var parser = Parser.init(std.testing.allocator, "@ 42;", &tokens, &error_handler);
    defer parser.deinit();

    const statements = try parser.parse();
    defer std.testing.allocator.free(statements);

    // Should have 0 statements since the entire "@ 42;" is malformed
    try std.testing.expectEqual(0, statements.len);
    try std.testing.expect(error_handler.totalErrorCount() > 0);
}

test "parser recovers after error token" {
    // Mock tokens for "@ 42; 100;"
    const tokens = [_]Token{
        .{ .kind = .Error, .span = undefined }, // @
        .{ .kind = .Number, .span = undefined }, // 42
        .{ .kind = .Semicolon, .span = undefined }, // ;
        .{ .kind = .Number, .span = undefined }, // 100
        .{ .kind = .Semicolon, .span = undefined }, // ;
        .{ .kind = .EOF, .span = undefined },
    };

    var error_handler = ErrorHandler.init(std.testing.allocator, "@ 42; 100;");
    defer error_handler.deinit();

    var parser = Parser.init(std.testing.allocator, "@ 42; 100;", &tokens, &error_handler);
    defer parser.deinit();

    const statements = try parser.parse();
    defer std.testing.allocator.free(statements);

    // Should have 1 valid statement (100;) after skipping the malformed one (@ 42;)
    try std.testing.expectEqual(1, statements.len);
    try std.testing.expectEqual(Stmt.expression, std.meta.activeTag(statements[0]));
    try std.testing.expect(error_handler.totalErrorCount() > 0);
}
