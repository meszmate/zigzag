//! ZigZag Counter Example
//! Demonstrates state management with a simple counter.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    count: i32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .count = 0 };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '+', '=' => self.count += 1,
                        '-', '_' => self.count -= 1,
                        'r' => self.count = 0,
                        else => {},
                    },
                    .up => self.count += 1,
                    .down => self.count -= 1,
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Title style
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);

        // Counter value style - changes color based on value
        var counter_style = zz.Style{};
        counter_style = counter_style.bold(true);
        counter_style = counter_style.inline_style(true);
        counter_style = counter_style.fg(if (self.count > 0)
            zz.Color.green
        else if (self.count < 0)
            zz.Color.red
        else
            zz.Color.white);

        // Border style
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.cyan);
        box_style = box_style.paddingAll(1);
        box_style = box_style.alignH(.center);

        const title = title_style.render(ctx.allocator, "Counter Demo") catch "Counter Demo";
        const counter = std.fmt.allocPrint(ctx.allocator, "{d}", .{self.count}) catch "?";
        const styled_counter = counter_style.render(ctx.allocator, counter) catch counter;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\nCount: {s}",
            .{ title, styled_counter },
        ) catch "Error";

        const boxed = box_style.render(ctx.allocator, content) catch content;

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Up/+ Increment  Down/- Decrement  r Reset  q Quit",
        ) catch "";

        // Get max width for centering
        const box_width = zz.measure.maxLineWidth(boxed);
        const help_width = zz.measure.width(help);
        const max_width = @max(box_width, help_width);

        // Center elements
        const centered_box = zz.place.place(ctx.allocator, max_width, zz.measure.height(boxed), .center, .top, boxed) catch boxed;
        const centered_help = zz.place.place(ctx.allocator, max_width, 1, .center, .top, help) catch help;

        const final_content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}",
            .{ centered_box, centered_help },
        ) catch "Error";

        // Center in terminal
        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            final_content,
        ) catch final_content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
