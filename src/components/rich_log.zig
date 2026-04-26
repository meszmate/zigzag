//! Rich log widget — append-only, virtualized, level-aware.
//!
//! Stores a bounded ring buffer of log entries with severity levels and
//! optional timestamps. Renders only the visible window so cost stays O(rows)
//! regardless of buffer size. Supports follow-mode (auto-scroll to tail),
//! per-level styling, level filters, and substring search highlighting.
//!
//! Distinct from Viewport (raw text) and Toast (transient notification): this
//! is the right widget for a long-running app's persistent log/audit pane.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub const Style = style_mod.Style;

pub const Level = enum {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn label(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
        };
    }

    pub fn rank(self: Level) u8 {
        return switch (self) {
            .trace => 0,
            .debug => 1,
            .info => 2,
            .warn => 3,
            .err => 4,
        };
    }
};

pub const Entry = struct {
    level: Level,
    /// Unix nanoseconds, populated by `append` from `std.time.nanoTimestamp()`.
    timestamp_ns: i128,
    text: []u8,
};

pub const RichLog = struct {
    allocator: std.mem.Allocator,

    /// Ring buffer of entries.
    entries: std.array_list.Managed(Entry),
    /// Maximum entries retained; older entries are dropped on append.
    capacity: usize,

    /// Indices into `entries` after applying min_level + search filter.
    /// Recomputed lazily.
    visible: std.array_list.Managed(usize),
    visible_dirty: bool,

    /// Display configuration.
    width: u16,
    height: u16,
    y_offset: usize,
    follow: bool,

    /// Filtering.
    min_level: Level,
    search_term: std.array_list.Managed(u8),

    /// Display options.
    show_timestamps: bool,
    show_level: bool,

    /// Styling.
    timestamp_style: Style,
    level_styles: [5]Style,
    text_style: Style,
    highlight_style: Style,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) RichLog {
        var ts = Style{};
        ts = ts.fg(.gray(8));
        ts = ts.inline_style(true);

        var trace_s = Style{};
        trace_s = trace_s.fg(.gray(6));
        trace_s = trace_s.inline_style(true);
        var debug_s = Style{};
        debug_s = debug_s.fg(.gray(10));
        debug_s = debug_s.inline_style(true);
        var info_s = Style{};
        info_s = info_s.fg(.cyan);
        info_s = info_s.inline_style(true);
        var warn_s = Style{};
        warn_s = warn_s.fg(.yellow);
        warn_s = warn_s.inline_style(true);
        var err_s = Style{};
        err_s = err_s.fg(.red);
        err_s = err_s.bold(true);
        err_s = err_s.inline_style(true);

        var text = Style{};
        text = text.inline_style(true);

        var hi = Style{};
        hi = hi.bg(.yellow);
        hi = hi.fg(.black);
        hi = hi.inline_style(true);

        return .{
            .allocator = allocator,
            .entries = std.array_list.Managed(Entry).init(allocator),
            .capacity = @max(capacity, 1),
            .visible = std.array_list.Managed(usize).init(allocator),
            .visible_dirty = true,
            .width = 80,
            .height = 10,
            .y_offset = 0,
            .follow = true,
            .min_level = .trace,
            .search_term = std.array_list.Managed(u8).init(allocator),
            .show_timestamps = false,
            .show_level = true,
            .timestamp_style = ts,
            .level_styles = .{ trace_s, debug_s, info_s, warn_s, err_s },
            .text_style = text,
            .highlight_style = hi,
        };
    }

    pub fn deinit(self: *RichLog) void {
        for (self.entries.items) |e| self.allocator.free(e.text);
        self.entries.deinit();
        self.visible.deinit();
        self.search_term.deinit();
    }

    pub fn setSize(self: *RichLog, w: u16, h: u16) void {
        self.width = w;
        self.height = h;
    }

    pub fn setMinLevel(self: *RichLog, lvl: Level) void {
        self.min_level = lvl;
        self.visible_dirty = true;
    }

    pub fn setSearch(self: *RichLog, term: []const u8) !void {
        self.search_term.clearRetainingCapacity();
        try self.search_term.appendSlice(term);
        self.visible_dirty = true;
    }

    pub fn clearSearch(self: *RichLog) void {
        self.search_term.clearRetainingCapacity();
        self.visible_dirty = true;
    }

    /// Append an entry, dropping the oldest if at capacity.
    pub fn append(self: *RichLog, level: Level, text: []const u8) !void {
        const owned = try self.allocator.dupe(u8, text);
        if (self.entries.items.len >= self.capacity) {
            const oldest = self.entries.orderedRemove(0);
            self.allocator.free(oldest.text);
        }
        try self.entries.append(.{
            .level = level,
            .timestamp_ns = std.time.nanoTimestamp(),
            .text = owned,
        });
        self.visible_dirty = true;
        if (self.follow) self.scrollToEnd();
    }

    /// Append using std.fmt-style formatting.
    pub fn appendFmt(self: *RichLog, level: Level, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.append(level, formatted);
    }

    pub fn clear(self: *RichLog) void {
        for (self.entries.items) |e| self.allocator.free(e.text);
        self.entries.clearRetainingCapacity();
        self.visible.clearRetainingCapacity();
        self.visible_dirty = false;
        self.y_offset = 0;
    }

    pub fn scrollUp(self: *RichLog, n: usize) void {
        self.follow = false;
        self.y_offset -|= n;
    }

    pub fn scrollDown(self: *RichLog, n: usize) !void {
        try self.refresh();
        const max_off = self.maxOffset();
        self.y_offset = @min(self.y_offset + n, max_off);
        if (self.y_offset == max_off) self.follow = true;
    }

    pub fn scrollToEnd(self: *RichLog) void {
        self.refresh() catch return;
        self.y_offset = self.maxOffset();
        self.follow = true;
    }

    pub fn scrollToStart(self: *RichLog) void {
        self.y_offset = 0;
        self.follow = false;
    }

    fn maxOffset(self: *const RichLog) usize {
        const visible_count = self.visible.items.len;
        if (visible_count <= self.height) return 0;
        return visible_count - self.height;
    }

    fn refresh(self: *RichLog) !void {
        if (!self.visible_dirty) return;
        self.visible.clearRetainingCapacity();
        for (self.entries.items, 0..) |e, i| {
            if (e.level.rank() < self.min_level.rank()) continue;
            if (self.search_term.items.len > 0 and
                std.mem.indexOf(u8, e.text, self.search_term.items) == null)
            {
                continue;
            }
            try self.visible.append(i);
        }
        self.visible_dirty = false;
        const max_off = self.maxOffset();
        if (self.y_offset > max_off) self.y_offset = max_off;
    }

    pub fn handleKey(self: *RichLog, key: keys.KeyEvent) !void {
        switch (key.key) {
            .up => self.scrollUp(1),
            .down => try self.scrollDown(1),
            .page_up => self.scrollUp(self.height),
            .page_down => try self.scrollDown(self.height),
            .home => self.scrollToStart(),
            .end => self.scrollToEnd(),
            .char => |c| switch (c) {
                'g' => self.scrollToStart(),
                'G' => self.scrollToEnd(),
                'k' => self.scrollUp(1),
                'j' => try self.scrollDown(1),
                else => {},
            },
            else => {},
        }
    }

    pub fn view(self: *RichLog, allocator: std.mem.Allocator) ![]const u8 {
        try self.refresh();

        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        const visible = self.visible.items;
        if (visible.len == 0) {
            return out.toOwnedSlice();
        }

        const start = self.y_offset;
        const end = @min(start + self.height, visible.len);

        var first = true;
        for (start..end) |row_idx| {
            if (!first) try w.writeByte('\n');
            first = false;
            const entry = self.entries.items[visible[row_idx]];
            try self.renderEntry(allocator, w, entry);
        }

        return out.toOwnedSlice();
    }

    fn renderEntry(self: *const RichLog, allocator: std.mem.Allocator, w: *Writer, entry: Entry) !void {
        if (self.show_timestamps) {
            const ts = try formatTimestamp(allocator, entry.timestamp_ns);
            defer allocator.free(ts);
            const styled = try self.timestamp_style.render(allocator, ts);
            defer allocator.free(styled);
            try w.writeAll(styled);
            try w.writeByte(' ');
        }

        if (self.show_level) {
            const lvl_style = self.level_styles[@intFromEnum(entry.level)];
            const styled = try lvl_style.render(allocator, entry.level.label());
            defer allocator.free(styled);
            try w.writeAll(styled);
            try w.writeByte(' ');
        }

        // Render text with optional search highlighting.
        if (self.search_term.items.len == 0) {
            const styled = try self.text_style.render(allocator, entry.text);
            defer allocator.free(styled);
            try w.writeAll(styled);
        } else {
            try self.renderHighlighted(allocator, w, entry.text);
        }
    }

    fn renderHighlighted(self: *const RichLog, allocator: std.mem.Allocator, w: *Writer, text: []const u8) !void {
        const term = self.search_term.items;
        var rest = text;
        while (std.mem.indexOf(u8, rest, term)) |pos| {
            if (pos > 0) {
                const before = try self.text_style.render(allocator, rest[0..pos]);
                defer allocator.free(before);
                try w.writeAll(before);
            }
            const hi = try self.highlight_style.render(allocator, rest[pos .. pos + term.len]);
            defer allocator.free(hi);
            try w.writeAll(hi);
            rest = rest[pos + term.len ..];
        }
        if (rest.len > 0) {
            const tail = try self.text_style.render(allocator, rest);
            defer allocator.free(tail);
            try w.writeAll(tail);
        }
    }
};

