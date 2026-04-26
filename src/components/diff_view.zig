//! Diff viewer component.
//! Displays unified or side-by-side text diffs with syntax coloring.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const DiffView = struct {
    old_text: []const u8 = "",
    new_text: []const u8 = "",
    old_label: []const u8 = "old",
    new_label: []const u8 = "new",
    mode: Mode = .unified,
    show_line_numbers: bool = true,
    context_lines: usize = 3,
    /// Width of each side in side-by-side mode.
    side_width: usize = 38,
    /// Separator character for side-by-side mode.
    separator: []const u8 = "\xe2\x94\x82",
    /// Add prefix symbol.
    add_prefix: []const u8 = "+",
    /// Remove prefix symbol.
    remove_prefix: []const u8 = "-",
    /// Context prefix symbol.
    context_prefix: []const u8 = " ",

    // Styles
    add_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.green);
        s = s.inline_style(true);
        break :blk s;
    },
    remove_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.red);
        s = s.inline_style(true);
        break :blk s;
    },
    context_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(12));
        s = s.inline_style(true);
        break :blk s;
    },
    header_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.cyan);
        s = s.bold(true);
        s = s.inline_style(true);
        break :blk s;
    },
    line_num_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(8));
        s = s.inline_style(true);
        break :blk s;
    },
    separator_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(6));
        s = s.inline_style(true);
        break :blk s;
    },

    pub const Mode = enum {
        unified,
        side_by_side,
    };

    pub fn view(self: *const DiffView, allocator: std.mem.Allocator) []const u8 {
        return switch (self.mode) {
            .unified => self.renderUnified(allocator),
            .side_by_side => self.renderSideBySide(allocator),
        };
    }

    fn renderUnified(self: *const DiffView, allocator: std.mem.Allocator) []const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        // Header
        const hdr = std.fmt.allocPrint(allocator, "--- {s}\n+++ {s}", .{ self.old_label, self.new_label }) catch "";
        writer.writeAll(self.header_style.render(allocator, hdr) catch hdr) catch {};
        writer.writeByte('\n') catch {};

        // Compute diff using LCS-based approach
        const old_lines = splitLines(allocator, self.old_text);
        const new_lines = splitLines(allocator, self.new_text);
        const ops = computeDiff(allocator, old_lines, new_lines);

        var old_num: usize = 1;
        var new_num: usize = 1;

        for (ops) |op| {
            switch (op) {
                .equal => |line| {
                    if (self.show_line_numbers) {
                        const nums = std.fmt.allocPrint(allocator, "{d:>4} {d:>4} ", .{ old_num, new_num }) catch "";
                        writer.writeAll(self.line_num_style.render(allocator, nums) catch nums) catch {};
                    }
                    writer.writeAll(self.context_style.render(allocator, " ") catch " ") catch {};
                    writer.writeAll(self.context_style.render(allocator, line) catch line) catch {};
                    writer.writeByte('\n') catch {};
                    old_num += 1;
                    new_num += 1;
                },
                .delete => |line| {
                    if (self.show_line_numbers) {
                        const nums = std.fmt.allocPrint(allocator, "{d:>4}      ", .{old_num}) catch "";
                        writer.writeAll(self.line_num_style.render(allocator, nums) catch nums) catch {};
                    }
                    const prefixed = std.fmt.allocPrint(allocator, "-{s}", .{line}) catch line;
                    writer.writeAll(self.remove_style.render(allocator, prefixed) catch prefixed) catch {};
                    writer.writeByte('\n') catch {};
                    old_num += 1;
                },
                .insert => |line| {
                    if (self.show_line_numbers) {
                        const nums = std.fmt.allocPrint(allocator, "     {d:>4} ", .{new_num}) catch "";
                        writer.writeAll(self.line_num_style.render(allocator, nums) catch nums) catch {};
                    }
                    const prefixed = std.fmt.allocPrint(allocator, "+{s}", .{line}) catch line;
                    writer.writeAll(self.add_style.render(allocator, prefixed) catch prefixed) catch {};
                    writer.writeByte('\n') catch {};
                    new_num += 1;
                },
            }
        }

        // Trim trailing newline
        var array = result.toArrayList();
        if (array.items.len > 0 and array.items[array.items.len - 1] == '\n') {
            _ = array.pop();
        }

        return array.items;
    }

    fn renderSideBySide(self: *const DiffView, allocator: std.mem.Allocator) []const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        const old_lines = splitLines(allocator, self.old_text);
        const new_lines = splitLines(allocator, self.new_text);
        const ops = computeDiff(allocator, old_lines, new_lines);

        const half_width: usize = self.side_width;

        // Header
        const old_hdr = padRight(allocator, self.old_label, half_width);
        const new_hdr = self.new_label;
        writer.writeAll(self.header_style.render(allocator, old_hdr) catch old_hdr) catch {};
        writer.writeAll(self.separator_style.render(allocator, " \xe2\x94\x82 ") catch " | ") catch {};
        writer.writeAll(self.header_style.render(allocator, new_hdr) catch new_hdr) catch {};
        writer.writeByte('\n') catch {};

        // Separator line
        for (0..half_width) |_| writer.writeAll("\xe2\x94\x80") catch {};
        writer.writeAll("\xe2\x94\xbc") catch {};
        for (0..half_width + 2) |_| writer.writeAll("\xe2\x94\x80") catch {};
        writer.writeByte('\n') catch {};

        for (ops) |op| {
            switch (op) {
                .equal => |line| {
                    const padded = padRight(allocator, line, half_width);
                    writer.writeAll(self.context_style.render(allocator, padded) catch padded) catch {};
                    writer.writeAll(self.separator_style.render(allocator, " \xe2\x94\x82 ") catch " | ") catch {};
                    writer.writeAll(self.context_style.render(allocator, line) catch line) catch {};
                    writer.writeByte('\n') catch {};
                },
                .delete => |line| {
                    const padded = padRight(allocator, line, half_width);
                    writer.writeAll(self.remove_style.render(allocator, padded) catch padded) catch {};
                    writer.writeAll(self.separator_style.render(allocator, " \xe2\x94\x82 ") catch " | ") catch {};
                    writer.writeByte('\n') catch {};
                },
                .insert => |line| {
                    const blank = padRight(allocator, "", half_width);
                    writer.writeAll(blank) catch {};
                    writer.writeAll(self.separator_style.render(allocator, " \xe2\x94\x82 ") catch " | ") catch {};
                    writer.writeAll(self.add_style.render(allocator, line) catch line) catch {};
                    writer.writeByte('\n') catch {};
                },
            }
        }

        var array = result.toArrayList();
        if (array.items.len > 0 and array.items[array.items.len - 1] == '\n') {
            _ = array.pop();
        }

        return array.items;
    }

    fn padRight(allocator: std.mem.Allocator, text: []const u8, target: usize) []const u8 {
        if (text.len >= target) return text[0..target];
        var buf = std.array_list.Managed(u8).init(allocator);
        buf.appendSlice(text) catch {};
        for (0..target - text.len) |_| buf.append(' ') catch {};
        return buf.items;
    }

    fn splitLines(allocator: std.mem.Allocator, text: []const u8) []const []const u8 {
        var lines = std.array_list.Managed([]const u8).init(allocator);
        var iter = std.mem.splitScalar(u8, text, '\n');
        while (iter.next()) |line| {
            lines.append(line) catch {};
        }
        return lines.items;
    }
};

