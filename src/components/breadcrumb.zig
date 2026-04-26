//! Breadcrumb navigation component.
//!
//! Renders a horizontal path like `root > users > profile` with the active
//! (last) segment highlighted. Supports custom separators and truncation when
//! the rendered path would exceed a max width.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub const Crumb = struct {
    label: []const u8,
    /// Optional user-defined id so consumers can identify which segment was
    /// clicked or selected. Not used for rendering.
    id: ?[]const u8 = null,
};

pub const Breadcrumb = struct {
    allocator: std.mem.Allocator,
    crumbs: std.array_list.Managed(Crumb),

    separator: []const u8,
    /// If non-zero, the rendered breadcrumb is truncated to fit this many
    /// columns, replacing the middle with an ellipsis segment.
    max_width: usize,

    segment_style: style_mod.Style,
    active_style: style_mod.Style,
    separator_style: style_mod.Style,

    pub fn init(allocator: std.mem.Allocator) Breadcrumb {
        var seg = style_mod.Style{};
        seg = seg.fg(.gray(12));
        seg = seg.inline_style(true);

        var active = style_mod.Style{};
        active = active.fg(.cyan);
        active = active.bold(true);
        active = active.inline_style(true);

        var sep = style_mod.Style{};
        sep = sep.fg(.gray(8));
        sep = sep.inline_style(true);

        return .{
            .allocator = allocator,
            .crumbs = std.array_list.Managed(Crumb).init(allocator),
            .separator = " › ",
            .max_width = 0,
            .segment_style = seg,
            .active_style = active,
            .separator_style = sep,
        };
    }

    pub fn deinit(self: *Breadcrumb) void {
        self.crumbs.deinit();
    }

    pub fn push(self: *Breadcrumb, crumb: Crumb) !void {
        try self.crumbs.append(crumb);
    }

    pub fn pop(self: *Breadcrumb) ?Crumb {
        if (self.crumbs.items.len == 0) return null;
        return self.crumbs.pop();
    }

    pub fn clear(self: *Breadcrumb) void {
        self.crumbs.clearRetainingCapacity();
    }

    pub fn setSeparator(self: *Breadcrumb, sep: []const u8) void {
        self.separator = sep;
    }

    pub fn setMaxWidth(self: *Breadcrumb, w: usize) void {
        self.max_width = w;
    }

    /// Replace all crumbs with a single path built from labels.
    pub fn setPath(self: *Breadcrumb, labels: []const []const u8) !void {
        self.crumbs.clearRetainingCapacity();
        for (labels) |label| try self.crumbs.append(.{ .label = label });
    }

    pub fn view(self: *const Breadcrumb, allocator: std.mem.Allocator) ![]const u8 {
        if (self.crumbs.items.len == 0) return try allocator.dupe(u8, "");

        var full = try self.renderCrumbs(allocator, self.crumbs.items);
        if (self.max_width == 0 or measure.width(full) <= self.max_width) return full;

        // Truncate: keep first and last N crumbs, replace middle with ellipsis.
        allocator.free(full);

        const n = self.crumbs.items.len;
        if (n <= 2) {
            full = try self.renderCrumbs(allocator, self.crumbs.items);
            return full;
        }

        // Start with [first, ..., last], then widen outward while fitting.
        var head_count: usize = 1;
        var tail_count: usize = 1;
        var best: ?[]u8 = null;

        while (head_count + tail_count < n) {
            const candidate = try self.renderTruncated(allocator, head_count, tail_count);
            if (measure.width(candidate) > self.max_width) {
                allocator.free(candidate);
                break;
            }
            if (best) |b| allocator.free(b);
            best = candidate;

            // Prefer growing the tail (most relevant to user's position).
            if (tail_count <= head_count) {
                tail_count += 1;
            } else {
                head_count += 1;
            }
        }

        if (best) |b| return b;
        return self.renderTruncated(allocator, 1, 1);
    }

    fn renderTruncated(self: *const Breadcrumb, allocator: std.mem.Allocator, head: usize, tail: usize) ![]u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        const head_slice = self.crumbs.items[0..head];
        const tail_slice = self.crumbs.items[self.crumbs.items.len - tail ..];

        var first = true;
        for (head_slice) |c| {
            if (!first) {
                const sep = try self.separator_style.render(allocator, self.separator);
                defer allocator.free(sep);
                try w.writeAll(sep);
            }
            first = false;
            const seg = try self.segment_style.render(allocator, c.label);
            defer allocator.free(seg);
            try w.writeAll(seg);
        }

        const sep = try self.separator_style.render(allocator, self.separator);
        defer allocator.free(sep);
        try w.writeAll(sep);
        const ellipsis = try self.segment_style.render(allocator, "…");
        defer allocator.free(ellipsis);
        try w.writeAll(ellipsis);

        for (tail_slice, 0..) |c, i| {
            const s = try self.separator_style.render(allocator, self.separator);
            defer allocator.free(s);
            try w.writeAll(s);

            const is_last = i == tail_slice.len - 1;
            const crumb_style = if (is_last) self.active_style else self.segment_style;
            const seg = try crumb_style.render(allocator, c.label);
            defer allocator.free(seg);
            try w.writeAll(seg);
        }

        return out.toOwnedSlice();
    }

    fn renderCrumbs(self: *const Breadcrumb, allocator: std.mem.Allocator, items: []const Crumb) ![]u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        for (items, 0..) |c, i| {
            if (i > 0) {
                const sep = try self.separator_style.render(allocator, self.separator);
                defer allocator.free(sep);
                try w.writeAll(sep);
            }
            const is_last = i == items.len - 1;
            const s = if (is_last) self.active_style else self.segment_style;
            const seg = try s.render(allocator, c.label);
            defer allocator.free(seg);
            try w.writeAll(seg);
        }

        return out.toOwnedSlice();
    }
};

test "breadcrumb renders empty as empty string" {
    const allocator = std.testing.allocator;
    var bc = Breadcrumb.init(allocator);
    defer bc.deinit();
    const out = try bc.view(allocator);
    defer allocator.free(out);
    try std.testing.expectEqual(@as(usize, 0), out.len);
}

test "breadcrumb renders path with separators" {
    const allocator = std.testing.allocator;
    var bc = Breadcrumb.init(allocator);
    defer bc.deinit();
    try bc.setPath(&.{ "root", "users", "profile" });
    const out = try bc.view(allocator);
    defer allocator.free(out);
    // 3 labels (13 chars: root=4, users=5, profile=7) + 2 separators (each 3 cols = 6).
    try std.testing.expectEqual(@as(usize, 4 + 3 + 5 + 3 + 7), measure.width(out));
}

test "breadcrumb truncates when over max width" {
    const allocator = std.testing.allocator;
    var bc = Breadcrumb.init(allocator);
    defer bc.deinit();
    try bc.setPath(&.{ "aaaa", "bbbb", "cccc", "dddd", "eeee" });
    bc.setMaxWidth(18);
    const out = try bc.view(allocator);
    defer allocator.free(out);
    try std.testing.expect(measure.width(out) <= 18);
    try std.testing.expect(std.mem.indexOf(u8, out, "…") != null);
}
