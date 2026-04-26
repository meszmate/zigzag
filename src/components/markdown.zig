//! Markdown renderer for terminal output.
//! Converts a subset of markdown to ANSI-styled text.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");

pub const Markdown = struct {
    // Styling
    h1_style: style_mod.Style,
    h2_style: style_mod.Style,
    h3_style: style_mod.Style,
    bold_style: style_mod.Style,
    italic_style: style_mod.Style,
    code_style: style_mod.Style,
    code_block_style: style_mod.Style,
    code_block_border: style_mod.Style,
    link_style: style_mod.Style,
    blockquote_style: style_mod.Style,
    blockquote_bar: style_mod.Style,
    list_bullet_style: style_mod.Style,
    hr_style: style_mod.Style,
    text_style: style_mod.Style,

    // Layout
    width: u16,
    hr_char: []const u8,

    pub fn init() Markdown {
        return .{
            .h1_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.magenta);
                s = s.underline(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .h2_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.cyan);
                s = s.inline_style(true);
                break :blk s;
            },
            .h3_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.green);
                s = s.inline_style(true);
                break :blk s;
            },
            .bold_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .italic_style = blk: {
                var s = style_mod.Style{};
                s = s.italic(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .code_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.yellow);
                s = s.bg(.fromRgb(40, 40, 40));
                s = s.inline_style(true);
                break :blk s;
            },
            .code_block_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.green);
                s = s.inline_style(true);
                break :blk s;
            },
            .code_block_border = blk: {
                var s = style_mod.Style{};
                s = s.fg(.gray(8));
                s = s.inline_style(true);
                break :blk s;
            },
            .link_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.underline(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .blockquote_style = blk: {
                var s = style_mod.Style{};
                s = s.italic(true);
                s = s.fg(.gray(14));
                s = s.inline_style(true);
                break :blk s;
            },
            .blockquote_bar = blk: {
                var s = style_mod.Style{};
                s = s.fg(.gray(10));
                s = s.inline_style(true);
                break :blk s;
            },
            .list_bullet_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.inline_style(true);
                break :blk s;
            },
            .hr_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.gray(8));
                s = s.inline_style(true);
                break :blk s;
            },
            .text_style = blk: {
                var s = style_mod.Style{};
                s = s.inline_style(true);
                break :blk s;
            },
            .width = 80,
            .hr_char = "─",
        };
    }

    /// Render markdown text to styled terminal output.
    pub fn render(self: *const Markdown, allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        var lines_iter = std.mem.splitScalar(u8, source, '\n');
        var in_code_block = false;
        var first_line = true;

        while (lines_iter.next()) |line| {
            if (!first_line) try writer.writeByte('\n');
            first_line = false;

            // Code block toggle
            if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " "), "```")) {
                in_code_block = !in_code_block;
                if (in_code_block) {
                    // Opening fence
                    const bar = try self.code_block_border.render(allocator, "┌");
                    try writer.writeAll(bar);
                    const dash = try self.code_block_border.render(allocator, "─");
                    for (0..@min(self.width - 2, 40)) |_| {
                        try writer.writeAll(dash);
                    }
                    const end = try self.code_block_border.render(allocator, "┐");
                    try writer.writeAll(end);
                } else {
                    // Closing fence
                    const bar = try self.code_block_border.render(allocator, "└");
                    try writer.writeAll(bar);
                    const dash = try self.code_block_border.render(allocator, "─");
                    for (0..@min(self.width - 2, 40)) |_| {
                        try writer.writeAll(dash);
                    }
                    const end = try self.code_block_border.render(allocator, "┘");
                    try writer.writeAll(end);
                }
                continue;
            }

            if (in_code_block) {
                const bar = try self.code_block_border.render(allocator, "│ ");
                try writer.writeAll(bar);
                const styled = try self.code_block_style.render(allocator, line);
                try writer.writeAll(styled);
                continue;
            }

            const trimmed = std.mem.trimLeft(u8, line, " ");

            // Horizontal rule
            if (trimmed.len >= 3 and isAllChar(trimmed, '-')) {
                const dash = try self.hr_style.render(allocator, self.hr_char);
                for (0..@min(self.width, 60)) |_| {
                    try writer.writeAll(dash);
                }
                continue;
            }

            if (trimmed.len >= 3 and isAllChar(trimmed, '*') and !std.mem.startsWith(u8, trimmed, "**")) {
                const dash = try self.hr_style.render(allocator, self.hr_char);
                for (0..@min(self.width, 60)) |_| {
                    try writer.writeAll(dash);
                }
                continue;
            }

            // Headers
            if (std.mem.startsWith(u8, trimmed, "### ")) {
                const content = trimmed[4..];
                const styled = try self.h3_style.render(allocator, content);
                try writer.writeAll(styled);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "## ")) {
                const content = trimmed[3..];
                const styled = try self.h2_style.render(allocator, content);
                try writer.writeAll(styled);
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "# ")) {
                const content = trimmed[2..];
                const styled = try self.h1_style.render(allocator, content);
                try writer.writeAll(styled);
                continue;
            }

            // Blockquote
            if (std.mem.startsWith(u8, trimmed, "> ")) {
                const content = trimmed[2..];
                const bar = try self.blockquote_bar.render(allocator, "│ ");
                try writer.writeAll(bar);
                const styled = try self.blockquote_style.render(allocator, content);
                try writer.writeAll(styled);
                continue;
            }

            // Unordered list
            if (std.mem.startsWith(u8, trimmed, "- ") or std.mem.startsWith(u8, trimmed, "* ")) {
                const indent = line.len - trimmed.len;
                for (0..indent) |_| try writer.writeByte(' ');
                const bullet = try self.list_bullet_style.render(allocator, "• ");
                try writer.writeAll(bullet);
                const content = trimmed[2..];
                const styled = try self.renderInline(allocator, content);
                try writer.writeAll(styled);
                continue;
            }

            // Ordered list (simple: "1. ", "2. ", etc.)
            if (trimmed.len >= 3 and trimmed[0] >= '0' and trimmed[0] <= '9') {
                if (std.mem.indexOf(u8, trimmed[0..@min(4, trimmed.len)], ". ")) |dot_pos| {
                    const indent = line.len - trimmed.len;
                    for (0..indent) |_| try writer.writeByte(' ');
                    const num = try self.list_bullet_style.render(allocator, trimmed[0 .. dot_pos + 2]);
                    try writer.writeAll(num);
                    const content = trimmed[dot_pos + 2 ..];
                    const styled = try self.renderInline(allocator, content);
                    try writer.writeAll(styled);
                    continue;
                }
            }

            // Empty line
            if (trimmed.len == 0) {
                continue;
            }

            // Regular paragraph with inline formatting
            const styled = try self.renderInline(allocator, line);
            try writer.writeAll(styled);
        }

        return result.toOwnedSlice();
    }

    /// Render inline formatting: **bold**, *italic*, `code`, [links](url)
    fn renderInline(self: *const Markdown, allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        var i: usize = 0;
        while (i < text.len) {
            // Bold: **text**
            if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
                if (std.mem.indexOf(u8, text[i + 2 ..], "**")) |end| {
                    const content = text[i + 2 .. i + 2 + end];
                    const styled = try self.bold_style.render(allocator, content);
                    try writer.writeAll(styled);
                    i += 4 + end;
                    continue;
                }
            }

            // Italic: *text*
            if (text[i] == '*' and (i + 1 >= text.len or text[i + 1] != '*')) {
                if (std.mem.indexOfScalar(u8, text[i + 1 ..], '*')) |end| {
                    const content = text[i + 1 .. i + 1 + end];
                    const styled = try self.italic_style.render(allocator, content);
                    try writer.writeAll(styled);
                    i += 2 + end;
                    continue;
                }
            }

            // Inline code: `code`
            if (text[i] == '`') {
                if (std.mem.indexOfScalar(u8, text[i + 1 ..], '`')) |end| {
                    const content = text[i + 1 .. i + 1 + end];
                    const styled = try self.code_style.render(allocator, content);
                    try writer.writeAll(styled);
                    i += 2 + end;
                    continue;
                }
            }

            // Link: [text](url)
            if (text[i] == '[') {
                if (std.mem.indexOfScalar(u8, text[i + 1 ..], ']')) |text_end| {
                    const link_text = text[i + 1 .. i + 1 + text_end];
                    const after_bracket = i + 2 + text_end;
                    if (after_bracket < text.len and text[after_bracket] == '(') {
                        if (std.mem.indexOfScalar(u8, text[after_bracket + 1 ..], ')')) |url_end| {
                            const url = text[after_bracket + 1 .. after_bracket + 1 + url_end];
                            const styled_text = try self.link_style.render(allocator, link_text);
                            try writer.writeAll(styled_text);
                            var dim = style_mod.Style{};
                            dim = dim.fg(.gray(10));
                            dim = dim.inline_style(true);
                            const url_str = try std.fmt.allocPrint(allocator, " ({s})", .{url});
                            const styled_url = try dim.render(allocator, url_str);
                            try writer.writeAll(styled_url);
                            i = after_bracket + 2 + url_end;
                            continue;
                        }
                    }
                }
            }

            // Regular character
            try writer.writeByte(text[i]);
            i += 1;
        }

        return result.toOwnedSlice();
    }

    fn isAllChar(s: []const u8, c: u8) bool {
        for (s) |ch| {
            if (ch != c and ch != ' ') return false;
        }
        return true;
    }
};
