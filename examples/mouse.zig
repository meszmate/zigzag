//! ZigZag Mouse Example
//! Demonstrates mouse tracking, hit testing, and interactive buttons.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const Model = struct {
    buttons: [3]ButtonState,
    click_count: usize,
    last_event: []const u8,
    mouse_x: u16,
    mouse_y: u16,

    const ButtonState = struct {
        label: []const u8,
        color: zz.Color,
        mouse: zz.MouseState,
    };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        mouse: zz.MouseEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.buttons = .{
            .{ .label = "  Click Me  ", .color = zz.Color.cyan, .mouse = .{} },
            .{ .label = "  Count++   ", .color = zz.Color.green, .mouse = .{} },
            .{ .label = "   Reset    ", .color = zz.Color.red, .mouse = .{} },
        };
        self.click_count = 0;
        self.last_event = "Move the mouse or click a button";
        self.mouse_x = 0;
        self.mouse_y = 0;
        return .enable_mouse;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .escape => return .quit,
                else => {},
            },
            .mouse => |m| {
                self.mouse_x = m.x;
                self.mouse_y = m.y;

                for (&self.buttons, 0..) |*btn, i| {
                    const box = buttonHitBox(i);
                    const interaction = btn.mouse.update(box, m);
                    switch (interaction) {
                        .click => {
                            switch (i) {
                                0 => {
                                    self.last_event = "Button 1 clicked!";
                                },
                                1 => {
                                    self.click_count += 1;
                                    self.last_event = std.fmt.allocPrint(
                                        ctx.allocator,
                                        "Count: {d}",
                                        .{self.click_count},
                                    ) catch "Count++";
                                },
                                2 => {
                                    self.click_count = 0;
                                    self.last_event = "Counter reset!";
                                },
                                else => {},
                            }
                        },
                        .enter => self.last_event = "Hovering button",
                        .leave => self.last_event = "Mouse left button",
                        else => {},
                    }
                }
            },
        }
        return .none;
    }

    fn buttonHitBox(index: usize) zz.HitBox {
        // Buttons start at row 5, spaced 14 columns apart
        const x: u16 = @intCast(2 + index * 16);
        return zz.HitBox.init(x, 5, 14, 3);
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.white);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Mouse Demo") catch "Mouse Demo";

        const coords = std.fmt.allocPrint(
            ctx.allocator,
            "Mouse: ({d}, {d})  |  {s}",
            .{ self.mouse_x, self.mouse_y, self.last_event },
        ) catch "";

        const count_str = std.fmt.allocPrint(
            ctx.allocator,
            "Click count: {d}",
            .{self.click_count},
        ) catch "";

        // Render buttons
        var buttons_line: Writer.Allocating = .init(ctx.allocator);
        const bw = &buttons_line.writer;
        for (&self.buttons, 0..) |*btn, i| {
            if (i > 0) bw.writeAll("  ") catch {};
            var s = zz.Style{};
            s = s.borderAll(zz.Border.rounded);
            if (btn.mouse.hover) {
                s = s.borderForeground(zz.Color.white);
                s = s.bold(true);
            } else {
                s = s.borderForeground(btn.color);
            }
            s = s.fg(btn.color);
            s = s.inline_style(false);
            const rendered = s.render(ctx.allocator, btn.label) catch btn.label;
            bw.writeAll(rendered) catch {};
        }
        const buttons = buttons_line.toOwnedSlice() catch "";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(12));
        help_s = help_s.inline_style(true);
        const help = help_s.render(ctx.allocator, "Click the buttons above | q: quit") catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n{s}\n\n{s}\n\n{s}",
            .{ title, coords, count_str, buttons, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).initWithOptions(init.gpa, init.io, init.environ_map, .{
        .mouse = true,
    });
    defer program.deinit();

    try program.run();
}
