//! RadioGroup component.
//! Single-select option group with radio button semantics.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub fn RadioGroup(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,

        // Items
        items: std.array_list.Managed(Item),

        // State
        selected: ?usize,
        cursor: usize,
        height: u16,
        y_offset: usize,

        // Focus
        focused: bool,

        // Symbols
        cursor_symbol: []const u8,
        selected_symbol: []const u8,
        unselected_symbol: []const u8,

        // Styling
        item_style: style_mod.Style,
        selected_style: style_mod.Style,
        cursor_style: style_mod.Style,
        disabled_style: style_mod.Style,

        const Self = @This();

        pub const Item = struct {
            value: T,
            label: []const u8,
            description: []const u8,
            enabled: bool,

            pub fn init(value: T, label: []const u8) Item {
                return .{
                    .value = value,
                    .label = label,
                    .description = "",
                    .enabled = true,
                };
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = std.array_list.Managed(Item).init(allocator),
                .selected = null,
                .cursor = 0,
                .height = 10,
                .y_offset = 0,
                .focused = true,
                .cursor_symbol = "> ",
                .selected_symbol = "(●) ",
                .unselected_symbol = "( ) ",
                .item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.inline_style(true);
                    break :blk s;
                },
                .selected_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.cyan);
                    s = s.bold(true);
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

        pub fn addOption(self: *Self, item: Item) !void {
            try self.items.append(item);
        }

        pub fn addOptions(self: *Self, new_items: []const Item) !void {
            try self.items.appendSlice(new_items);
        }

        pub fn selectCurrent(self: *Self) void {
            if (self.cursor >= self.items.items.len) return;
            if (!self.items.items[self.cursor].enabled) return;
            self.selected = self.cursor;
        }

        pub fn selectedItem(self: *const Self) ?*const Item {
            if (self.selected) |idx| {
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
                .space, .enter => self.selectCurrent(),
                .char => |c| switch (c) {
                    'j' => self.cursorDown(),
                    'k' => self.cursorUp(),
                    'g' => self.gotoFirst(),
                    'G' => self.gotoLast(),
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
                const is_selected = self.selected != null and self.selected.? == idx;

                // Cursor
                if (idx == self.cursor and self.focused) {
                    const styled = try self.cursor_style.render(allocator, self.cursor_symbol);
                    try writer.writeAll(styled);
                } else {
                    for (0..self.cursor_symbol.len) |_| {
                        try writer.writeByte(' ');
                    }
                }

                // Radio symbol
                const radio_sym = if (is_selected) self.selected_symbol else self.unselected_symbol;
                const radio_s = if (!item.enabled)
                    self.disabled_style
                else if (is_selected)
                    self.selected_style
                else
                    self.item_style;
                const styled_radio = try radio_s.render(allocator, radio_sym);
                try writer.writeAll(styled_radio);

                // Label
                const lbl_style = if (!item.enabled)
                    self.disabled_style
                else if (idx == self.cursor and self.focused)
                    self.cursor_style
                else if (is_selected)
                    self.selected_style
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
