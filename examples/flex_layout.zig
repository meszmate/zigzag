//! ZigZag Flex Layout Example
//! Demonstrates a dashboard-like layout using the constraint-based
//! flexbox engine: header, sidebar + main content, and footer.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    selected_panel: u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .selected_panel = 0 };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    '1' => self.selected_panel = 0,
                    '2' => self.selected_panel = 1,
                    '3' => self.selected_panel = 2,
                    else => {},
                },
                .tab => {
                    self.selected_panel = (self.selected_panel + 1) % 3;
                },
                .escape => return .quit,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        const w: u16 = @intCast(@min(ctx.width, std.math.maxInt(u16)));
        const h: u16 = @intCast(@min(ctx.height, std.math.maxInt(u16)));

        // Outer vertical layout: header(3) | body(fill) | footer(3)
        const rows = zz.flex.layout(alloc, w, h, &.{
            .{ .constraint = .{ .fixed = 3 } },
            .{ .constraint = .fill },
            .{ .constraint = .{ .fixed = 3 } },
        }, .{ .direction = .column }) catch return "layout error";

        // Body horizontal layout: sidebar(20%) | main(fill)
        const cols = zz.flex.layout(alloc, rows[1].width, rows[1].height, &.{
            .{ .constraint = .{ .percentage = 20 } },
            .{ .constraint = .fill },
        }, .{ .direction = .row, .gap = 1 }) catch return "layout error";

        // -- Render each panel into styled boxes --

        // Header
        const header = renderPanel(alloc, "Dashboard", rows[0].width, rows[0].height, zz.Color.cyan, true);

        // Sidebar
        const sidebar_items =
            "  [1] Overview\n" ++
            "  [2] Metrics\n" ++
            "  [3] Settings";
        const sidebar = renderPanel(alloc, sidebar_items, cols[0].width, cols[0].height, zz.Color.magenta, self.selected_panel == 0);

        // Main content area
        const main_text = switch (self.selected_panel) {
            0 => "Welcome to the ZigZag dashboard.\n\nThis layout is built with the\nflexbox constraint engine.\n\nPress 1/2/3 or Tab to navigate.",
            1 => "CPU: 42%\nMemory: 1.2 GB / 8 GB\nDisk: 120 GB / 500 GB\nUptime: 3d 14h 22m",
            2 => "Theme: Dark\nRefresh: 5s\nNotifications: On",
            else => "",
        };
        const main_panel = renderPanel(alloc, main_text, cols[1].width, cols[1].height, zz.Color.green, self.selected_panel == 1);

        // Footer
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const footer_text = help_style.render(alloc, "Tab: cycle panels  1/2/3: select panel  q: quit") catch "Tab: cycle  q: quit";
        const footer = renderPanel(alloc, footer_text, rows[2].width, rows[2].height, zz.Color.gray(8), false);

        // Compose the body row: sidebar | main
        const body = zz.join.horizontal(alloc, .top, &.{ sidebar, main_panel }) catch main_panel;

        // Stack vertically
        return zz.join.vertical(alloc, .left, &.{ header, body, footer }) catch "render error";
    }

    fn renderPanel(alloc: std.mem.Allocator, content: []const u8, w: u16, h: u16, border_color: zz.Color, highlight: bool) []const u8 {
        var s = zz.Style{};
        s = s.borderAll(zz.Border.rounded);
        if (highlight) {
            s = s.borderForeground(border_color);
        } else {
            s = s.borderForeground(zz.Color.gray(6));
        }
        // Account for border (2 cells each side)
        const inner_w: u16 = if (w > 4) w - 4 else 1;
        const inner_h: u16 = if (h > 2) h - 2 else 1;
        s = s.width(inner_w);
        s = s.height(inner_h);
        return s.render(alloc, content) catch content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
