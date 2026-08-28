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
///
/// The model counts display columns rather than bytes, and it reproduces the
/// two behaviours the renderer has to draw around:
///
///   * autowrap — a character written to the last column parks the cursor on
///     that column with the wrap deferred, instead of moving it off the row;
///   * `EL` erases from the column the cursor occupies, which in that parked
///     state is the column holding the character just written.
///
/// Both matter: without them a frame drawn to the full width of the screen
/// models perfectly and still loses its right-hand column on a real terminal.
const VirtualScreen = struct {
    const max_rows = 32;
    const max_cols = 128;

    /// One display column. A double-width character owns two of them: the
    /// first carries its bytes, the second is a continuation.
    const Cell = struct {
        bytes: [4]u8 = .{ ' ', 0, 0, 0 },
        len: u8 = 1,
        continuation: bool = false,

        fn isBlank(self: Cell) bool {
            return !self.continuation and self.len == 1 and self.bytes[0] == ' ';
        }
    };

    cells: [max_rows][max_cols]Cell,
    width: usize = max_cols,
    height: usize = max_rows,
    used: usize = 0,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    /// Set once the last column is filled and the wrap is deferred.
    wrap_pending: bool = false,

    fn init() VirtualScreen {
        const blank_row = [_]Cell{.{}} ** max_cols;
        return .{ .cells = [_][max_cols]Cell{blank_row} ** max_rows };
    }

    /// A reported size of zero means the terminal never told anyone how big it
    /// is; model a screen wide enough that nothing wraps, which is the same
    /// assumption the renderer falls back on.
    fn resize(self: *VirtualScreen, size: Size) void {
        self.width = if (size.width == 0) max_cols else @min(size.width, max_cols);
        self.height = if (size.height == 0) max_rows else @min(size.height, max_rows);
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
                self.wrap_pending = false;
                i += 1;
                continue;
            }
            if (c == '\n') {
                self.cursor_row += 1;
                self.wrap_pending = false;
                i += 1;
                continue;
            }

            // One character, however many bytes and columns it occupies.
            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch 1;
            const take = @min(byte_len, output.len - i);
            const bytes = output[i..][0..take];
            const cols = if (std.unicode.utf8Decode(bytes)) |cp|
                zz.unicode.charWidth(cp)
            else |_|
                1;
            try self.put(bytes, cols);
            i += take;
        }
    }

    /// Write one character at the cursor and advance past it.
    fn put(self: *VirtualScreen, bytes: []const u8, cols: usize) !void {
        if (cols == 0) return; // A combining mark claims no column of its own.

        if (self.wrap_pending) {
            self.cursor_row += 1;
            self.cursor_col = 0;
            self.wrap_pending = false;
        }
        // A double-width character that would straddle the edge wraps whole.
        if (self.cursor_col + cols > self.width) {
            self.cursor_row += 1;
            self.cursor_col = 0;
        }

        try testing.expect(self.cursor_row < max_rows);

        const row = &self.cells[self.cursor_row];
        row[self.cursor_col] = .{ .bytes = .{ 0, 0, 0, 0 }, .len = @intCast(bytes.len) };
        @memcpy(row[self.cursor_col].bytes[0..bytes.len], bytes);
        for (1..cols) |k| row[self.cursor_col + k] = .{ .len = 0, .continuation = true };

        self.used = @max(self.used, self.cursor_row + 1);

        self.cursor_col += cols;
        if (self.cursor_col >= self.width) {
            // The cursor stays on the last column; the wrap waits for the next
            // character, and may never happen.
            self.cursor_col = self.width - 1;
            self.wrap_pending = true;
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
                var row: usize = 1;
                var col: usize = 1;
                if (params.len > 0) {
                    var it = std.mem.splitScalar(u8, params, ';');
                    row = try std.fmt.parseInt(usize, it.next().?, 10);
                    col = try std.fmt.parseInt(usize, it.next() orelse "1", 10);
                }
                // `CUP` clamps to the screen. It never scrolls, which is the
                // whole reason the renderer addresses rows this way.
                self.cursor_row = @min(row -| 1, self.height - 1);
                self.cursor_col = @min(col -| 1, self.width - 1);
                self.wrap_pending = false;
                self.used = @max(self.used, self.cursor_row + 1);
            },
            'K' => {
                // Deliberately leaves `wrap_pending` set: erasing from a
                // parked cursor is precisely the case being modelled, and it
                // takes the character under the cursor with it.
                const from = if (std.mem.eql(u8, params, "2")) 0 else self.cursor_col;
                for (self.cells[self.cursor_row][from..self.width]) |*cell| cell.* = .{};
                self.used = @max(self.used, self.cursor_row + 1);
            },
            // Style and synchronized-output sequences do not move the cursor
            // or change cell contents.
            else => {},
        }

        return consumed;
    }

    /// Columns up to and including the last non-blank one.
    fn rowWidth(self: *const VirtualScreen, row: usize) usize {
        var end: usize = 0;
        for (self.cells[row][0..self.width], 0..) |cell, col| {
            if (!cell.isBlank()) end = col + 1;
        }
        return end;
    }

    /// Visible content, trailing blanks trimmed, as a newline-joined string.
    fn text(self: *const VirtualScreen, out: *std.array_list.Managed(u8)) !void {
        out.clearRetainingCapacity();

        var last: usize = 0;
        for (0..@min(self.used, self.height)) |row| {
            if (self.rowWidth(row) > 0) last = row + 1;
        }

        for (0..last) |row| {
            if (row > 0) try out.append('\n');
            for (self.cells[row][0..self.rowWidth(row)]) |cell| {
                if (cell.continuation) continue;
                try out.appendSlice(cell.bytes[0..cell.len]);
            }
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
        self.screen.resize(size);
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

/// A full repaint rewrites every row of the frame; the diff path only touches
/// rows whose content changed. Whether a row that did *not* change was written
/// is what tells the two apart.
///
/// The leading cursor address does not: `writeDiff` emits `CSI 1;1H` too,
/// whenever row 0 happens to be the row that changed. Asserting on it would
/// pass for a diff that touched the top row.
fn expectRepainted(out: []const u8, unchanged_row: []const u8) !void {
    if (std.mem.indexOf(u8, out, unchanged_row) == null) {
        std.debug.print("expected a full repaint to rewrite '{s}'\n", .{unchanged_row});
        return error.TestExpectedFullRepaint;
    }
}

fn expectDiffed(out: []const u8, unchanged_row: []const u8) !void {
    if (std.mem.indexOf(u8, out, unchanged_row) != null) {
        std.debug.print("expected a diff to leave '{s}' alone\n", .{unchanged_row});
        return error.TestExpectedDiff;
    }
}

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

    for ([_][]const u8{ "alpha", "beta", "gamma" }) |row| try expectRepainted(out, row);
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

    // Wrapping shifts every row below it, so the frame can no longer be
    // addressed by row: row 0 is rewritten even though it did not change.
    try expectRepainted(out, "short");
}

test "a frame taller than the terminal falls back to a full repaint" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const short = Size{ .width = 80, .height = 3 };
    _ = try h.render("top\nmid\nbot", short);

    const out = try h.render("top\nmid\nbot\nextra", short);
    try expectRepainted(out, "top");

    // The frame does not fit, so the one after it cannot be diffed either.
    const next = try h.render("top\nmid\nbot\nother", short);
    try expectRepainted(next, "top");
}

