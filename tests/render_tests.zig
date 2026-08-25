//! Frame renderer tests.
//!
//! The important property is not which bytes come out but what the terminal
//! ends up showing: `VirtualScreen` replays the renderer's output so a diffed
//! frame can be compared against the same frame painted in full.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const Renderer = zz.FrameRenderer;
const Size = zz.frame.Size;

const size_80x24 = Size{ .width = 80, .height = 24 };

/// Minimal terminal model: enough of the control sequences the renderer emits
/// to reconstruct what would be on screen.
const VirtualScreen = struct {
    rows: [64][256]u8,
    used: usize,
    cursor_row: usize = 0,
    cursor_col: usize = 0,

    fn init() VirtualScreen {
        var self = VirtualScreen{ .rows = undefined, .used = 0 };
        for (&self.rows) |*row| @memset(row, ' ');
        return self;
    }

    fn apply(self: *VirtualScreen, output: []const u8) !void {
        var i: usize = 0;
        while (i < output.len) {
            const c = output[i];

            if (c == 0x1b) {
                i += try self.applyEscape(output[i..]);
                continue;
            }

            if (c == '\r') {
                self.cursor_col = 0;
                i += 1;
                continue;
            }
            if (c == '\n') {
                self.cursor_row += 1;
                i += 1;
                continue;
            }

            try testing.expect(self.cursor_row < self.rows.len);
            try testing.expect(self.cursor_col < self.rows[0].len);
            self.rows[self.cursor_row][self.cursor_col] = c;
            self.cursor_col += 1;
            self.used = @max(self.used, self.cursor_row + 1);
            i += 1;
        }
    }

    /// Returns how many bytes the sequence at the front of `data` occupies.
    fn applyEscape(self: *VirtualScreen, data: []const u8) !usize {
        if (data.len < 2 or data[1] != '[') return 1;

        var end: usize = 2;
        while (end < data.len and (data[end] < 0x40 or data[end] > 0x7e)) : (end += 1) {}
        if (end >= data.len) return data.len;

        const params = data[2..end];
        const final = data[end];
        const consumed = end + 1;

        switch (final) {
            'H' => {
                if (params.len == 0) {
                    self.cursor_row = 0;
                    self.cursor_col = 0;
                } else {
                    var it = std.mem.splitScalar(u8, params, ';');
                    const row = try std.fmt.parseInt(usize, it.next().?, 10);
                    const col = try std.fmt.parseInt(usize, it.next() orelse "1", 10);
                    self.cursor_row = row - 1;
                    self.cursor_col = col - 1;
                }
                self.used = @max(self.used, self.cursor_row + 1);
            },
            'K' => {
                const from = if (std.mem.eql(u8, params, "2")) 0 else self.cursor_col;
                @memset(self.rows[self.cursor_row][from..], ' ');
                self.used = @max(self.used, self.cursor_row + 1);
            },
            // Style and synchronized-output sequences do not move the cursor
            // or change cell contents.
            else => {},
        }

        return consumed;
    }

    /// Visible content, trailing blanks trimmed, as a newline-joined string.
    fn text(self: *const VirtualScreen, out: *std.array_list.Managed(u8)) !void {
        out.clearRetainingCapacity();

        var last: usize = 0;
        for (0..self.used) |row| {
            if (std.mem.trimEnd(u8, &self.rows[row], " ").len > 0) last = row + 1;
        }

        for (0..last) |row| {
            if (row > 0) try out.append('\n');
            try out.appendSlice(std.mem.trimEnd(u8, &self.rows[row], " "));
        }
    }
};

/// Drives a renderer and keeps a virtual screen in sync with its output.
const Harness = struct {
    renderer: Renderer,
    screen: VirtualScreen,
    out: std.Io.Writer.Allocating,

    fn init(mode: zz.RenderMode) Harness {
        return .{
            .renderer = Renderer.init(testing.allocator, mode),
            .screen = VirtualScreen.init(),
            .out = std.Io.Writer.Allocating.init(testing.allocator),
        };
    }

    fn deinit(self: *Harness) void {
        self.renderer.deinit();
        self.out.deinit();
    }

    /// Renders one frame; returns the bytes it produced.
    fn render(self: *Harness, view: []const u8, size: Size) ![]const u8 {
        self.out.clearRetainingCapacity();
        _ = try self.renderer.render(&self.out.writer, view, size);
        const written = self.out.written();
        try self.screen.apply(written);
        return written;
    }

    fn expectScreen(self: *const Harness, expected: []const u8) !void {
        var buf = std.array_list.Managed(u8).init(testing.allocator);
        defer buf.deinit();
        try self.screen.text(&buf);
        try testing.expectEqualStrings(expected, buf.items);
    }
};

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, needle)) |found| {
        count += 1;
        i = found + needle.len;
    }
    return count;
}

