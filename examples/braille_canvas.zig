//! ZigZag BrailleCanvas Example
//! Animated bouncing ball with a faint grid background.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    canvas: zz.components.BrailleCanvas,
    ball_x: f64,
    ball_y: f64,
    vx: f64,
    vy: f64,
    paused: bool,
    frame: u64,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        const c = zz.components.BrailleCanvas.init(ctx.persistent_allocator, 50, 12) catch return .quit;
        self.* = .{
            .canvas = c,
            .ball_x = 10,
            .ball_y = 10,
            .vx = 0.9,
            .vy = 0.6,
            .paused = false,
            .frame = 0,
        };
        return .{ .every = 33 * std.time.ns_per_ms }; // ~30 fps
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    ' ' => self.paused = !self.paused,
                    'r' => {
                        self.ball_x = 10;
                        self.ball_y = 10;
                        self.vx = 0.9;
                        self.vy = 0.6;
                    },
                    else => {},
                },
                .escape => return .quit,
                else => {},
            },
            .tick => {
                if (!self.paused) self.advance();
                self.frame +%= 1;
            },
        }
        return .none;
    }

    fn advance(self: *Model) void {
        const max_x: f64 = @floatFromInt(self.canvas.pixelWidth() - 1);
        const max_y: f64 = @floatFromInt(self.canvas.pixelHeight() - 1);

        self.ball_x += self.vx;
        self.ball_y += self.vy;

        if (self.ball_x <= 4 or self.ball_x >= max_x - 4) self.vx = -self.vx;
        if (self.ball_y <= 4 or self.ball_y >= max_y - 4) self.vy = -self.vy;
        self.ball_x = std.math.clamp(self.ball_x, 4, max_x - 4);
        self.ball_y = std.math.clamp(self.ball_y, 4, max_y - 4);
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        var c = @constCast(&self.canvas);
        c.clear();

        // Faint grid: dotted border + crosshair through the centre.
        var grid_style = zz.Style{};
        grid_style = grid_style.fg(zz.Color.gray(6));
        grid_style = grid_style.inline_style(true);

        const w = c.pixelWidth();
        const h = c.pixelHeight();
        c.drawRectStyled(0, 0, @intCast(w - 1), @intCast(h - 1), false, grid_style);
        c.drawLineStyled(@intCast(w / 2), 0, @intCast(w / 2), @intCast(h - 1), grid_style);
        c.drawLineStyled(0, @intCast(h / 2), @intCast(w - 1), @intCast(h / 2), grid_style);

        // Ball trail.
        const tx: i32 = @intFromFloat(self.ball_x);
        const ty: i32 = @intFromFloat(self.ball_y);

        var trail_style = zz.Style{};
        trail_style = trail_style.fg(zz.Color.cyan());
        trail_style = trail_style.inline_style(true);
        c.drawCircleStyled(tx, ty, 3, trail_style);

        var ball_style = zz.Style{};
        ball_style = ball_style.fg(zz.Color.magenta());
        ball_style = ball_style.bold(true);
        ball_style = ball_style.inline_style(true);
        c.drawCircleStyled(tx, ty, 1, ball_style);

        const canvas_view = c.view(alloc) catch "";

        var title = zz.Style{};
        title = title.bold(true);
        title = title.fg(zz.Color.cyan());
        title = title.inline_style(true);
        const t = title.render(alloc, "BrailleCanvas — bouncing ball") catch "";

        var box = zz.Style{};
        box = box.borderAll(zz.Border.rounded);
        box = box.borderForeground(zz.Color.gray(8));
        const boxed = box.render(alloc, canvas_view) catch canvas_view;

        var help = zz.Style{};
        help = help.fg(zz.Color.gray(10));
        help = help.inline_style(true);
        const status = if (self.paused) "PAUSED  " else "        ";
        const help_text = std.fmt.allocPrint(
            alloc,
            "{s}space pause  r reset  q quit   |   frame {d}",
            .{ status, self.frame },
        ) catch "";
        const help_str = help.render(alloc, help_text) catch "";

        return std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}", .{ t, boxed, help_str }) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.canvas.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
