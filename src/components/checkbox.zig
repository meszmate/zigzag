//! Checkbox and CheckboxGroup components.
//! Standalone boolean toggle and multi-select checkbox group.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

/// Standalone checkbox - a single boolean toggle.
pub const Checkbox = struct {
    label: []const u8,
    checked: bool,
    enabled: bool,
    focused: bool,

    // Symbols
    checked_symbol: []const u8,
    unchecked_symbol: []const u8,

    // Styling
    label_style: style_mod.Style,
    checked_style: style_mod.Style,
    unchecked_style: style_mod.Style,
    focused_style: style_mod.Style,
    disabled_style: style_mod.Style,

    pub fn init(label: []const u8) Checkbox {
        return .{
            .label = label,
            .checked = false,
            .enabled = true,
            .focused = true,
            .checked_symbol = "[x] ",
            .unchecked_symbol = "[ ] ",
            .label_style = blk: {
                var s = style_mod.Style{};
                s = s.inline_style(true);
                break :blk s;
            },
            .checked_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.bold(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .unchecked_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.gray(12));
                s = s.inline_style(true);
                break :blk s;
            },
            .focused_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.magenta);
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
        };
    }

    pub fn toggle(self: *Checkbox) void {
        if (!self.enabled) return;
        self.checked = !self.checked;
    }

    pub fn setChecked(self: *Checkbox, value: bool) void {
        self.checked = value;
    }

    pub fn isChecked(self: *const Checkbox) bool {
        return self.checked;
    }

    pub fn focus(self: *Checkbox) void {
        self.focused = true;
    }

    pub fn blur(self: *Checkbox) void {
        self.focused = false;
    }

    pub fn handleKey(self: *Checkbox, key: keys.KeyEvent) void {
        if (!self.focused or !self.enabled) return;

        switch (key.key) {
            .space, .enter => self.toggle(),
            else => {},
        }
    }

    pub fn view(self: *const Checkbox, allocator: std.mem.Allocator) ![]const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        const symbol = if (self.checked) self.checked_symbol else self.unchecked_symbol;
        const sym_style = if (!self.enabled)
            self.disabled_style
        else if (self.checked)
            self.checked_style
        else
            self.unchecked_style;

        const styled_symbol = try sym_style.render(allocator, symbol);
        try writer.writeAll(styled_symbol);

        const lbl_style = if (!self.enabled)
            self.disabled_style
        else if (self.focused)
            self.focused_style
        else
            self.label_style;

        const styled_label = try lbl_style.render(allocator, self.label);
        try writer.writeAll(styled_label);

        return result.toOwnedSlice();
    }
};