test "unchanged view produces no output" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("hello\nworld", size_80x24);
    const second = try h.render("hello\nworld", size_80x24);

    try testing.expectEqual(@as(usize, 0), second.len);
}

test "first frame is painted in full" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const out = try h.render("alpha\nbeta\ngamma", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
    try h.expectScreen("alpha\nbeta\ngamma");
}

test "diff rewrites only the changed line" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("alpha\nbeta\ngamma", size_80x24);
    const out = try h.render("alpha\nBETA\ngamma", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "BETA") != null);
    try testing.expect(std.mem.indexOf(u8, out, "alpha") == null);
    try testing.expect(std.mem.indexOf(u8, out, "gamma") == null);
    // Row 2 of the terminal, one-indexed.
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[2;1H") != null);

    try h.expectScreen("alpha\nBETA\ngamma");
}

test "a spinner frame costs one line of output, not a screenful" {
    var h = Harness.init(.diff);
    defer h.deinit();

    var body = std.array_list.Managed(u8).init(testing.allocator);
    defer body.deinit();
    for (0..23) |i| {
        var buf: [64]u8 = undefined;
        try body.appendSlice(try std.fmt.bufPrint(&buf, "line {d} of streaming output\n", .{i}));
    }

    const frames = [_][]const u8{ "|", "/", "-", "\\" };
    var previous: []const u8 = undefined;

    for (frames, 0..) |spinner, i| {
        var view = std.array_list.Managed(u8).init(testing.allocator);
        defer view.deinit();
        try view.appendSlice(body.items);
        try view.appendSlice(spinner);

        const out = try h.render(view.items, size_80x24);
        if (i == 0) {
            previous = "";
            continue;
        }
        // Only the spinner row is touched: nowhere near the ~700 bytes the
        // body would cost.
        try testing.expect(out.len < 64);
        try testing.expect(std.mem.indexOf(u8, out, "streaming output") == null);
    }
}

test "shrinking frame clears the rows it gave up" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("one\ntwo\nthree\nfour", size_80x24);
    _ = try h.render("one\ntwo", size_80x24);

    try h.expectScreen("one\ntwo");
}

test "growing frame writes the rows it gained" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("one\ntwo", size_80x24);
    _ = try h.render("one\ntwo\nthree\nfour", size_80x24);

    try h.expectScreen("one\ntwo\nthree\nfour");
}

test "diff and full renderers leave the same screen" {
    const script = [_][]const u8{
        "alpha\nbeta\ngamma",
        "alpha\nBETA\ngamma",
        "alpha\nBETA\ngamma\ndelta",
        "alpha",
        "alpha\n\n\nomega",
        "",
        "one\ntwo\nthree",
        "one\ntwo\nthree",
        "\x1b[31mred\x1b[0m\nplain",
        "\x1b[31mred\x1b[0m\nPLAIN",
        "one\ntwo\nthree\nfour\nfive",
        "one\nX\nthree\nY\nfive",
    };

    var diff_h = Harness.init(.diff);
    defer diff_h.deinit();
    var full_h = Harness.init(.full);
    defer full_h.deinit();

    for (script) |view| {
        _ = try diff_h.render(view, size_80x24);
        _ = try full_h.render(view, size_80x24);

        var diff_text = std.array_list.Managed(u8).init(testing.allocator);
        defer diff_text.deinit();
        var full_text = std.array_list.Managed(u8).init(testing.allocator);
        defer full_text.deinit();
        try diff_h.screen.text(&diff_text);
        try full_h.screen.text(&full_text);

        try testing.expectEqualStrings(full_text.items, diff_text.items);
    }
}

