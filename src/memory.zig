const std = @import("std");
const value_file = @import("values.zig");

const Allocator = std.mem.Allocator;
const Object = value_file.Object;
const Value = value_file.Value;
const StringObject = value_file.StringObject;
const ArrayObject = value_file.ArrayObject;
const VM = @import("runtime.zig").VM;

const STACK_MAX: usize = 2048;

pub const GC = struct {
    const Self = @This();

    allocator: Allocator,
    objects: std.ArrayList(*Object),
    bytes_allocated: usize = 0,
    next_gc: usize = 1024 * 1024, // 1MB default

    // Stack is owned by the GC for convenience.
    stack: [STACK_MAX]Value,
    stack_top: usize = 0,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .objects = std.ArrayList(*Object).init(allocator),
            .stack = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |obj| {
            self.freeObject(obj);
        }
        self.objects.deinit();
    }

    pub fn safePoint(self: *Self) void {
        self.mark();
        self.sweep();
        self.adjustThreshold();
    }

    // --- Mark Phase ---
    fn mark(self: *Self) void {
        // Mark roots (stack + globals)
        for (self.stack.items) |value| {
            if (value.isObject()) {
                self.markObject(value.Object);
            }
        }
        // TODO: Add global variables, registers, etc.
    }

    fn markObject(self: *Self, obj: *Object) void {
        if (obj.marked) return;
        obj.marked = true;

        // Recursively mark children
        switch (obj.type) {
            .String => {},
            .Array => {
                const arr = obj.as(ArrayObject);
                for (arr.values) |val| {
                    if (val.isObject()) self.markObject(val.Object);
                }
            },
            else => @panic("Unsupported object type"),
        }
    }

    // --- Sweep Phase ---
    fn sweep(self: *Self) void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];
            if (obj.marked) {
                obj.marked = false; // Reset for next GC
                i += 1;
            } else {
                _ = self.objects.swapRemove(i);
                self.freeObject(obj);
            }
        }
    }

    // --- Threshold Adjustment ---
    fn adjustThreshold(self: *Self) void {
        self.next_gc = self.bytes_allocated * 2; // Simple heuristic
    }

    // --- Stack Operations (Called by VM) ---
    pub fn push(self: *Self, value: Value) void {
        if (self.stack_top >= STACK_MAX) {
            @panic("Stack overflow");
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    pub fn pop(self: *Self) Value {
        if (self.stack_top == 0) {
            @panic("Stack underflow");
        }
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    pub fn peek(self: *Self, distance: usize) Value {
        if (distance >= self.stack_top) {
            @panic("Stack underflow in peek");
        }
        return self.stack[self.stack_top - 1 - distance];
    }

    // --- Heap Allocations ---
    pub fn alloc(self: *Self, comptime T: type) *T {
        const obj = self.allocator.create(T) catch @panic("OOM");
        self.bytes_allocated += @sizeOf(T);
        self.objects.append(&obj.object) catch @panic("GC OOM");
        return obj;
    }

    pub fn allocSlice(self: *Self, comptime T: type, len: usize) []T {
        const slice = self.allocator.alloc(T, len) catch @panic("OOM");
        self.bytes_allocated += @sizeOf(T) * len;
        return slice;
    }

    fn freeObject(self: *Self, obj: *Object) void {
        switch (obj.type) {
            .String => {
                const str = obj.as(StringObject);
                self.allocator.free(str.chars);
                self.bytes_allocated -= str.chars.len;
                self.allocator.destroy(str);
            },
            .Array => {
                const arr = obj.as(ArrayObject);
                self.allocator.free(arr.values);
                self.bytes_allocated -= arr.values.len * @sizeOf(Value);
                self.allocator.destroy(arr);
            },
            else => @panic("Unknown object type"),
        }
    }
};
