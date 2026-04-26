//! Slider component.
//! Interactive numeric range input with keyboard control.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const progress_mod = @import("progress.zig");

pub const Slider = struct {
    // Value
    value: f64,
    min: f64,
    max: f64,
    step: f64,
    large_step: f64,

    // Display
    width: u16,
    precision: u8,
    show_value: bool,
    show_bounds: bool,
    show_percent: bool,
    label: []const u8,

    // Characters
    track_char: []const u8,
    thumb_char: []const u8,
    filled_char: []const u8,

    // Styling
    track_style: style_mod.Style,
    filled_style: style_mod.Style,
    thumb_style: style_mod.Style,
    label_style: style_mod.Style,
    value_style: style_mod.Style,

    // Gradient
    gradient_start: ?Color,
    gradient_end: ?Color,

    // Focus
    focused: bool,

    pub fn init(min: f64, max: f64) Slider {
        return .{
            .value = min,
            .min = min,
            .max = max,
            .step = 1,
            .large_step = 10,
            .width = 30,
            .precision = 0,
            .show_value = true,
            .show_bounds = false,
            .show_percent = false,
            .label = "",
            .track_char = "━",
            .thumb_char = "●",
            .filled_char = "━",
            .track_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.gray(8));
                s = s.inline_style(true);
                break :blk s;
            },
            .filled_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.inline_style(true);
                break :blk s;
            },
            .thumb_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(.white);
                s = s.inline_style(true);
                break :blk s;
            },
            .label_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .value_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(.cyan);
                s = s.inline_style(true);
                break :blk s;
            },
            .gradient_start = null,
            .gradient_end = null,
            .focused = true,
        };
    }

    pub fn setValue(self: *Slider, val: f64) void {
        self.value = @max(self.min, @min(val, self.max));
    }

    pub fn getValue(self: *const Slider) f64 {
        return self.value;
    }

    pub fn percent(self: *const Slider) f64 {
        if (self.max == self.min) return 0;
        return ((self.value - self.min) / (self.max - self.min)) * 100.0;
    }

    pub fn setStep(self: *Slider, s: f64) void {
        self.step = s;
    }

    pub fn setLargeStep(self: *Slider, s: f64) void {
        self.large_step = s;
    }

    pub fn setWidth(self: *Slider, w: u16) void {
        self.width = w;
    }

    pub fn setPrecision(self: *Slider, p: u8) void {
        self.precision = p;
    }

    pub fn setGradient(self: *Slider, start: Color, end: Color) void {
        self.gradient_start = start;
        self.gradient_end = end;
    }

    // Focus protocol
    pub fn focus(self: *Slider) void {
        self.focused = true;
    }

    pub fn blur(self: *Slider) void {
        self.focused = false;
    }

    pub fn handleKey(self: *Slider, key: keys.KeyEvent) void {
        if (!self.focused) return;

        switch (key.key) {
            .left => self.decrement(self.step),
            .right => self.increment(self.step),
            .page_down => self.decrement(self.large_step),
            .page_up => self.increment(self.large_step),
            .home => self.setValue(self.min),
            .end => self.setValue(self.max),
            .char => |c| switch (c) {
                'h' => self.decrement(self.step),
                'l' => self.increment(self.step),
                'H' => self.decrement(self.large_step),
                'L' => self.increment(self.large_step),
                '0' => self.setValue(self.min),
                '$' => self.setValue(self.max),
                else => {},
            },
            else => {},
        }
    }

    fn increment(self: *Slider, amount: f64) void {
        self.setValue(self.value + amount);
    }

    fn decrement(self: *Slider, amount: f64) void {
        self.setValue(self.value - amount);
    }

    pub fn view(self: *const Slider, allocator: std.mem.Allocator) ![]const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        // Label
        if (self.label.len > 0) {
            const styled = try self.label_style.render(allocator, self.label);
            try writer.writeAll(styled);
            try writer.writeAll(" ");
        }

        // Bounds (left)
        if (self.show_bounds) {
            const min_str = try self.formatValue(allocator, self.min);
            try writer.writeAll(min_str);
            try writer.writeAll(" ");
        }

        // Track
        const range = self.max - self.min;
        const ratio: f64 = if (range > 0) (self.value - self.min) / range else 0;
        const track_width = self.width;
        const thumb_pos = @as(usize, @intFromFloat(ratio * @as(f64, @floatFromInt(track_width -| 1))));

        for (0..track_width) |i| {
            if (i == thumb_pos) {
                // Thumb
                const styled = try self.thumb_style.render(allocator, self.thumb_char);
                try writer.writeAll(styled);
            } else if (i < thumb_pos) {
                // Filled portion
                if (self.gradient_start != null and self.gradient_end != null and thumb_pos > 0) {
                    const t: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(@max(1, thumb_pos)));
                    const col = progress_mod.interpolateColor(self.gradient_start.?, self.gradient_end.?, t);
                    var grad_style = style_mod.Style{};
                    grad_style = grad_style.fg(col);
                    grad_style = grad_style.inline_style(true);
                    const styled = try grad_style.render(allocator, self.filled_char);
                    try writer.writeAll(styled);
                } else {
                    const styled = try self.filled_style.render(allocator, self.filled_char);
                    try writer.writeAll(styled);
                }
            } else {
                // Empty track
                const styled = try self.track_style.render(allocator, self.track_char);
                try writer.writeAll(styled);
            }
        }

        // Bounds (right)
        if (self.show_bounds) {
            try writer.writeAll(" ");
            const max_str = try self.formatValue(allocator, self.max);
            try writer.writeAll(max_str);
        }

        // Value display
        if (self.show_value) {
            try writer.writeAll(" ");
            const val_str = try self.formatValue(allocator, self.value);
            const styled = try self.value_style.render(allocator, val_str);
            try writer.writeAll(styled);
        }

        // Percentage
        if (self.show_percent) {
            const pct = self.percent();
            const pct_str = try std.fmt.allocPrint(allocator, " ({d:.0}%)", .{pct});
            try writer.writeAll(pct_str);
        }

        return result.toOwnedSlice();
    }

    fn formatValue(self: *const Slider, allocator: std.mem.Allocator, val: f64) ![]const u8 {
        return switch (self.precision) {
            0 => std.fmt.allocPrint(allocator, "{d:.0}", .{val}),
            1 => std.fmt.allocPrint(allocator, "{d:.1}", .{val}),
            2 => std.fmt.allocPrint(allocator, "{d:.2}", .{val}),
            else => std.fmt.allocPrint(allocator, "{d:.3}", .{val}),
        };
    }
};

/// Slider style presets
pub const SliderStyle = struct {
    pub fn block() Slider {
        var s = Slider.init(0, 100);
        s.filled_char = "█";
        s.track_char = "░";
        s.thumb_char = "▓";
        return s;
    }

    pub fn ascii() Slider {
        var s = Slider.init(0, 100);
        s.filled_char = "=";
        s.track_char = "-";
        s.thumb_char = ">";
        return s;
    }

    pub fn thin() Slider {
        var s = Slider.init(0, 100);
        s.filled_char = "─";
        s.track_char = "─";
        s.thumb_char = "◆";
        return s;
    }

    pub fn dots() Slider {
        var s = Slider.init(0, 100);
        s.filled_char = "•";
        s.track_char = "·";
        s.thumb_char = "◉";
        return s;
    }
};