fn formatTimestamp(allocator: std.mem.Allocator, ns: i128) ![]u8 {
    const seconds_total: i64 = @intCast(@divTrunc(ns, std.time.ns_per_s));
    // HH:MM:SS in UTC.
    const sec_in_day: u32 = @intCast(@mod(seconds_total, 86400));
    const hh = sec_in_day / 3600;
    const mm = (sec_in_day % 3600) / 60;
    const ss = sec_in_day % 60;
    return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hh, mm, ss });
}

test "append respects capacity" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 3);
    defer log.deinit();
    try log.append(.info, "a");
    try log.append(.info, "b");
    try log.append(.info, "c");
    try log.append(.info, "d");
    try std.testing.expectEqual(@as(usize, 3), log.entries.items.len);
    try std.testing.expectEqualStrings("b", log.entries.items[0].text);
    try std.testing.expectEqualStrings("d", log.entries.items[2].text);
}

test "min level filters entries" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 100);
    defer log.deinit();
    try log.append(.debug, "noise");
    try log.append(.warn, "important");
    log.setMinLevel(.warn);
    try log.refresh();
    try std.testing.expectEqual(@as(usize, 1), log.visible.items.len);
}

test "search filter matches substring" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 10);
    defer log.deinit();
    try log.append(.info, "hello world");
    try log.append(.info, "goodbye");
    try log.setSearch("hello");
    try log.refresh();
    try std.testing.expectEqual(@as(usize, 1), log.visible.items.len);
}

test "follow mode auto-scrolls" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 100);
    defer log.deinit();
    log.setSize(80, 2);
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try log.appendFmt(.info, "line {d}", .{i});
    }
    try log.refresh();
    // Last two entries should fit; offset should be 3.
    try std.testing.expectEqual(@as(usize, 3), log.y_offset);
}

test "scrollUp disables follow" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 100);
    defer log.deinit();
    try log.append(.info, "a");
    log.scrollUp(1);
    try std.testing.expect(!log.follow);
}

test "view emits at most height lines" {
    const allocator = std.testing.allocator;
    var log = RichLog.init(allocator, 100);
    defer log.deinit();
    log.setSize(80, 3);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try log.appendFmt(.info, "line {d}", .{i});
    }
    const out = try log.view(allocator);
    defer allocator.free(out);
    var newlines: usize = 0;
    for (out) |b| if (b == '\n') {
        newlines += 1;
    };
    try std.testing.expect(newlines <= 2);
}
