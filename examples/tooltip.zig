//! ZigZag Tooltip Example
//! Demonstrates the Tooltip component with different placements and presets.
//!
//! Keys:
//!   1-4 — Show tooltip with different placements (bottom/top/right/left)
//!   5   — Show titled tooltip
//!   6   — Show help-style tooltip
//!   7   — Show shortcut tooltip
//!   h   — Hide tooltip
//!   q   — Quit

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    tooltip: zz.Tooltip,
    status: []const u8,

    // Button positions (computed in view, used for tooltip targeting)
    btn_positions: [7]ButtonPos = @splat(.{}),

    const ButtonPos = struct {
        x: usize = 0,
        y: usize = 0,
        w: usize = 0,
    };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.tooltip = clearTooltip("This is a tooltip!");
        self.status = "Press 1-7 to show tooltips, h to hide, q to quit";
        return .none;
    }

    pub fn update(self: *Model, m: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (m) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '1' => {
                            self.tooltip = clearTooltip("Bottom placement tooltip");
                            self.tooltip.target_x = self.btn_positions[0].x;
                            self.tooltip.target_y = self.btn_positions[0].y;
                            self.tooltip.target_width = self.btn_positions[0].w;
                            self.tooltip.placement = .bottom;
                            self.tooltip.show();
                            self.status = "Showing: bottom placement";
                        },
                        '2' => {
                            self.tooltip = clearTooltip("Top placement tooltip");
                            self.tooltip.target_x = self.btn_positions[1].x;
                            self.tooltip.target_y = self.btn_positions[1].y;
                            self.tooltip.target_width = self.btn_positions[1].w;
                            self.tooltip.placement = .top;
                            self.tooltip.show();
                            self.status = "Showing: top placement";
                        },
                        '3' => {
                            self.tooltip = clearTooltip("Right placement");
                            self.tooltip.target_x = self.btn_positions[2].x;
                            self.tooltip.target_y = self.btn_positions[2].y;
                            self.tooltip.target_width = self.btn_positions[2].w;
                            self.tooltip.placement = .right;
                            self.tooltip.show();
                            self.status = "Showing: right placement";
                        },
                        '4' => {
                            self.tooltip = clearTooltip("Left placement");
                            self.tooltip.target_x = self.btn_positions[3].x;
                            self.tooltip.target_y = self.btn_positions[3].y;
                            self.tooltip.target_width = self.btn_positions[3].w;
                            self.tooltip.placement = .left;
                            self.tooltip.show();
                            self.status = "Showing: left placement";
                        },
                        '5' => {
                            self.tooltip = clearTitled("File Info", "Size: 1.2 MB\nModified: Today\nType: Document");
                            self.tooltip.target_x = self.btn_positions[4].x;
                            self.tooltip.target_y = self.btn_positions[4].y;
                            self.tooltip.target_width = self.btn_positions[4].w;
                            self.tooltip.show();
                            self.status = "Showing: titled tooltip";
                        },
                        '6' => {
                            self.tooltip = clearHelp("Press Enter to confirm your selection");
                            self.tooltip.target_x = self.btn_positions[5].x;
                            self.tooltip.target_y = self.btn_positions[5].y;
                            self.tooltip.target_width = self.btn_positions[5].w;
                            self.tooltip.show();
                            self.status = "Showing: help-style tooltip";
                        },
                        '7' => {
                            self.tooltip = clearShortcut("Save", "Ctrl+S");
                            self.tooltip.target_x = self.btn_positions[6].x;
                            self.tooltip.target_y = self.btn_positions[6].y;
                            self.tooltip.target_width = self.btn_positions[6].w;
                            self.tooltip.show();
                            self.status = "Showing: shortcut tooltip";
                        },
                        'h' => {
                            self.tooltip.hide();
                            self.status = "Tooltip hidden";
                        },
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    pub fn view(self: *Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        // Title
        var title_s = zz.Style{};
        title_s = title_s.bold(true).fg(zz.Color.hex("#FF6B6B")).inline_style(true);
        const title = title_s.render(alloc, "Tooltip Component Demo") catch "Tooltip Component Demo";

        // Status
        var status_s = zz.Style{};
        status_s = status_s.fg(zz.Color.gray(12)).inline_style(true);
        const status = status_s.render(alloc, self.status) catch "";

        // Button labels
        const labels = [_][]const u8{
            "[1] Bottom",
            "[2] Top",
            "[3] Right",
            "[4] Left",
            "[5] Titled",
            "[6] Help",
            "[7] Shortcut",
        };

        // Render buttons in a row
        var btn_s = zz.Style{};
        btn_s = btn_s.fg(zz.Color.white).inline_style(true);

        var btn_parts: [7][]const u8 = undefined;
        for (labels, 0..) |label, i| {
            const padded = std.fmt.allocPrint(alloc, " {s} ", .{label}) catch label;
            btn_parts[i] = btn_s.render(alloc, padded) catch padded;
        }

        // Join buttons with gaps
        const row1 = std.fmt.allocPrint(alloc, "{s}  {s}  {s}  {s}", .{
            btn_parts[0], btn_parts[1], btn_parts[2], btn_parts[3],
        }) catch "";
        const row2 = std.fmt.allocPrint(alloc, "{s}  {s}  {s}", .{
            btn_parts[4], btn_parts[5], btn_parts[6],
        }) catch "";

        const content = std.fmt.allocPrint(alloc, "{s}\n\n{s}\n{s}\n\n{s}", .{
            title, row1, row2, status,
        }) catch "Error";

        // Center content
        const content_w = zz.measure.maxLineWidth(content);
        const content_h = zz.measure.height(content);
        const h_pad = if (ctx.width > content_w) (ctx.width - content_w) / 2 else 0;
        const v_pad = if (ctx.height > content_h) (ctx.height - content_h) / 2 else 0;

        const base = zz.place.place(alloc, ctx.width, ctx.height, .center, .middle, content) catch content;

        // Compute button positions for tooltip targeting
        // Row 1 buttons: title line is at v_pad, blank line, then row1 at v_pad+2
        const row1_y = v_pad + 2;
        const row2_y = v_pad + 3;

        // Button widths (plain text width of " [N] Label ")
        const btn_widths = [7]usize{
            zz.measure.width(" [1] Bottom "),
            zz.measure.width(" [2] Top "),
            zz.measure.width(" [3] Right "),
            zz.measure.width(" [4] Left "),
            zz.measure.width(" [5] Titled "),
            zz.measure.width(" [6] Help "),
            zz.measure.width(" [7] Shortcut "),
        };

        // Row 1 x positions
        var x = h_pad;
        for (0..4) |i| {
            self.btn_positions[i] = .{ .x = x, .y = row1_y, .w = btn_widths[i] };
            x += btn_widths[i] + 2; // +2 for gap
        }

        // Row 2 x positions
        x = h_pad;
        for (4..7) |i| {
            self.btn_positions[i] = .{ .x = x, .y = row2_y, .w = btn_widths[i] };
            x += btn_widths[i] + 2;
        }

        // Overlay tooltip if visible
        if (self.tooltip.isVisible()) {
            return self.tooltip.overlay(alloc, base, ctx.width, ctx.height) catch base;
        }

        return base;
    }
};

/// Create a tooltip with clear terminal background (no bg color, no inheritance).
fn clearTooltip(text: []const u8) zz.Tooltip {
    var t = zz.Tooltip.init(text);
    t.content_bg = .none;
    t.border_bg = .none;
    t.arrow_bg = .none;
    t.inherit_bg = false;
    return t;
}

fn clearTitled(title: []const u8, text: []const u8) zz.Tooltip {
    var t = zz.Tooltip.titled(title, text);
    t.content_bg = .none;
    t.border_bg = .none;
    t.arrow_bg = .none;
    t.inherit_bg = false;
    return t;
}

fn clearHelp(text: []const u8) zz.Tooltip {
    var t = zz.Tooltip.help(text);
    t.content_bg = .none;
    t.border_bg = .none;
    t.arrow_bg = .none;
    t.inherit_bg = false;
    return t;
}

fn clearShortcut(label: []const u8, key: []const u8) zz.Tooltip {
    var t = zz.Tooltip.shortcut(label, key);
    t.content_bg = .none;
    t.border_bg = .none;
    t.arrow_bg = .none;
    t.inherit_bg = false;
    return t;
}

pub fn main(init: std.process.Init) !void {
    var prog = try zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer prog.deinit();

    try prog.run();
}
