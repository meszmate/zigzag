//! ZigZag Mouse Example
//! Demonstrates mouse tracking, hit testing, and interactive buttons.

const std = @import("std");
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

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
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
                                    // ctx.allocator is a per-frame arena, so
                                    // strings stored in the model must not be
                                    // allocated from it.
                                    self.last_event = "Count incremented!";
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
        // The three buttons render as a horizontal row starting at row 4
        // (after the title, mouse coords, count, and a blank line). Each box
        // is 14 columns wide (12-char label + 2 border) with a 2-column gap,
        // so the boxes start 16 columns apart.
        const x: u16 = @intCast(index * 16);
        return zz.HitBox.init(x, 4, 14, 3);
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.white);
        title_style = title_style.inline_style(true);
        const title = try title_style.render(ctx.allocator, "Mouse Demo");

        const coords = try std.fmt.allocPrint(
            ctx.allocator,
            "Mouse: ({d}, {d})  |  {s}",
            .{ self.mouse_x, self.mouse_y, self.last_event },
        );

        const count_str = try std.fmt.allocPrint(
            ctx.allocator,
            "Click count: {d}",
            .{self.click_count},
        );

        // Render each button as its own bordered box, then place the boxes
        // side by side with joinHorizontal. Each box is multi-line, so simply
        // concatenating them would stair-step the boxes diagonally (issue #117).
        var boxes: [self.buttons.len][]const u8 = undefined;
        for (&self.buttons, 0..) |*btn, i| {
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
            boxes[i] = try s.render(ctx.allocator, btn.label);
        }
        const buttons = try zz.joinHorizontal(ctx.allocator, &.{
            boxes[0], "  ", boxes[1], "  ", boxes[2],
        });

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(12));
        help_s = help_s.inline_style(true);
        const help = try help_s.render(ctx.allocator, "Click the buttons above | q: quit");

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n{s}\n\n{s}\n\n{s}",
            .{ title, coords, count_str, buttons, help },
        );
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).initWithOptions(init.gpa, init.io, init.environ_map, .{
        .mouse = true,
    });
    defer program.deinit();

    try program.run();
}
