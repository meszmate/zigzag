//! ZigZag Accessibility Example
//! Demonstrates WCAG contrast checking, accessible labels,
//! and the suggestForeground helper for picking readable colors.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const ColorPair = struct {
    name: []const u8,
    fg: zz.Color,
    bg: zz.Color,
};

const Model = struct {
    pairs: [8]ColorPair,
    selected: usize,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.pairs = .{
            .{ .name = "White on Black", .fg = .white, .bg = .black },
            .{ .name = "Black on White", .fg = .black, .bg = .white },
            .{ .name = "Cyan on Dark", .fg = .cyan, .bg = .fromRgb(30, 30, 46) },
            .{ .name = "Gray on Gray", .fg = .fromRgb(120, 120, 120), .bg = .fromRgb(140, 140, 140) },
            .{ .name = "Yellow on White", .fg = .yellow, .bg = .white },
            .{ .name = "Green on Black", .fg = .green, .bg = .black },
            .{ .name = "Red on Dark Red", .fg = .red, .bg = .fromRgb(60, 10, 10) },
            .{ .name = "Blue on Blue", .fg = .fromRgb(100, 100, 200), .bg = .fromRgb(80, 80, 180) },
        };
        self.selected = 0;
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .up => self.selected = if (self.selected == 0) self.pairs.len - 1 else self.selected - 1,
                .down => self.selected = (self.selected + 1) % self.pairs.len,
                .escape => return .quit,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var result: Writer.Allocating = .init(ctx.allocator);
        const w = &result.writer;

        // Title
        const title = (zz.Style{})
            .bold(true)
            .fg(.white)
            .inline_style(true)
            .render(ctx.allocator, "Accessibility: WCAG Contrast Checker") catch "A11y Demo";
        w.print("{s}\n\n", .{title}) catch {};

        // Table header
        w.writeAll("  Name                   Ratio    Level     Sample\n") catch {};
        w.writeAll("  ────────────────────── ──────── ───────── ──────────────\n") catch {};

        // Color pairs
        for (&self.pairs, 0..) |*pair, i| {
            const ratio = pair.fg.contrastRatio(pair.bg);
            const level = zz.a11y.checkContrast(pair.fg, pair.bg);

            const level_name: []const u8 = switch (level) {
                .aaa => "AAA",
                .aa => "AA",
                .aa_large => "AA Large",
                .fail => "FAIL",
            };

            // Level badge color
            const level_color: zz.Color = switch (level) {
                .aaa => .green,
                .aa => .cyan,
                .aa_large => .yellow,
                .fail => .red,
            };

            // Row indicator
            const prefix: []const u8 = if (i == self.selected) "> " else "  ";
            w.writeAll(prefix) catch {};

            // Name (padded to 23 chars)
            w.print("{s}", .{pair.name}) catch {};
            const name_len = pair.name.len;
            if (name_len < 23) {
                for (0..23 - name_len) |_| w.writeByte(' ') catch {};
            }

            // Ratio
            w.print("{d:.1}:1   ", .{ratio}) catch {};

            // Level badge
            const badge = (zz.Style{})
                .fg(level_color)
                .bold(true)
                .inline_style(true)
                .render(ctx.allocator, level_name) catch level_name;
            w.print("{s}", .{badge}) catch {};
            const badge_len = level_name.len;
            if (badge_len < 10) {
                for (0..10 - badge_len) |_| w.writeByte(' ') catch {};
            }

            // Sample text with the actual colors
            const sample = (zz.Style{})
                .fg(pair.fg)
                .bg(pair.bg)
                .inline_style(true)
                .render(ctx.allocator, " Sample Text ") catch "Sample";
            w.print("{s}", .{sample}) catch {};

            w.writeByte('\n') catch {};
        }

        // Selected pair detail
        const pair = &self.pairs[self.selected];
        w.writeAll("\n") catch {};

        // Accessible label demo
        const a11y_label = zz.AccessibleLabel{
            .role = .status,
            .name = pair.name,
            .value = std.fmt.allocPrint(ctx.allocator, "contrast {d:.1}:1", .{pair.fg.contrastRatio(pair.bg)}) catch "",
            .state = switch (zz.a11y.checkContrast(pair.fg, pair.bg)) {
                .aaa => "passes AAA",
                .aa => "passes AA",
                .aa_large => "passes AA for large text only",
                .fail => "fails WCAG requirements",
            },
        };
        const label_text = a11y_label.format(ctx.allocator) catch "?";
        const label = (zz.Style{})
            .fg(.gray(14))
            .inline_style(true)
            .render(ctx.allocator, label_text) catch label_text;
        w.print("Screen reader: {s}\n", .{label}) catch {};

        // Suggested foreground
        const suggested = zz.a11y.suggestForeground(pair.bg);
        const sugg_name: []const u8 = if (std.meta.eql(suggested, .white)) "white" else "black";
        w.print("Suggested foreground for this bg: {s}\n", .{sugg_name}) catch {};

        // Help
        w.writeAll("\n") catch {};
        const help = (zz.Style{})
            .fg(.gray(12))
            .inline_style(true)
            .render(ctx.allocator, "Up/Down: select pair | q: quit") catch "";
        w.writeAll(help) catch {};

        return result.toOwnedSlice() catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
