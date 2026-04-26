//! Menu bar component.
//! Horizontal menu bar with dropdown menus and keyboard navigation.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");

pub fn MenuBar(comptime Action: type) type {
    return struct {
        const max_menus = 10;
        const max_items = 20;

        // Menus
        menus: [max_menus]?Menu,
        menu_count: usize,

        // State
        state: State,
        active_menu: usize,
        active_item: usize,

        // Result
        selected_action: ?Action,

        // Styling
        bar_style: style_mod.Style,
        bar_item_style: style_mod.Style,
        bar_active_style: style_mod.Style,
        item_style: style_mod.Style,
        item_active_style: style_mod.Style,
        item_disabled_style: style_mod.Style,
        separator_style: style_mod.Style,
        shortcut_style: style_mod.Style,
        border_chars: border_mod.BorderChars,
        border_fg: Color,

        // Layout
        gap: usize,

        const Self = @This();

        pub const State = enum {
            closed,
            bar_focused,
            dropdown_open,
        };

        pub const MenuItem = union(enum) {
            action: ActionItem,
            separator: void,
        };

        pub const ActionItem = struct {
            label: []const u8,
            shortcut_display: []const u8,
            action: Action,
            enabled: bool,
            checked: ?bool,
        };

        pub const Menu = struct {
            label: []const u8,
            accelerator: ?u8,
            items: [max_items]?MenuItem,
            item_count: usize,
        };

        pub fn init() Self {
            return .{
                .menus = [_]?Menu{null} ** max_menus,
                .menu_count = 0,
                .state = .closed,
                .active_menu = 0,
                .active_item = 0,
                .selected_action = null,
                .bar_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bg(.fromRgb(40, 40, 50));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .bar_item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(18));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .bar_active_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.white);
                    s = s.bg(.fromRgb(60, 60, 80));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .item_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(18));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .item_active_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.white);
                    s = s.bg(.cyan);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .item_disabled_style = blk: {
                    var s = style_mod.Style{};
                    s = s.dim(true);
                    s = s.fg(.gray(10));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .separator_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(10));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .shortcut_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.gray(12));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .border_chars = .normal,
                .border_fg = .gray(14),
                .gap = 2,
            };
        }

        /// Add a menu to the bar.
        pub fn addMenu(self: *Self, label: []const u8, accelerator: ?u8, items: []const MenuItem) void {
            if (self.menu_count >= max_menus) return;

            var menu = Menu{
                .label = label,
                .accelerator = accelerator,
                .items = [_]?MenuItem{null} ** max_items,
                .item_count = 0,
            };

            for (items) |item| {
                if (menu.item_count >= max_items) break;
                menu.items[menu.item_count] = item;
                menu.item_count += 1;
            }

            self.menus[self.menu_count] = menu;
            self.menu_count += 1;
        }

        /// Create an action menu item.
        pub fn action(label: []const u8, shortcut: []const u8, act: Action) MenuItem {
            return .{ .action = .{
                .label = label,
                .shortcut_display = shortcut,
                .action = act,
                .enabled = true,
                .checked = null,
            } };
        }

        /// Create a disabled action menu item.
        pub fn disabledAction(label: []const u8, shortcut: []const u8, act: Action) MenuItem {
            return .{ .action = .{
                .label = label,
                .shortcut_display = shortcut,
                .action = act,
                .enabled = false,
                .checked = null,
            } };
        }

        /// Create a checked action menu item.
        pub fn checkedAction(label: []const u8, act: Action, is_checked: bool) MenuItem {
            return .{ .action = .{
                .label = label,
                .shortcut_display = "",
                .action = act,
                .enabled = true,
                .checked = is_checked,
            } };
        }

        /// Create a separator.
        pub fn separator() MenuItem {
            return .{ .separator = {} };
        }

        // ── State management ─────────────────────────

        pub fn isOpen(self: *const Self) bool {
            return self.state != .closed;
        }

        pub fn activate(self: *Self) void {
            self.state = .bar_focused;
            self.selected_action = null;
        }

        pub fn deactivate(self: *Self) void {
            self.state = .closed;
        }

        pub fn getSelectedAction(self: *Self) ?Action {
            const act = self.selected_action;
            self.selected_action = null;
            return act;
        }

        // ── Input handling ───────────────────────────

        pub fn handleKey(self: *Self, key: keys.KeyEvent) bool {
            // Check for Alt+letter accelerators
            if (key.modifiers.alt and key.key == .char) {
                const c = key.key.char;
                for (self.menus[0..self.menu_count], 0..) |maybe_menu, i| {
                    if (maybe_menu) |menu| {
                        if (menu.accelerator) |acc| {
                            if (toLowerChar(c) == toLowerChar(acc)) {
                                self.active_menu = i;
                                self.active_item = 0;
                                self.state = .dropdown_open;
                                self.skipToNextEnabled();
                                return true;
                            }
                        }
                    }
                }
            }

            switch (self.state) {
                .closed => return false,
                .bar_focused => return self.handleBarKey(key),
                .dropdown_open => return self.handleDropdownKey(key),
            }
        }

        fn handleBarKey(self: *Self, key: keys.KeyEvent) bool {
            switch (key.key) {
                .left => {
                    if (self.active_menu > 0) {
                        self.active_menu -= 1;
                    } else if (self.menu_count > 0) {
                        self.active_menu = self.menu_count - 1;
                    }
                    return true;
                },
                .right => {
                    if (self.active_menu + 1 < self.menu_count) {
                        self.active_menu += 1;
                    } else {
                        self.active_menu = 0;
                    }
                    return true;
                },
                .down, .enter => {
                    self.state = .dropdown_open;
                    self.active_item = 0;
                    self.skipToNextEnabled();
                    return true;
                },
                .escape => {
                    self.state = .closed;
                    return true;
                },
                else => return false,
            }
        }

        fn handleDropdownKey(self: *Self, key: keys.KeyEvent) bool {
            switch (key.key) {
                .up => {
                    self.moveCursorUp();
                    return true;
                },
                .down => {
                    self.moveCursorDown();
                    return true;
                },
                .left => {
                    if (self.active_menu > 0) {
                        self.active_menu -= 1;
                    } else if (self.menu_count > 0) {
                        self.active_menu = self.menu_count - 1;
                    }
                    self.active_item = 0;
                    self.skipToNextEnabled();
                    return true;
                },
                .right => {
                    if (self.active_menu + 1 < self.menu_count) {
                        self.active_menu += 1;
                    } else {
                        self.active_menu = 0;
                    }
                    self.active_item = 0;
                    self.skipToNextEnabled();
                    return true;
                },
                .enter => {
                    self.selectCurrentItem();
                    return true;
                },
                .escape => {
                    self.state = .bar_focused;
                    return true;
                },
                else => return false,
            }
        }

        fn moveCursorUp(self: *Self) void {
            const menu = self.menus[self.active_menu] orelse return;
            if (menu.item_count == 0) return;

            var pos = self.active_item;
            var attempts: usize = 0;
            while (attempts < menu.item_count) : (attempts += 1) {
                if (pos == 0) {
                    pos = menu.item_count - 1;
                } else {
                    pos -= 1;
                }
                if (self.isSelectableItem(menu.items[pos])) {
                    self.active_item = pos;
                    return;
                }
            }
        }

        fn moveCursorDown(self: *Self) void {
            const menu = self.menus[self.active_menu] orelse return;
            if (menu.item_count == 0) return;

            var pos = self.active_item;
            var attempts: usize = 0;
            while (attempts < menu.item_count) : (attempts += 1) {
                pos = if (pos + 1 < menu.item_count) pos + 1 else 0;
                if (self.isSelectableItem(menu.items[pos])) {
                    self.active_item = pos;
                    return;
                }
            }
        }

        fn skipToNextEnabled(self: *Self) void {
            const menu = self.menus[self.active_menu] orelse return;
            if (menu.item_count == 0) return;

            if (self.isSelectableItem(menu.items[self.active_item])) return;
            self.moveCursorDown();
        }

        fn isSelectableItem(_: *const Self, maybe_item: ?MenuItem) bool {
            const item = maybe_item orelse return false;
            return switch (item) {
                .action => |a| a.enabled,
                .separator => false,
            };
        }

        fn selectCurrentItem(self: *Self) void {
            const menu = self.menus[self.active_menu] orelse return;
            if (self.active_item >= menu.item_count) return;

            const item = menu.items[self.active_item] orelse return;
            switch (item) {
                .action => |a| {
                    if (a.enabled) {
                        self.selected_action = a.action;
                        self.state = .closed;
                    }
                },
                .separator => {},
            }
        }

        fn toLowerChar(c: u21) u21 {
            return if (c >= 'A' and c <= 'Z') c + 32 else c;
        }

        // ── Rendering ───────────────────────────────

        pub fn view(self: *const Self, allocator: std.mem.Allocator, term_width: usize) ![]const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;

            // Render menu bar
            var bar_content: Writer.Allocating = .init(allocator);
            const bar_writer = &bar_content.writer;

            try bar_writer.writeAll(" ");

            for (self.menus[0..self.menu_count], 0..) |maybe_menu, i| {
                const menu = maybe_menu orelse continue;

                if (i > 0) {
                    for (0..self.gap) |_| try bar_writer.writeByte(' ');
                }

                const is_active = (self.state != .closed and self.active_menu == i);
                const menu_style = if (is_active) self.bar_active_style else self.bar_item_style;
                const padded = try std.fmt.allocPrint(allocator, " {s} ", .{menu.label});
                const styled = try menu_style.render(allocator, padded);
                try bar_writer.writeAll(styled);
            }

            // Pad bar to terminal width
            const bar_text = try bar_content.toOwnedSlice();
            const bar_width = measure.width(bar_text);
            try writer.writeAll(bar_text);
            if (bar_width < term_width) {
                const pad_text = try allocator.alloc(u8, term_width - bar_width);
                @memset(pad_text, ' ');
                const styled_pad = try self.bar_style.render(allocator, pad_text);
                try writer.writeAll(styled_pad);
            }

            // Render dropdown if open
            if (self.state == .dropdown_open) {
                if (self.menus[self.active_menu]) |menu| {
                    const dropdown = try self.renderDropdown(allocator, menu);
                    try writer.writeByte('\n');
                    try writer.writeAll(dropdown);
                }
            }

            return result.toOwnedSlice();
        }

        fn renderDropdown(self: *const Self, allocator: std.mem.Allocator, menu: Menu) ![]const u8 {
            var result: Writer.Allocating = .init(allocator);
            const w = &result.writer;

            // Calculate width
            var max_label_width: usize = 0;
            var max_shortcut_width: usize = 0;
            for (menu.items[0..menu.item_count]) |maybe_item| {
                const item = maybe_item orelse continue;
                switch (item) {
                    .action => |a| {
                        const lw = measure.width(a.label) + if (a.checked != null) @as(usize, 2) else 0;
                        if (lw > max_label_width) max_label_width = lw;
                        const sw = measure.width(a.shortcut_display);
                        if (sw > max_shortcut_width) max_shortcut_width = sw;
                    },
                    .separator => {},
                }
            }

            const inner_width = max_label_width + max_shortcut_width + 4; // padding + gap

            // Calculate x offset for dropdown
            var x_offset: usize = 1;
            for (self.menus[0..self.active_menu]) |maybe_menu| {
                if (maybe_menu) |m| {
                    x_offset += measure.width(m.label) + 2 + self.gap;
                }
            }
            // Indent dropdown to align with menu item
            for (0..x_offset) |_| try w.writeByte(' ');

            // Top border
            try self.writeBorder(w, allocator, inner_width, .top);
            try w.writeByte('\n');

            // Items
            for (menu.items[0..menu.item_count], 0..) |maybe_item, i| {
                const item = maybe_item orelse continue;

                for (0..x_offset) |_| try w.writeByte(' ');

                switch (item) {
                    .separator => {
                        try self.writeBorder(w, allocator, inner_width, .middle);
                    },
                    .action => |a| {
                        try self.writeBorderChar(w, allocator, .left);

                        const is_active = (i == self.active_item);
                        const s = if (!a.enabled) self.item_disabled_style else if (is_active) self.item_active_style else self.item_style;

                        // Build line content
                        var line: Writer.Allocating = .init(allocator);
                        const lw = &line.writer;

                        try lw.writeByte(' ');

                        // Check mark
                        if (a.checked) |checked| {
                            if (checked) {
                                try lw.writeAll("\u{2713} ");
                            } else {
                                try lw.writeAll("  ");
                            }
                        }

                        try lw.writeAll(a.label);

                        // Pad between label and shortcut
                        const label_width = measure.width(a.label) + if (a.checked != null) @as(usize, 2) else @as(usize, 0);
                        const gap_needed = inner_width -| label_width -| measure.width(a.shortcut_display) -| 2;
                        for (0..gap_needed) |_| try lw.writeByte(' ');

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
            for (0..x_offset) |_| try w.writeByte(' ');
            try self.writeBorder(w, allocator, inner_width, .bottom);

            return result.toOwnedSlice();
        }

        const BorderPos = enum { top, middle, bottom };
        const BorderSide = enum { left, right };

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
                .left => self.border_chars.vertical,
                .right => self.border_chars.vertical,
            };
            try writer.writeAll(try bs.render(allocator, char));
        }
    };
}
