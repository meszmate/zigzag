//! Layer compositing system for z-ordered UI overlays.
//! Manages a stack of rendered text layers and composites them
//! into a single output with proper z-ordering and transparency.

const std = @import("std");
const Writer = std.Io.Writer;
const measure = @import("measure.zig");

/// A single layer in the stack.
pub const Layer = struct {
    /// Rendered content string.
    content: []const u8,
    /// X position (column offset).
    x: u16 = 0,
    /// Y position (row offset).
    y: u16 = 0,
    /// Z-index for ordering. Higher = on top.
    z: i16 = 0,
    /// If true, space characters are transparent (show layer below).
    transparent: bool = true,
};

/// Composites multiple layers into a single rendered output.
pub const LayerStack = struct {
    allocator: std.mem.Allocator,
    layers: std.array_list.Managed(Layer),
    width: u16 = 80,
    height: u16 = 24,
    /// Background character for empty cells.
    background: u8 = ' ',

    pub fn init(allocator: std.mem.Allocator) LayerStack {
        return .{
            .allocator = allocator,
            .layers = std.array_list.Managed(Layer).init(allocator),
        };
    }

    pub fn deinit(self: *LayerStack) void {
        self.layers.deinit();
    }

    pub fn setSize(self: *LayerStack, w: u16, h: u16) void {
        self.width = w;
        self.height = h;
    }

    pub fn push(self: *LayerStack, layer: Layer) !void {
        try self.layers.append(layer);
    }

    pub fn clear(self: *LayerStack) void {
        self.layers.clearRetainingCapacity();
    }

    /// Composite all layers and return the final rendered string.
    pub fn render(self: *const LayerStack, allocator: std.mem.Allocator) []const u8 {
        const w: usize = self.width;
        const h: usize = self.height;

        // Create cell buffer: each cell stores a byte slice (content) and ANSI state
        // For simplicity, we use a 2D grid of cells that stores display characters
        const grid = allocator.alloc(Cell, w * h) catch return "";

        // Fill with background
        const bg = [1]u8{self.background};
        for (grid) |*cell| {
            cell.* = .{ .content = &bg, .ansi_prefix = "" };
        }

        // Sort layers by z-index
        const sorted = allocator.alloc(Layer, self.layers.items.len) catch return "";
        @memcpy(sorted, self.layers.items);
        std.mem.sort(Layer, sorted, {}, struct {
            fn lessThan(_: void, a: Layer, b: Layer) bool {
                return a.z < b.z;
            }
        }.lessThan);

        // Paint each layer onto the grid
        for (sorted) |layer| {
            self.paintLayer(grid, w, h, layer);
        }

        // Render grid to string
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        for (0..h) |row| {
            if (row > 0) writer.writeByte('\n') catch {};
            for (0..w) |col| {
                const cell = grid[row * w + col];
                // Empty content marks the second column of a wide character
                if (cell.content.len == 0) continue;
                if (cell.ansi_prefix.len > 0) {
                    writer.writeAll(cell.ansi_prefix) catch {};
                    writer.writeAll(cell.content) catch {};
                    writer.writeAll("\x1b[0m") catch {};
                } else {
                    writer.writeAll(cell.content) catch {};
                }
            }
        }

        return result.toArrayList().items;
    }

    fn paintLayer(self: *const LayerStack, grid: []Cell, w: usize, h: usize, layer: Layer) void {
        _ = self;
        const content = layer.content;
        var row: usize = layer.y;
        var col: usize = layer.x;
        var i: usize = 0;
        var current_ansi: []const u8 = "";

        while (i < content.len and row < h) {
            if (content[i] == '\n') {
                row += 1;
                col = layer.x;
                i += 1;
                continue;
            }

            // Detect ANSI escape sequence
            if (content[i] == 0x1b and i + 1 < content.len and content[i + 1] == '[') {
                const seq_start = i;
                i += 2;
                while (i < content.len and content[i] != 'm' and content[i] != 'H' and content[i] != 'J' and content[i] != 'K') : (i += 1) {}
                if (i < content.len) {
                    i += 1;
                    // Check if it's a reset sequence
                    if (content[seq_start + 2 .. i - 1].len == 1 and content[seq_start + 2] == '0') {
                        current_ansi = "";
                    } else {
                        current_ansi = content[seq_start..i];
                    }
                }
                continue;
            }

            // Decode one UTF-8 character; treat invalid bytes as single cells
            const char_len = std.unicode.utf8ByteSequenceLength(content[i]) catch 1;
            const end = @min(i + char_len, content.len);
            const char = content[i..end];
            const codepoint: u21 = std.unicode.utf8Decode(char) catch content[i];
            const char_width = measure.charWidth(codepoint);
            i = end;

            // Zero-width characters (e.g. combining marks) get no cell
            if (char_width == 0) continue;

            const is_transparent = layer.transparent and codepoint == ' ' and current_ansi.len == 0;
            if (!is_transparent and col + char_width <= w) {
                grid[row * w + col] = .{
                    .content = char,
                    .ansi_prefix = current_ansi,
                };
                // A wide character covers the following cell as well
                if (char_width == 2) {
                    grid[row * w + col + 1] = .{ .content = "" };
                }
            }
            col += char_width;
        }
    }
};

const Cell = struct {
    /// UTF-8 bytes of the character in this cell.
    /// Empty for the second column of a wide character.
    content: []const u8 = " ",
    ansi_prefix: []const u8 = "",
};
