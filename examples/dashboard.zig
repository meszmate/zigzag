//! ZigZag Dashboard Example
//! Demonstrates multi-component layout with various widgets.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    // Components
    spinner: zz.Spinner,
    progress: zz.Progress,
    timer: zz.components.Timer,

    // State
    frame_count: u64,
    task_progress: f64,
    tasks_complete: u32,
    total_tasks: u32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.spinner = zz.Spinner.init();
        self.spinner.setFrames(zz.Spinner.Styles.dots);

        self.progress = zz.Progress.init();
        self.progress.setWidth(30);
        self.progress.useGradient();

        self.timer = zz.components.Timer.stopwatch();
        self.timer.start();

        self.frame_count = 0;
        self.task_progress = 0;
        self.tasks_complete = 3;
        self.total_tasks = 10;

        // Start the animation loop
        return zz.Cmd(Msg).tickMs(16); // ~60fps
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => |t| {
                // Only update animations when not paused
                if (self.timer.running) {
                    self.frame_count = ctx.frame;
                    _ = self.spinner.update(@intCast(ctx.elapsed));
                    self.timer.update(t.delta);

                    // Simulate progress
                    if (self.task_progress < 100) {
                        self.task_progress += 0.1;
                        self.progress.setPercent(self.task_progress);
                    }
                }

                // Continue the animation loop
                return zz.Cmd(Msg).tickMs(16);
            },
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'r' => {
                            // Reset
                            self.task_progress = 0;
                            self.progress.setPercent(0);
                            self.timer.reset();
                        },
                        ' ' => self.timer.toggle(),
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return zz.Cmd(Msg).tickMs(16);
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Title
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.hex("#FF6B6B"));
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Dashboard") catch "Dashboard";

        // Stats section
        const stats_box = self.renderStats(ctx) catch "";

        // Progress section
        const progress_box = self.renderProgress(ctx) catch "";

        // Activity section
        const activity_box = self.renderActivity(ctx) catch "";

        // Layout - join horizontally
        const top_row = zz.joinHorizontal(ctx.allocator, &.{ stats_box, "  ", progress_box }) catch stats_box;
        const main_content = zz.joinVertical(ctx.allocator, &.{ top_row, "", activity_box }) catch top_row;

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Space: Pause/Resume timer  r: Reset  q: Quit",
        ) catch "";

        // Get max width for centering
        const main_width = zz.measure.maxLineWidth(main_content);
        const title_width = zz.measure.width(title);
        const help_width = zz.measure.width(help);
        const max_width = @max(main_width, @max(title_width, help_width));

        // Center elements
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_main = zz.place.place(ctx.allocator, max_width, zz.measure.height(main_content), .center, .top, main_content) catch main_content;
        const centered_help = zz.place.place(ctx.allocator, max_width, 1, .center, .top, help) catch help;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}",
            .{ centered_title, centered_main, centered_help },
        ) catch "Error";

        // Center in terminal
        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;
    }

    fn renderStats(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.cyan);
        box_style = box_style.paddingAll(1);
        box_style = box_style.width(25);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.cyan);
        header_style = header_style.inline_style(true);

        var value_style = zz.Style{};
        value_style = value_style.bold(true);
        value_style = value_style.fg(zz.Color.white);
        value_style = value_style.inline_style(true);

        var label_style = zz.Style{};
        label_style = label_style.fg(zz.Color.gray(15));
        label_style = label_style.inline_style(true);

        const header = try header_style.render(ctx.allocator, "Statistics");

        const frame_val = try value_style.render(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{d}", .{self.frame_count}));
        const frame_label = try label_style.render(ctx.allocator, "Frames");

        const task_val = try value_style.render(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{d}/{d}", .{ self.tasks_complete, self.total_tasks }));
        const task_label = try label_style.render(ctx.allocator, "Tasks");

        const fps_val = try value_style.render(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{d:.0}", .{ctx.fps()}));
        const fps_label = try label_style.render(ctx.allocator, "FPS");

        const content = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s} {s}\n{s} {s}\n{s} {s}",
            .{ header, frame_val, frame_label, task_val, task_label, fps_val, fps_label },
        );

        return box_style.render(ctx.allocator, content);
    }

    fn renderProgress(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.magenta);
        box_style = box_style.paddingAll(1);
        box_style = box_style.width(40);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.magenta);
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, "Progress");

        const progress_bar = try self.progress.view(ctx.allocator);

        var timer_label_style = zz.Style{};
        timer_label_style = timer_label_style.fg(zz.Color.gray(15));
        timer_label_style = timer_label_style.inline_style(true);
        const timer_label = timer_label_style.render(ctx.allocator, "Elapsed: ") catch "";
        const timer_view = try self.timer.view(ctx.allocator);

        // Show paused indicator
        var paused_style = zz.Style{};
        paused_style = paused_style.fg(zz.Color.yellow);
        paused_style = paused_style.inline_style(true);
        const paused_indicator = if (!self.timer.running)
            paused_style.render(ctx.allocator, " (PAUSED)") catch ""
        else
            "";

        const content = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}{s}{s}",
            .{ header, progress_bar, timer_label, timer_view, paused_indicator },
        );

        return box_style.render(ctx.allocator, content);
    }

    fn renderActivity(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.green);
        box_style = box_style.paddingAll(1);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.green);
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, "Activity");

        var complete_style = zz.Style{};
        complete_style = complete_style.fg(zz.Color.green);
        complete_style = complete_style.inline_style(true);

        var progress_style = zz.Style{};
        progress_style = progress_style.fg(zz.Color.yellow);
        progress_style = progress_style.inline_style(true);

        const is_complete = self.task_progress >= 100;

        const activity_view = if (is_complete)
            try complete_style.render(ctx.allocator, "✓ Done!")
        else
            try self.spinner.viewWithTitle(ctx.allocator, "Processing data...");

        const status = if (is_complete)
            try complete_style.render(ctx.allocator, "Complete!")
        else
            try progress_style.render(ctx.allocator, "In progress...");

        const content = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\nStatus: {s}",
            .{ header, activity_view, status },
        );

        return box_style.render(ctx.allocator, content);
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
