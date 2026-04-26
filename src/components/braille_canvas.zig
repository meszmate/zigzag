//! Braille canvas with direct pixel-grid API.
//!
//! Each terminal cell holds 2x4 sub-cell "pixels" via Unicode braille
//! characters (U+2800..U+28FF). Pixel coordinates use (px, py) with origin at
//! top-left; cell coordinates use (col, row).
//!
//! For chart-style data plotting, see `Canvas`. This component is intended
//! for raw pixel work — world maps, scopes, simple bitmaps — where the
//! caller already knows pixel coordinates.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const Style = style_mod.Style;

const BRAILLE_BASE: u21 = 0x2800;

/// Bit position within a braille cell for each (sub_x, sub_y) coordinate.
/// Layout matches Unicode braille:
///   0 3
///   1 4
///   2 5
///   6 7
const BRAILLE_BITS = [4][2]u8{
    .{ 0x01, 0x08 },
    .{ 0x02, 0x10 },
    .{ 0x04, 0x20 },
    .{ 0x40, 0x80 },
};

const BrailleCell = struct {
    bits: u8 = 0,
    style: ?Style = null,
};

const TextOverlay = struct {
    col: u16,
    row: u16,
    text: []const u8,
    style: Style,
};

pub const BrailleCanvas = struct {
    allocator: std.mem.Allocator,
    /// Cell width (each cell = 2 pixels wide).
    cell_width: u16,
    /// Cell height (each cell = 4 pixels tall).
    cell_height: u16,

    cells: []BrailleCell,
    overlays: std.array_list.Managed(TextOverlay),
    text_arena: std.heap.ArenaAllocator,

    default_style: Style,
    background_glyph: []const u8,

    pub fn init(allocator: std.mem.Allocator, cell_width: u16, cell_height: u16) !BrailleCanvas {
        const w = @max(@as(u16, 1), cell_width);
        const h = @max(@as(u16, 1), cell_height);
        const cells = try allocator.alloc(BrailleCell, @as(usize, w) * @as(usize, h));
        for (cells) |*c| c.* = .{};

        var inline_style = Style{};
        inline_style = inline_style.inline_style(true);

        return .{
            .allocator = allocator,
            .cell_width = w,
            .cell_height = h,
            .cells = cells,
            .overlays = std.array_list.Managed(TextOverlay).init(allocator),
            .text_arena = std.heap.ArenaAllocator.init(allocator),
            .default_style = inline_style,
            .background_glyph = " ",
        };
    }

    pub fn deinit(self: *BrailleCanvas) void {
        self.allocator.free(self.cells);
        self.overlays.deinit();
        self.text_arena.deinit();
    }

    pub fn setSize(self: *BrailleCanvas, cell_width: u16, cell_height: u16) !void {
        const w = @max(@as(u16, 1), cell_width);
        const h = @max(@as(u16, 1), cell_height);
        if (w == self.cell_width and h == self.cell_height) {
            self.clear();
            return;
        }
        self.allocator.free(self.cells);
        self.cells = try self.allocator.alloc(BrailleCell, @as(usize, w) * @as(usize, h));
        for (self.cells) |*c| c.* = .{};
        self.cell_width = w;
        self.cell_height = h;
        self.overlays.clearRetainingCapacity();
        _ = self.text_arena.reset(.retain_capacity);
    }

    pub fn setStyle(self: *BrailleCanvas, style: Style) void {
        var s = style;
        s = s.inline_style(true);
        self.default_style = s;
    }

    pub fn setBackground(self: *BrailleCanvas, glyph: []const u8) void {
        self.background_glyph = glyph;
    }

    /// Pixel grid dimensions.
    pub fn pixelWidth(self: *const BrailleCanvas) u16 {
        return self.cell_width *| 2;
    }
    pub fn pixelHeight(self: *const BrailleCanvas) u16 {
        return self.cell_height *| 4;
    }

    pub fn clear(self: *BrailleCanvas) void {
        for (self.cells) |*c| c.* = .{};
        self.overlays.clearRetainingCapacity();
        _ = self.text_arena.reset(.retain_capacity);
    }

    pub fn setPixel(self: *BrailleCanvas, px: i32, py: i32) void {
        self.setPixelStyled(px, py, self.default_style);
    }

    pub fn setPixelStyled(self: *BrailleCanvas, px: i32, py: i32, style: Style) void {
        if (px < 0 or py < 0) return;
        const upx: u32 = @intCast(px);
        const upy: u32 = @intCast(py);
        if (upx >= self.pixelWidth() or upy >= self.pixelHeight()) return;

        const col: usize = upx / 2;
        const row: usize = upy / 4;
        const sx: usize = upx % 2;
        const sy: usize = upy % 4;

        const idx = row * self.cell_width + col;
        var cell = &self.cells[idx];
        cell.bits |= BRAILLE_BITS[sy][sx];
        var s = style;
        s = s.inline_style(true);
        cell.style = s;
    }

    pub fn clearPixel(self: *BrailleCanvas, px: i32, py: i32) void {
        if (px < 0 or py < 0) return;
        const upx: u32 = @intCast(px);
        const upy: u32 = @intCast(py);
        if (upx >= self.pixelWidth() or upy >= self.pixelHeight()) return;

        const col: usize = upx / 2;
        const row: usize = upy / 4;
        const sx: usize = upx % 2;
        const sy: usize = upy % 4;

        const idx = row * self.cell_width + col;
        var cell = &self.cells[idx];
        cell.bits &= ~BRAILLE_BITS[sy][sx];
        if (cell.bits == 0) cell.style = null;
    }

    pub fn togglePixel(self: *BrailleCanvas, px: i32, py: i32) void {
        if (self.isPixelSet(px, py)) {
            self.clearPixel(px, py);
        } else {
            self.setPixel(px, py);
        }
    }

    pub fn isPixelSet(self: *const BrailleCanvas, px: i32, py: i32) bool {
        if (px < 0 or py < 0) return false;
        const upx: u32 = @intCast(px);
        const upy: u32 = @intCast(py);
        if (upx >= self.pixelWidth() or upy >= self.pixelHeight()) return false;
        const col: usize = upx / 2;
        const row: usize = upy / 4;
        const sx: usize = upx % 2;
        const sy: usize = upy % 4;
        const idx = row * self.cell_width + col;
        return (self.cells[idx].bits & BRAILLE_BITS[sy][sx]) != 0;
    }

    pub fn drawLine(self: *BrailleCanvas, x0: i32, y0: i32, x1: i32, y1: i32) void {
        self.drawLineStyled(x0, y0, x1, y1, self.default_style);
    }

    pub fn drawLineStyled(self: *BrailleCanvas, x0: i32, y0: i32, x1: i32, y1: i32, style: Style) void {
        // Bresenham.
        var x = x0;
        var y = y0;
        const dx = @as(i32, @intCast(@abs(x1 - x0)));
        const dy = -@as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;
        while (true) {
            self.setPixelStyled(x, y, style);
            if (x == x1 and y == y1) break;
            const e2 = err * 2;
            if (e2 >= dy) {
                if (x == x1) break;
                err += dy;
                x += sx;
            }
            if (e2 <= dx) {
                if (y == y1) break;
                err += dx;
                y += sy;
            }
        }
    }

    pub fn drawRect(self: *BrailleCanvas, x0: i32, y0: i32, x1: i32, y1: i32, filled: bool) void {
        self.drawRectStyled(x0, y0, x1, y1, filled, self.default_style);
    }

    pub fn drawRectStyled(self: *BrailleCanvas, x0: i32, y0: i32, x1: i32, y1: i32, filled: bool, style: Style) void {
        const lx = @min(x0, x1);
        const hx = @max(x0, x1);
        const ly = @min(y0, y1);
        const hy = @max(y0, y1);
        if (filled) {
            var y = ly;
            while (y <= hy) : (y += 1) {
                var x = lx;
                while (x <= hx) : (x += 1) {
                    self.setPixelStyled(x, y, style);
                }
            }
        } else {
            self.drawLineStyled(lx, ly, hx, ly, style);
            self.drawLineStyled(lx, hy, hx, hy, style);
            self.drawLineStyled(lx, ly, lx, hy, style);
            self.drawLineStyled(hx, ly, hx, hy, style);
        }
    }

    pub fn drawCircle(self: *BrailleCanvas, cx: i32, cy: i32, radius: i32) void {
        self.drawCircleStyled(cx, cy, radius, self.default_style);
    }

    pub fn drawCircleStyled(self: *BrailleCanvas, cx: i32, cy: i32, radius: i32, style: Style) void {
        if (radius <= 0) {
            self.setPixelStyled(cx, cy, style);
            return;
        }
        // Midpoint circle algorithm.
        var x: i32 = radius;
        var y: i32 = 0;
        var err: i32 = 1 - radius;
        while (x >= y) {
            self.setPixelStyled(cx + x, cy + y, style);
            self.setPixelStyled(cx + y, cy + x, style);
            self.setPixelStyled(cx - y, cy + x, style);
            self.setPixelStyled(cx - x, cy + y, style);
            self.setPixelStyled(cx - x, cy - y, style);
            self.setPixelStyled(cx - y, cy - x, style);
            self.setPixelStyled(cx + y, cy - x, style);
            self.setPixelStyled(cx + x, cy - y, style);
            y += 1;
            if (err < 0) {
                err += 2 * y + 1;
            } else {
                x -= 1;
                err += 2 * (y - x) + 1;
            }
        }
    }

    /// Overlay text at cell coordinates, replacing the braille at those cells.
    pub fn drawText(self: *BrailleCanvas, col: u16, row: u16, text: []const u8, style: Style) !void {
        const owned = try self.text_arena.allocator().dupe(u8, text);
        var s = style;
        s = s.inline_style(true);
        try self.overlays.append(.{ .col = col, .row = row, .text = owned, .style = s });
    }

    pub fn view(self: *const BrailleCanvas, allocator: std.mem.Allocator) ![]const u8 {
        // Materialize each cell into a string (braille char or background),
        // styled. Then apply text overlays.
        const total_cells = @as(usize, self.cell_width) * @as(usize, self.cell_height);
        var glyph_for_cell = try allocator.alloc(?[]const u8, total_cells);
        defer allocator.free(glyph_for_cell);
        for (glyph_for_cell) |*g| g.* = null;

        // Apply text overlays first so they take precedence.
        for (self.overlays.items) |ov| {
            if (ov.row >= self.cell_height) continue;
            var col: u16 = ov.col;
            var view_iter = std.unicode.Utf8View.init(ov.text) catch continue;
            var iter = view_iter.iterator();
            while (iter.nextCodepointSlice()) |cp_slice| {
                if (col >= self.cell_width) break;
                const idx = @as(usize, ov.row) * self.cell_width + col;
                glyph_for_cell[idx] = try ov.style.render(allocator, cp_slice);
                col += 1;
            }
        }

        var result: Writer.Allocating = .init(allocator);
        const w = &result.writer;

        var row: usize = 0;
        while (row < self.cell_height) : (row += 1) {
            if (row > 0) try w.writeByte('\n');
            var col: usize = 0;
            while (col < self.cell_width) : (col += 1) {
                const idx = row * self.cell_width + col;
                if (glyph_for_cell[idx]) |overlay| {
                    try w.writeAll(overlay);
                    allocator.free(overlay);
                    continue;
                }

                const cell = self.cells[idx];
                if (cell.bits == 0) {
                    try w.writeAll(self.background_glyph);
                    continue;
                }
                var buf: [4]u8 = undefined;
                const cp: u21 = BRAILLE_BASE + @as(u21, cell.bits);
                const len = std.unicode.utf8Encode(cp, &buf) catch {
                    try w.writeAll(self.background_glyph);
                    continue;
                };
                const styled = try (cell.style orelse self.default_style).render(allocator, buf[0..len]);
                defer allocator.free(styled);
                try w.writeAll(styled);
            }
        }

        return result.toOwnedSlice();
    }
};

