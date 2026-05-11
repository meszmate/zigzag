//! ZigZag Layers Example
//! Demonstrates z-ordered layer compositing with overlapping panels.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    show_popup: bool,
    show_tooltip: bool,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .show_popup = false, .show_tooltip = false };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    'p' => self.show_popup = !self.show_popup,
                    't' => self.show_tooltip = !self.show_tooltip,
                    else => {},
                },
                .escape => {
                    if (self.show_popup) {
                        self.show_popup = false;
                    } else if (self.show_tooltip) {
                        self.show_tooltip = false;
                    } else {
                        return .quit;
                    }
                },
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        const w: u16 = @intCast(@min(ctx.width, std.math.maxInt(u16)));
        const h: u16 = @intCast(@min(ctx.height, std.math.maxInt(u16)));

        var stack = zz.layout.layer.LayerStack.init(alloc);
        stack.setSize(w, h);

        // Background layer (z=0)
        var bg_style = zz.Style{};
        bg_style = bg_style.fg(zz.Color.gray(8));
        bg_style = bg_style.inline_style(true);

        var bg_content = std.array_list.Managed(u8).init(alloc);
        for (0..h) |row| {
            if (row > 0) bg_content.append('\n') catch {};
            for (0..w) |col| {
                const c: u8 = if ((row + col) % 2 == 0) '.' else ' ';
                bg_content.append(c) catch {};
            }
        }
        stack.push(.{ .content = bg_content.items, .z = 0, .transparent = false }) catch {};

        // Main info panel (z=1)
        var info_style = zz.Style{};
        info_style = info_style.borderAll(zz.Border.rounded);
        info_style = info_style.borderForeground(zz.Color.cyan);
        info_style = info_style.paddingAll(1);
        info_style = info_style.width(40);
        info_style = info_style.height(8);

        const info_text = "Layer Compositing Demo\n\np: toggle popup\nt: toggle tooltip\nq: quit";
        const info_panel = info_style.render(alloc, info_text) catch info_text;
        stack.push(.{ .content = info_panel, .x = 5, .y = 2, .z = 1 }) catch {};

        // Popup (z=10)
        if (self.show_popup) {
            var popup_style = zz.Style{};
            popup_style = popup_style.borderAll(zz.Border.double);
            popup_style = popup_style.borderForeground(zz.Color.yellow);
            popup_style = popup_style.paddingAll(1);
            popup_style = popup_style.width(30);
            popup_style = popup_style.height(5);

            const popup_text = "Modal Popup\n\nThis is on top!\nEsc to close";
            const popup = popup_style.render(alloc, popup_text) catch popup_text;
            const px: u16 = if (w > 34) (w - 34) / 2 else 0;
            const py: u16 = if (h > 9) (h - 9) / 2 else 0;
            stack.push(.{ .content = popup, .x = px, .y = py, .z = 10 }) catch {};
        }

        // Tooltip (z=20)
        if (self.show_tooltip) {
            var tt_style = zz.Style{};
            tt_style = tt_style.borderAll(zz.Border.normal);
            tt_style = tt_style.borderForeground(zz.Color.green);
            tt_style = tt_style.width(20);

            const tt = tt_style.render(alloc, "Tooltip z=20") catch "tooltip";
            stack.push(.{ .content = tt, .x = 15, .y = 5, .z = 20 }) catch {};
        }

        return stack.render(alloc);
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
