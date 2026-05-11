//! ZigZag Slider Example
//! Demonstrates various slider styles and configurations.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    volume: zz.Slider,
    brightness: zz.Slider,
    temperature: zz.Slider,
    progress_slider: zz.Slider,
    focus_group: zz.FocusGroup(4),

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        // Default style
        self.volume = zz.Slider.init(0, 100);
        self.volume.label = "Volume:";
        self.volume.value = 50;
        self.volume.show_percent = true;

        // Block style with gradient
        self.brightness = zz.SliderStyle.block();
        self.brightness.label = "Brightness:";
        self.brightness.value = 75;
        self.brightness.show_value = true;
        self.brightness.setGradient(zz.Color.fromRgb(50, 50, 50), zz.Color.yellow);

        // Thin style with decimal precision
        self.temperature = zz.SliderStyle.thin();
        self.temperature.min = -20;
        self.temperature.max = 50;
        self.temperature.value = 22;
        self.temperature.step = 0.5;
        self.temperature.large_step = 5;
        self.temperature.precision = 1;
        self.temperature.label = "Temp (C):";
        self.temperature.show_bounds = true;

        // ASCII style
        self.progress_slider = zz.SliderStyle.ascii();
        self.progress_slider.label = "Speed:";
        self.progress_slider.value = 30;
        self.progress_slider.width = 40;

        self.focus_group = .{};
        self.focus_group.add(&self.volume);
        self.focus_group.add(&self.brightness);
        self.focus_group.add(&self.temperature);
        self.focus_group.add(&self.progress_slider);
        self.focus_group.initFocus();

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| if (c == 'q') return .quit,
                    .escape => return .quit,
                    else => {},
                }

                if (self.focus_group.handleKey(k)) return .none;

                self.volume.handleKey(k);
                self.brightness.handleKey(k);
                self.temperature.handleKey(k);
                self.progress_slider.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Slider Example") catch "Slider Example";

        const vol = self.volume.view(ctx.allocator) catch "error";
        const bright = self.brightness.view(ctx.allocator) catch "error";
        const temp = self.temperature.view(ctx.allocator) catch "error";
        const spd = self.progress_slider.view(ctx.allocator) catch "error";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Tab: switch | Left/Right or h/l: adjust | Home/End: min/max | PgUp/PgDn: large step | q: quit",
        ) catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}\n\n{s}\n\n{s}\n\n{s}",
            .{ title, vol, bright, temp, spd, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
