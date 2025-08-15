//! This module contains all the necessary abstractions to load and read source code files

const std = @import("std");

const Allocator = std.mem.Allocator;

/// loadFile reads the source code from a file.
///
/// Params:
/// * allocator - The allocator used to allocate space for the source code.
/// * path - The file path where the source code file is.
///
/// Returns:
/// * []u8 - An owned slice containing the source code from the file.
pub fn loadFile(allocator: Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
}

test "loadFile works correctly" {
    const alloc = std.testing.allocator;

    // Create a temporary directory that gets cleaned up automatically
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup(); // This deletes the whole temp directory

    // Write test content to a file in the temp directory
    const test_content = "This is test content for loadFile!";
    try tmp.dir.writeFile(.{ .sub_path = "test.txt", .data = test_content });

    // Get the absolute path to the temp file
    const temp_file_path = try tmp.dir.realpathAlloc(alloc, "test.txt");
    defer alloc.free(temp_file_path);

    // Test your loadFile function
    const result = try loadFile(alloc, temp_file_path);
    defer alloc.free(result);

    try std.testing.expectEqualStrings(test_content, result);
}
