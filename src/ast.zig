const std = @import("std");
const token_file = @import("tokens.zig");

const Token = token_file.Token;

pub const Expr = union(enum) {
    literal: Literal,
    identifier: []const u8,
    binary: *Binary,
    unary: *Unary,
    call: *Call,
    property_access: *PropertyAccess,
    function_expr: *FunctionExpr,
    grouping: *Expr,
    assignment: *Assignment,

    pub const Literal = union(enum) {
        number: []const u8,
        string: []const u8,
        boolean: bool,
        none: void,
    };

    pub const Binary = struct {
        left: Expr,
        operator: Token,
        right: Expr,
    };

    pub const Unary = struct {
        operator: Token,
        right: Expr,
    };

    pub const Call = struct {
        callee: Expr,
        arguments: []Expr,
    };

    pub const Assignment = struct {
        name: []const u8,
        value: Expr,
    };

    pub const PropertyAccess = struct {
        object: []const u8, // "this"
        property: []const u8,
    };

    pub const FunctionExpr = struct {
        parameters: []Parameter,
        body: []Stmt,
    };
};

pub const Stmt = union(enum) {
    expression: Expr,
    if_stmt: *IfStmt,
    while_stmt: *WhileStmt,
    for_stmt: *ForStmt,
    return_stmt: *ReturnStmt,
    class_decl: *ClassDecl,
    block: []Stmt,
    print: Expr,

    pub const IfStmt = struct {
        condition: Expr,
        then_branch: *Stmt,
        else_branch: ?*Stmt,
    };

    pub const WhileStmt = struct {
        condition: Expr,
        body: *Stmt,
    };

    pub const ForStmt = struct {
        initializer: ?Expr,
        condition: ?Expr,
        increment: ?Expr,
        body: *Stmt,
    };

    pub const ReturnStmt = struct {
        value: Expr,
    };

    pub const ClassDecl = struct {
        name: []const u8,
        constructor: ?Constructor,
        methods: []Method,
    };

    pub const Constructor = struct {
        parameters: []Parameter,
        body: []Stmt,
    };

    pub const Method = struct {
        name: []const u8,
        parameters: []Parameter,
        body: []Stmt,
    };
};

pub const Parameter = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
};
