//! ZigZag Text Overflow Example
//! Demonstrates overflow policies: hidden, ellipsis, word_wrap, char_wrap.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{};
        return .none;
    }

    pub fn update(_: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .escape => return .quit,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(_: *const Model, ctx: *const zz.Context) ![]const u8 {
        const alloc = ctx.allocator;
        const long_text = "The quick brown fox jumps over the lazy dog. This is a long sentence that demonstrates how text overflow policies work in the ZigZag TUI framework.";
        const box_width: u16 = 35;

        // Title
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);
        const title = try title_style.render(alloc, "Text Overflow Policies");

        // visible (no overflow handling)
        var vis_style = zz.Style{};
        vis_style = vis_style.width(box_width);
        vis_style = vis_style.borderAll(zz.Border.rounded);
        vis_style = vis_style.borderForeground(zz.Color.gray(8));
        vis_style = vis_style.overflow(.visible);
        const vis = try vis_style.render(alloc, long_text);

        // hidden (clip)
        var clip_style = zz.Style{};
        clip_style = clip_style.width(box_width);
        clip_style = clip_style.borderAll(zz.Border.rounded);
        clip_style = clip_style.borderForeground(zz.Color.yellow);
        clip_style = clip_style.overflow(.hidden);
        const clip = try clip_style.render(alloc, long_text);

        // ellipsis
        var ell_style = zz.Style{};
        ell_style = ell_style.width(box_width);
        ell_style = ell_style.borderAll(zz.Border.rounded);
        ell_style = ell_style.borderForeground(zz.Color.green);
        ell_style = ell_style.overflow(.ellipsis);
        const ell = try ell_style.render(alloc, long_text);

        // word_wrap
        var ww_style = zz.Style{};
        ww_style = ww_style.width(box_width);
        ww_style = ww_style.borderAll(zz.Border.rounded);
        ww_style = ww_style.borderForeground(zz.Color.blue);
        ww_style = ww_style.overflow(.word_wrap);
        const ww = try ww_style.render(alloc, long_text);

        // char_wrap
        var cw_style = zz.Style{};
        cw_style = cw_style.width(box_width);
        cw_style = cw_style.borderAll(zz.Border.rounded);
        cw_style = cw_style.borderForeground(zz.Color.magenta);
        cw_style = cw_style.overflow(.char_wrap);
        const cw = try cw_style.render(alloc, long_text);

        // Labels
        var label_style = zz.Style{};
        label_style = label_style.fg(zz.Color.gray(12));
        label_style = label_style.inline_style(true);

        const content = try std.fmt.allocPrint(
            alloc,
            "{s}\n\n{s} visible (default):\n{s}\n\n{s} hidden (clip):\n{s}\n\n{s} ellipsis:\n{s}\n\n{s} word_wrap:\n{s}\n\n{s} char_wrap:\n{s}\n\nPress q to quit",
            .{
                title,
                try label_style.render(alloc, "\xe2\x96\xb8"),
                vis,
                try label_style.render(alloc, "\xe2\x96\xb8"),
                clip,
                try label_style.render(alloc, "\xe2\x96\xb8"),
                ell,
                try label_style.render(alloc, "\xe2\x96\xb8"),
                ww,
                try label_style.render(alloc, "\xe2\x96\xb8"),
                cw,
            },
        );

        return content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
