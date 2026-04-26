//! Gauge component for displaying a value within a range.
//! Supports bar, level meter, and block display styles with thresholds and gradients.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const Gauge = struct {
    /// Current value.
    value: f64 = 0,
    /// Minimum value.
    min: f64 = 0,
    /// Maximum value.
    max: f64 = 100,
    /// Display width in cells.
    width: u16 = 40,
    /// Display style.
    display_style: DisplayStyle = .bar,
    /// Show value label.
    show_value: bool = true,
    /// Show percentage.
    show_percent: bool = false,
    /// Label format (prefix text).
    label: []const u8 = "",
    /// Thresholds for color changes.
    thresholds: []const Threshold = &.{},
    /// Base color (used when below all thresholds).
    base_color: Color = .green,
    /// Empty/background color.
    empty_color: Color = .gray(6),
    /// Label style.
    label_style: style_mod.Style = .{},
    /// Value/percent label style.
    value_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.inline_style(true);
        break :blk s;
    },
    /// Filled bar character.
    full_char: []const u8 = "\xe2\x96\x88",
    /// Empty bar character.
    empty_char: []const u8 = "\xe2\x96\x91",
    /// Level meter bracket left.
    bracket_left: []const u8 = "[",
    /// Level meter bracket right.
    bracket_right: []const u8 = "]",
    /// Number of segments in level meter.
    level_segments: usize = 10,
    /// Value format string prefix.
    value_prefix: []const u8 = "",
    /// Value format string suffix.
    value_suffix: []const u8 = "",

    pub const DisplayStyle = enum {
        /// Horizontal bar with fill characters.
        bar,
        /// Vertical level meter segments.
        level_meter,
        /// Block characters showing intensity.
        blocks,
    };

    pub const Threshold = struct {
        value: f64,
        color: Color,
    };

    /// Set the gauge value clamped to min/max.
    pub fn setValue(self: *Gauge, v: f64) void {
        self.value = @max(self.min, @min(v, self.max));
    }

    /// Get the ratio (0.0 to 1.0).
    pub fn ratio(self: *const Gauge) f64 {
        const range = self.max - self.min;
        if (range <= 0) return 0;
        return (self.value - self.min) / range;
    }

    /// Get the active color based on thresholds.
    fn activeColor(self: *const Gauge) Color {
        var result = self.base_color;
        for (self.thresholds) |t| {
            if (self.value >= t.value) result = t.color;
        }
        return result;
    }

    /// Render the gauge.
    pub fn view(self: *const Gauge, allocator: std.mem.Allocator) []const u8 {
        return switch (self.display_style) {
            .bar => self.renderBar(allocator),
            .level_meter => self.renderLevelMeter(allocator),
            .blocks => self.renderBlocks(allocator),
        };
    }

    fn renderBar(self: *const Gauge, allocator: std.mem.Allocator) []const u8 {
        const pct = self.ratio();
        const active_color = self.activeColor();
        const bar_width: usize = self.width;
        const filled: usize = @intFromFloat(@as(f64, @floatFromInt(bar_width)) * pct);

        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        // Label
        if (self.label.len > 0) {
            if (self.label_style.bold_attr != null or !self.label_style.foreground.isNone()) {
                writer.writeAll(self.label_style.render(allocator, self.label) catch self.label) catch {};
            } else {
                writer.writeAll(self.label) catch {};
            }
            writer.writeByte(' ') catch {};
        }

        // Filled portion
        var fill_style = style_mod.Style{};
        fill_style = fill_style.fg(active_color);
        fill_style = fill_style.inline_style(true);

        var empty_style = style_mod.Style{};
        empty_style = empty_style.fg(self.empty_color);
        empty_style = empty_style.inline_style(true);

        for (0..bar_width) |col| {
            if (col < filled) {
                writer.writeAll(fill_style.render(allocator, "\xe2\x96\x88") catch "\xe2\x96\x88") catch {};
            } else if (col == filled and pct > 0) {
                // Partial fill using fractional blocks
                const frac = (@as(f64, @floatFromInt(bar_width)) * pct) - @as(f64, @floatFromInt(filled));
                const block_idx: usize = @intFromFloat(frac * 8);
                const partial_blocks = [_][]const u8{
                    " ",
                    "\xe2\x96\x8f", // ▏
                    "\xe2\x96\x8e", // ▎
                    "\xe2\x96\x8d", // ▍
                    "\xe2\x96\x8c", // ▌
                    "\xe2\x96\x8b", // ▋
                    "\xe2\x96\x8a", // ▊
                    "\xe2\x96\x89", // ▉
                };
                const ch = if (block_idx < partial_blocks.len) partial_blocks[block_idx] else "\xe2\x96\x88";
                writer.writeAll(fill_style.render(allocator, ch) catch ch) catch {};
            } else {
                writer.writeAll(empty_style.render(allocator, "\xe2\x96\x91") catch "\xe2\x96\x91") catch {};
            }
        }

        // Value/percent label
        if (self.show_value or self.show_percent) {
            writer.writeByte(' ') catch {};
            if (self.show_percent) {
                const pct_val = pct * 100;
                writer.print("{d:.0}%", .{pct_val}) catch {};
            } else {
                writer.print("{d:.1}/{d:.1}", .{ self.value, self.max }) catch {};
            }
        }

        return result.toArrayList().items;
    }

    fn renderLevelMeter(self: *const Gauge, allocator: std.mem.Allocator) []const u8 {
        const pct = self.ratio();
        const levels: usize = 10;
        const filled: usize = @intFromFloat(@as(f64, @floatFromInt(levels)) * pct);

        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        if (self.label.len > 0) {
            writer.writeAll(self.label) catch {};
            writer.writeByte(' ') catch {};
        }

        writer.writeAll("[") catch {};
        for (0..levels) |lvl| {
            const level_pct = @as(f64, @floatFromInt(lvl)) / @as(f64, @floatFromInt(levels));
            const c = self.colorForLevel(level_pct);
            var s = style_mod.Style{};
            s = s.fg(c);
            s = s.inline_style(true);

            if (lvl < filled) {
                writer.writeAll(s.render(allocator, "\xe2\x96\x88") catch "\xe2\x96\x88") catch {};
            } else {
                writer.writeAll("\xe2\x96\x91") catch {};
            }
        }
        writer.writeAll("]") catch {};

        if (self.show_percent) {
            writer.print(" {d:.0}%", .{pct * 100}) catch {};
        }

        return result.toArrayList().items;
    }

    fn renderBlocks(self: *const Gauge, allocator: std.mem.Allocator) []const u8 {
        const pct = self.ratio();
        const active_color = self.activeColor();
        const block_count: usize = self.width;

        // Use shade characters based on intensity
        const shades = [_][]const u8{ " ", "\xe2\x96\x91", "\xe2\x96\x92", "\xe2\x96\x93", "\xe2\x96\x88" };

        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        if (self.label.len > 0) {
            writer.writeAll(self.label) catch {};
            writer.writeByte(' ') catch {};
        }

        var s = style_mod.Style{};
        s = s.fg(active_color);
        s = s.inline_style(true);

        for (0..block_count) |col| {
            const col_pct = @as(f64, @floatFromInt(col)) / @as(f64, @floatFromInt(block_count));
            if (col_pct < pct) {
                // Full block for cells well below the value
                const local_pct = (pct - col_pct) * @as(f64, @floatFromInt(block_count));
                const shade_idx: usize = @intFromFloat(@min(local_pct, 4));
                const ch = if (shade_idx < shades.len) shades[shade_idx] else shades[4];
                writer.writeAll(s.render(allocator, ch) catch ch) catch {};
            } else {
                writer.writeByte(' ') catch {};
            }
        }

        if (self.show_percent) {
            writer.print(" {d:.0}%", .{pct * 100}) catch {};
        }

        return result.toArrayList().items;
    }

    fn colorForLevel(self: *const Gauge, level_pct: f64) Color {
        const value = self.min + (self.max - self.min) * level_pct;
        var result = self.base_color;
        for (self.thresholds) |t| {
            if (value >= t.value) result = t.color;
        }
        return result;
    }
};
