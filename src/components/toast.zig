//! Enhanced Toast/Snackbar notification system.
//! Supports positioning, stacking, icons, borders, and auto-dismiss with countdown.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");

pub const Level = enum {
    info,
    success,
    warning,
    err,
};

pub const Position = enum {
    top_left,
    top_center,
    top_right,
    bottom_left,
    bottom_center,
    bottom_right,
};

pub const StackOrder = enum {
    newest_first,
    oldest_first,
};

pub const ToastMessage = struct {
    text: []const u8,
    level: Level,
    created_ns: u64,
    duration_ms: u64,
    dismissable: bool,
};

pub const Toast = struct {
    allocator: std.mem.Allocator,
    messages: std.array_list.Managed(ToastMessage),

    // Layout
    max_visible: usize,
    position: Position,
    stack_order: StackOrder,
    min_width: u16,
    max_width: u16,

    // Visual
    show_icons: bool,
    show_border: bool,
    show_countdown: bool,
    border_chars: border_mod.BorderChars,

    // Icons per level
    info_icon: []const u8,
    success_icon: []const u8,
    warning_icon: []const u8,
    err_icon: []const u8,

    // Styling per level
    info_style: style_mod.Style,
    success_style: style_mod.Style,
    warning_style: style_mod.Style,
    err_style: style_mod.Style,

    info_border_fg: Color,
    success_border_fg: Color,
    warning_border_fg: Color,
    err_border_fg: Color,

    pub fn init(allocator: std.mem.Allocator) Toast {
        return .{
            .allocator = allocator,
            .messages = std.array_list.Managed(ToastMessage).init(allocator),
            .max_visible = 5,
            .position = .top_right,
            .stack_order = .newest_first,
            .min_width = 20,
            .max_width = 50,
            .show_icons = true,
            .show_border = true,
            .show_countdown = false,
            .border_chars = .rounded,
            .info_icon = "\u{2139}  ",
            .success_icon = "\u{2713} ",
            .warning_icon = "\u{26a0} ",
            .err_icon = "\u{2717} ",
            .info_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.inline_style(true);
                break :blk s;
            },
            .success_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.green);
                s = s.inline_style(true);
                break :blk s;
            },
            .warning_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.yellow);
                s = s.inline_style(true);
                break :blk s;
            },
            .err_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.red);
                s = s.inline_style(true);
                break :blk s;
            },
            .info_border_fg = .cyan,
            .success_border_fg = .green,
            .warning_border_fg = .yellow,
            .err_border_fg = .red,
        };
    }

    pub fn deinit(self: *Toast) void {
        self.dismissAll();
        self.messages.deinit();
    }

    /// Push a notification.
    pub fn push(self: *Toast, text: []const u8, level: Level, duration_ms: u64, current_ns: u64) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        try self.messages.append(.{
            .text = owned_text,
            .level = level,
            .created_ns = current_ns,
            .duration_ms = duration_ms,
            .dismissable = true,
        });
    }

    /// Push a persistent notification (no auto-dismiss).
    pub fn pushPersistent(self: *Toast, text: []const u8, level: Level, current_ns: u64) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        try self.messages.append(.{
            .text = owned_text,
            .level = level,
            .created_ns = current_ns,
            .duration_ms = 0, // 0 = no auto-dismiss
            .dismissable = true,
        });
    }

    /// Dismiss the most recent notification.
    pub fn dismiss(self: *Toast) void {
        if (self.messages.items.len > 0) {
            const msg = self.messages.pop().?;
            self.freeMessage(msg);
        }
    }

    /// Dismiss the oldest notification.
    pub fn dismissOldest(self: *Toast) void {
        if (self.messages.items.len > 0) {
            self.removeAt(0);
        }
    }

    /// Dismiss all notifications.
    pub fn dismissAll(self: *Toast) void {
        for (self.messages.items) |msg| {
            self.freeMessage(msg);
        }
        self.messages.clearRetainingCapacity();
    }

    /// Remove expired notifications.
    pub fn update(self: *Toast, current_ns: u64) void {
        var i: usize = 0;
        while (i < self.messages.items.len) {
            const msg = self.messages.items[i];
            if (msg.duration_ms == 0) {
                // Persistent - don't auto-dismiss
                i += 1;
                continue;
            }
            const elapsed_ms = (current_ns -| msg.created_ns) / std.time.ns_per_ms;
            if (elapsed_ms >= msg.duration_ms) {
                self.removeAt(i);
            } else {
                i += 1;
            }
        }
    }

    /// Check if there are any active notifications.
    pub fn hasMessages(self: *const Toast) bool {
        return self.messages.items.len > 0;
    }

    /// Count of active messages.
    pub fn count(self: *const Toast) usize {
        return self.messages.items.len;
    }

    /// Render notifications as a vertical stack.
    pub fn view(self: *const Toast, allocator: std.mem.Allocator, current_ns: u64) ![]const u8 {
        if (self.messages.items.len == 0) {
            return try allocator.dupe(u8, "");
        }

        var result: Writer.Allocating = .init(allocator);
        errdefer result.deinit();
        const writer = &result.writer;

        const visible_count = @min(self.messages.items.len, self.max_visible);

        const total = self.messages.items.len;
        for (0..visible_count) |render_idx| {
            if (render_idx > 0) try writer.writeByte('\n');

            const idx = switch (self.stack_order) {
                .newest_first => total - 1 - render_idx,
                .oldest_first => blk: {
                    const start = if (total > self.max_visible) total - self.max_visible else 0;
                    break :blk start + render_idx;
                },
            };
            const msg = self.messages.items[idx];
            const toast_str = try self.renderSingleToast(allocator, msg, current_ns);
            defer allocator.free(toast_str);
            try writer.writeAll(toast_str);
        }

        // Show overflow indicator
        if (total > self.max_visible) {
            try writer.writeByte('\n');
            const overflow_text = try std.fmt.allocPrint(allocator, "  +{d} more", .{total - self.max_visible});
            defer allocator.free(overflow_text);
            var dim_style = style_mod.Style{};
            dim_style = dim_style.fg(.gray(10));
            dim_style = dim_style.inline_style(true);
            const styled = try dim_style.render(allocator, overflow_text);
            defer allocator.free(styled);
            try writer.writeAll(styled);
        }

        return result.toOwnedSlice();
    }

    /// Render for positioned display within a terminal.
    pub fn viewPositioned(self: *const Toast, allocator: std.mem.Allocator, term_width: usize, term_height: usize, current_ns: u64) ![]const u8 {
        const toast_content = try self.view(allocator, current_ns);
        if (toast_content.len == 0) return toast_content;
        defer allocator.free(toast_content);

        const place_mod = @import("../layout/place.zig");
        const line_alignment: style_mod.Align = switch (self.position) {
            .top_left, .bottom_left => .left,
            .top_center, .bottom_center => .center,
            .top_right, .bottom_right => .right,
        };
        const aligned_content = try alignLines(allocator, toast_content, line_alignment);
        defer allocator.free(aligned_content);

        const hpos: f32 = switch (self.position) {
            .top_left, .bottom_left => 0.0,
            .top_center, .bottom_center => 0.5,
            .top_right, .bottom_right => 1.0,
        };
        const vpos: f32 = switch (self.position) {
            .top_left, .top_center, .top_right => 0.0,
            .bottom_left, .bottom_center, .bottom_right => 1.0,
        };

        return place_mod.placeFloat(allocator, term_width, term_height, hpos, vpos, aligned_content);
    }

    fn renderSingleToast(self: *const Toast, allocator: std.mem.Allocator, msg: ToastMessage, current_ns: u64) ![]const u8 {
        const active_style = self.styleForLevel(msg.level);

        var line: Writer.Allocating = .init(allocator);
        errdefer line.deinit();
        const lw = &line.writer;

        const icon = if (self.show_icons) switch (msg.level) {
            .info => self.info_icon,
            .success => self.success_icon,
            .warning => self.warning_icon,
            .err => self.err_icon,
        } else "";
        const icon_width = measure.width(icon);

        var countdown_text: []const u8 = "";
        var countdown_width: usize = 0;
        if (self.show_countdown and msg.duration_ms > 0) {
            const elapsed_ms = (current_ns -| msg.created_ns) / std.time.ns_per_ms;
            const remaining = if (elapsed_ms < msg.duration_ms) msg.duration_ms - elapsed_ms else 0;
            const remaining_sec = remaining / 1000;
            countdown_text = try std.fmt.allocPrint(allocator, " ({d}s)", .{remaining_sec});
            countdown_width = measure.width(countdown_text);
        }
        defer if (countdown_text.len > 0) allocator.free(countdown_text);

        const max_inner_width = @max(self.minInnerWidth(), self.maxInnerWidth());
        const prefix_suffix_width = icon_width + countdown_width;
        const available_text_width = max_inner_width -| prefix_suffix_width;
        const display_text = if (measure.width(msg.text) > available_text_width)
            try measure.truncate(allocator, msg.text, available_text_width)
        else
            try allocator.dupe(u8, msg.text);
        defer allocator.free(display_text);

        // Icon
        if (self.show_icons) {
            const styled_icon = try active_style.render(allocator, icon);
            defer allocator.free(styled_icon);
            try lw.writeAll(styled_icon);
        }

        // Text
        const styled_text = try active_style.render(allocator, display_text);
        defer allocator.free(styled_text);
        try lw.writeAll(styled_text);

        // Countdown
        if (countdown_text.len > 0) {
            var dim_style = style_mod.Style{};
            dim_style = dim_style.fg(.gray(10));
            dim_style = dim_style.inline_style(true);
            const styled_cd = try dim_style.render(allocator, countdown_text);
            defer allocator.free(styled_cd);
            try lw.writeAll(styled_cd);
        }

        const line_content = try line.toOwnedSlice();

        if (!self.show_border) {
            return line_content;
        }

        const target_inner_width = @max(self.minInnerWidth(), measure.width(line_content));

        // Wrap in border
        var box_style = style_mod.Style{};
        box_style = box_style.borderAll(self.border_chars);
        box_style = box_style.borderForeground(self.borderColorForLevel(msg.level));
        box_style = box_style.paddingLeft(1).paddingRight(1);
        box_style = box_style.width(@intCast(target_inner_width));
        box_style = box_style.inline_style(false);

        defer allocator.free(line_content);
        return box_style.render(allocator, line_content);
    }

    fn styleForLevel(self: *const Toast, level: Level) style_mod.Style {
        return switch (level) {
            .info => self.info_style,
            .success => self.success_style,
            .warning => self.warning_style,
            .err => self.err_style,
        };
    }

    fn borderColorForLevel(self: *const Toast, level: Level) Color {
        return switch (level) {
            .info => self.info_border_fg,
            .success => self.success_border_fg,
            .warning => self.warning_border_fg,
            .err => self.err_border_fg,
        };
    }

    fn freeMessage(self: *Toast, msg: ToastMessage) void {
        self.allocator.free(msg.text);
    }

    fn removeAt(self: *Toast, idx: usize) void {
        const msg = self.messages.orderedRemove(idx);
        self.freeMessage(msg);
    }

    fn toastChromeWidth(self: *const Toast) usize {
        if (!self.show_border) return 0;
        return 4; // 2 border columns + 2 horizontal padding columns
    }

    fn minInnerWidth(self: *const Toast) usize {
        const min_total = @as(usize, self.min_width);
        return if (min_total > self.toastChromeWidth())
            min_total - self.toastChromeWidth()
        else
            0;
    }

    fn maxInnerWidth(self: *const Toast) usize {
        const min_inner = self.minInnerWidth();
        const max_total = @as(usize, self.max_width);
        const max_inner = if (max_total > self.toastChromeWidth())
            max_total - self.toastChromeWidth()
        else
            0;
        return @max(min_inner, max_inner);
    }
};

fn alignLines(allocator: std.mem.Allocator, content: []const u8, alignment: style_mod.Align) ![]const u8 {
    const target_width = measure.maxLineWidth(content);
    var result: Writer.Allocating = .init(allocator);
    errdefer result.deinit();
    const writer = &result.writer;

    var lines = std.mem.splitScalar(u8, content, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try writer.writeByte('\n');
        first = false;

        const line_width = measure.width(line);
        const padding = target_width -| line_width;
        const left_padding: usize = switch (alignment) {
            .left => 0,
            .center => padding / 2,
            .right => padding,
        };
        const right_padding: usize = switch (alignment) {
            .left => padding,
            .center => padding - left_padding,
            .right => 0,
        };

        for (0..left_padding) |_| {
            try writer.writeByte(' ');
        }
        try writer.writeAll(line);
        for (0..right_padding) |_| {
            try writer.writeByte(' ');
        }
    }

    return result.toOwnedSlice();
}
