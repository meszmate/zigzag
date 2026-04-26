//! Sortable and filterable table component.
//! Extends basic table with column sorting and text filtering.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");
const keys = @import("../input/keys.zig");

pub fn SortableTable(comptime num_cols: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        headers: [num_cols][]const u8,
        rows: std.array_list.Managed([num_cols][]const u8),
        /// Indices into rows for display order (sorted/filtered view).
        view_indices: std.array_list.Managed(usize),

        // Sort state
        sort_column: ?usize = null,
        sort_ascending: bool = true,

        // Filter
        filter_text: std.array_list.Managed(u8),
        filter_column: ?usize = null, // null = search all columns
        filter_active: bool = false,

        // Display
        col_widths: [num_cols]?u16 = .{null} ** num_cols,
        col_aligns: [num_cols]Align = .{.left} ** num_cols,
        show_header: bool = true,
        show_border: bool = true,
        border_chars: border_mod.BorderChars = .normal,

        // Interactive
        cursor_row: usize = 0,
        y_offset: usize = 0,
        visible_rows: u16 = 20,
        focused: bool = true,

        // Styling
        header_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.bold(true);
            s = s.inline_style(true);
            break :blk s;
        },
        cell_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.inline_style(true);
            break :blk s;
        },
        cursor_row_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.bg(.blue);
            s = s.fg(.white);
            s = s.inline_style(true);
            break :blk s;
        },
        sort_indicator_asc: []const u8 = " \xe2\x96\xb2",
        sort_indicator_desc: []const u8 = " \xe2\x96\xbc",

        const Self = @This();

        pub const Align = enum { left, center, right };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .headers = .{""} ** num_cols,
                .rows = std.array_list.Managed([num_cols][]const u8).init(allocator),
                .view_indices = std.array_list.Managed(usize).init(allocator),
                .filter_text = std.array_list.Managed(u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
            self.view_indices.deinit();
            self.filter_text.deinit();
        }

        pub fn setHeaders(self: *Self, hdrs: [num_cols][]const u8) void {
            self.headers = hdrs;
        }

        pub fn addRow(self: *Self, row: [num_cols][]const u8) !void {
            try self.rows.append(row);
            try self.rebuildView();
        }

        pub fn update(self: *Self, key: keys.KeyEvent) void {
            const total = self.view_indices.items.len;
            switch (key.key) {
                .up => {
                    if (self.cursor_row > 0) self.cursor_row -= 1;
                    self.ensureVisible();
                },
                .down => {
                    if (self.cursor_row + 1 < total) self.cursor_row += 1;
                    self.ensureVisible();
                },
                .char => |c| {
                    if (c >= '1' and c <= '9') {
                        const col: usize = c - '1';
                        if (col < num_cols) self.toggleSort(col);
                    } else if (c == '/') {
                        self.filter_active = true;
                    } else if (self.filter_active) {
                        if (c < 128) {
                            self.filter_text.append(@intCast(c)) catch {};
                            self.rebuildView() catch {};
                        }
                    }
                },
                .backspace => {
                    if (self.filter_active and self.filter_text.items.len > 0) {
                        _ = self.filter_text.pop();
                        self.rebuildView() catch {};
                    }
                },
                .escape => {
                    if (self.filter_active) {
                        self.filter_active = false;
                        self.filter_text.clearRetainingCapacity();
                        self.rebuildView() catch {};
                    }
                },
                .enter => {
                    if (self.filter_active) {
                        self.filter_active = false;
                    }
                },
                else => {},
            }
        }

        fn toggleSort(self: *Self, col: usize) void {
            if (self.sort_column == col) {
                self.sort_ascending = !self.sort_ascending;
            } else {
                self.sort_column = col;
                self.sort_ascending = true;
            }
            self.rebuildView() catch {};
        }

        fn rebuildView(self: *Self) !void {
            self.view_indices.clearRetainingCapacity();
            const filter = self.filter_text.items;

            for (0..self.rows.items.len) |i| {
                if (filter.len > 0) {
                    var matches = false;
                    for (self.rows.items[i]) |cell| {
                        if (containsIgnoreCase(cell, filter)) {
                            matches = true;
                            break;
                        }
                    }
                    if (!matches) continue;
                }
                try self.view_indices.append(i);
            }

            // Sort using bubble sort (simple, avoids comptime context issues)
            if (self.sort_column) |col| {
                const indices = self.view_indices.items;
                const rws = self.rows.items;
                const asc = self.sort_ascending;
                var sorted = false;
                while (!sorted) {
                    sorted = true;
                    for (0..indices.len -| 1) |i| {
                        const va = rws[indices[i]][col];
                        const vb = rws[indices[i + 1]][col];
                        const cmp = std.mem.order(u8, va, vb);
                        const should_swap = if (asc) cmp == .gt else cmp == .lt;
                        if (should_swap) {
                            const tmp = indices[i];
                            indices[i] = indices[i + 1];
                            indices[i + 1] = tmp;
                            sorted = false;
                        }
                    }
                }
            }

            if (self.cursor_row >= self.view_indices.items.len and self.view_indices.items.len > 0) {
                self.cursor_row = self.view_indices.items.len - 1;
            }
        }

        fn ensureVisible(self: *Self) void {
            if (self.cursor_row < self.y_offset) self.y_offset = self.cursor_row;
            if (self.cursor_row >= self.y_offset + self.visible_rows) {
                self.y_offset = self.cursor_row - self.visible_rows + 1;
            }
        }

        pub fn view(self: *const Self, allocator: std.mem.Allocator) []const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;

            // Compute column widths
            var widths: [num_cols]usize = undefined;
            for (0..num_cols) |c| {
                widths[c] = if (self.col_widths[c]) |w| w else blk: {
                    var max_w: usize = self.headers[c].len + 2; // room for sort indicator
                    for (self.rows.items) |row| {
                        max_w = @max(max_w, row[c].len);
                    }
                    break :blk max_w;
                };
            }

            // Header
            if (self.show_header) {
                for (0..num_cols) |c| {
                    if (c > 0) writer.writeAll(" \xe2\x94\x82 ") catch {};
                    const hdr = self.headers[c];
                    writer.writeAll(self.header_style.render(allocator, hdr) catch hdr) catch {};

                    // Sort indicator
                    if (self.sort_column == c) {
                        if (self.sort_ascending) {
                            writer.writeAll(self.sort_indicator_asc) catch {};
                        } else {
                            writer.writeAll(self.sort_indicator_desc) catch {};
                        }
                        const used = hdr.len + 2;
                        if (used < widths[c]) {
                            for (0..widths[c] - used) |_| writer.writeByte(' ') catch {};
                        }
                    } else {
                        if (hdr.len < widths[c]) {
                            for (0..widths[c] - hdr.len) |_| writer.writeByte(' ') catch {};
                        }
                    }
                }
                writer.writeByte('\n') catch {};

                // Separator
                for (0..num_cols) |c| {
                    if (c > 0) writer.writeAll("\xe2\x94\xbc\xe2\x94\x80\xe2\x94\x80") catch {};
                    for (0..widths[c]) |_| writer.writeAll("\xe2\x94\x80") catch {};
                }
                writer.writeByte('\n') catch {};
            }

            // Rows
            const end = @min(self.y_offset + self.visible_rows, self.view_indices.items.len);
            for (self.y_offset..end) |vi| {
                if (vi > self.y_offset) writer.writeByte('\n') catch {};
                const ri = self.view_indices.items[vi];
                const row = self.rows.items[ri];
                const is_cursor = (vi == self.cursor_row and self.focused);

                for (0..num_cols) |c| {
                    if (c > 0) writer.writeAll(" \xe2\x94\x82 ") catch {};
                    const cell = row[c];
                    const s = if (is_cursor) self.cursor_row_style else self.cell_style;
                    const padded = padTo(allocator, cell, widths[c], self.col_aligns[c]);
                    writer.writeAll(s.render(allocator, padded) catch padded) catch {};
                }
            }

            // Filter bar
            if (self.filter_active or self.filter_text.items.len > 0) {
                writer.writeAll("\n\nFilter: ") catch {};
                writer.writeAll(self.filter_text.items) catch {};
                if (self.filter_active) writer.writeByte('_') catch {};
            }

            // Count
            writer.writeByte('\n') catch {};
            const count = std.fmt.allocPrint(allocator, " {d}/{d} rows", .{ self.view_indices.items.len, self.rows.items.len }) catch "";
            var cs = style_mod.Style{};
            cs = cs.fg(.gray(10));
            cs = cs.inline_style(true);
            writer.writeAll(cs.render(allocator, count) catch count) catch {};

            return result.toArrayList().items;
        }

        fn padTo(allocator: std.mem.Allocator, text: []const u8, target: usize, alignment: Align) []const u8 {
            if (text.len >= target) return text;
            var buf = std.array_list.Managed(u8).init(allocator);
            const pad = target - text.len;
            switch (alignment) {
                .left => {
                    buf.appendSlice(text) catch {};
                    for (0..pad) |_| buf.append(' ') catch {};
                },
                .right => {
                    for (0..pad) |_| buf.append(' ') catch {};
                    buf.appendSlice(text) catch {};
                },
                .center => {
                    const left = pad / 2;
                    for (0..left) |_| buf.append(' ') catch {};
                    buf.appendSlice(text) catch {};
                    for (0..pad - left) |_| buf.append(' ') catch {};
                },
            }
            return buf.items;
        }

        fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
            if (needle.len > haystack.len) return false;
            outer: for (0..haystack.len - needle.len + 1) |i| {
                for (0..needle.len) |j| {
                    if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) continue :outer;
                }
                return true;
            }
            return false;
        }
    };
}
