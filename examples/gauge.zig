//! ZigZag Gauge Example
//! Demonstrates gauge component with bar, level meter, and block styles.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    value: f64,
    tick_count: u32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .value = 0, .tick_count = 0 };
        return zz.Cmd(Msg).everyMs(100);
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    'r' => {
                        self.value = 0;
                        self.tick_count = 0;
                    },
                    else => {},
                },
                .escape => return .quit,
                .up => self.value = @min(100, self.value + 5),
                .down => self.value = @max(0, self.value - 5),
                else => {},
            },
            .tick => {
                self.tick_count += 1;
                // Slowly oscillate
                self.value = 50 + 45 * @sin(@as(f64, @floatFromInt(self.tick_count)) * 0.05);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);
        const title = title_s.render(alloc, "Gauge Component Demo") catch "Gauge Demo";

        const thresholds = &[_]zz.Gauge.Threshold{
            .{ .value = 70, .color = zz.Color.yellow },
            .{ .value = 90, .color = zz.Color.red },
        };

        // Bar gauge
        var bar = zz.Gauge{};
        bar.value = self.value;
        bar.width = 40;
        bar.display_style = .bar;
        bar.show_percent = true;
        bar.label = "CPU";
        bar.thresholds = thresholds;
        const bar_view = bar.view(alloc);

        // Level meter
        var level = zz.Gauge{};
        level.value = self.value;
        level.display_style = .level_meter;
        level.show_percent = true;
        level.label = "MEM";
        level.thresholds = thresholds;
        const level_view = level.view(alloc);

        // Blocks
        var blocks = zz.Gauge{};
        blocks.value = self.value;
        blocks.width = 40;
        blocks.display_style = .blocks;
        blocks.show_percent = true;
        blocks.label = "DSK";
        blocks.base_color = zz.Color.blue;
        const blocks_view = blocks.view(alloc);

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(alloc,
            "{s}\n\n{s}\n\n{s}\n\n{s}\n\n{s}",
            .{
                title,
                bar_view,
                level_view,
                blocks_view,
                help_s.render(alloc, "Up/Down: adjust  r: reset  q: quit") catch "",
            },
        ) catch "Error";

        return zz.place.place(alloc, ctx.width, ctx.height, .center, .middle, content) catch content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