test "diff and full leave the cursor in the same place" {
    const script = [_][]const u8{
        "alpha\nbeta",
        "alpha\nbeta gamma",
        "alpha",
        "alpha\nbeta\ngamma",
    };

    var diff_h = Harness.init(.diff);
    defer diff_h.deinit();
    var full_h = Harness.init(.full);
    defer full_h.deinit();

    for (script) |view| {
        _ = try diff_h.render(view, size_80x24);
        _ = try full_h.render(view, size_80x24);

        try testing.expectEqual(full_h.screen.cursor_row, diff_h.screen.cursor_row);
        try testing.expectEqual(full_h.screen.cursor_col, diff_h.screen.cursor_col);
    }
}

test "a line wider than the terminal falls back to a full repaint" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const narrow = Size{ .width = 10, .height = 24 };
    _ = try h.render("short\nalso short", narrow);

    const out = try h.render("short\nthis line is far too wide to fit", narrow);

    // Wrapping shifts every row below it, so absolute addressing is off the
    // table: the whole frame is rewritten from home.
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
    try testing.expect(std.mem.indexOf(u8, out, "short") != null);
}

test "a frame taller than the terminal falls back to a full repaint" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const short = Size{ .width = 80, .height = 3 };
    _ = try h.render("a\nb\nc", short);

    const out = try h.render("a\nb\nc\nd", short);
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);

    // The frame scrolled, so the one after it cannot be diffed either.
    const next = try h.render("a\nb\nc\ne", short);
    try testing.expect(std.mem.indexOf(u8, next, "\x1b[1;1H") != null);
}

test "a style left open disables diffing for the following frame" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // The background colour on the first line bleeds onto the second, so the
    // second cannot be repainted on its own.
    _ = try h.render("\x1b[41mred background\nstill red", size_80x24);
    const out = try h.render("\x1b[41mred background\nSTILL RED", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
    try testing.expect(std.mem.indexOf(u8, out, "red background") != null);
}

test "styles closed per line still diff" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("\x1b[31mred\x1b[0m\n\x1b[1mbold\x1b[0m plain", size_80x24);
    const out = try h.render("\x1b[31mred\x1b[0m\n\x1b[1mbold\x1b[0m PLAIN", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") == null);
    try testing.expect(std.mem.indexOf(u8, out, "PLAIN") != null);
}

test "truecolor sequences do not read as a reset" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // `38;2;r;g;b` contains a literal 0 parameter; treating it as SGR 0 would
    // wrongly mark the line closed and diff a frame that bleeds colour.
    _ = try h.render("\x1b[38;2;255;0;0mred\nsecond", size_80x24);
    const out = try h.render("\x1b[38;2;255;0;0mred\nSECOND", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
}

test "invalidate forces a repaint of an unchanged view" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("stable\nframe", size_80x24);
    try testing.expectEqual(@as(usize, 0), (try h.render("stable\nframe", size_80x24)).len);

    h.renderer.invalidate();
    try testing.expect(h.renderer.needsRepaint());

    const out = try h.render("stable\nframe", size_80x24);
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
    try testing.expect(!h.renderer.needsRepaint());
}

test "full mode always rewrites every line" {
    var h = Harness.init(.full);
    defer h.deinit();

    _ = try h.render("alpha\nbeta\ngamma", size_80x24);
    const out = try h.render("alpha\nBETA\ngamma", size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") != null);
    try testing.expect(std.mem.indexOf(u8, out, "alpha") != null);
    try testing.expect(std.mem.indexOf(u8, out, "gamma") != null);
}

test "every frame is wrapped in synchronized output" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const first = try h.render("a\nb", size_80x24);
    try testing.expectEqual(@as(usize, 1), countOccurrences(first, "\x1b[?2026h"));
    try testing.expectEqual(@as(usize, 1), countOccurrences(first, "\x1b[?2026l"));

    const second = try h.render("a\nc", size_80x24);
    try testing.expectEqual(@as(usize, 1), countOccurrences(second, "\x1b[?2026h"));
    try testing.expectEqual(@as(usize, 1), countOccurrences(second, "\x1b[?2026l"));
}

test "wide characters are measured by display width, not bytes" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // Four double-width characters occupy eight columns: they fit in ten, and
    // the frame stays diffable.
    const narrow = Size{ .width = 10, .height = 4 };
    _ = try h.render("日本語だ\nplain", narrow);
    const out = try h.render("日本語だ\nPLAIN", narrow);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[1;1H") == null);
}

test "empty view is handled" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("", size_80x24);
    _ = try h.render("content", size_80x24);
    _ = try h.render("", size_80x24);

    try h.expectScreen("");
}