test "a style left open disables diffing for the following frame" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // The background colour on the first line bleeds onto the second, so the
    // second cannot be repainted on its own.
    _ = try h.render("\x1b[41mred background\nstill red", size_80x24);
    const out = try h.render("\x1b[41mred background\nSTILL RED", size_80x24);

    try expectRepainted(out, "red background");
}

test "styles closed per line still diff" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("\x1b[31mred\x1b[0m\n\x1b[1mbold\x1b[0m plain", size_80x24);
    const out = try h.render("\x1b[31mred\x1b[0m\n\x1b[1mbold\x1b[0m PLAIN", size_80x24);

    try expectDiffed(out, "\x1b[31mred");
    try testing.expect(std.mem.indexOf(u8, out, "PLAIN") != null);
}

test "truecolor sequences do not read as a reset" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // `38;2;r;g;b` contains a literal 0 parameter; treating it as SGR 0 would
    // wrongly mark the line closed and diff a frame that bleeds colour.
    _ = try h.render("\x1b[38;2;255;0;0mred\nsecond", size_80x24);
    const out = try h.render("\x1b[38;2;255;0;0mred\nSECOND", size_80x24);

    try expectRepainted(out, "\x1b[38;2;255;0;0mred");
}

test "invalidate forces a repaint of an unchanged view" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("stable\nframe", size_80x24);
    try testing.expectEqual(@as(usize, 0), (try h.render("stable\nframe", size_80x24)).len);

    h.renderer.invalidate();
    try testing.expect(h.renderer.needsRepaint());

    const out = try h.render("stable\nframe", size_80x24);
    try expectRepainted(out, "stable");
    try testing.expect(!h.renderer.needsRepaint());
}

