const std = @import("std");
const value_file = @import("values.zig");

const Value = value_file.Value;
const Object = value_file.Object;
const ObjectType = value_file.ObjectType;
const ArrayObject = value_file.ArrayObject;
const StringObject = value_file.StringObject;
const Allocator = std.mem.Allocator;
const GC = @import("memory.zig").GC;

// Bytecode opcodes
pub const OpCode = enum(u8) {
    // Literals
    op_constant, // Push constant from constant table
    op_none, // Push none
    op_true, // Push true
    op_false, // Push false

    // Unary operations
    op_negate, // -value
    op_not, // !value

    // Binary operations
    op_add, // +
    op_subtract, // -
    op_multiply, // *
    op_divide, // /
    op_equal, // ==
    op_not_equal, // !=
    op_greater, // >
    op_greater_equal, // >=
    op_less, // <
    op_less_equal, // <=

    // Stack operations
    op_pop, // Pop and discard top value
    op_print, // Pop and print top value (for debugging)

    // Control flow (for later)
    op_jump, // Unconditional jump
    op_jump_if_false, // Jump if top value is falsy
    op_loop, // Jump backwards

    // Variable operations
    op_get_global, // Get global variable
    op_set_global, // Set global variable
    op_define_global, // Define new global variable

    // Program end
    op_return, // Return from current function/script
};

// Chunk of bytecode
pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(u32), // Line numbers for debugging

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
            .lines = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn writeOpcode(self: *Chunk, opcode: OpCode, line: u32) !void {
        try self.code.append(@intFromEnum(opcode));
        try self.lines.append(line);
    }

    pub fn writeByte(self: *Chunk, byte: u8, line: u32) !void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn addConstant(self: *Chunk, value: Value) !u8 {
        try self.constants.append(value);
        const index = self.constants.items.len - 1;
        if (index > std.math.maxInt(u8)) {
            @panic("Too many constants in one chunk");
        }
        return @intCast(index);
    }

    pub fn writeConstant(self: *Chunk, value: Value, line: u32) !void {
        const constant_index = try self.addConstant(value);
        try self.writeOpcode(.op_constant, line);
        try self.writeByte(constant_index, line);

        // DEBUG: Confirm what we just wrote
        // std.debug.print("DEBUG: Wrote op_constant followed by index {} for type {}\n", .{ constant_index, std.meta.activeTag(value) });
    }
};

