//! Context menu component.
//! Popup menu triggered by keyboard shortcut or mouse, positioned at a target location.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");

pub fn ContextMenu(comptime Action: type) type {
    return struct {
        const max_items = 20;

        // Items
        items: [max_items]?MenuItem,
        item_count: usize,

        // State
        visible: bool,
        cursor: usize,
        selected_action: ?Action,

        // Position
        x: usize,
        y: usize,

        // Styling
        item_style: style_mod.Style,
        active_style: style_mod.Style,
        disabled_style: style_mod.Style,
        separator_style: style_mod.Style,
        shortcut_style: style_mod.Style,
        border_chars: border_mod.BorderChars,
        border_fg: Color,

        const Self = @This();

        pub const MenuItem = union(enum) {
            action: ActionItem,
            separator: void,
        };

        pub const ActionItem = struct {
            label: []const u8,
            shortcut_display: []const u8,
            action: Action,
            enabled: bool,
        };

        pub fn init() Self {
            return .{
                .items = [_]?MenuItem{null} ** max_items,
                .item_count = 0,
                .visible = false,
                .cursor = 0,
                .selected_action = null,
                .x = 0,
                .y = 0,
                .item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(18));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .active_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.white);
                    s = s.bg(.cyan);
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
                .separator_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(8));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .shortcut_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(12));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .border_chars = .rounded,
                .border_fg = .gray(14),
            };
        }

        /// Add an action item.
        pub fn addItem(self: *Self, label: []const u8, shortcut: []const u8, action: Action) void {
            if (self.item_count >= max_items) return;
            self.items[self.item_count] = .{ .action = .{
                .label = label,
                .shortcut_display = shortcut,
                .action = action,
                .enabled = true,
            } };
            self.item_count += 1;
        }

        /// Add a disabled item.
        pub fn addDisabledItem(self: *Self, label: []const u8, action: Action) void {
            if (self.item_count >= max_items) return;
            self.items[self.item_count] = .{ .action = .{
                .label = label,
                .shortcut_display = "",
                .action = action,
                .enabled = false,
            } };
            self.item_count += 1;
        }

        /// Add a separator.
        pub fn addSeparator(self: *Self) void {
            if (self.item_count >= max_items) return;
            self.items[self.item_count] = .{ .separator = {} };
            self.item_count += 1;
        }

        /// Show the menu at a position.
        pub fn show(self: *Self, pos_x: usize, pos_y: usize) void {
            self.visible = true;
            self.cursor = 0;
            self.selected_action = null;
            self.x = pos_x;
            self.y = pos_y;
            self.skipToNextEnabled();
        }

        /// Show clamped to terminal bounds.
        pub fn showClamped(self: *Self, pos_x: usize, pos_y: usize, term_width: usize, term_height: usize) void {
            const menu_width = self.calcWidth() + 4; // borders + padding
            const menu_height = self.item_count + 2; // borders

            const clamped_x = if (pos_x + menu_width > term_width)
                term_width -| menu_width
            else
                pos_x;

            const clamped_y = if (pos_y + menu_height > term_height)
                term_height -| menu_height
            else
                pos_y;

            self.show(clamped_x, clamped_y);
        }

        /// Hide the menu.
        pub fn hide(self: *Self) void {
            self.visible = false;
        }

        pub fn isVisible(self: *const Self) bool {
            return self.visible;
        }

        /// Get and consume the selected action.
        pub fn getSelectedAction(self: *Self) ?Action {
            const act = self.selected_action;
            self.selected_action = null;
            return act;
        }

        /// Handle key events. Returns true if consumed.
        pub fn handleKey(self: *Self, key: keys.KeyEvent) bool {
            if (!self.visible) return false;

            switch (key.key) {
                .up => {
                    self.moveCursorUp();
                    return true;
                },
                .down => {
                    self.moveCursorDown();
                    return true;
                },
                .enter => {
                    self.selectCurrent();
                    return true;
                },
                .escape => {
                    self.hide();
                    return true;
                },
                .char => |c| {
                    switch (c) {
                        'k' => {
                            self.moveCursorUp();
                            return true;
                        },
                        'j' => {
                            self.moveCursorDown();
                            return true;
                        },
                        else => return false,
                    }
                },
                else => return false,
            }
        }

        fn moveCursorUp(self: *Self) void {
            if (self.item_count == 0) return;
            var pos = self.cursor;
            var attempts: usize = 0;
            while (attempts < self.item_count) : (attempts += 1) {
                if (pos == 0) {
                    pos = self.item_count - 1;
                } else {
                    pos -= 1;
                }
                if (self.isSelectable(self.items[pos])) {
                    self.cursor = pos;
                    return;
                }
            }
        }

        fn moveCursorDown(self: *Self) void {
            if (self.item_count == 0) return;
            var pos = self.cursor;
            var attempts: usize = 0;
            while (attempts < self.item_count) : (attempts += 1) {
                pos = if (pos + 1 < self.item_count) pos + 1 else 0;
                if (self.isSelectable(self.items[pos])) {
                    self.cursor = pos;
                    return;
                }
            }
        }

        fn skipToNextEnabled(self: *Self) void {
            if (self.item_count == 0) return;
            if (self.isSelectable(self.items[self.cursor])) return;
            self.moveCursorDown();
        }

        fn isSelectable(_: *const Self, maybe_item: ?MenuItem) bool {
            const item = maybe_item orelse return false;
            return switch (item) {
                .action => |a| a.enabled,
                .separator => false,
            };
        }

        fn selectCurrent(self: *Self) void {
            if (self.cursor >= self.item_count) return;
            const item = self.items[self.cursor] orelse return;
            switch (item) {
                .action => |a| {
                    if (a.enabled) {
                        self.selected_action = a.action;
                        self.hide();
                    }
                },
                .separator => {},
            }
        }

        fn calcWidth(self: *const Self) usize {
            var max_label: usize = 0;
            var max_shortcut: usize = 0;
            for (self.items[0..self.item_count]) |maybe_item| {
                const item = maybe_item orelse continue;
                switch (item) {
                    .action => |a| {
                        const lw = measure.width(a.label);
                        if (lw > max_label) max_label = lw;
                        const sw = measure.width(a.shortcut_display);
                        if (sw > max_shortcut) max_shortcut = sw;
                    },
                    .separator => {},
                }
            }
            return max_label + max_shortcut + 4;
        }

        /// Render the context menu.
        pub fn view(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            if (!self.visible) return try allocator.dupe(u8, "");

            var result: Writer.Allocating = .init(allocator);
            const w = &result.writer;

            const inner_width = self.calcWidth();

            // Indent to x position
            // Top border
            try self.writeIndent(w, self.x);
            try self.writeBorder(w, allocator, inner_width, .top);
            try w.writeByte('\n');

            // Items
            for (self.items[0..self.item_count], 0..) |maybe_item, i| {
                const item = maybe_item orelse continue;

                try self.writeIndent(w, self.x);

                switch (item) {
                    .separator => {
                        try self.writeBorder(w, allocator, inner_width, .middle);
                    },
                    .action => |a| {
                        try self.writeBorderChar(w, allocator, .left);

                        const is_active = (i == self.cursor);
                        const s = if (!a.enabled) self.disabled_style else if (is_active) self.active_style else self.item_style;

                        var line: Writer.Allocating = .init(allocator);
                        const lw = &line.writer;
                        try lw.writeByte(' ');
                        try lw.writeAll(a.label);

                        const label_w = measure.width(a.label);
                        const shortcut_w = measure.width(a.shortcut_display);
                        const gap = inner_width -| label_w -| shortcut_w -| 2;
                        for (0..gap) |_| try lw.writeByte(' ');

                        if (a.shortcut_display.len > 0) {
                            try lw.writeAll(a.shortcut_display);
                        }
                        try lw.writeByte(' ');

                        const line_text = try line.toOwnedSlice();
                        const styled = try s.render(allocator, line_text);
                        try w.writeAll(styled);

                        try self.writeBorderChar(w, allocator, .right);
                    },
                }
                try w.writeByte('\n');
            }

            // Bottom border
            try self.writeIndent(w, self.x);
            try self.writeBorder(w, allocator, inner_width, .bottom);

            return result.toOwnedSlice();
        }

        const BorderPos = enum { top, middle, bottom };
        const BorderSide = enum { left, right };

        fn writeIndent(_: *const Self, writer: *Writer, count: usize) !void {
            for (0..count) |_| try writer.writeByte(' ');
        }

        fn writeBorder(self: *const Self, writer: *Writer, allocator: std.mem.Allocator, width: usize, pos: BorderPos) !void {
            var bs = style_mod.Style{};
            bs = bs.fg(self.border_fg);
            bs = bs.inline_style(true);

            const bc = self.border_chars;
            const cl = switch (pos) {
                .top => bc.top_left,
                .middle => if (bc.middle_left.len > 0) bc.middle_left else bc.vertical,
                .bottom => bc.bottom_left,
            };
            const cr = switch (pos) {
                .top => bc.top_right,
                .middle => if (bc.middle_right.len > 0) bc.middle_right else bc.vertical,
                .bottom => bc.bottom_right,
            };

            try writer.writeAll(try bs.render(allocator, cl));
            for (0..width) |_| {
                try writer.writeAll(try bs.render(allocator, bc.horizontal));
            }
            try writer.writeAll(try bs.render(allocator, cr));
        }

        fn writeBorderChar(self: *const Self, writer: *Writer, allocator: std.mem.Allocator, side: BorderSide) !void {
            var bs = style_mod.Style{};
            bs = bs.fg(self.border_fg);
            bs = bs.inline_style(true);
            const char = switch (side) {
                .left, .right => self.border_chars.vertical,
            };
            try writer.writeAll(try bs.render(allocator, char));
        }
    };
}
