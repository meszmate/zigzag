//! ZigZag Animation Example
//! Demonstrates tweens with various easing functions.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const Model = struct {
    tweens: [9]zz.Tween,
    easing_names: [9][]const u8,
    color_tween: zz.Tween,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        const easings = [_]zz.Easing{
            .linear,
            .ease_in,
            .ease_out,
            .ease_in_out,
            .ease_in_cubic,
            .ease_out_cubic,
            .ease_in_out_cubic,
            .bounce,
            .elastic,
        };
        self.easing_names = .{
            "linear",
            "ease_in",
            "ease_out",
            "ease_in_out",
            "ease_in_cubic",
            "ease_out_cubic",
            "ease_in_out_cubic",
            "bounce",
            "elastic",
        };

        for (&self.tweens, easings) |*tw, easing| {
            tw.* = zz.Tween.init(0, 30, 2000);
            tw.setEasing(easing);
            tw.setLoop(.ping_pong);
            tw.start();
        }

        self.color_tween = zz.Tween.init(0, 1, 3000);
        self.color_tween.setEasing(.ease_in_out);
        self.color_tween.setLoop(.ping_pong);
        self.color_tween.start();

        return zz.Cmd(Msg).tickMs(16);
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => |t| {
                for (&self.tweens) |*tw| {
                    tw.update(t.delta);
                }
                self.color_tween.update(t.delta);
                return zz.Cmd(Msg).tickMs(16);
            },
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'r' => {
                            for (&self.tweens) |*tw| {
                                tw.reset();
                                tw.start();
                            }
                            self.color_tween.reset();
                            self.color_tween.start();
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

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Animation & Easing Demo") catch "Animation";

        var buf: Writer.Allocating = .init(ctx.allocator);
        const writer = &buf.writer;
        writer.writeAll(title) catch {};
        writer.writeAll("\n\n") catch {};

        // Render each tween as a bar
        for (&self.tweens, self.easing_names) |*tw, name| {
            // Label
            var label_style = zz.Style{};
            label_style = label_style.fg(zz.Color.cyan);
            label_style = label_style.inline_style(true);
            const label = std.fmt.allocPrint(ctx.allocator, "{s:>20}: ", .{name}) catch "";
            const styled_label = label_style.render(ctx.allocator, label) catch label;
            writer.writeAll(styled_label) catch {};

            // Bar
            const pos = @as(usize, @intFromFloat(@max(0, tw.value())));
            for (0..30) |i| {
                if (i == pos) {
                    var dot_style = zz.Style{};
                    dot_style = dot_style.fg(zz.Color.green);
                    dot_style = dot_style.bold(true);
                    dot_style = dot_style.inline_style(true);
                    const dot = dot_style.render(ctx.allocator, "●") catch "o";
                    writer.writeAll(dot) catch {};
                } else {
                    var track_style = zz.Style{};
                    track_style = track_style.fg(zz.Color.gray(6));
                    track_style = track_style.inline_style(true);
                    const track = track_style.render(ctx.allocator, "─") catch "-";
                    writer.writeAll(track) catch {};
                }
            }
            writer.writeByte('\n') catch {};
        }

        // Color tween demo
        writer.writeAll("\n") catch {};
        var color_label_style = zz.Style{};
        color_label_style = color_label_style.fg(zz.Color.cyan);
        color_label_style = color_label_style.inline_style(true);
        const color_label = color_label_style.render(ctx.allocator, "     Color tween: ") catch "";
        writer.writeAll(color_label) catch {};

        const ct = self.color_tween.value();
        const color = zz.tweenColor(zz.Color.red, zz.Color.cyan, ct);
        var cs = zz.Style{};
        cs = cs.fg(color);
        cs = cs.bold(true);
        cs = cs.inline_style(true);
        const color_block = cs.render(ctx.allocator, "████████████████████████████████") catch "";
        writer.writeAll(color_block) catch {};

        // Help
        writer.writeAll("\n\n") catch {};
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator, "r: restart animations | q: quit") catch "";
        writer.writeAll(help) catch {};

        return buf.toOwnedSlice() catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