// Virtual Machine
pub const VM = struct {
    const Self = @This();

    chunk: *Chunk,
    ip: usize, // Instruction pointer
    gc: *GC,
    allocator: Allocator,
    globals: std.HashMap(*StringObject, Value, StringContext, std.hash_map.default_max_load_percentage),

    const StringContext = struct {
        pub fn hash(self: @This(), s: *StringObject) u64 {
            _ = self;
            return std.hash_map.hashString(s.chars);
        }

        pub fn eql(self: @This(), a: *StringObject, b: *StringObject) bool {
            _ = self;
            return std.mem.eql(u8, a.chars, b.chars);
        }
    };

    pub fn init(allocator: Allocator, gc: *GC, chunk: *Chunk) VM {
        return VM{
            .chunk = chunk,
            .ip = 0,
            .allocator = allocator,
            .gc = gc,
            .globals = std.HashMap(*StringObject, Value, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.globals.deinit();
    }

    fn push(self: *Self, value: Value) void {
        self.gc.push(value);
    }

    fn pop(self: *Self) Value {
        return self.gc.pop();
    }

    fn peek(self: *Self, depth: usize) Value {
        return self.gc.peek(depth);
    }

    fn readByte(self: *Self) u8 {
        const byte = self.chunk.code.items[self.ip];
        // std.debug.print("DEBUG: Reading byte {any} at IP {any}\n", .{ byte, self.ip });
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *Self) Value {
        const constant_index = self.readByte();
        return self.chunk.constants.items[constant_index];
    }

    fn readConstantString(self: *Self) *StringObject {
        const constant = self.readConstant();

        // Debug: print what type of constant we got
        // std.debug.print("DEBUG: readConstantString got constant type: {any}\n", .{std.meta.activeTag(constant)});

        switch (constant) {
            .RawString => |chars| {
                // std.debug.print("DEBUG: Converting RawString '{s}' to StringObject\n", .{chars});
                return StringObject.create(self.gc, chars);
            },
            .Object => |obj| {
                // std.debug.print("DEBUG: Got Object with type: {any}\n", .{obj.type});
                if (obj.type == .String) {
                    return obj.as(StringObject);
                } else {
                    @panic("Expected string object");
                }
            },
            else => {
                // std.debug.print("DEBUG: Got unexpected constant type in readConstantString\n", .{});
                @panic("Expected string constant");
            },
        }
    }

    pub fn numberToString(gc: *GC, num: f64) !Value {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "{d}", .{num});
        return Value.string(gc, str);
    }

    pub fn interpret(self: *Self) !void {
        // DEBUG: Print all constants before execution
        // std.debug.print("DEBUG: VM starting with {any} constants:\n", .{self.chunk.constants.items.len});
        // for (self.chunk.constants.items, 0..) |constant, i| {
        //     std.debug.print("  [{}]: type = {any}", .{ i, std.meta.activeTag(constant) });
        //     switch (constant) {
        //         .Object => |obj| {
        //             std.debug.print(" (Object: {any})", .{obj.type});
        //             if (obj.type == .String) {
        //                 const str_obj = obj.as(StringObject);
        //                 std.debug.print(" '{s}'", .{str_obj.chars});
        //             }
        //         },
        //         .Number => |n| std.debug.print(" (Number: {any})", .{n}),
        //         .RawString => |s| std.debug.print(" (RawString: '{s}')", .{s}),
        //         else => {},
        //     }
        //     std.debug.print("\n", .{});
        // }

        while (self.ip < self.chunk.code.items.len) {
            // const instruction_ip = self.ip;
            const instruction = @as(OpCode, @enumFromInt(self.readByte()));
            // std.debug.print("\nDEBUG: [IP={any}] Executing: {any}\n", .{ instruction_ip, instruction });

            switch (instruction) {
                .op_constant => {
                    const constant = self.readConstant();
                    // std.debug.print("DEBUG: Pushing constant to stack: type {any}\n", .{std.meta.activeTag(constant)});
                    self.push(constant);
                },
                .op_none => {
                    // std.debug.print("DEBUG: Pushing none\n", .{});
                    self.push(Value.none());
                },
                .op_true => {
                    // std.debug.print("DEBUG: Pushing true\n", .{});
                    self.push(Value.boolean(true));
                },
                .op_false => {
                    // std.debug.print("DEBUG: Pushing false\n", .{});
                    self.push(Value.boolean(false));
                },

                .op_add => {
                    const b = self.pop();
                    const a = self.pop();

                    // Number + Number
                    if (a.isNumber() and b.isNumber()) {
                        const result = a.asNumber() + b.asNumber();
                        self.push(Value.number(result));
                    }
                    // String + String
                    else if (a.isString() and b.isString()) {
                        const a_str = a.asString();
                        const b_str = b.asString();
                        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ a_str.chars, b_str.chars });
                        defer self.allocator.free(combined);
                        self.push(Value.string(self.gc, combined));
                    }
                    // Number + String
                    else if (a.isNumber() and b.isString()) {
                        const num_str = try numberToString(self.gc, a.asNumber());
                        const b_str = b.asString();
                        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ num_str.asString().chars, b_str.chars });
                        defer self.allocator.free(combined);
                        self.push(Value.string(self.gc, combined));
                    }
                    // String + Number
                    else if (a.isString() and b.isNumber()) {
                        const a_str = a.asString();
                        const num_str = try numberToString(self.gc, b.asNumber());
                        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ a_str.chars, num_str.asString().chars });
                        defer self.allocator.free(combined);
                        self.push(Value.string(self.gc, combined));
                    }
                    // Boolean + String (if you want to support it)
                    else if (a.isBoolean() and b.isString()) {
                        const bool_str = if (a.asBoolean()) "true" else "false";
                        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ bool_str, b.asString().chars });
                        defer self.allocator.free(combined);
                        self.push(Value.string(self.gc, combined));
                    }
                    // Other unsupported combinations
                    else {
                        @panic("Unsupported operands for addition");
                    }
                },

                .op_print => {
                    const value = self.pop();
                    value.print();
                    std.debug.print("\n", .{}); // Newline after print
                },

                .op_get_global => {
                    // std.debug.print("DEBUG: Getting global variable\n", .{});
                    const name = self.readConstantString();
                    if (self.globals.get(name)) |value| {
                        // std.debug.print("DEBUG: Retrieved variable '{any}' with value type {any}\n", .{ name.chars, std.meta.activeTag(value) });
                        self.push(value);
                    } else {
                        // std.debug.print("Undefined variable '{s}'\n", .{name.chars});
                        @panic("Undefined variable");
                    }
                },

                .op_set_global => {
                    // std.debug.print("DEBUG: Setting global variable\n", .{});
                    const name = self.readConstantString();
                    const value = self.peek(0);
                    // std.debug.print("DEBUG: Setting variable '{any}' to value type {any}\n", .{ name.chars, std.meta.activeTag(value) });

                    if (self.globals.contains(name)) {
                        self.globals.put(name, value) catch @panic("Failed to set global variable");
                    } else {
                        self.globals.put(name, value) catch @panic("Failed to create global variable");
                    }
                },

                .op_return => {
                    // std.debug.print("DEBUG: Returning from program\n", .{});
                    return;
                },

                else => {
                    // std.debug.print("DEBUG: Unhandled instruction: {any}\n", .{instruction});
                    @panic("Unknown opcode");
                },
            }
        }
    }
};

// Tests
test "value creation and type checking" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();

    const none_val = Value.none();
    const bool_val = Value.boolean(true);
    const num_val = Value.number(42.0);
    const str_val = Value.string(&gc, "hello");

    try std.testing.expect(none_val.isNone());
    try std.testing.expect(bool_val.isBoolean());
    try std.testing.expect(num_val.isNumber());
    try std.testing.expect(str_val.isString());

    try std.testing.expectEqual(true, bool_val.asBoolean());
    try std.testing.expectEqual(42.0, num_val.asNumber());
    try std.testing.expectEqualStrings("hello", str_val.asString().chars);
}

test "value equality" {
    const a = Value.number(42.0);
    const b = Value.number(42.0);
    const c = Value.number(43.0);

    try std.testing.expect(a.equals(b));
    try std.testing.expect(!a.equals(c));
}

test "simple VM execution" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    // Bytecode for: 1.2 + 3.4
    try chunk.writeConstant(Value.number(1.2), 1);
    try chunk.writeConstant(Value.number(3.4), 1);
    try chunk.writeOpcode(.op_add, 1);
    try chunk.writeOpcode(.op_return, 1);

    var vm = VM.init(std.testing.allocator, &chunk);
    try vm.interpret();

    // Result should be on stack
    try std.testing.expectEqual(1, vm.gc.stack_top);
    try std.testing.expectEqual(4.6, vm.gc.stack[0].asNumber());
}
