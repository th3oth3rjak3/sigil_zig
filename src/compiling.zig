const std = @import("std");
const runtime = @import("runtime.zig");
const lexer_file = @import("lexing.zig");
const error_handling = @import("error_handling.zig");
const parsing_file = @import("parsing.zig");
const common_file = @import("common.zig");
const ast_file = @import("ast.zig");
const value_file = @import("values.zig");
const memory = @import("memory.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Chunk = runtime.Chunk;
const Lexer = lexer_file.Lexer;
const ErrorHandler = error_handling.ErrorHandler;
const Parser = parsing_file.Parser;
const Span = common_file.Span;
const Position = common_file.Position;
const Stmt = ast_file.Stmt;
const Expr = ast_file.Expr;
const Value = value_file.Value;
const Object = value_file.Object;
const OpCode = runtime.OpCode;
const GC = memory.GC;

pub const Compiler = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    chunk: *Chunk,
    arena: ArenaAllocator,
    gc: *GC,

    pub fn init(allocator: Allocator, gc: *GC, source: []const u8, chunk: *Chunk) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .chunk = chunk,
            .arena = ArenaAllocator.init(allocator),
            .gc = gc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn compile(self: *Self) !bool {
        const alloc = self.arena.allocator();
        var lexer = Lexer.init(alloc, self.source);
        var error_handler = ErrorHandler.init(alloc, self.source);

        const tokens = try lexer.tokenize();

        var parser = Parser.init(alloc, self.source, tokens, &error_handler);
        const ast = try parser.parse();
        if (error_handler.totalErrorCount() > 0) {
            try error_handler.writeErrors(std.io.getStdErr().writer().any());
            return false;
        }

        for (ast) |stmt| {
            try self.compileStmt(stmt);
        }

        try self.chunk.writeOpcode(.op_return, 0);

        // // DEBUG: Print final bytecode sequence
        // std.debug.print("\n=== FINAL BYTECODE SEQUENCE ===\n", .{});
        // var i: usize = 0;
        // while (i < self.chunk.code.items.len) {
        //     const opcode = @as(OpCode, @enumFromInt(self.chunk.code.items[i]));
        //     std.debug.print("[{}] {}", .{ i, opcode });
        //     i += 1;

        //     switch (opcode) {
        //         .op_constant => {
        //             if (i < self.chunk.code.items.len) {
        //                 const constant_index = self.chunk.code.items[i];
        //                 std.debug.print(" (constant_index: {})", .{constant_index});
        //                 i += 1;
        //             }
        //         },
        //         .op_jump_if_false => {
        //             if (i < self.chunk.code.items.len) {
        //                 const jump_offset = self.chunk.code.items[i];
        //                 std.debug.print(" (jump_offset: {})", .{jump_offset});
        //                 i += 1;
        //             }
        //         },
        //         else => {},
        //     }
        //     std.debug.print("\n", .{});
        // }
        // std.debug.print("=== END BYTECODE ===\n\n", .{});

        return true;
    }

    fn compileStmt(self: *Compiler, stmt: Stmt) !void {
        switch (stmt) {
            .expression => |expr| try self.compileExpr(expr),
            .if_stmt => |if_stmt| try self.compileIfStmt(if_stmt),
            // .while_stmt => |while_stmt| try self.compileWhileStmt(while_stmt),
            .block => |stmts| {
                for (stmts) |s| try self.compileStmt(s);
            },
            .print => |print| try self.compilePrintStmt(print),
            // Handle other statement types...
            else => @panic("Unimplemented statement type"),
        }
    }

    fn compileExpr(self: *Compiler, expr: Expr) !void {
        switch (expr) {
            .literal => |lit| try self.compileLiteral(lit),
            .binary => |bin| try self.compileBinary(bin),
            .unary => |un| try self.compileUnary(un),
            .grouping => |group| try self.compileExpr(group.*),
            .identifier => |name| try self.compileIdentifier(name), // Add this
            .assignment => |assign| try self.compileAssignment(assign), // Add this
            .call => |call| try self.compileCall(call),
            // Handle other expression types...
            else => {
                const msg = try std.fmt.allocPrint(self.allocator, "Unimplemented expression type: {any}", .{expr});
                defer self.allocator.free(msg);
                @panic(msg);
            },
        }
    }

    fn compilePrintStmt(self: *Compiler, expr: Expr) !void {
        try self.compileExpr(expr);
        try self.chunk.writeOpcode(.op_print, 0); // Use line 0 for now
    }

    fn compileIdentifier(self: *Compiler, name: []const u8) anyerror!void {
        // Store name in constants and emit its INDEX as an operand
        const name_value = Value.string(self.gc, name);
        const name_index = try self.chunk.addConstant(name_value);

        // Emit op_get_global with name index operand
        try self.chunk.writeOpcode(.op_get_global, 0);
        try self.chunk.writeByte(name_index, 0); // Operand: name's constant index
    }

    fn compileAssignment(self: *Compiler, assign: *Expr.Assignment) anyerror!void {
        // Compile the value expression (e.g., `10` in `a = 10`)
        try self.compileExpr(assign.value);

        // Store the name in constants and emit its INDEX as an operand
        const name_value = Value.string(self.gc, assign.name);
        const name_index = try self.chunk.addConstant(name_value);

        // Emit op_set_global with name index operand
        try self.chunk.writeOpcode(.op_set_global, 0);
        try self.chunk.writeByte(name_index, 0); // Operand: name's constant index
    }
    // --- Expression Compilation ---
    fn compileLiteral(self: *Compiler, lit: Expr.Literal) anyerror!void {
        const value = switch (lit) {
            .number => |num| Value.number(try std.fmt.parseFloat(f64, num)),
            .string => |str| Value.string(self.gc, str),
            .boolean => |b| Value.boolean(b),
            .none => Value.none(),
        };
        try self.chunk.writeConstant(value, 0); // TODO: Track line numbers
    }

    fn compileBinary(self: *Compiler, bin: *Expr.Binary) anyerror!void {
        try self.compileExpr(bin.left);
        try self.compileExpr(bin.right);

        const op = switch (bin.operator.kind) {
            .Plus => OpCode.op_add,
            .Minus => OpCode.op_subtract,
            .Star => OpCode.op_multiply,
            .Slash => OpCode.op_divide,
            .EqualEqual => OpCode.op_equal,
            .BangEqual => OpCode.op_not_equal,
            .Greater => OpCode.op_greater,
            .GreaterEqual => OpCode.op_greater_equal,
            .Less => OpCode.op_less,
            .LessEqual => OpCode.op_less_equal,
            else => @panic("Invalid binary operator"),
        };
        try self.chunk.writeOpcode(op, 0); // TODO: Track line numbers
    }

    fn compileUnary(self: *Compiler, un: *Expr.Unary) anyerror!void {
        try self.compileExpr(un.right);

        const op = switch (un.operator.kind) {
            .Minus => OpCode.op_negate,
            .Bang => OpCode.op_not,
            else => @panic("Invalid unary operator"),
        };
        try self.chunk.writeOpcode(op, 0); // TODO: Track line numbers
    }

    // --- Statement Compilation ---
    fn compileIfStmt(self: *Compiler, if_stmt: *Stmt.IfStmt) anyerror!void {
        try self.compileExpr(if_stmt.condition);

        // Emit conditional jump (jump if false)
        try self.chunk.writeOpcode(.op_jump_if_false, 0);
        const jump_pos = self.chunk.code.items.len;
        try self.chunk.writeByte(0xFF, 0); // Placeholder for jump offset

        // Compile 'then' branch
        try self.compileStmt(if_stmt.then_branch.*);

        // Patch jump offset (now we know how far to jump)
        const jump_offset = self.chunk.code.items.len - jump_pos;
        self.chunk.code.items[jump_pos] = @intCast(jump_offset);

        // TODO: Handle 'else' branch
    }

    fn compileCall(self: *Compiler, call: *Expr.Call) anyerror!void {
        // Compile the callee (the function being called)
        try self.compileExpr(call.callee);

        // Special case for built-in 'print' function
        if (call.callee == .identifier and std.mem.eql(u8, call.callee.identifier, "print")) {
            // Compile each argument
            for (call.arguments) |arg| {
                try self.compileExpr(arg);
                try self.chunk.writeOpcode(.op_print, 0);
            }
            return;
        }

        // Handle normal function calls here
        @panic("Regular function calls not implemented yet");
    }
};
