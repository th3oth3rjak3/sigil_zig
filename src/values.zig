const std = @import("std");

const GC = @import("memory.zig").GC;

// Object types that live on the heap
pub const ObjectType = enum {
    String,
    Array,
    Function,
    Class,
    Instance,
};

// Base object header - all heap objects start with this
pub const Object = struct {
    type: ObjectType,

    pub fn as(self: *Object, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("object", self));
    }
};

// String object
pub const StringObject = struct {
    object: Object,
    chars: []const u8,

    pub fn create(gc: *GC, chars: []const u8) *StringObject {
        const obj = gc.alloc(StringObject);
        // Copy the string data to GC-managed memory
        const owned_chars = gc.allocSlice(u8, chars.len);
        @memcpy(owned_chars, chars);

        obj.* = StringObject{
            .object = .{ .type = .String },
            .chars = owned_chars,
        };
        return obj;
    }
};

// Array object
pub const ArrayObject = struct {
    object: Object,
    values: []Value,
    count: usize,
    capacity: usize,

    pub fn create(gc: *GC, initial_capacity: usize) *ArrayObject {
        const obj = gc.alloc(ArrayObject);
        const values = if (initial_capacity > 0)
            gc.allocSlice(Value, initial_capacity)
        else
            @as([]Value, &[_]Value{});

        obj.* = ArrayObject{
            .object = .{ .type = .Array },
            .values = values,
            .count = 0,
            .capacity = initial_capacity,
        };
        return obj;
    }

    pub fn append(gc: *GC, self: *ArrayObject, value: Value) void {
        if (self.count >= self.capacity) {
            const new_capacity = if (self.capacity < 8) 8 else self.capacity * 2;
            const new_values = gc.allocSlice(Value, new_capacity);
            if (self.count > 0) {
                @memcpy(new_values[0..self.count], self.values[0..self.count]);
            }
            self.values = new_values;
            self.capacity = new_capacity;
        }

        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn get(self: *ArrayObject, index: usize) ?Value {
        if (index >= self.count) return null;
        return self.values[index];
    }

    pub fn set(self: *ArrayObject, index: usize, value: Value) bool {
        if (index >= self.count) return false;
        self.values[index] = value;
        return true;
    }
};

// Runtime value type
pub const Value = union(enum) {
    None,
    Boolean: bool,
    Number: f64,
    Object: *Object,
    RawString: []const u8, // Add this line

    // Add this method to check for raw strings
    pub fn isRawString(self: Value) bool {
        return std.meta.activeTag(self) == .RawString;
    }

    pub fn asRawString(self: Value) []const u8 {
        std.debug.assert(self.isRawString());
        return self.RawString;
    }

    // Add constructor for raw strings
    pub fn rawString(chars: []const u8) Value {
        return Value{ .RawString = chars };
    }

    pub fn isNone(self: Value) bool {
        return std.meta.activeTag(self) == .None;
    }

    pub fn isBoolean(self: Value) bool {
        return std.meta.activeTag(self) == .Boolean;
    }

    pub fn isNumber(self: Value) bool {
        return std.meta.activeTag(self) == .Number;
    }

    pub fn isObject(self: Value) bool {
        return std.meta.activeTag(self) == .Object;
    }

    pub fn isString(self: Value) bool {
        return self.isObject() and self.Object.type == .String;
    }

    pub fn isArray(self: Value) bool {
        return self.isObject() and self.Object.type == .Array;
    }

    pub fn asBoolean(self: Value) bool {
        std.debug.assert(self.isBoolean());
        return self.Boolean;
    }

    pub fn asNumber(self: Value) f64 {
        std.debug.assert(self.isNumber());
        return self.Number;
    }

    pub fn asObject(self: Value) *Object {
        std.debug.assert(self.isObject());
        return self.Object;
    }

    pub fn asString(self: Value) *StringObject {
        std.debug.assert(self.isString());
        return self.Object.as(StringObject);
    }

    pub fn asArray(self: Value) *ArrayObject {
        std.debug.assert(self.isArray());
        return self.Object.as(ArrayObject);
    }

    // Truthiness: none and false are falsy, everything else is truthy
    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .None => false,
            .Boolean => |b| b,
            .Number => |n| n != 0.0,
            .Object => true, // All objects are truthy
            .RawString => |s| s.len > 0,
        };
    }

    // Equality comparison
    pub fn equals(self: Value, other: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return false;
        }

        return switch (self) {
            .None => true,
            .Boolean => |a| a == other.Boolean,
            .Number => |a| a == other.Number,
            .Object => |a| a == other.Object, // Reference equality for now
            .RawString => |a| std.mem.eql(u8, a, other.RawString),
        };
    }

    // Create value constructors
    pub fn none() Value {
        return Value{ .None = {} };
    }

    pub fn boolean(value: bool) Value {
        return Value{ .Boolean = value };
    }

    pub fn number(value: f64) Value {
        return Value{ .Number = value };
    }

    pub fn string(gc: *GC, chars: []const u8) Value {
        return Value{ .Object = &StringObject.create(gc, chars).object };
    }

    pub fn array(gc: *GC, initial_capacity: usize) Value {
        return Value{ .Object = &ArrayObject.create(gc, initial_capacity).object };
    }

    // Debug printing
    pub fn print(self: Value) void {
        switch (self) {
            .None => std.debug.print("none", .{}),
            .Boolean => |b| std.debug.print("{any}", .{b}),
            .Number => |n| std.debug.print("{any}", .{n}),
            .RawString => |s| std.debug.print("{s}", .{s}),
            .Object => |obj| switch (obj.type) {
                .String => {
                    const str_obj = obj.as(StringObject);
                    std.debug.print("{s}", .{str_obj.chars});
                },
                .Array => {
                    const arr_obj = obj.as(ArrayObject);
                    std.debug.print("[", .{});
                    for (0..arr_obj.count) |i| {
                        if (i > 0) std.debug.print(", ", .{});
                        arr_obj.values[i].print();
                    }
                    std.debug.print("]", .{});
                },
                else => std.debug.print("<object:{any}>", .{obj.type}),
            },
        }
    }
};
