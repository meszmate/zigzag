//! The Model contract, and the comptime helpers that let it be flexible.
//!
//! A model supplies three functions:
//!
//!     pub fn init(self: *Model, ctx: *Context) Cmd(Msg)
//!     pub fn update(self: *Model, msg: Msg, ctx: *Context) Cmd(Msg)
//!     pub fn view(self: *const Model, ctx: *const Context) []const u8
//!
//! Each of them may return an error union instead (`!Cmd(Msg)`, `![]const u8`).
//! Views allocate on nearly every line, so without that every one of them ends
//! up littered with `catch "Error"`, which turns an allocation failure into a
//! rendering artefact.

const std = @import("std");

/// Whether a function returns an error union. Accepts a function type or a
/// pointer to one.
pub fn returnsError(comptime Func: type) bool {
    const return_type = returnType(Func) orelse return false;
    return @typeInfo(return_type) == .error_union;
}

/// The result type a wrapper should use to mirror `Func`'s fallibility:
/// `Payload` when `Func` cannot fail, `E!Payload` when it can.
pub fn Result(comptime Func: type, comptime Payload: type) type {
    const return_type = returnType(Func) orelse return Payload;
    return switch (@typeInfo(return_type)) {
        .error_union => |eu| eu.error_set!Payload,
        else => Payload,
    };
}

fn returnType(comptime Func: type) ?type {
    return switch (@typeInfo(Func)) {
        .@"fn" => |f| f.return_type,
        .pointer => |p| @typeInfo(p.child).@"fn".return_type,
        else => null,
    };
}

/// Fail at compile time with a readable message when a type is missing part of
/// the Model contract.
pub fn validate(comptime Model: type, comptime role: []const u8) void {
    comptime {
        for ([_][]const u8{ "Msg", "init", "update", "view" }) |name| {
            if (!@hasDecl(Model, name)) {
                @compileError(role ++ " '" ++ @typeName(Model) ++ "' is missing '" ++
                    name ++ "'. A model needs a 'Msg' type plus 'init', 'update' and 'view'.");
            }
        }
    }
}

test "returnsError distinguishes fallible signatures" {
    const S = struct {
        fn plain() u8 {
            return 0;
        }
        fn fallible() !u8 {
            return 0;
        }
    };

    try std.testing.expect(!returnsError(@TypeOf(S.plain)));
    try std.testing.expect(returnsError(@TypeOf(S.fallible)));
    try std.testing.expect(returnsError(@TypeOf(&S.fallible)));
}

test "Result mirrors fallibility" {
    const S = struct {
        fn plain() u8 {
            return 0;
        }
        fn fallible() error{Boom}!u8 {
            return 0;
        }
    };

    try std.testing.expectEqual([]const u8, Result(@TypeOf(S.plain), []const u8));
    try std.testing.expectEqual(
        error{Boom}![]const u8,
        Result(@TypeOf(S.fallible), []const u8),
    );
}
