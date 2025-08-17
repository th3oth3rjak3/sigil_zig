const std = @import("std");
const source_loader = @import("source_loading.zig");
const compiling = @import("compiling.zig");
const runtime = @import("runtime.zig");
const memory = @import("memory.zig");
const disassembler = @import("disassembler.zig");

const Compiler = compiling.Compiler;
const Allocator = std.mem.Allocator;
const Chunk = runtime.Chunk;
const VM = runtime.VM;
const GC = memory.GC;
const print = std.debug.print;

const Command = enum {
    repl,
    run,
    help,
};

const RunTarget = union(enum) {
    directory: []u8,
    file: []u8,
};

const Args = struct {
    command: Command,
    run_target: ?RunTarget = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer {
        const result = gpa.deinit();

        print("\n\n============== LEAK SUMMARY ==============\n", .{});

        if (result == .leak) {
            print("Allocator leaked!\n", .{});
        } else {
            print("No leaks detected!\n", .{});
        }

        print("\n", .{});
    }
    const allocator = gpa.allocator();

    const parsed_args = parseArgs(allocator) catch |err| switch (err) {
        error.MissingCommand, error.UnknownCommand, error.UnexpectedArgument, error.MissingPath, error.PathNotFound, error.InvalidPathType => return, // Error already printed
        else => return err,
    };

    switch (parsed_args.command) {
        .help => printUsage(), // Already handled in parseArgs
        .repl => try handleRepl(),
        .run => {
            if (parsed_args.run_target) |target| {
                switch (target) {
                    .directory => |path| {
                        try handleRunDirectory(allocator, path);
                    },
                    .file => |path| {
                        try handleRunFile(allocator, path);
                    },
                }
            }
        },
    }
}

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    const command_str = args.next() orelse {
        print("Error: No command provided\n", .{});
        printUsage();
        return error.MissingCommand;
    };

    const command = std.meta.stringToEnum(Command, command_str) orelse {
        print("Error: Unknown command '{s}'\n", .{command_str});
        printUsage();
        return error.UnknownCommand;
    };

    switch (command) {
        .help => {
            return Args{ .command = .help };
        },
        .repl => {
            // Check if there are unexpected additional arguments
            if (args.next()) |extra| {
                print("Error: Unexpected argument '{s}' for repl command\n", .{extra});
                return error.UnexpectedArgument;
            }
            return Args{ .command = .repl };
        },
        .run => {
            const path = args.next() orelse {
                print("Error: 'run' command requires a path argument\n", .{});
                printUsage();
                return error.MissingPath;
            };

            // Check if there are unexpected additional arguments
            if (args.next()) |extra| {
                print("Error: Unexpected argument '{s}' for run command\n", .{extra});
                return error.UnexpectedArgument;
            }

            // Determine if it's a directory or file
            const cwd = std.fs.cwd();
            const stat = cwd.statFile(path) catch |err| switch (err) {
                error.FileNotFound => {
                    print("Error: Path '{s}' not found\n", .{path});
                    return error.PathNotFound;
                },
                else => return err,
            };

            const target = switch (stat.kind) {
                .directory => RunTarget{ .directory = try allocator.dupe(u8, path) },
                .file => RunTarget{ .file = try allocator.dupe(u8, path) },
                else => {
                    print("Error: Path '{s}' is not a file or directory\n", .{path});
                    return error.InvalidPathType;
                },
            };

            return Args{ .command = .run, .run_target = target };
        },
    }
}

fn printUsage() void {
    print("Sigil Programming Language Interpreter\n", .{});
    print("\n", .{});
    print("Usage: sigil <command> [args]\n", .{});
    print("\nCommands:\n", .{});
    print("  repl           Start the REPL\n", .{});
    print("  run <path>     Run a file or directory\n", .{});
    print("  help           Show this help message\n", .{});
    print("\nExamples:\n", .{});
    print("  sigil repl\n", .{});
    print("  sigil run .            # Looks for main.sgl in the provided directory\n", .{});
    print("  sigil run ./hello.sgl  # Runs the file directly\n", .{});
}

fn handleRepl() !void {
    print("Starting REPL...\n", .{});
    // TODO: Implement REPL
}

fn handleRunDirectory(allocator: Allocator, path: []u8) !void {
    defer allocator.free(path);
    print("Running directory: {s}\n", .{path});
    print("Looking for main.sgl...\n", .{});
    // TODO: Find and run main.sgl
}

fn handleRunFile(allocator: Allocator, path: []u8) !void {
    defer allocator.free(path);
    const source = try source_loader.loadFile(allocator, @constCast(path));
    defer allocator.free(source);
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();
    var gc = GC.init(allocator);
    defer gc.deinit();

    var compiler = Compiler.init(allocator, &gc, @constCast(source), &chunk);
    defer compiler.deinit();
    const succeeded = try compiler.compile();
    if (!succeeded) {
        return;
    }

    // Add disassembly output
    // disassembler.disassembleChunk(&chunk, path);

    var vm = VM.init(allocator, &gc, &chunk);
    defer vm.deinit();
    try vm.interpret();
}

test "main tests" {
    _ = @import("ast.zig");
    _ = @import("common.zig");
    _ = @import("compiling.zig");
    _ = @import("disassembler.zig");
    _ = @import("error_handling.zig");
    _ = @import("lexing.zig");
    _ = @import("memory.zig");
    _ = @import("parsing.zig");
    _ = @import("runtime.zig");
    _ = @import("source_loading.zig");
    _ = @import("tokens.zig");
    _ = @import("values.zig");
}
