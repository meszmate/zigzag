//! Dropdown/Select component.
//! Collapsible list for selecting one or more options.

const std = @import("std");
const keys = @import("../input/keys.zig");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");
const fuzzy = @import("../core/fuzzy.zig");

pub fn Dropdown(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,

        // Items
        items: std.array_list.Managed(Item),
        filtered_indices: std.array_list.Managed(usize),

        // State
        expanded: bool,
        cursor: usize,
        selected_index: ?usize,
        selected_indices: std.AutoHashMap(usize, void),

        // Filtering
        filter_text: std.array_list.Managed(u8),
        filter_active: bool,

        // Scrolling
        y_offset: usize,
        max_visible: u16,

        // Focus
        focused: bool,

        // Behavior
        multi_select: bool,
        close_on_select: bool,
        wrap_around: bool,

        // Labels
        label: []const u8,
        placeholder: []const u8,

        // Symbols
        expand_symbol: []const u8,
        cursor_symbol: []const u8,
        checked_symbol: []const u8,
        unchecked_symbol: []const u8,
        scroll_up_symbol: []const u8,
        scroll_down_symbol: []const u8,

        // Styling
        label_style: style_mod.Style,
        trigger_style: style_mod.Style,
        trigger_focused_style: style_mod.Style,
        item_style: style_mod.Style,
        cursor_item_style: style_mod.Style,
        selected_item_style: style_mod.Style,
        disabled_style: style_mod.Style,
        filter_style: style_mod.Style,
        border_chars: border_mod.BorderChars,
        border_fg: Color,

        const Self = @This();

        pub const Item = struct {
            value: T,
            label: []const u8,
            description: []const u8,
            enabled: bool,

            pub fn init(value: T, label_text: []const u8) Item {
                return .{
                    .value = value,
                    .label = label_text,
                    .description = "",
                    .enabled = true,
                };
            }

            pub fn withDescription(value: T, label_text: []const u8, desc: []const u8) Item {
                return .{
                    .value = value,
                    .label = label_text,
                    .description = desc,
                    .enabled = true,
                };
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = std.array_list.Managed(Item).init(allocator),
                .filtered_indices = std.array_list.Managed(usize).init(allocator),
                .expanded = false,
                .cursor = 0,
                .selected_index = null,
                .selected_indices = std.AutoHashMap(usize, void).init(allocator),
                .filter_text = std.array_list.Managed(u8).init(allocator),
                .filter_active = false,
                .y_offset = 0,
                .max_visible = 6,
                .focused = true,
                .multi_select = false,
                .close_on_select = true,
                .wrap_around = false,
                .label = "",
                .placeholder = "Select...",
                .expand_symbol = "▼",
                .cursor_symbol = "> ",
                .checked_symbol = "[x] ",
                .unchecked_symbol = "[ ] ",
                .scroll_up_symbol = "▲",
                .scroll_down_symbol = "▼",
                .label_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .trigger_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.white);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .trigger_focused_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.cyan);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.inline_style(true);
                    break :blk s;
                },
                .cursor_item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.cyan);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .selected_item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.green);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .disabled_style = blk: {
                    var s = style_mod.Style{};
                    s = s.dim(true);
                    s = s.fg(.gray(10));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .filter_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.yellow);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .border_chars = .rounded,
                .border_fg = .gray(14),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
            self.filtered_indices.deinit();
            self.selected_indices.deinit();
            self.filter_text.deinit();
        }

        // ── Item management ─────────────────────────────

        pub fn addItem(self: *Self, item: Item) !void {
            try self.items.append(item);
            try self.rebuildFilter();
        }

        pub fn addItems(self: *Self, new_items: []const Item) !void {
            try self.items.appendSlice(new_items);
            try self.rebuildFilter();
        }

        pub fn setItems(self: *Self, new_items: []const Item) !void {
            self.items.clearRetainingCapacity();
            try self.items.appendSlice(new_items);
            self.cursor = 0;
            self.y_offset = 0;
            self.selected_index = null;
            self.selected_indices.clearRetainingCapacity();
            try self.rebuildFilter();
        }

        // ── State ───────────────────────────────────────

        pub fn open(self: *Self) void {
            self.expanded = true;
            self.filter_active = false;
            self.filter_text.clearRetainingCapacity();
            self.rebuildFilter() catch {};
            // Position cursor at selected item if any
            if (self.selected_index) |sel| {
                for (self.filtered_indices.items, 0..) |idx, i| {
                    if (idx == sel) {
                        self.cursor = i;
                        self.ensureVisible();
                        break;
                    }
                }
            }
        }

        pub fn close(self: *Self) void {
            self.expanded = false;
            self.filter_active = false;
            self.filter_text.clearRetainingCapacity();
        }

        pub fn toggle(self: *Self) void {
            if (self.expanded) self.close() else self.open();
        }

        pub fn isExpanded(self: *const Self) bool {
            return self.expanded;
        }

        // ── Selection ───────────────────────────────────

        pub fn selectedItem(self: *const Self) ?*const Item {
            if (self.selected_index) |idx| {
                if (idx < self.items.items.len) {
                    return &self.items.items[idx];
                }
            }
            return null;
        }

        pub fn selectedValue(self: *const Self) ?T {
            if (self.selectedItem()) |item| {
                return item.value;
            }
            return null;
        }

        pub fn selectedItems(self: *const Self, allocator: std.mem.Allocator) ![]const *const Item {
            var result = std.array_list.Managed(*const Item).init(allocator);
            var iter = self.selected_indices.keyIterator();
            while (iter.next()) |idx| {
                if (idx.* < self.items.items.len) {
                    try result.append(&self.items.items[idx.*]);
                }
            }
            return result.toOwnedSlice();
        }

        fn selectAtCursor(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (self.cursor >= visible.len) return;
            const idx = visible[self.cursor];
            if (!self.items.items[idx].enabled) return;

            if (self.multi_select) {
                if (self.selected_indices.contains(idx)) {
                    _ = self.selected_indices.remove(idx);
                } else {
                    self.selected_indices.put(idx, {}) catch {};
                }
            } else {
                self.selected_index = idx;
                if (self.close_on_select) {
                    self.close();
                }
            }
        }

        // ── Focus protocol ──────────────────────────────

        pub fn focus(self: *Self) void {
            self.focused = true;
        }

        pub fn blur(self: *Self) void {
            self.focused = false;
        }

        // ── Input handling ──────────────────────────────

        pub fn handleKey(self: *Self, key: keys.KeyEvent) void {
            if (!self.focused) return;

            // When filter is active, capture typed characters
            if (self.expanded and self.filter_active and key.key == .char and !key.modifiers.ctrl) {
                const c = key.key.char;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &buf) catch return;
                self.filter_text.appendSlice(buf[0..len]) catch {};
                self.rebuildFilter() catch {};
                return;
            }

            if (self.expanded and self.filter_active and key.key == .backspace) {
                if (self.filter_text.items.len > 0) {
                    _ = self.filter_text.pop();
                    self.rebuildFilter() catch {};
                }
                return;
            }

            if (!self.expanded) {
                // Collapsed state
                switch (key.key) {
                    .enter, .space => self.open(),
                    .down => self.open(),
                    else => {},
                }
                return;
            }

            // Expanded state
            switch (key.key) {
                .up => self.cursorUp(),
                .down => self.cursorDown(),
                .page_up => self.pageUp(),
                .page_down => self.pageDown(),
                .home => self.gotoFirst(),
                .end => self.gotoLast(),
                .enter => self.selectAtCursor(),
                .space => if (self.multi_select) self.selectAtCursor(),
                .escape => {
                    if (self.filter_active) {
                        self.filter_active = false;
                        self.filter_text.clearRetainingCapacity();
                        self.rebuildFilter() catch {};
                    } else {
                        self.close();
                    }
                },
                .char => |c| switch (c) {
                    'j' => self.cursorDown(),
                    'k' => self.cursorUp(),
                    'g' => self.gotoFirst(),
                    'G' => self.gotoLast(),
                    '/' => {
                        self.filter_active = true;
                        self.filter_text.clearRetainingCapacity();
                    },
                    'q' => self.close(),
                    else => {},
                },
                else => {},
            }
        }

        // ── Navigation ──────────────────────────────────

        fn cursorUp(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (visible.len == 0) return;
            if (self.cursor > 0) {
                self.cursor -= 1;
            } else if (self.wrap_around) {
                self.cursor = visible.len - 1;
            }
            self.skipDisabledUp();
            self.ensureVisible();
        }

        fn cursorDown(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (visible.len == 0) return;
            if (self.cursor < visible.len - 1) {
                self.cursor += 1;
            } else if (self.wrap_around) {
                self.cursor = 0;
            }
            self.skipDisabledDown();
            self.ensureVisible();
        }

        fn pageUp(self: *Self) void {
            if (self.cursor >= self.max_visible) {
                self.cursor -= self.max_visible;
            } else {
                self.cursor = 0;
            }
            self.ensureVisible();
        }

        fn pageDown(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (self.cursor + self.max_visible < visible.len) {
                self.cursor += self.max_visible;
            } else if (visible.len > 0) {
                self.cursor = visible.len - 1;
            }
            self.ensureVisible();
        }

        fn gotoFirst(self: *Self) void {
            self.cursor = 0;
            self.y_offset = 0;
        }

        fn gotoLast(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (visible.len > 0) {
                self.cursor = visible.len - 1;
                self.ensureVisible();
            }
        }

        fn skipDisabledDown(self: *Self) void {
            const visible = self.filtered_indices.items;
            const start = self.cursor;
            while (self.cursor < visible.len) {
                if (self.items.items[visible[self.cursor]].enabled) return;
                self.cursor += 1;
            }
            self.cursor = start; // no enabled item found, revert
        }

        fn skipDisabledUp(self: *Self) void {
            const visible = self.filtered_indices.items;
            if (visible.len == 0) return;
            const start = self.cursor;
            while (true) {
                if (self.items.items[visible[self.cursor]].enabled) return;
                if (self.cursor == 0) break;
                self.cursor -= 1;
            }
            self.cursor = start; // revert
        }

        fn ensureVisible(self: *Self) void {
            if (self.cursor < self.y_offset) {
                self.y_offset = self.cursor;
            } else if (self.cursor >= self.y_offset + self.max_visible) {
                self.y_offset = self.cursor - self.max_visible + 1;
            }
        }

        // ── Filtering ──────────────────────────────────

        fn rebuildFilter(self: *Self) !void {
            self.filtered_indices.clearRetainingCapacity();

            if (self.filter_text.items.len == 0) {
                for (0..self.items.items.len) |i| {
                    try self.filtered_indices.append(i);
                }
            } else {
                var scored = std.array_list.Managed(fuzzy.Ranked).init(self.allocator);
                defer scored.deinit();

                for (self.items.items, 0..) |item, i| {
                    const s = fuzzy.scoreIgnoreCase(item.label, self.filter_text.items);
                    if (s > 0) try scored.append(.{ .index = i, .score = s });
                }

                std.mem.sort(fuzzy.Ranked, scored.items, {}, struct {
                    pub fn lessThan(_: void, a: fuzzy.Ranked, b: fuzzy.Ranked) bool {
                        return a.score > b.score;
                    }
                }.lessThan);

                for (scored.items) |s| {
                    try self.filtered_indices.append(s.index);
                }
            }

            if (self.cursor >= self.filtered_indices.items.len and self.filtered_indices.items.len > 0) {
                self.cursor = self.filtered_indices.items.len - 1;
            }
            self.ensureVisible();
        }

        // ── Rendering ───────────────────────────────────

        pub fn view(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;

            // Label
            if (self.label.len > 0) {
                const styled_label = try self.label_style.render(allocator, self.label);
                try writer.writeAll(styled_label);
                try writer.writeAll(" ");
            }

            // Trigger line
            const display_text = if (self.selectedItem()) |item|
                item.label
            else if (self.multi_select and self.selectedCount() > 0)
                try std.fmt.allocPrint(allocator, "{d} selected", .{self.selectedCount()})
            else
                self.placeholder;

            const trig_style = if (self.focused) self.trigger_focused_style else self.trigger_style;
            const styled_trigger = try trig_style.render(allocator, display_text);
            try writer.writeAll(styled_trigger);
            try writer.writeAll(" ");

            const expand_str = if (self.expanded) "▲" else self.expand_symbol;
            try writer.writeAll(expand_str);

            if (!self.expanded) {
                return result.toOwnedSlice();
            }

            // Expanded dropdown
            try writer.writeByte('\n');

            // Compute dropdown width
            var max_item_width: usize = 0;
            for (self.items.items) |item| {
                const w = measure.width(item.label) + self.cursor_symbol.len;
                const extra: usize = if (self.multi_select) self.checked_symbol.len else 0;
                if (w + extra > max_item_width) max_item_width = w + extra;
            }
            max_item_width = @max(max_item_width, 10);
            const inner_width = max_item_width + 2; // padding

            // Top border
            try self.writeBorderLine(writer, allocator, inner_width, .top);
            try writer.writeByte('\n');

            // Filter line
            if (self.filter_active) {
                try self.writeBorderSide(writer, allocator, .left);
                const filter_line = try std.fmt.allocPrint(allocator, " / {s}_", .{self.filter_text.items});
                const styled = try self.filter_style.render(allocator, filter_line);
                try writer.writeAll(styled);
                const used = measure.width(filter_line);
                if (used < inner_width) {
                    try self.writePadding(writer, inner_width - used);
                }
                try self.writeBorderSide(writer, allocator, .right);
                try writer.writeByte('\n');

                // Separator
                try self.writeBorderLine(writer, allocator, inner_width, .middle);
                try writer.writeByte('\n');
            }

            // Scroll indicator (top)
            const visible = self.filtered_indices.items;
            const has_above = self.y_offset > 0;
            const end_idx = @min(self.y_offset + self.max_visible, visible.len);
            const has_below = end_idx < visible.len;

            if (has_above) {
                try self.writeBorderSide(writer, allocator, .left);
                const up_str = try std.fmt.allocPrint(allocator, " {s}", .{self.scroll_up_symbol});
                try writer.writeAll(up_str);
                const used = measure.width(up_str);
                if (used < inner_width) {
                    try self.writePadding(writer, inner_width - used);
                }
                try self.writeBorderSide(writer, allocator, .right);
                try writer.writeByte('\n');
            }

            // Items
            var rendered: usize = 0;
            while (rendered < self.max_visible) : (rendered += 1) {
                const idx = self.y_offset + rendered;
                if (idx >= visible.len) break;

                if (rendered > 0 or has_above) {
                    // already have newline from previous
                }

                try self.writeBorderSide(writer, allocator, .left);

                const item_idx = visible[idx];
                const item = self.items.items[item_idx];
                var line: Writer.Allocating = .init(allocator);
                const line_writer = &line.writer;

                try line_writer.writeByte(' ');

                // Cursor symbol
                if (idx == self.cursor) {
                    try line_writer.writeAll(self.cursor_symbol);
                } else {
                    for (0..self.cursor_symbol.len) |_| {
                        try line_writer.writeByte(' ');
                    }
                }

                // Multi-select check
                if (self.multi_select) {
                    if (self.selected_indices.contains(item_idx)) {
                        try line_writer.writeAll(self.checked_symbol);
                    } else {
                        try line_writer.writeAll(self.unchecked_symbol);
                    }
                }

                // Label
                try line_writer.writeAll(item.label);

                const line_text = try line.toOwnedSlice();
                const item_s = if (!item.enabled)
                    self.disabled_style
                else if (idx == self.cursor)
                    self.cursor_item_style
                else if (self.isItemSelected(item_idx))
                    self.selected_item_style
                else
                    self.item_style;

                const styled_line = try item_s.render(allocator, line_text);
                try writer.writeAll(styled_line);

                // Pad to width
                const used = measure.width(line_text);
                if (used < inner_width) {
                    try self.writePadding(writer, inner_width - used);
                }

                try self.writeBorderSide(writer, allocator, .right);
                if (rendered + 1 < self.max_visible and idx + 1 < visible.len) {
                    try writer.writeByte('\n');
                }
            }

            // Scroll indicator (bottom)
            if (has_below) {
                try writer.writeByte('\n');
                try self.writeBorderSide(writer, allocator, .left);
                const down_str = try std.fmt.allocPrint(allocator, " {s}", .{self.scroll_down_symbol});
                try writer.writeAll(down_str);
                const used = measure.width(down_str);
                if (used < inner_width) {
                    try self.writePadding(writer, inner_width - used);
                }
                try self.writeBorderSide(writer, allocator, .right);
            }

            // Bottom border
            try writer.writeByte('\n');
            try self.writeBorderLine(writer, allocator, inner_width, .bottom);

            return result.toOwnedSlice();
        }

        fn isItemSelected(self: *const Self, idx: usize) bool {
            if (self.multi_select) {
                return self.selected_indices.contains(idx);
            }
            return self.selected_index != null and self.selected_index.? == idx;
        }

        fn selectedCount(self: *const Self) usize {
            return self.selected_indices.count();
        }

        const BorderPos = enum { top, middle, bottom };
        const BorderSide = enum { left, right };

        fn writeBorderLine(self: *const Self, writer: *Writer, allocator: std.mem.Allocator, width: usize, pos: BorderPos) !void {
            const bc = self.border_chars;
            var border_style = style_mod.Style{};
            border_style = border_style.fg(self.border_fg);
            border_style = border_style.inline_style(true);

            const corner_l = switch (pos) {
                .top => bc.top_left,
                .middle => if (bc.middle_left.len > 0) bc.middle_left else bc.vertical,
                .bottom => bc.bottom_left,
            };
            const corner_r = switch (pos) {
                .top => bc.top_right,
                .middle => if (bc.middle_right.len > 0) bc.middle_right else bc.vertical,
                .bottom => bc.bottom_right,
            };

            const styled_l = try border_style.render(allocator, corner_l);
            try writer.writeAll(styled_l);

            for (0..width) |_| {
                const styled = try border_style.render(allocator, bc.horizontal);
                try writer.writeAll(styled);
            }

            const styled_r = try border_style.render(allocator, corner_r);
            try writer.writeAll(styled_r);
        }

        fn writeBorderSide(self: *const Self, writer: *Writer, allocator: std.mem.Allocator, side: BorderSide) !void {
            var border_style = style_mod.Style{};
            border_style = border_style.fg(self.border_fg);
            border_style = border_style.inline_style(true);

            const char = switch (side) {
                .left => self.border_chars.vertical,
                .right => self.border_chars.vertical,
            };
            const styled = try border_style.render(allocator, char);
            try writer.writeAll(styled);
        }

        fn writePadding(_: *const Self, writer: *Writer, count: usize) !void {
            for (0..count) |_| {
                try writer.writeByte(' ');
            }
        }
    };
}