test "full mode always rewrites every line" {
    var h = Harness.init(.full);
    defer h.deinit();

    _ = try h.render("alpha\nbeta\ngamma", size_80x24);
    const out = try h.render("alpha\nBETA\ngamma", size_80x24);

    try expectRepainted(out, "alpha");
    try expectRepainted(out, "gamma");
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

    try expectDiffed(out, "日本語だ");
}

test "a frame that fills the width keeps its last column" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // The right border sits on the last column, so the cursor is parked there
    // with its wrap deferred. `EL` erases from the parked column and would
    // take the border with it.
    const exact = Size{ .width = 5, .height = 4 };
    _ = try h.render("┌───┐\n│ a │\n└───┘", exact);
    try h.expectScreen("┌───┐\n│ a │\n└───┘");

    // And again down the diff path, which repaints the middle row alone.
    _ = try h.render("┌───┐\n│ b │\n└───┘", exact);
    try h.expectScreen("┌───┐\n│ b │\n└───┘");
}

test "a full-width line is not followed by an erase" {
    var h = Harness.init(.diff);
    defer h.deinit();

    const out = try h.render("abcde\nxy", Size{ .width = 5, .height = 4 });

    try testing.expect(std.mem.indexOf(u8, out, "abcde\x1b[K") == null);
    // A line with room to spare still gets one.
    try testing.expect(std.mem.indexOf(u8, out, "xy\x1b[K") != null);
}

test "a wrapped line that ends on a row edge keeps its last column" {
    var h = Harness.init(.full);
    defer h.deinit();

    // Ten columns of text on a five-column screen wraps onto a second row and
    // fills that one exactly, parking the cursor on the edge a second time.
    // Landing there is a question of width modulo the row, not of fitting.
    _ = try h.render("abcdefghij", Size{ .width = 5, .height = 4 });
    try h.expectScreen("abcde\nfghij");
}

test "a frame taller than the terminal is truncated, not smeared" {
    var h = Harness.init(.full);
    defer h.deinit();

    const short = Size{ .width = 10, .height = 3 };
    const out = try h.render("a\nb\nc\nd\ne\nf", short);

    // Addressing row 4 would clamp onto row 3, so each overflow line would
    // overwrite the one before it and the bottom row would end up showing the
    // last line of the frame rather than the third.
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[4;1H") == null);
    try h.expectScreen("a\nb\nc");
}

test "a view with more rows than a cursor address can hold does not overflow" {
    var h = Harness.init(.full);
    defer h.deinit();

    var view = std.array_list.Managed(u8).init(testing.allocator);
    defer view.deinit();
    for (0..70_000) |_| try view.appendSlice("x\n");

    // The row of a `CUP` sequence is a u16 and this view has more lines than
    // one can count, so every row past the bottom has to be dropped before it
    // reaches the sequence.
    const out = try h.render(view.items, size_80x24);

    try testing.expect(std.mem.indexOf(u8, out, "\x1b[24;1H") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\x1b[25;1H") == null);
}

test "an unknown terminal width still erases stale text" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // `TIOCGWINSZ` reports 0x0 for a terminal whose window size was never set.
    // Nothing can be concluded about which lines fill a row, so every line is
    // erased rather than none of them.
    const unknown = Size{ .width = 0, .height = 0 };
    _ = try h.render("stale-long-content\nsecond", unknown);
    _ = try h.render("x\ny", unknown);

    try h.expectScreen("x\ny");
}

test "no frame is ever written with a newline" {
    var h = Harness.init(.diff);
    defer h.deinit();

    // A newline on the bottom row scrolls the screen, which shifts every row
    // of the frame up by one and leaves the diff path addressing the wrong
    // rows from then on.
    const short = Size{ .width = 10, .height = 3 };
    for ([_][]const u8{ "a\nb\nc", "a\nB\nc", "a", "a\nb\nc\nd", "" }) |view| {
        const out = try h.render(view, short);
        try testing.expect(std.mem.indexOfScalar(u8, out, '\n') == null);
        try testing.expect(std.mem.indexOfScalar(u8, out, '\r') == null);
    }
}

test "empty view is handled" {
    var h = Harness.init(.diff);
    defer h.deinit();

    _ = try h.render("", size_80x24);
    _ = try h.render("content", size_80x24);
    _ = try h.render("", size_80x24);

    try h.expectScreen("");
}
