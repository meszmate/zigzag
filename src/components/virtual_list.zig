//! Virtual list component for efficiently rendering large datasets.
//! Only renders items visible in the viewport.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const keys = @import("../input/keys.zig");
const measure = @import("../layout/measure.zig");

pub fn VirtualList(comptime T: type) type {
    return struct {
        /// All items (not copied — references the original slice).
        items: []const T = &.{},
        /// Number of visible rows.
        viewport_height: u16 = 20,
        /// Current cursor position (absolute index).
        cursor: usize = 0,
        /// Scroll offset (first visible item index).
        offset: usize = 0,
        /// Selection set.
        selected: ?std.AutoHashMap(usize, void) = null,
        /// Multi-select mode.
        multi_select: bool = false,
        /// Focused state.
        focused: bool = true,
        /// Render function: called for each visible item.
        render_fn: ?*const fn (item: T, index: usize, selected: bool, allocator: std.mem.Allocator) []const u8 = null,
        /// Wrap cursor around list ends.
        wrap_around: bool = false,
        /// Text shown when list is empty.
        empty_text: []const u8 = "(empty)",
        /// Width for each row (0 = no padding).
        row_width: u16 = 0,

        // Styling
        cursor_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.bg(.blue);
            s = s.fg(.white);
            s = s.inline_style(true);
            break :blk s;
        },
        item_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.inline_style(true);
            break :blk s;
        },
        selected_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.fg(.green);
            s = s.inline_style(true);
            break :blk s;
        },
        scrollbar_style: style_mod.Style = blk: {
            var s = style_mod.Style{};
            s = s.fg(.gray(8));
            s = s.inline_style(true);
            break :blk s;
        },
        /// Cursor prefix.
        cursor_symbol: []const u8 = "> ",
        /// Normal prefix.
        normal_symbol: []const u8 = "  ",
        /// Show scrollbar.
        show_scrollbar: bool = true,
        /// Show item count.
        show_count: bool = true,

        const Self = @This();

        pub fn setItems(self: *Self, items: []const T) void {
            self.items = items;
            if (self.cursor >= items.len and items.len > 0) {
                self.cursor = items.len - 1;
            }
            self.ensureVisible();
        }

        pub fn update(self: *Self, key: keys.KeyEvent) void {
            const total = self.items.len;
            if (total == 0) return;

            switch (key.key) {
                .up => {
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                    } else if (self.wrap_around and total > 0) {
                        self.cursor = total - 1;
                    }
                    self.ensureVisible();
                },
                .down => {
                    if (self.cursor + 1 < total) {
                        self.cursor += 1;
                    } else if (self.wrap_around) {
                        self.cursor = 0;
                    }
                    self.ensureVisible();
                },
                .page_up => {
                    if (self.cursor >= self.viewport_height) {
                        self.cursor -= self.viewport_height;
                    } else {
                        self.cursor = 0;
                    }
                    self.ensureVisible();
                },
                .page_down => {
                    self.cursor += self.viewport_height;
                    if (self.cursor >= total) self.cursor = total - 1;
                    self.ensureVisible();
                },
                .home => {
                    self.cursor = 0;
                    self.ensureVisible();
                },
                .end => {
                    if (total > 0) self.cursor = total - 1;
                    self.ensureVisible();
                },
                .char => |c| {
                    if (c == ' ' and self.multi_select) {
                        self.toggleSelection(self.cursor);
                    }
                },
                .enter => {
                    self.toggleSelection(self.cursor);
                },
                else => {},
            }
        }

        fn toggleSelection(self: *Self, index: usize) void {
            _ = self;
            _ = index;
            // Selection is managed externally; this is a placeholder for signaling
        }

        fn ensureVisible(self: *Self) void {
            if (self.cursor < self.offset) {
                self.offset = self.cursor;
            }
            if (self.cursor >= self.offset + self.viewport_height) {
                self.offset = self.cursor - self.viewport_height + 1;
            }
        }

        pub fn view(self: *const Self, allocator: std.mem.Allocator) []const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;
            const total = self.items.len;
            const vh: usize = self.viewport_height;

            if (total == 0) {
                writer.writeAll(self.empty_text) catch {};
                return result.toArrayList().items;
            }

            const end = @min(self.offset + vh, total);

            for (self.offset..end) |i| {
                if (i > self.offset) writer.writeByte('\n') catch {};

                const is_cursor = (i == self.cursor and self.focused);
                const is_selected = false; // Could check selection map

                // Get item text
                const item_text = if (self.render_fn) |rf|
                    rf(self.items[i], i, is_selected, allocator)
                else
                    defaultRender(self.items[i], i, allocator);

                // Apply style
                const prefix = if (is_cursor) self.cursor_symbol else self.normal_symbol;
                const s = if (is_cursor) self.cursor_style else if (is_selected) self.selected_style else self.item_style;

                const line = std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, item_text }) catch item_text;
                writer.writeAll(s.render(allocator, line) catch line) catch {};

                // Scrollbar
                if (self.show_scrollbar and total > vh) {
                    const row = i - self.offset;
                    const thumb_start = (self.offset * vh) / total;
                    const thumb_size = @max(1, (vh * vh) / total);
                    const is_thumb = row >= thumb_start and row < thumb_start + thumb_size;
                    const sb_char: []const u8 = if (is_thumb) "\xe2\x96\x88" else "\xe2\x96\x91";
                    writer.writeByte(' ') catch {};
                    writer.writeAll(self.scrollbar_style.render(allocator, sb_char) catch sb_char) catch {};
                }
            }

            // Item count
            if (self.show_count) {
                writer.writeByte('\n') catch {};
                const count_str = std.fmt.allocPrint(allocator, " {d}/{d}", .{ self.cursor + 1, total }) catch "";
                var cs = style_mod.Style{};
                cs = cs.fg(.gray(10));
                cs = cs.inline_style(true);
                writer.writeAll(cs.render(allocator, count_str) catch count_str) catch {};
            }

            return result.toArrayList().items;
        }

        fn defaultRender(item: T, index: usize, allocator: std.mem.Allocator) []const u8 {
            if (comptime @typeInfo(T) == .pointer) {
                if (comptime @typeInfo(std.meta.Child(T)) == .int) {
                    // T is []const u8
                    return item;
                }
            }
            return std.fmt.allocPrint(allocator, "Item {d}", .{index}) catch "?";
        }
    };
}