test "set and check pixel" {
    var c = try BrailleCanvas.init(std.testing.allocator, 4, 4);
    defer c.deinit();
    c.setPixel(0, 0);
    try std.testing.expect(c.isPixelSet(0, 0));
    try std.testing.expect(!c.isPixelSet(1, 0));
    c.clearPixel(0, 0);
    try std.testing.expect(!c.isPixelSet(0, 0));
}

test "out-of-bounds writes are ignored" {
    var c = try BrailleCanvas.init(std.testing.allocator, 2, 2);
    defer c.deinit();
    c.setPixel(-1, -1);
    c.setPixel(100, 100);
    // Nothing crashes; nothing set.
    try std.testing.expect(!c.isPixelSet(0, 0));
}

test "drawLine sets endpoints" {
    var c = try BrailleCanvas.init(std.testing.allocator, 8, 4);
    defer c.deinit();
    c.drawLine(0, 0, 10, 10);
    try std.testing.expect(c.isPixelSet(0, 0));
    try std.testing.expect(c.isPixelSet(10, 10));
}

test "drawCircle hits cardinal points" {
    var c = try BrailleCanvas.init(std.testing.allocator, 16, 16);
    defer c.deinit();
    c.drawCircle(10, 10, 5);
    try std.testing.expect(c.isPixelSet(15, 10));
    try std.testing.expect(c.isPixelSet(5, 10));
    try std.testing.expect(c.isPixelSet(10, 15));
    try std.testing.expect(c.isPixelSet(10, 5));
}