/// Diff operation.
const DiffOp = union(enum) {
    equal: []const u8,
    delete: []const u8,
    insert: []const u8,
};

/// Simple Myers-like diff: compute edit operations between old and new line arrays.
fn computeDiff(allocator: std.mem.Allocator, old: []const []const u8, new: []const []const u8) []const DiffOp {
    var ops = std.array_list.Managed(DiffOp).init(allocator);

    // Simple O(n*m) LCS-based diff
    const m = old.len;
    const n = new.len;

    if (m == 0) {
        for (new) |line| ops.append(.{ .insert = line }) catch {};
        return ops.items;
    }
    if (n == 0) {
        for (old) |line| ops.append(.{ .delete = line }) catch {};
        return ops.items;
    }

    // Build LCS table
    const table = allocator.alloc(usize, (m + 1) * (n + 1)) catch {
        // Fallback: show all as delete + insert
        for (old) |line| ops.append(.{ .delete = line }) catch {};
        for (new) |line| ops.append(.{ .insert = line }) catch {};
        return ops.items;
    };
    for (0..m + 1) |i| {
        for (0..n + 1) |j| {
            if (i == 0 or j == 0) {
                table[i * (n + 1) + j] = 0;
            } else if (std.mem.eql(u8, old[i - 1], new[j - 1])) {
                table[i * (n + 1) + j] = table[(i - 1) * (n + 1) + (j - 1)] + 1;
            } else {
                table[i * (n + 1) + j] = @max(table[(i - 1) * (n + 1) + j], table[i * (n + 1) + (j - 1)]);
            }
        }
    }

    // Backtrack to produce ops
    var rev_ops = std.array_list.Managed(DiffOp).init(allocator);
    var i: usize = m;
    var j: usize = n;
    while (i > 0 or j > 0) {
        if (i > 0 and j > 0 and std.mem.eql(u8, old[i - 1], new[j - 1])) {
            rev_ops.append(.{ .equal = old[i - 1] }) catch {};
            i -= 1;
            j -= 1;
        } else if (j > 0 and (i == 0 or table[i * (n + 1) + (j - 1)] >= table[(i - 1) * (n + 1) + j])) {
            rev_ops.append(.{ .insert = new[j - 1] }) catch {};
            j -= 1;
        } else if (i > 0) {
            rev_ops.append(.{ .delete = old[i - 1] }) catch {};
            i -= 1;
        }
    }

    // Reverse
    var idx: usize = rev_ops.items.len;
    while (idx > 0) {
        idx -= 1;
        ops.append(rev_ops.items[idx]) catch {};
    }

    return ops.items;
}
