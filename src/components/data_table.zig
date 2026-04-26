//! DataTable — table with cell-level cursor, frozen columns, and horizontal
//! scroll.
//!
//! Distinct from the existing `Table` (compile-time column count, row-only
//! cursor) and `SortableTable` (sorting and styling). DataTable targets the
//! "spreadsheet view" use case: many columns, navigable cell-by-cell,
//! leftmost columns pinned so they stay visible while the rest of the grid
//! scrolls horizontally.
//!
//! The column count is runtime, so it's a good fit for dynamic schemas
//! (database results, log fields, CSV files).

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const border_mod = @import("../style/border.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub const Align = enum { left, center, right };

pub const Column = struct {
    header: []const u8,
    /// Fixed display width in cells. Required (we don't auto-fit since the
    /// row store may be huge or lazy-loaded).
    width: u16,
    @"align": Align = .left,
};

pub const DataTable = struct {
    allocator: std.mem.Allocator,

    columns: std.array_list.Managed(Column),
    /// Row store: each row is a slice of cell strings, length must match
    /// columns.len. The DataTable does not own these strings; the caller
    /// guarantees they live as long as the table is rendered.
    rows: std.array_list.Managed([]const []const u8),

    cursor_row: usize,
    cursor_col: usize,
    /// Leftmost N columns never scroll out of view.
    frozen_columns: usize,

    /// Display config.
    width: u16,
    height: u16,
    show_header: bool,
    show_borders: bool,
    /// Horizontal scroll offset in *columns* (not cells), excluding frozen.
    col_x_offset: usize,
    /// Vertical scroll offset in rows.
    y_offset: usize,

    /// Styling.
    header_style: style_mod.Style,
    cell_style: style_mod.Style,
    cursor_cell_style: style_mod.Style,
    cursor_row_style: style_mod.Style,
    frozen_separator_style: style_mod.Style,
    border_chars: border_mod.BorderChars,

    pub fn init(allocator: std.mem.Allocator) DataTable {
        var header_s = style_mod.Style{};
        header_s = header_s.bold(true);
        header_s = header_s.inline_style(true);

        var cell_s = style_mod.Style{};
        cell_s = cell_s.inline_style(true);

        var cursor_cell = style_mod.Style{};
        cursor_cell = cursor_cell.bg(.cyan);
        cursor_cell = cursor_cell.fg(.black);
        cursor_cell = cursor_cell.inline_style(true);

        var cursor_row = style_mod.Style{};
        cursor_row = cursor_row.bg(.gray(4));
        cursor_row = cursor_row.inline_style(true);

        var frozen_sep = style_mod.Style{};
        frozen_sep = frozen_sep.fg(.gray(8));
        frozen_sep = frozen_sep.inline_style(true);

        return .{
            .allocator = allocator,
            .columns = std.array_list.Managed(Column).init(allocator),
            .rows = std.array_list.Managed([]const []const u8).init(allocator),
            .cursor_row = 0,
            .cursor_col = 0,
            .frozen_columns = 0,
            .width = 80,
            .height = 12,
            .show_header = true,
            .show_borders = false,
            .col_x_offset = 0,
            .y_offset = 0,
            .header_style = header_s,
            .cell_style = cell_s,
            .cursor_cell_style = cursor_cell,
            .cursor_row_style = cursor_row,
            .frozen_separator_style = frozen_sep,
            .border_chars = .normal,
        };
    }

    pub fn deinit(self: *DataTable) void {
        self.columns.deinit();
        self.rows.deinit();
    }

    pub fn setColumns(self: *DataTable, cols: []const Column) !void {
        self.columns.clearRetainingCapacity();
        try self.columns.appendSlice(cols);
        if (self.cursor_col >= self.columns.items.len) {
            self.cursor_col = self.columns.items.len -| 1;
        }
        if (self.frozen_columns > self.columns.items.len) {
            self.frozen_columns = self.columns.items.len;
        }
    }

    pub fn addRow(self: *DataTable, cells: []const []const u8) !void {
        if (cells.len != self.columns.items.len) return error.ColumnCountMismatch;
        try self.rows.append(cells);
    }

    pub fn setRows(self: *DataTable, rows: []const []const []const u8) !void {
        for (rows) |r| {
            if (r.len != self.columns.items.len) return error.ColumnCountMismatch;
        }
        self.rows.clearRetainingCapacity();
        try self.rows.appendSlice(rows);
        if (self.cursor_row >= self.rows.items.len) {
            self.cursor_row = self.rows.items.len -| 1;
        }
    }

    pub fn setSize(self: *DataTable, w: u16, h: u16) void {
        self.width = w;
        self.height = h;
    }

    pub fn setFrozenColumns(self: *DataTable, n: usize) void {
        self.frozen_columns = @min(n, self.columns.items.len);
        if (self.cursor_col < self.frozen_columns) {
            // Frozen cells are still cursorable.
        }
        self.col_x_offset = 0;
    }

    pub fn moveLeft(self: *DataTable) void {
        if (self.cursor_col > 0) self.cursor_col -= 1;
        self.ensureCursorVisible();
    }

    pub fn moveRight(self: *DataTable) void {
        if (self.cursor_col + 1 < self.columns.items.len) self.cursor_col += 1;
        self.ensureCursorVisible();
    }

    pub fn moveUp(self: *DataTable) void {
        if (self.cursor_row > 0) self.cursor_row -= 1;
        self.ensureCursorRowVisible();
    }

    pub fn moveDown(self: *DataTable) void {
        if (self.cursor_row + 1 < self.rows.items.len) self.cursor_row += 1;
        self.ensureCursorRowVisible();
    }

    pub fn pageUp(self: *DataTable) void {
        const visible = self.dataRowsAvailable();
        self.cursor_row -|= visible;
        self.ensureCursorRowVisible();
    }

    pub fn pageDown(self: *DataTable) void {
        const visible = self.dataRowsAvailable();
        self.cursor_row = @min(self.cursor_row + visible, self.rows.items.len -| 1);
        self.ensureCursorRowVisible();
    }

    pub fn gotoFirstRow(self: *DataTable) void {
        self.cursor_row = 0;
        self.y_offset = 0;
    }

    pub fn gotoLastRow(self: *DataTable) void {
        self.cursor_row = self.rows.items.len -| 1;
        self.ensureCursorRowVisible();
    }

    pub fn gotoFirstColumn(self: *DataTable) void {
        self.cursor_col = 0;
        self.col_x_offset = 0;
    }

    pub fn gotoLastColumn(self: *DataTable) void {
        self.cursor_col = self.columns.items.len -| 1;
        self.ensureCursorVisible();
    }

    pub fn handleKey(self: *DataTable, key: keys.KeyEvent) void {
        switch (key.key) {
            .left => self.moveLeft(),
            .right => self.moveRight(),
            .up => self.moveUp(),
            .down => self.moveDown(),
            .page_up => self.pageUp(),
            .page_down => self.pageDown(),
            .home => self.gotoFirstColumn(),
            .end => self.gotoLastColumn(),
            .char => |c| switch (c) {
                'h' => self.moveLeft(),
                'l' => self.moveRight(),
                'k' => self.moveUp(),
                'j' => self.moveDown(),
                'g' => self.gotoFirstRow(),
                'G' => self.gotoLastRow(),
                else => {},
            },
            else => {},
        }
    }

    /// Number of data rows that fit in the viewport (excluding header).
    fn dataRowsAvailable(self: *const DataTable) usize {
        const header_lines: usize = if (self.show_header) 2 else 0; // header + separator
        return @as(usize, self.height) -| header_lines;
    }

    fn ensureCursorRowVisible(self: *DataTable) void {
        const avail = self.dataRowsAvailable();
        if (avail == 0) return;
        if (self.cursor_row < self.y_offset) {
            self.y_offset = self.cursor_row;
        } else if (self.cursor_row >= self.y_offset + avail) {
            self.y_offset = self.cursor_row - avail + 1;
        }
    }

    fn ensureCursorVisible(self: *DataTable) void {
        // Frozen cursors don't scroll.
        if (self.cursor_col < self.frozen_columns) {
            self.col_x_offset = 0;
            return;
        }

        // Compute non-frozen visible width.
        const frozen_w = self.frozenWidth();
        const avail: usize = @as(usize, self.width) -| frozen_w;

        // Walk from col_x_offset to find which non-frozen columns fit.
        const total_non_frozen = self.columns.items.len - self.frozen_columns;
        const cursor_idx = self.cursor_col - self.frozen_columns;

        // First, scroll right if cursor is past visible.
        var off = self.col_x_offset;
        while (off < total_non_frozen) {
            var used: usize = 0;
            var i = off;
            var found = false;
            while (i < total_non_frozen) : (i += 1) {
                const col_w = self.columns.items[self.frozen_columns + i].width;
                if (used + col_w > avail) break;
                used += col_w + 1; // 1 for column gap
                if (i == cursor_idx) {
                    found = true;
                    break;
                }
            }
            if (cursor_idx >= off and found) break;
            if (cursor_idx < off) {
                off = cursor_idx;
                break;
            }
            off += 1;
        }
        self.col_x_offset = off;
    }

    fn frozenWidth(self: *const DataTable) usize {
        var sum: usize = 0;
        for (self.columns.items[0..self.frozen_columns], 0..) |c, i| {
            sum += c.width;
            if (i + 1 < self.frozen_columns) sum += 1;
        }
        if (self.frozen_columns > 0 and self.frozen_columns < self.columns.items.len) {
            sum += 2; // separator " │ "
        }
        return sum;
    }

    pub fn view(self: *DataTable, allocator: std.mem.Allocator) ![]const u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        const visible_cols = try self.computeVisibleColumns(allocator);
        defer allocator.free(visible_cols);

        if (self.show_header) {
            try self.renderRow(allocator, w, null, visible_cols, true);
            try w.writeByte('\n');
            try self.renderHeaderSeparator(allocator, w, visible_cols);
            try w.writeByte('\n');
        }

        const avail = self.dataRowsAvailable();
        const start = self.y_offset;
        const end = @min(start + avail, self.rows.items.len);
        var first = true;
        for (start..end) |row_idx| {
            if (!first) try w.writeByte('\n');
            first = false;
            try self.renderRow(allocator, w, row_idx, visible_cols, false);
        }

        return out.toOwnedSlice();
    }

    /// Indices of columns to render: all frozen + a slice of non-frozen
    /// starting at col_x_offset that fits in the remaining width.
    fn computeVisibleColumns(self: *const DataTable, allocator: std.mem.Allocator) ![]usize {
        var list = std.array_list.Managed(usize).init(allocator);
        errdefer list.deinit();

        var i: usize = 0;
        while (i < self.frozen_columns) : (i += 1) try list.append(i);

        const frozen_w = self.frozenWidth();
        const avail: usize = @as(usize, self.width) -| frozen_w;
        var used: usize = 0;
        i = self.frozen_columns + self.col_x_offset;
        while (i < self.columns.items.len) : (i += 1) {
            const c = self.columns.items[i];
            const need = c.width + (if (used > 0) @as(usize, 1) else 0);
            if (used + need > avail) break;
            used += need;
            try list.append(i);
        }
        return list.toOwnedSlice();
    }

    fn renderRow(self: *const DataTable, allocator: std.mem.Allocator, writer: *Writer, row_idx: ?usize, visible_cols: []const usize, is_header: bool) !void {
        for (visible_cols, 0..) |col_idx, i| {
            // Frozen separator.
            if (self.frozen_columns > 0 and i == self.frozen_columns) {
                const sep = try self.frozen_separator_style.render(allocator, " │ ");
                defer allocator.free(sep);
                try writer.writeAll(sep);
            } else if (i > 0) {
                try writer.writeByte(' ');
            }

            const col = self.columns.items[col_idx];
            const cell_text: []const u8 = if (is_header)
                col.header
            else
                self.rows.items[row_idx.?][col_idx];

            const formatted = try formatCell(allocator, cell_text, col.width, col.@"align");
            defer allocator.free(formatted);

            const is_cursor_cell = !is_header and row_idx.? == self.cursor_row and col_idx == self.cursor_col;
            const is_cursor_row = !is_header and row_idx.? == self.cursor_row;

            const s = if (is_header)
                self.header_style
            else if (is_cursor_cell)
                self.cursor_cell_style
            else if (is_cursor_row)
                self.cursor_row_style
            else
                self.cell_style;

            const styled = try s.render(allocator, formatted);
            defer allocator.free(styled);
            try writer.writeAll(styled);
        }
    }

    fn renderHeaderSeparator(self: *const DataTable, allocator: std.mem.Allocator, writer: *Writer, visible_cols: []const usize) !void {
        for (visible_cols, 0..) |col_idx, i| {
            if (self.frozen_columns > 0 and i == self.frozen_columns) {
                const sep = try self.frozen_separator_style.render(allocator, "─┼─");
                defer allocator.free(sep);
                try writer.writeAll(sep);
            } else if (i > 0) {
                try writer.writeAll("─");
            }
            const col = self.columns.items[col_idx];
            const dashes = try allocator.alloc(u8, col.width * 3); // up to 3 bytes per UTF-8 dash
            defer allocator.free(dashes);
            const dash = "─";
            var written: usize = 0;
            var k: usize = 0;
            while (k < col.width) : (k += 1) {
                @memcpy(dashes[written .. written + dash.len], dash);
                written += dash.len;
            }
            const styled = try self.frozen_separator_style.render(allocator, dashes[0..written]);
            defer allocator.free(styled);
            try writer.writeAll(styled);
        }
    }
};