test "view emits cell_height lines" {
    const allocator = std.testing.allocator;
    var c = try BrailleCanvas.init(allocator, 4, 3);
    defer c.deinit();
    c.setPixel(0, 0);
    c.setPixel(1, 1);
    const out = try c.view(allocator);
    defer allocator.free(out);
    var newlines: usize = 0;
    for (out) |b| if (b == '\n') {
        newlines += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), newlines);
}

test "drawText overlay replaces braille" {
    const allocator = std.testing.allocator;
    var c = try BrailleCanvas.init(allocator, 10, 2);
    defer c.deinit();
    c.drawLine(0, 0, 19, 7);
    try c.drawText(0, 0, "hi", Style{});
    const out = try c.view(allocator);
    defer allocator.free(out);
    // Both characters should appear somewhere; styling may sit between them.
    try std.testing.expect(std.mem.indexOfScalar(u8, out, 'h') != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, out, 'i') != null);
}

test "setSize resets cells" {
    var c = try BrailleCanvas.init(std.testing.allocator, 2, 2);
    defer c.deinit();
    c.setPixel(0, 0);
    try c.setSize(4, 4);
    try std.testing.expect(!c.isPixelSet(0, 0));
    try std.testing.expectEqual(@as(u16, 8), c.pixelWidth());
}
