//! ZigZag Animation Example
//! Demonstrates tweens with various easing functions.

const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
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
        const title = comptime zz.newStyle()
            .bold(true)
            .fg(.magenta)
            .inline_style(true)
            .renderComptime("Animation & Easing Demo");

        var buf: Writer.Allocating = .init(ctx.allocator);
        const writer = &buf.writer;
        writer.writeAll(title) catch {};
        writer.writeAll("\n\n") catch {};

        // Render each tween as a bar
        for (&self.tweens, self.easing_names) |*tw, name| {
            // Label
            const label_text = std.fmt.allocPrint(ctx.allocator, "{s:>20}: ", .{name}) catch "";
            const label = zz.newStyle()
                .fg(.cyan)
                .inline_style(true)
                .render(ctx.allocator, label_text) catch label_text;
            writer.writeAll(label) catch {};

            // Bar
            const pos = @as(usize, @intFromFloat(@max(0, tw.value())));
            for (0..30) |i| {
                if (i == pos) {
                    const dot = comptime zz.newStyle()
                        .fg(.green)
                        .bold(true)
                        .inline_style(true)
                        .renderComptime("●");
                    writer.writeAll(dot) catch {};
                } else {
                    const track = comptime zz.newStyle()
                        .fg(.gray(6))
                        .inline_style(true)
                        .renderComptime("─");
                    writer.writeAll(track) catch {};
                }
            }
            writer.writeByte('\n') catch {};
        }

        // Color tween demo
        writer.writeAll("\n") catch {};
        const color_label = comptime zz.newStyle()
            .fg(.cyan)
            .inline_style(true)
            .renderComptime("     Color tween: ");
        writer.writeAll(color_label) catch {};

        const ct = self.color_tween.value();
        const color = zz.tweenColor(.red, .cyan, ct);
        const color_block = zz.newStyle()
            .fg(color)
            .bold(true)
            .inline_style(true)
            .render(ctx.allocator, "████████████████████████████████") catch "";
        writer.writeAll(color_block) catch {};

        // Help
        writer.writeAll("\n\n") catch {};
        const help = comptime zz.newStyle()
            .fg(.gray(12))
            .inline_style(true)
            .renderComptime("r: restart animations | q: quit");
        writer.writeAll(help) catch {};

        return buf.toOwnedSlice() catch "Error";
    }
};

pub fn main() !void {
    var gpa: GeneralPurposeAllocator = .init;
    defer std.debug.assert(gpa.deinit() == .ok);

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