fn formatCell(allocator: std.mem.Allocator, text: []const u8, width: u16, align_: Align) ![]u8 {
    const w = measure.width(text);
    if (w == width) return allocator.dupe(u8, text);
    if (w > width) {
        const truncated = try measure.truncate(allocator, text, width);
        // Always cast away const since we ultimately return `[]u8`.
        return @constCast(truncated);
    }
    const padding = width - w;
    return switch (align_) {
        .left => @constCast(try measure.padRight(allocator, text, width)),
        .right => @constCast(try measure.padLeft(allocator, text, width)),
        .center => blk: {
            const left = padding / 2;
            const right = padding - left;
            const out = try allocator.alloc(u8, left + text.len + right);
            @memset(out[0..left], ' ');
            @memcpy(out[left .. left + text.len], text);
            @memset(out[left + text.len ..], ' ');
            break :blk out;
        },
    };
}

// `measure.padRight` and `padLeft` return `[]const u8`; cast for callers
// expecting `[]u8`.
fn padOwned(allocator: std.mem.Allocator, text: []const u8, w: usize, left: bool) ![]u8 {
    const r = if (left) try measure.padLeft(allocator, text, w) else try measure.padRight(allocator, text, w);
    return @constCast(r);
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "moveRight clamps at last column" {
    var t = DataTable.init(testing.allocator);
    defer t.deinit();
    try t.setColumns(&.{
        .{ .header = "A", .width = 4 },
        .{ .header = "B", .width = 4 },
    });
    try t.addRow(&.{ "1", "2" });
    t.moveRight();
    try testing.expectEqual(@as(usize, 1), t.cursor_col);
    t.moveRight();
    try testing.expectEqual(@as(usize, 1), t.cursor_col);
}

test "moveDown advances cursor row" {
    var t = DataTable.init(testing.allocator);
    defer t.deinit();
    try t.setColumns(&.{.{ .header = "A", .width = 4 }});
    try t.addRow(&.{"1"});
    try t.addRow(&.{"2"});
    t.moveDown();
    try testing.expectEqual(@as(usize, 1), t.cursor_row);
}

test "frozen columns stay at zero offset" {
    var t = DataTable.init(testing.allocator);
    defer t.deinit();
    try t.setColumns(&.{
        .{ .header = "id", .width = 4 },
        .{ .header = "name", .width = 6 },
        .{ .header = "x", .width = 4 },
        .{ .header = "y", .width = 4 },
        .{ .header = "z", .width = 4 },
    });
    try t.addRow(&.{ "1", "alice", "10", "20", "30" });
    t.setSize(20, 5);
    t.setFrozenColumns(1);
    t.cursor_col = 4;
    t.moveLeft();
    t.moveLeft();
    t.moveLeft();
    t.moveLeft(); // back to col 0 (frozen)
    try testing.expectEqual(@as(usize, 0), t.cursor_col);
    try testing.expectEqual(@as(usize, 0), t.col_x_offset);
}

test "view contains headers and data" {
    const allocator = testing.allocator;
    var t = DataTable.init(allocator);
    defer t.deinit();
    try t.setColumns(&.{
        .{ .header = "id", .width = 4 },
        .{ .header = "name", .width = 6 },
    });
    try t.addRow(&.{ "42", "alice" });

    const out = try t.view(allocator);
    defer allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "id") != null);
    try testing.expect(std.mem.indexOf(u8, out, "alice") != null);
    try testing.expect(std.mem.indexOf(u8, out, "42") != null);
}

test "view renders frozen separator when columns are frozen" {
    const allocator = testing.allocator;
    var t = DataTable.init(allocator);
    defer t.deinit();
    try t.setColumns(&.{
        .{ .header = "id", .width = 4 },
        .{ .header = "name", .width = 6 },
        .{ .header = "value", .width = 6 },
    });
    try t.addRow(&.{ "1", "alice", "10" });
    t.setFrozenColumns(1);
    const out = try t.view(allocator);
    defer allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "│") != null);
}

test "addRow rejects mismatched column count" {
    var t = DataTable.init(testing.allocator);
    defer t.deinit();
    try t.setColumns(&.{
        .{ .header = "A", .width = 4 },
        .{ .header = "B", .width = 4 },
    });
    try testing.expectError(error.ColumnCountMismatch, t.addRow(&.{"only one"}));
}
