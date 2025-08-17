const std = @import("std");
const runtime = @import("runtime.zig");

pub fn disassembleChunk(chunk: *runtime.Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: *runtime.Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});

    const instruction = @as(runtime.OpCode, @enumFromInt(chunk.code.items[offset]));
    switch (instruction) {
        .op_constant => {
            const constant_index = chunk.code.items[offset + 1];
            std.debug.print("{s:<16} {d:4} '", .{ @tagName(instruction), constant_index });
            chunk.constants.items[constant_index].print();
            std.debug.print("'\n", .{});
            return offset + 2;
        },
        .op_set_global, .op_get_global => {
            const name_index = chunk.code.items[offset + 1];
            std.debug.print("{s:<16} {d:4} '", .{ @tagName(instruction), name_index });
            chunk.constants.items[name_index].print();
            std.debug.print("'\n", .{});
            return offset + 2;
        },
        .op_add, .op_subtract, .op_multiply, .op_divide, .op_return, .op_print => {
            std.debug.print("{s}\n", .{@tagName(instruction)});
            return offset + 1;
        },
        else => {
            std.debug.print("Unknown opcode {d}\n", .{@intFromEnum(instruction)});
            return offset + 1;
        },
    }
}
