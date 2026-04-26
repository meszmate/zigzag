//! Code viewer with syntax highlighting.
//! Provides keyword-based highlighting for common languages.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const CodeView = struct {
    source: []const u8 = "",
    language: Language = .zig,
    show_line_numbers: bool = true,
    start_line: usize = 1,
    /// Highlight specific line (1-indexed, 0 = none).
    highlight_line: usize = 0,
    /// Line number width (number of digits, 0 = auto).
    line_number_width: u8 = 4,
    /// Separator between line numbers and code.
    line_separator: []const u8 = "\xe2\x94\x82",
    /// Tab display width.
    tab_width: u8 = 4,
    /// Operator style.
    operator_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.white);
        s = s.inline_style(true);
        break :blk s;
    },

    // Styles
    keyword_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.magenta);
        s = s.bold(true);
        s = s.inline_style(true);
        break :blk s;
    },
    string_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.green);
        s = s.inline_style(true);
        break :blk s;
    },
    comment_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(10));
        s = s.italic(true);
        s = s.inline_style(true);
        break :blk s;
    },
    number_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.cyan);
        s = s.inline_style(true);
        break :blk s;
    },
    type_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.yellow);
        s = s.inline_style(true);
        break :blk s;
    },
    builtin_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.cyan);
        s = s.bold(true);
        s = s.inline_style(true);
        break :blk s;
    },
    line_number_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(8));
        s = s.inline_style(true);
        break :blk s;
    },
    highlight_bg: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bg(.fromRgb(40, 40, 60));
        s = s.inline_style(true);
        break :blk s;
    },

    pub const Language = enum {
        zig,
        python,
        javascript,
        go,
        rust,
        plain,
    };

    pub fn view(self: *const CodeView, allocator: std.mem.Allocator) []const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        var lines = std.mem.splitScalar(u8, self.source, '\n');
        var line_num: usize = self.start_line;
        var first = true;
        var in_multiline_comment = false;

        while (lines.next()) |line| {
            if (!first) writer.writeByte('\n') catch {};
            first = false;

            // Line number
            if (self.show_line_numbers) {
                const num_str = std.fmt.allocPrint(allocator, "{d:>4} {s} ", .{ line_num, self.line_separator }) catch "   ? | ";
                writer.writeAll(self.line_number_style.render(allocator, num_str) catch num_str) catch {};
            }

            // Highlight line background
            const is_highlighted = (self.highlight_line > 0 and line_num == self.highlight_line);

            // Syntax highlight the line
            const highlighted = self.highlightLine(allocator, line, &in_multiline_comment);
            if (is_highlighted) {
                writer.writeAll(self.highlight_bg.render(allocator, highlighted) catch highlighted) catch {};
            } else {
                writer.writeAll(highlighted) catch {};
            }

            line_num += 1;
        }

        return result.toArrayList().items;
    }

    fn highlightLine(self: *const CodeView, allocator: std.mem.Allocator, line: []const u8, in_multiline: *bool) []const u8 {
        if (self.language == .plain) return line;

        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        var i: usize = 0;
        while (i < line.len) {
            // Multi-line comment continuation
            if (in_multiline.*) {
                if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    writer.writeAll(self.comment_style.render(allocator, "*/") catch "*/") catch {};
                    i += 2;
                    in_multiline.* = false;
                    continue;
                }
                writer.writeAll(self.comment_style.render(allocator, line[i .. i + 1]) catch line[i .. i + 1]) catch {};
                i += 1;
                continue;
            }

            // Line comments
            if (isLineComment(self.language, line, i)) {
                writer.writeAll(self.comment_style.render(allocator, line[i..]) catch line[i..]) catch {};
                break;
            }

            // Multi-line comment start
            if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*') {
                in_multiline.* = true;
                writer.writeAll(self.comment_style.render(allocator, "/*") catch "/*") catch {};
                i += 2;
                continue;
            }

            // Strings
            if (line[i] == '"' or line[i] == '\'') {
                const quote = line[i];
                const str_start = i;
                i += 1;
                while (i < line.len and line[i] != quote) {
                    if (line[i] == '\\') i += 1; // skip escape
                    i += 1;
                }
                if (i < line.len) i += 1; // closing quote
                writer.writeAll(self.string_style.render(allocator, line[str_start..i]) catch line[str_start..i]) catch {};
                continue;
            }

            // Builtins (Zig @-prefixed)
            if (self.language == .zig and line[i] == '@' and i + 1 < line.len and std.ascii.isAlphabetic(line[i + 1])) {
                const start = i;
                i += 1;
                while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) : (i += 1) {}
                writer.writeAll(self.builtin_style.render(allocator, line[start..i]) catch line[start..i]) catch {};
                continue;
            }

            // Numbers
            if (std.ascii.isDigit(line[i])) {
                const start = i;
                while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '.' or line[i] == 'x' or line[i] == '_')) : (i += 1) {}
                writer.writeAll(self.number_style.render(allocator, line[start..i]) catch line[start..i]) catch {};
                continue;
            }

            // Identifiers / keywords
            if (std.ascii.isAlphabetic(line[i]) or line[i] == '_') {
                const start = i;
                while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) : (i += 1) {}
                const word = line[start..i];

                if (isKeyword(self.language, word)) {
                    writer.writeAll(self.keyword_style.render(allocator, word) catch word) catch {};
                } else if (isType(self.language, word)) {
                    writer.writeAll(self.type_style.render(allocator, word) catch word) catch {};
                } else {
                    writer.writeAll(word) catch {};
                }
                continue;
            }

            // Other characters
            writer.writeByte(line[i]) catch {};
            i += 1;
        }

        return result.toArrayList().items;
    }

    fn isLineComment(lang: Language, line: []const u8, pos: usize) bool {
        return switch (lang) {
            .zig, .go, .rust, .javascript => pos + 1 < line.len and line[pos] == '/' and line[pos + 1] == '/',
            .python => line[pos] == '#',
            .plain => false,
        };
    }

    fn isKeyword(lang: Language, word: []const u8) bool {
        const keywords = switch (lang) {
            .zig => &[_][]const u8{ "const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch", "break", "continue", "defer", "errdefer", "try", "catch", "comptime", "inline", "struct", "enum", "union", "error", "test", "unreachable", "undefined", "null", "true", "false", "and", "or", "orelse", "import" },
            .python => &[_][]const u8{ "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "yield", "lambda", "pass", "break", "continue", "True", "False", "None", "and", "or", "not", "in", "is", "raise", "async", "await" },
            .javascript => &[_][]const u8{ "const", "let", "var", "function", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "class", "extends", "new", "this", "import", "export", "from", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "true", "false", "null", "undefined" },
            .go => &[_][]const u8{ "func", "var", "const", "type", "struct", "interface", "return", "if", "else", "for", "switch", "case", "break", "continue", "defer", "go", "select", "chan", "map", "range", "import", "package", "true", "false", "nil" },
            .rust => &[_][]const u8{ "fn", "let", "mut", "const", "pub", "return", "if", "else", "for", "while", "loop", "match", "struct", "enum", "impl", "trait", "use", "mod", "crate", "self", "super", "move", "async", "await", "true", "false", "where" },
            .plain => &[_][]const u8{},
        };
        for (keywords) |kw| {
            if (std.mem.eql(u8, word, kw)) return true;
        }
        return false;
    }

    fn isType(lang: Language, word: []const u8) bool {
        const types = switch (lang) {
            .zig => &[_][]const u8{ "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64", "bool", "void", "usize", "isize", "type", "anytype", "anyerror", "noreturn" },
            .python => &[_][]const u8{ "int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes", "type", "object" },
            .javascript => &[_][]const u8{ "number", "string", "boolean", "object", "Array", "Promise", "Map", "Set" },
            .go => &[_][]const u8{ "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "string", "bool", "byte", "rune", "error" },
            .rust => &[_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "bool", "str", "String", "Vec", "Box", "Option", "Result", "usize", "isize" },
            .plain => &[_][]const u8{},
        };
        for (types) |t| {
            if (std.mem.eql(u8, word, t)) return true;
        }
        return false;
    }
};