/// Multi-select checkbox group.
pub fn CheckboxGroup(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,

        // Items
        items: std.array_list.Managed(Item),

        // Navigation
        cursor: usize,
        height: u16,
        y_offset: usize,

        // Focus
        focused: bool,

        // Constraints
        min_selected: usize,
        max_selected: ?usize,

        // Symbols
        cursor_symbol: []const u8,
        checked_symbol: []const u8,
        unchecked_symbol: []const u8,

        // Styling
        item_style: style_mod.Style,
        checked_style: style_mod.Style,
        cursor_style: style_mod.Style,
        disabled_style: style_mod.Style,

        const Self = @This();

        pub const Item = struct {
            value: T,
            label: []const u8,
            description: []const u8,
            enabled: bool,
            checked: bool,

            pub fn init(value: T, label: []const u8) Item {
                return .{
                    .value = value,
                    .label = label,
                    .description = "",
                    .enabled = true,
                    .checked = false,
                };
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = std.array_list.Managed(Item).init(allocator),
                .cursor = 0,
                .height = 10,
                .y_offset = 0,
                .focused = true,
                .min_selected = 0,
                .max_selected = null,
                .cursor_symbol = "> ",
                .checked_symbol = "[x] ",
                .unchecked_symbol = "[ ] ",
                .item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.inline_style(true);
                    break :blk s;
                },
                .checked_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.cyan);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .cursor_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.magenta);
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
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn addItem(self: *Self, item: Item) !void {
            try self.items.append(item);
        }

        pub fn addItems(self: *Self, new_items: []const Item) !void {
            try self.items.appendSlice(new_items);
        }

        pub fn toggleCurrent(self: *Self) void {
            if (self.cursor >= self.items.items.len) return;
            const item = &self.items.items[self.cursor];
            if (!item.enabled) return;

            if (item.checked) {
                // Check min constraint
                if (self.checkedCount() <= self.min_selected) return;
                item.checked = false;
            } else {
                // Check max constraint
                if (self.max_selected) |max| {
                    if (self.checkedCount() >= max) return;
                }
                item.checked = true;
            }
        }

        pub fn selectAll(self: *Self) void {
            for (self.items.items) |*item| {
                if (item.enabled) item.checked = true;
            }
        }

        pub fn selectNone(self: *Self) void {
            for (self.items.items) |*item| {
                if (item.enabled) item.checked = false;
            }
        }

        pub fn invertSelection(self: *Self) void {
            for (self.items.items) |*item| {
                if (item.enabled) item.checked = !item.checked;
            }
        }

        pub fn checkedCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.items.items) |item| {
                if (item.checked) count += 1;
            }
            return count;
        }

        pub fn checkedValues(self: *const Self, allocator: std.mem.Allocator) ![]const T {
            var result = std.array_list.Managed(T).init(allocator);
            for (self.items.items) |item| {
                if (item.checked) try result.append(item.value);
            }
            return result.toOwnedSlice();
        }

        // Focus protocol
        pub fn focus(self: *Self) void {
            self.focused = true;
        }

        pub fn blur(self: *Self) void {
            self.focused = false;
        }

        pub fn handleKey(self: *Self, key: keys.KeyEvent) void {
            if (!self.focused) return;

            switch (key.key) {
                .up => self.cursorUp(),
                .down => self.cursorDown(),
                .page_up => self.pageUp(),
                .page_down => self.pageDown(),
                .home => self.gotoFirst(),
                .end => self.gotoLast(),
                .space => self.toggleCurrent(),
                .char => |c| switch (c) {
                    'j' => self.cursorDown(),
                    'k' => self.cursorUp(),
                    'g' => self.gotoFirst(),
                    'G' => self.gotoLast(),
                    'a' => self.selectAll(),
                    'n' => self.selectNone(),
                    'i' => self.invertSelection(),
                    else => {},
                },
                else => {},
            }
        }

        fn cursorUp(self: *Self) void {
            if (self.items.items.len == 0) return;
            if (self.cursor > 0) {
                self.cursor -= 1;
            } else {
                self.cursor = self.items.items.len - 1;
            }
            self.ensureVisible();
        }

        fn cursorDown(self: *Self) void {
            if (self.items.items.len == 0) return;
            if (self.cursor < self.items.items.len - 1) {
                self.cursor += 1;
            } else {
                self.cursor = 0;
            }
            self.ensureVisible();
        }

        fn pageUp(self: *Self) void {
            if (self.cursor >= self.height) {
                self.cursor -= self.height;
            } else {
                self.cursor = 0;
            }
            self.ensureVisible();
        }

        fn pageDown(self: *Self) void {
            if (self.cursor + self.height < self.items.items.len) {
                self.cursor += self.height;
            } else if (self.items.items.len > 0) {
                self.cursor = self.items.items.len - 1;
            }
            self.ensureVisible();
        }

        fn gotoFirst(self: *Self) void {
            self.cursor = 0;
            self.y_offset = 0;
        }

        fn gotoLast(self: *Self) void {
            if (self.items.items.len > 0) {
                self.cursor = self.items.items.len - 1;
                self.ensureVisible();
            }
        }

        fn ensureVisible(self: *Self) void {
            if (self.cursor < self.y_offset) {
                self.y_offset = self.cursor;
            } else if (self.cursor >= self.y_offset + self.height) {
                self.y_offset = self.cursor - self.height + 1;
            }
        }

        pub fn view(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;

            var rendered: usize = 0;
            while (rendered < self.height) : (rendered += 1) {
                if (rendered > 0) try writer.writeByte('\n');

                const idx = self.y_offset + rendered;
                if (idx >= self.items.items.len) break;

                const item = self.items.items[idx];

                // Cursor
                if (idx == self.cursor and self.focused) {
                    const styled = try self.cursor_style.render(allocator, self.cursor_symbol);
                    try writer.writeAll(styled);
                } else {
                    for (0..self.cursor_symbol.len) |_| {
                        try writer.writeByte(' ');
                    }
                }

                // Check symbol
                const check_sym = if (item.checked) self.checked_symbol else self.unchecked_symbol;
                const check_s = if (!item.enabled)
                    self.disabled_style
                else if (item.checked)
                    self.checked_style
                else
                    self.item_style;
                const styled_check = try check_s.render(allocator, check_sym);
                try writer.writeAll(styled_check);

                // Label
                const lbl_style = if (!item.enabled)
                    self.disabled_style
                else if (idx == self.cursor and self.focused)
                    self.cursor_style
                else if (item.checked)
                    self.checked_style
                else
                    self.item_style;
                const styled_label = try lbl_style.render(allocator, item.label);
                try writer.writeAll(styled_label);

                // Description
                if (item.description.len > 0) {
                    try writer.writeAll(" - ");
                    try writer.writeAll(item.description);
                }
            }

            return result.toOwnedSlice();
        }
    };
}
