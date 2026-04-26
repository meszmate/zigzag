//! Status bar component.
//!
//! Renders a single-line bar with left, center, and right-aligned segments.
//! Each segment may have its own style and is styled independently so the bar
//! can show, for example, a mode indicator, the current file, and cursor
//! position simultaneously.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub const Segment = struct {
    text: []const u8,
    style: ?style_mod.Style = null,
};

pub const StatusBar = struct {
    allocator: std.mem.Allocator,

    left: std.array_list.Managed(Segment),
    center: std.array_list.Managed(Segment),
    right: std.array_list.Managed(Segment),

    width: u16,
    separator: []const u8,
    /// Style applied to the gap characters between segment groups.
    base_style: style_mod.Style,

    pub fn init(allocator: std.mem.Allocator) StatusBar {
        var base = style_mod.Style{};
        base = base.bg(.gray(4));
        base = base.fg(.gray(14));
        base = base.inline_style(true);

        return .{
            .allocator = allocator,
            .left = std.array_list.Managed(Segment).init(allocator),
            .center = std.array_list.Managed(Segment).init(allocator),
            .right = std.array_list.Managed(Segment).init(allocator),
            .width = 80,
            .separator = " │ ",
            .base_style = base,
        };
    }

    pub fn deinit(self: *StatusBar) void {
        self.left.deinit();
        self.center.deinit();
        self.right.deinit();
    }

    pub fn setWidth(self: *StatusBar, w: u16) void {
        self.width = w;
    }

    pub fn setBaseStyle(self: *StatusBar, s: style_mod.Style) void {
        self.base_style = s;
    }

    pub fn setSeparator(self: *StatusBar, sep: []const u8) void {
        self.separator = sep;
    }

    pub fn addLeft(self: *StatusBar, segment: Segment) !void {
        try self.left.append(segment);
    }

    pub fn addCenter(self: *StatusBar, segment: Segment) !void {
        try self.center.append(segment);
    }

    pub fn addRight(self: *StatusBar, segment: Segment) !void {
        try self.right.append(segment);
    }

    pub fn clear(self: *StatusBar) void {
        self.left.clearRetainingCapacity();
        self.center.clearRetainingCapacity();
        self.right.clearRetainingCapacity();
    }

    /// Replace all left segments with a single-segment string.
    pub fn setLeft(self: *StatusBar, text: []const u8, s: ?style_mod.Style) !void {
        self.left.clearRetainingCapacity();
        try self.left.append(.{ .text = text, .style = s });
    }

    pub fn setCenter(self: *StatusBar, text: []const u8, s: ?style_mod.Style) !void {
        self.center.clearRetainingCapacity();
        try self.center.append(.{ .text = text, .style = s });
    }

    pub fn setRight(self: *StatusBar, text: []const u8, s: ?style_mod.Style) !void {
        self.right.clearRetainingCapacity();
        try self.right.append(.{ .text = text, .style = s });
    }

    /// Render the status bar to a single line padded to `width` columns.
    pub fn view(self: *const StatusBar, allocator: std.mem.Allocator) ![]const u8 {
        const left_str = try self.renderGroup(allocator, self.left.items);
        defer allocator.free(left_str);
        const center_str = try self.renderGroup(allocator, self.center.items);
        defer allocator.free(center_str);
        const right_str = try self.renderGroup(allocator, self.right.items);
        defer allocator.free(right_str);

        const lw = measure.width(left_str);
        const cw = measure.width(center_str);
        const rw = measure.width(right_str);

        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        try writer.writeAll(left_str);

        // Center text: place it so its midpoint sits on width/2, but never
        // overlap the left or right groups.
        if (cw > 0) {
            const target_start = (self.width -| cw) / 2;
            const start = @max(lw, target_start);
            const gap = start -| lw;
            try self.writeGap(writer, allocator, gap);
            try writer.writeAll(center_str);
            const consumed = lw + gap + cw;
            const trailing = (self.width -| rw) -| consumed;
            try self.writeGap(writer, allocator, trailing);
        } else {
            const gap = (self.width -| rw) -| lw;
            try self.writeGap(writer, allocator, gap);
        }

        try writer.writeAll(right_str);

        return result.toOwnedSlice();
    }

    fn renderGroup(self: *const StatusBar, allocator: std.mem.Allocator, items: []const Segment) ![]u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;
        for (items, 0..) |seg, i| {
            if (i > 0) {
                if (self.separator.len > 0) {
                    const sep_styled = try self.base_style.render(allocator, self.separator);
                    defer allocator.free(sep_styled);
                    try w.writeAll(sep_styled);
                }
            }
            if (seg.style) |s| {
                const styled = try s.render(allocator, seg.text);
                defer allocator.free(styled);
                try w.writeAll(styled);
            } else {
                const styled = try self.base_style.render(allocator, seg.text);
                defer allocator.free(styled);
                try w.writeAll(styled);
            }
        }
        return out.toOwnedSlice();
    }

    fn writeGap(self: *const StatusBar, writer: *std.Io.Writer, allocator: std.mem.Allocator, count: usize) !void {
        if (count == 0) return;
        const spaces = try allocator.alloc(u8, count);
        defer allocator.free(spaces);
        @memset(spaces, ' ');
        const styled = try self.base_style.render(allocator, spaces);
        defer allocator.free(styled);
        try writer.writeAll(styled);
    }
};

test "status bar places left and right segments on opposite ends" {
    const allocator = std.testing.allocator;
    var bar = StatusBar.init(allocator);
    defer bar.deinit();

    bar.setWidth(20);
    try bar.setLeft("L", null);
    try bar.setRight("R", null);

    const out = try bar.view(allocator);
    defer allocator.free(out);
    try std.testing.expectEqual(@as(usize, 20), measure.width(out));
}

test "status bar centers middle segment" {
    const allocator = std.testing.allocator;
    var bar = StatusBar.init(allocator);
    defer bar.deinit();

    bar.setWidth(30);
    try bar.setLeft("A", null);
    try bar.setCenter("MID", null);
    try bar.setRight("Z", null);

    const out = try bar.view(allocator);
    defer allocator.free(out);
    try std.testing.expectEqual(@as(usize, 30), measure.width(out));
}

test "status bar tolerates narrow width" {
    const allocator = std.testing.allocator;
    var bar = StatusBar.init(allocator);
    defer bar.deinit();

    bar.setWidth(5);
    try bar.setLeft("hello", null);
    try bar.setRight("world", null);

    // Even with overflow, rendering must not crash.
    const out = try bar.view(allocator);
    defer allocator.free(out);
}
