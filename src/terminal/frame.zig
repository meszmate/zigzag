//! Frame rendering: turns the string a `view` returns into terminal output.
//!
//! The straightforward approach — home the cursor and rewrite every line — is
//! robust but costs a screenful of output for a one-character change, which is
//! exactly what an animated spinner asks for ten times a second. `.diff`
//! compares the frame against the one before it and touches only the lines
//! that actually differ.

const std = @import("std");
const Writer = std.Io.Writer;
const ansi = @import("ansi.zig");
const measure = @import("../layout/measure.zig");

/// How a new frame is pushed to the terminal.
pub const Mode = enum {
    /// Rewrite every line of the frame whenever the view changes.
    full,
    /// Rewrite only the lines that differ from the previous frame, falling
    /// back to `full` whenever the screen cannot be addressed by row.
    diff,
};

/// Terminal dimensions the frame is rendered against.
pub const Size = struct {
    width: u16,
    height: u16,
};

/// Stateful renderer: owns the previous frame so it can be diffed against.
pub const Renderer = struct {
    mode: Mode,
    previous: std.array_list.Managed(u8),
    last_line_count: usize = 0,
    last_hash: u64 = 0,
    /// Set when the screen no longer matches `previous` — before the first
    /// frame, and after anything that wrote outside the renderer's control
    /// (resize, suspend, `println`, an inline image).
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Renderer {
        return .{
            .mode = mode,
            .previous = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.previous.deinit();
    }

    /// Repaint the next frame in full, even if the view has not changed.
    pub fn invalidate(self: *Renderer) void {
        self.dirty = true;
    }

    /// Whether the next `render` will produce output regardless of the view.
    pub fn needsRepaint(self: *const Renderer) bool {
        return self.dirty;
    }

    /// Write `view` to `writer`, returning true when anything was emitted.
    ///
    /// The caller still owns flushing; nothing here writes to the terminal
    /// directly.
    pub fn render(self: *Renderer, writer: *Writer, view: []const u8, size: Size) !bool {
        const hash = std.hash.Wyhash.hash(0, view);
        if (!self.dirty and hash == self.last_hash) return false;

        // Only the diff path cares what the frame looks like.
        const shape: Shape = if (self.mode == .diff)
            scan(view, size)
        else
            .{ .addressable = true, .styles_closed = true };

        const use_diff = self.mode == .diff and
            !self.dirty and
            self.previous.items.len > 0 and
            shape.addressable and
            shape.styles_closed;

        // Synchronized output keeps terminals that support it from showing a
        // half-drawn frame.
        try writer.writeAll(ansi.sync_start);
        const line_count = if (use_diff)
            try self.writeDiff(writer, view, size)
        else
            try self.writeFull(writer, view, size);
        try writer.writeAll(ansi.sync_end);

        self.remember(view, line_count, hash);

        // A frame that wrapped, scrolled, or left a style open no longer maps
        // cleanly onto rows, so the frame after it starts from scratch.
        if (!shape.addressable or !shape.styles_closed) self.dirty = true;

        return true;
    }

    fn remember(self: *Renderer, view: []const u8, line_count: usize, hash: u64) void {
        self.last_line_count = line_count;
        self.last_hash = hash;

        self.previous.clearRetainingCapacity();
        self.previous.appendSlice(view) catch {
            // Without a copy of what is on screen there is nothing to diff
            // against; fall back to a full repaint rather than guessing.
            self.previous.clearRetainingCapacity();
            self.dirty = true;
            return;
        };
        self.dirty = false;
    }

    /// Rewrite the whole frame, addressing every row absolutely.
    ///
    /// Absolute addressing rather than `\r\n` between lines: a newline on the
    /// bottom row scrolls the screen, which silently shifts every row of the
    /// frame up by one and leaves the diff path writing to the wrong rows from
    /// then on.
    fn writeFull(self: *Renderer, writer: *Writer, view: []const u8, size: Size) !usize {
        const max_row = addressableRows(size);

        var lines = std.mem.splitScalar(u8, view, '\n');
        var line_count: usize = 0;
        while (lines.next()) |line| {
            defer line_count += 1;
            // A row past the bottom cannot be addressed — the terminal clamps
            // the cursor to the last row, so every line beyond it would land
            // on top of the one before. Count them so `last_line_count` still
            // describes the frame, but do not draw them.
            if (line_count >= max_row) continue;

            try ansi.cursorTo0(writer, @intCast(line_count), 0);
            try writer.writeAll(line);
            if (!fillsRow(line, size)) try writer.writeAll(ansi.line_clear_right);
        }

        // Clear the rows the previous frame used and this one does not.
        var row = line_count;
        while (row < self.last_line_count and row < max_row) : (row += 1) {
            try ansi.cursorTo0(writer, @intCast(row), 0);
            try writer.writeAll(ansi.line_clear);
        }

        return line_count;
    }

    /// Rewrite only the rows whose content changed.
    fn writeDiff(self: *Renderer, writer: *Writer, view: []const u8, size: Size) !usize {
        var new_lines = std.mem.splitScalar(u8, view, '\n');
        var old_lines = std.mem.splitScalar(u8, self.previous.items, '\n');

        var line_count: usize = 0;
        var last_line: []const u8 = "";
        while (new_lines.next()) |line| {
            const row: u16 = @intCast(line_count);
            line_count += 1;
            last_line = line;

            // A row the previous frame never reached is blank on screen, so it
            // always has to be written.
            if (old_lines.next()) |old_line| {
                if (std.mem.eql(u8, old_line, line)) continue;
            }

            try ansi.cursorTo0(writer, row, 0);
            try writer.writeAll(line);
            if (!fillsRow(line, size)) try writer.writeAll(ansi.line_clear_right);
        }

        // Clear the rows the previous frame used and this one does not.
        var row = line_count;
        while (row < self.last_line_count and row < addressableRows(size)) : (row += 1) {
            try ansi.cursorTo0(writer, @intCast(row), 0);
            try writer.writeAll(ansi.line_clear);
        }

        // Leave the cursor where a full repaint would have left it, so
        // anything drawn relative to it — a visible cursor, a `.cursor`-placed
        // image — does not depend on which path ran. Clearing trailing rows
        // already ends on the last of them, which is where a full repaint
        // finishes too.
        if (row == line_count) {
            const col = @min(measure.width(last_line), size.width);
            try ansi.cursorTo0(writer, @intCast(line_count -| 1), @intCast(col));
        }

        return line_count;
    }
};

/// How many rows can be addressed with `CUP`, which carries a `u16` row.
///
/// A height of zero means the size is not known — `TIOCGWINSZ` reports it that
/// way on a terminal whose window size has never been set. Fall back to the
/// widest row the sequence can express so an oversized view cannot overflow
/// the row counter.
fn addressableRows(size: Size) usize {
    return if (size.height > 0) size.height else std.math.maxInt(u16);
}

/// Whether writing `line` leaves the cursor parked at the far edge of a row.
///
/// A terminal that has just filled the last column keeps the cursor on it with
/// the wrap deferred until the next character arrives. `EL` erases from the
/// column the cursor sits on, so issuing it in that state destroys the
/// character that was just written — the right-hand border of a frame drawn to
/// the full width of the screen. Nothing follows such a line on its row, so
/// the erase is skipped rather than fixed up.
///
/// A line long enough to wrap lands on the edge whenever its width is an exact
/// multiple of the row width, not only when it fills a single row.
fn fillsRow(line: []const u8, size: Size) bool {
    // Size unknown: erase, because leaving stale text on screen is the worse
    // of the two failures.
    if (size.width == 0) return false;

    const w = measure.width(line);
    return w > 0 and w % size.width == 0;
}

/// What a frame looks like on screen, as far as the diff path cares.
const Shape = struct {
    /// Every line fits on one row and the frame fits on screen, so row `n` of
    /// the frame really is row `n` of the terminal.
    addressable: bool,
    /// No line leaves a style or hyperlink open. Lines that inherit styling
    /// from the line above them cannot be repainted independently.
    styles_closed: bool,
};

fn scan(view: []const u8, size: Size) Shape {
    var addressable = size.width > 0 and size.height > 0;
    var styles_closed = true;

    var lines = std.mem.splitScalar(u8, view, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        count += 1;
        if (addressable and (count > size.height or measure.width(line) > size.width)) {
            addressable = false;
        }
        if (styles_closed and leavesStyleOpen(line)) styles_closed = false;
        if (!addressable and !styles_closed) break;
    }

    return .{ .addressable = addressable, .styles_closed = styles_closed };
}

/// One bit per aspect of the SGR state a line can leave switched on.
const Attr = struct {
    const fg: u16 = 1 << 0;
    const bg: u16 = 1 << 1;
    const underline_color: u16 = 1 << 2;
    const bold_dim: u16 = 1 << 3;
    const italic: u16 = 1 << 4;
    const underline: u16 = 1 << 5;
    const blink: u16 = 1 << 6;
    const reverse: u16 = 1 << 7;
    const hidden: u16 = 1 << 8;
    const strike: u16 = 1 << 9;
    /// Anything unrecognised, tracked so it errs towards a full repaint.
    const other: u16 = 1 << 10;
};

/// Whether `line` ends with an SGR attribute or a hyperlink still in effect.
///
/// Such a line changes how the lines below it are drawn, so those lines cannot
/// be repainted on their own.
fn leavesStyleOpen(line: []const u8) bool {
    var active: u16 = 0;
    var link_open = false;

    var i: usize = 0;
    while (i < line.len) {
        if (line[i] != 0x1b or i + 1 >= line.len) {
            i += 1;
            continue;
        }

        switch (line[i + 1]) {
            '[' => {
                const params_start = i + 2;
                var end = params_start;
                while (end < line.len and line[end] >= 0x20 and line[end] <= 0x3f) : (end += 1) {}
                if (end >= line.len) break; // truncated sequence
                if (line[end] == 'm') active = applySgr(line[params_start..end], active);
                i = end + 1;
            },
            ']' => {
                const payload_start = i + 2;
                var end = payload_start;
                while (end < line.len and line[end] != 0x07 and line[end] != 0x1b) : (end += 1) {}

                // OSC 8 ; params ; URI opens a hyperlink; an empty URI closes it.
                const payload = line[payload_start..end];
                if (std.mem.startsWith(u8, payload, "8;")) {
                    const uri_start = (std.mem.indexOfScalarPos(u8, payload, 2, ';') orelse
                        payload.len -| 1) + 1;
                    link_open = uri_start < payload.len;
                }

                i = if (end >= line.len)
                    line.len
                else if (line[end] == 0x07)
                    end + 1
                else
                    end + 2; // ST
            },
            else => i += 2,
        }
    }

    return active != 0 or link_open;
}

/// Fold one `CSI ... m` sequence into the running attribute set.
fn applySgr(params: []const u8, current: u16) u16 {
    // `CSI m` with no parameters means `CSI 0m`.
    if (params.len == 0) return 0;

    var state = current;
    var it = std.mem.splitScalar(u8, params, ';');
    while (it.next()) |param| {
        // A colon introduces sub-parameters that refine the code before it.
        const colon = std.mem.indexOfScalar(u8, param, ':');
        const head = if (colon) |c| param[0..c] else param;
        const code = std.fmt.parseInt(u16, head, 10) catch {
            state |= Attr.other;
            continue;
        };

        switch (code) {
            0 => state = 0,
            1, 2 => state |= Attr.bold_dim,
            3 => state |= Attr.italic,
            4, 21 => state |= Attr.underline,
            5, 6 => state |= Attr.blink,
            7 => state |= Attr.reverse,
            8 => state |= Attr.hidden,
            9 => state |= Attr.strike,
            22 => state &= ~Attr.bold_dim,
            23 => state &= ~Attr.italic,
            24 => state &= ~Attr.underline,
            25 => state &= ~Attr.blink,
            27 => state &= ~Attr.reverse,
            28 => state &= ~Attr.hidden,
            29 => state &= ~Attr.strike,
            30...37, 90...97 => state |= Attr.fg,
            39 => state &= ~Attr.fg,
            40...47, 100...107 => state |= Attr.bg,
            49 => state &= ~Attr.bg,
            59 => state &= ~Attr.underline_color,
            38, 48, 58 => {
                state |= switch (code) {
                    38 => Attr.fg,
                    48 => Attr.bg,
                    else => Attr.underline_color,
                };
                // The colon form packs its arguments into this parameter; the
                // semicolon form spreads them across the ones that follow, and
                // those must not be read as codes of their own.
                if (colon != null) continue;
                const kind = it.next() orelse break;
                const arg_count: usize = if (std.mem.eql(u8, kind, "2"))
                    3 // r;g;b
                else if (std.mem.eql(u8, kind, "5"))
                    1 // palette index
                else
                    0;
                for (0..arg_count) |_| {
                    _ = it.next() orelse break;
                }
            },
            else => state |= Attr.other,
        }
    }

    return state;
}

test "leavesStyleOpen: plain text closes nothing" {
    try std.testing.expect(!leavesStyleOpen(""));
    try std.testing.expect(!leavesStyleOpen("just text"));
}

test "leavesStyleOpen: a reset closes the line" {
    try std.testing.expect(!leavesStyleOpen("\x1b[31mred\x1b[0m"));
    try std.testing.expect(!leavesStyleOpen("\x1b[1;4;31mfancy\x1b[m tail"));
    try std.testing.expect(!leavesStyleOpen("\x1b[38;2;255;0;0mred\x1b[0m"));
}

test "leavesStyleOpen: an unclosed attribute leaves the line open" {
    try std.testing.expect(leavesStyleOpen("\x1b[31mred"));
    try std.testing.expect(leavesStyleOpen("\x1b[41mbackground"));
    try std.testing.expect(leavesStyleOpen("\x1b[1mbold\x1b[0m\x1b[4munderline"));
}

test "leavesStyleOpen: extended colour arguments are not read as codes" {
    // The trailing `0` parameters here belong to the colour, not to SGR 0.
    try std.testing.expect(leavesStyleOpen("\x1b[38;2;255;0;0mred"));
    try std.testing.expect(leavesStyleOpen("\x1b[48;5;0mblack background"));
    try std.testing.expect(leavesStyleOpen("\x1b[38:2::255:0:0mcolon form"));
}

test "leavesStyleOpen: attributes turned off individually" {
    try std.testing.expect(!leavesStyleOpen("\x1b[1mbold\x1b[22m"));
    try std.testing.expect(!leavesStyleOpen("\x1b[31mred\x1b[39m"));
    try std.testing.expect(!leavesStyleOpen("\x1b[41mbg\x1b[49m"));
    try std.testing.expect(leavesStyleOpen("\x1b[1;31mboth\x1b[22m"));
}

test "leavesStyleOpen: non-SGR sequences are ignored" {
    try std.testing.expect(!leavesStyleOpen("\x1b[2Ktext"));
    try std.testing.expect(!leavesStyleOpen("\x1b[10;5Htext"));
}

test "leavesStyleOpen: hyperlinks" {
    try std.testing.expect(leavesStyleOpen("\x1b]8;;https://example.com\x07link text"));
    try std.testing.expect(!leavesStyleOpen("\x1b]8;;https://example.com\x07link\x1b]8;;\x07"));
    try std.testing.expect(!leavesStyleOpen("\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\"));
}

test "fillsRow: a line that ends on the row edge" {
    const size = Size{ .width = 5, .height = 4 };

    try std.testing.expect(!fillsRow("", size));
    try std.testing.expect(!fillsRow("abc", size));
    try std.testing.expect(fillsRow("abcde", size));

    // A line long enough to wrap comes back to the edge at every multiple of
    // the row width, not only on the first row it fills.
    try std.testing.expect(!fillsRow("abcdefgh", size));
    try std.testing.expect(fillsRow("abcdefghij", size));

    // Escape sequences occupy no columns; double-width characters occupy two.
    try std.testing.expect(fillsRow("\x1b[31mabcde\x1b[0m", size));
    try std.testing.expect(!fillsRow("日本", size));
    try std.testing.expect(fillsRow("日本語だよ", size));

    // An unknown width cannot rule the erase out.
    try std.testing.expect(!fillsRow("abcde", .{ .width = 0, .height = 0 }));
}

test "addressableRows: an unknown height falls back to the sequence limit" {
    try std.testing.expectEqual(@as(usize, 24), addressableRows(.{ .width = 80, .height = 24 }));
    try std.testing.expectEqual(
        @as(usize, std.math.maxInt(u16)),
        addressableRows(.{ .width = 80, .height = 0 }),
    );
}

test "scan: frame geometry" {
    const size = Size{ .width = 10, .height = 3 };

    try std.testing.expect(scan("abc\ndef", size).addressable);
    try std.testing.expect(!scan("abc\ndef\nghi\njkl", size).addressable);
    try std.testing.expect(!scan("this line is too wide", size).addressable);
    // Escape sequences do not count towards the visible width.
    try std.testing.expect(scan("\x1b[31mabc\x1b[0m", size).addressable);
    // Double-width characters do.
    try std.testing.expect(scan("日本語だ", size).addressable);
    try std.testing.expect(!scan("日本語だよね", size).addressable);
}
