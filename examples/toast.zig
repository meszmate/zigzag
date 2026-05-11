//! ZigZag Toast Example
//! Demonstrates the enhanced toast notification system with positioning and styles.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    toast: zz.Toast,
    msg_counter: usize,
    last_elapsed: u64,
    width_preset_idx: usize,
    border_style_idx: usize,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.toast = zz.Toast.init(ctx.persistent_allocator);
        self.toast.position = .top_right;
        self.toast.show_countdown = true;
        self.toast.min_width = 24;
        self.toast.max_width = 50;
        self.msg_counter = 0;
        self.last_elapsed = 0;
        self.width_preset_idx = 1;
        self.border_style_idx = 0;

        // Initial welcome toast
        self.toast.push("Welcome to the Toast demo!", .info, 5000, 0) catch {};

        return .{ .every = 100_000_000 };
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => {
                self.last_elapsed = ctx.elapsed;
                self.toast.update(ctx.elapsed);
            },
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '1' => {
                            self.pushNumberedToast(ctx, .info, "Info message #{d}", 3000);
                        },
                        '2' => {
                            self.pushNumberedToast(ctx, .success, "Success #{d}!", 3000);
                        },
                        '3' => {
                            self.pushNumberedToast(ctx, .warning, "Warning #{d}", 4000);
                        },
                        '4' => {
                            self.pushNumberedToast(ctx, .err, "Error #{d}!", 5000);
                        },
                        '5' => {
                            self.toast.pushPersistent("Persistent notification (press d to dismiss)", .info, ctx.elapsed) catch {};
                        },
                        '6' => {
                            self.msg_counter += 1;
                            const text = std.fmt.allocPrint(
                                ctx.allocator,
                                "Long toast #{d}: right-side stacks now flush correctly, messages are owned by the component, and long lines are trimmed to the configured width instead of spilling awkwardly across the layout.",
                                .{self.msg_counter},
                            ) catch "Long toast";
                            self.toast.push(text, .info, 5500, ctx.elapsed) catch {};
                        },
                        'd' => self.toast.dismiss(),
                        'D' => self.toast.dismissAll(),
                        'x' => self.toast.dismissOldest(),
                        'b' => self.toast.show_border = !self.toast.show_border,
                        'i' => self.toast.show_icons = !self.toast.show_icons,
                        'c' => self.toast.show_countdown = !self.toast.show_countdown,
                        'w' => self.cycleWidthPreset(),
                        't' => self.cycleBorderStyle(),
                        'p', 'P' => {
                            self.toast.position = switch (self.toast.position) {
                                .top_left => .top_center,
                                .top_center => .top_right,
                                .top_right => .bottom_right,
                                .bottom_right => .bottom_center,
                                .bottom_center => .bottom_left,
                                .bottom_left => .top_left,
                            };
                            self.announceSetting(
                                ctx,
                                "Toast position: {s}",
                                .{self.positionName()},
                            );
                        },
                        's' => {
                            self.toast.stack_order = if (self.toast.stack_order == .newest_first) .oldest_first else .newest_first;
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
        const title = title_style.render(ctx.allocator, "Toast Notifications") catch "Toast";

        const pos_name = self.positionName();
        const order_name: []const u8 = if (self.toast.stack_order == .newest_first) "newest first" else "oldest first";
        const border_name: []const u8 = switch (self.border_style_idx) {
            0 => "rounded",
            1 => "normal",
            else => "thick",
        };

        var info_style = zz.Style{};
        info_style = info_style.fg(zz.Color.cyan);
        info_style = info_style.inline_style(true);
        const info = std.fmt.allocPrint(
            ctx.allocator,
            "Position: {s} | Order: {s} | Active: {d} | Width: {d}-{d} | Border style: {s} | Borders: {s} | Icons: {s} | Countdown: {s}",
            .{
                pos_name,
                order_name,
                self.toast.count(),
                self.toast.min_width,
                self.toast.max_width,
                border_name,
                if (self.toast.show_border) "on" else "off",
                if (self.toast.show_icons) "on" else "off",
                if (self.toast.show_countdown) "on" else "off",
            },
        ) catch "?";
        const styled_info = info_style.render(ctx.allocator, info) catch info;

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator,
            \\Quick start: press p to move the toast around the screen.
            \\1: info  2: success  3: warning  4: error  5: persistent  6: long toast
            \\d: dismiss newest  x: dismiss oldest  D: dismiss all
            \\b: borders  i: icons  c: countdown  w: width preset  t: border style
            \\p/P: switch position  s: stack order  q: quit
        ) catch "";

        // Render toast notifications
        const toast_view = self.toast.viewPositioned(ctx.allocator, ctx.width, ctx.height -| 8, self.last_elapsed) catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n\n{s}\n\n{s}",
            .{ title, styled_info, help, toast_view },
        ) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.toast.deinit();
    }

    fn pushNumberedToast(self: *Model, ctx: *zz.Context, level: zz.ToastLevel, comptime fmt: []const u8, duration_ms: u64) void {
        self.msg_counter += 1;
        const text = std.fmt.allocPrint(ctx.allocator, fmt, .{self.msg_counter}) catch return;
        self.toast.push(text, level, duration_ms, ctx.elapsed) catch {};
    }

    fn cycleWidthPreset(self: *Model) void {
        self.width_preset_idx = (self.width_preset_idx + 1) % 3;
        switch (self.width_preset_idx) {
            0 => {
                self.toast.min_width = 18;
                self.toast.max_width = 34;
            },
            1 => {
                self.toast.min_width = 24;
                self.toast.max_width = 50;
            },
            2 => {
                self.toast.min_width = 32;
                self.toast.max_width = 72;
            },
            else => unreachable,
        }
    }

    fn cycleBorderStyle(self: *Model) void {
        self.border_style_idx = (self.border_style_idx + 1) % 3;
        self.toast.border_chars = switch (self.border_style_idx) {
            0 => zz.Border.rounded,
            1 => zz.Border.normal,
            2 => zz.Border.thick,
            else => unreachable,
        };
    }

    fn positionName(self: *const Model) []const u8 {
        return switch (self.toast.position) {
            .top_left => "top-left",
            .top_center => "top-center",
            .top_right => "top-right",
            .bottom_left => "bottom-left",
            .bottom_center => "bottom-center",
            .bottom_right => "bottom-right",
        };
    }

    fn announceSetting(self: *Model, ctx: *zz.Context, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(ctx.allocator, fmt, args) catch return;
        self.toast.push(text, .success, 1800, ctx.elapsed) catch {};
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
