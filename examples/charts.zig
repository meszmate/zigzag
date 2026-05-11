//! Charts example showcasing a compact chart-focused screen.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    chart: zz.Chart,
    bars: zz.BarChart,
    spark: zz.Sparkline,
    phase: f64,
    sample_gate: u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
        window_size: zz.msg.WindowSize,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.chart = zz.Chart.init(ctx.persistent_allocator);
        self.chart.setSize(36, 9);
        self.chart.setMarker(.braille);
        self.chart.setLegendPosition(.top);
        self.chart.x_axis = .{
            .title = "Time",
            .tick_count = 5,
            .show_grid = true,
        };
        self.chart.y_axis = .{
            .title = "Load",
            .tick_count = 5,
            .show_grid = true,
        };

        var cpu = zz.ChartDataset.init(ctx.persistent_allocator, "CPU") catch unreachable;
        cpu.setStyle((zz.Style{}).fg(zz.Color.cyan).bold(true));
        cpu.setShowPoints(true);
        cpu.setInterpolation(.monotone_cubic);
        cpu.setInterpolationSteps(10);

        var mem = zz.ChartDataset.init(ctx.persistent_allocator, "Memory") catch unreachable;
        mem.setStyle((zz.Style{}).fg(zz.Color.magenta));
        mem.setInterpolation(.catmull_rom);
        mem.setInterpolationSteps(10);

        var backlog = zz.ChartDataset.init(ctx.persistent_allocator, "Backlog") catch unreachable;
        backlog.setStyle((zz.Style{}).fg(zz.Color.yellow));
        backlog.setGraphType(.area);
        backlog.setInterpolation(.step_center);
        backlog.setFillBaseline(18.0);

        for (0..24) |i| {
            const x = @as(f64, @floatFromInt(i));
            cpu.appendPoint(.{ .x = x, .y = 55.0 + @sin(x / 3.0) * 18.0 }) catch unreachable;
            mem.appendPoint(.{ .x = x, .y = 40.0 + @cos(x / 4.0) * 14.0 }) catch unreachable;
            backlog.appendPoint(.{ .x = x, .y = 18.0 + @sin(x / 2.4) * 7.0 + 3.0 }) catch unreachable;
        }

        self.chart.addDataset(cpu) catch unreachable;
        self.chart.addDataset(mem) catch unreachable;
        self.chart.addDataset(backlog) catch unreachable;

        self.bars = zz.BarChart.init(ctx.persistent_allocator);
        self.bars.setOrientation(.horizontal);
        self.bars.setBarWidth(1);
        self.bars.setGap(0);
        self.bars.show_values = false;
        self.bars.label_style = (zz.Style{}).fg(zz.Color.gray(18)).inline_style(true);
        self.bars.positive_style = (zz.Style{}).fg(zz.Color.green).inline_style(true);
        self.bars.negative_style = (zz.Style{}).fg(zz.Color.red).inline_style(true);
        self.bars.axis_style = (zz.Style{}).fg(zz.Color.gray(10)).inline_style(true);
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "api", 31) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "db", -12) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "queue", 22) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "cache", 14) catch unreachable) catch unreachable;

        self.spark = zz.Sparkline.init(ctx.persistent_allocator);
        self.spark.setWidth(22);
        self.spark.setSummary(.average);
        self.spark.setRetentionLimit(120);
        self.spark.setGradient(zz.Color.hex("#F97316"), zz.Color.hex("#22C55E"));

        for (0..60) |i| {
            const x = @as(f64, @floatFromInt(i));
            self.spark.push(30.0 + 10.0 * @sin(x / 5.0)) catch unreachable;
        }

        self.phase = 0;
        self.sample_gate = 0;
        self.syncChartsLayout(ctx);
        return zz.Cmd(Msg).tickMs(80);
    }

    pub fn deinit(self: *Model) void {
        self.chart.deinit();
        self.bars.deinit();
        self.spark.deinit();
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |key| switch (key.key) {
                .char => |c| if (c == 'q') return .quit,
                .escape => return .quit,
                else => {},
            },
            .window_size => {
                self.syncChartsLayout(ctx);
                return .none;
            },
            .tick => {
                self.sample_gate +%= 1;
                if (self.sample_gate >= 6) {
                    self.sample_gate = 0;
                    self.phase += 1.0;

                    var cpu = &self.chart.datasets.items[0];
                    var mem = &self.chart.datasets.items[1];
                    var backlog = &self.chart.datasets.items[2];
                    if (cpu.points.items.len >= 32) _ = cpu.points.orderedRemove(0);
                    if (mem.points.items.len >= 32) _ = mem.points.orderedRemove(0);
                    if (backlog.points.items.len >= 32) _ = backlog.points.orderedRemove(0);

                    const next_x = if (cpu.points.items.len == 0) 0.0 else cpu.points.items[cpu.points.items.len - 1].x + 1.0;
                    cpu.appendPoint(.{ .x = next_x, .y = 55.0 + @sin((self.phase + next_x) / 3.0) * 18.0 }) catch {};
                    mem.appendPoint(.{ .x = next_x, .y = 40.0 + @cos((self.phase + next_x) / 4.0) * 14.0 }) catch {};
                    backlog.appendPoint(.{ .x = next_x, .y = 18.0 + @sin((self.phase + next_x) / 2.4) * 7.0 + 3.0 }) catch {};
                    self.chart.x_axis.bounds = .{ .min = @max(0.0, next_x - 31.0), .max = next_x };

                    self.spark.push(30.0 + 10.0 * @sin((self.phase + next_x) / 5.0)) catch {};

                    self.bars.bars.items[0].value = 20.0 + @sin(self.phase / 3.0) * 18.0;
                    self.bars.bars.items[1].value = -5.0 - @cos(self.phase / 4.0) * 15.0;
                    self.bars.bars.items[2].value = 12.0 + @sin(self.phase / 5.0) * 12.0;
                    self.bars.bars.items[3].value = 8.0 + @cos(self.phase / 6.0) * 10.0;
                }

                self.syncChartsLayout(ctx);
                return zz.Cmd(Msg).tickMs(80);
            },
        }

        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        @constCast(self).syncChartsLayout(ctx);
        const content = self.composeContent(ctx) catch return "Error rendering charts";
        return zz.place.place(ctx.allocator, ctx.width, ctx.height, .center, .top, content) catch content;
    }

    fn chartsCompact(ctx: *const zz.Context) bool {
        return ctx.height <= 32 or ctx.width <= 110;
    }

    fn chartsUltraCompact(ctx: *const zz.Context) bool {
        return ctx.height <= 24 or ctx.width <= 88;
    }

    fn syncChartsLayout(self: *Model, ctx: *const zz.Context) void {
        const ultra = chartsUltraCompact(ctx);
        const compact = ultra or chartsCompact(ctx);

        self.chart.setSize(
            if (ultra) 30 else if (compact) 32 else 36,
            if (ultra) 6 else if (compact) 7 else 9,
        );
        self.chart.setLegendPosition(if (compact) .hidden else .top);
        self.chart.x_axis.title = if (compact) "" else "Time";
        self.chart.x_axis.tick_count = if (ultra) 4 else 5;
        self.chart.y_axis.title = if (compact) "" else "Load";
        self.chart.y_axis.tick_count = if (ultra) 4 else 5;

        self.bars.setSize(if (ultra) 18 else 22, 4);
        self.bars.show_values = !compact;
        self.spark.setWidth(if (ultra) 12 else if (compact) 16 else 22);
    }

    fn composeContent(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        const line_chart = try self.chart.view(ctx.allocator);
        const snapshot = try self.renderStaticSnapshot(ctx);
        const bars = try self.bars.view(ctx.allocator);
        const spark = try self.spark.view(ctx.allocator);
        const canvas = try self.renderCanvas(ctx);

        const ultra = chartsUltraCompact(ctx);
        const compact = ultra or chartsCompact(ctx);

        const top = try box(ctx, "Live Trend", line_chart);
        const bottom = if (ultra)
            try zz.join.horizontal(ctx.allocator, .middle, &.{
                try box(ctx, "Bars", bars),
                "  ",
                try box(ctx, "Canvas", canvas),
            })
        else if (compact)
            try zz.join.horizontal(ctx.allocator, .middle, &.{
                try box(ctx, "Bars", bars),
                "  ",
                try box(ctx, "Snapshot", snapshot),
            })
        else
            try zz.join.horizontal(ctx.allocator, .middle, &.{
                try box(ctx, "Bars", bars),
                "  ",
                try box(ctx, "Snapshot", snapshot),
                "  ",
                try box(ctx, "Canvas", canvas),
            });

        const spark_row = try inlineStat(ctx, "Spark", spark);
        const footer = try inlineStat(ctx, "Keys", "q quit");
        return try zz.join.vertical(ctx.allocator, .center, &.{ top, "", bottom, "", spark_row, footer });
    }

    fn renderCanvas(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        const ultra = chartsUltraCompact(ctx);
        const compact = ultra or chartsCompact(ctx);

        var canvas = zz.Canvas.init(ctx.allocator);
        defer canvas.deinit();

        canvas.setSize(if (ultra) 12 else if (compact) 14 else 16, if (ultra) 4 else 5);
        canvas.setMarker(.braille);
        canvas.setRanges(.{ .min = -1.2, .max = 1.2 }, .{ .min = -1.2, .max = 1.2 });

        var point_style = zz.Style{};
        point_style = point_style.fg(zz.Color.yellow);
        point_style = point_style.inline_style(true);

        for (0..64) |i| {
            const t = self.phase / 10.0 + @as(f64, @floatFromInt(i)) / 18.0;
            try canvas.drawPointStyled(@sin(t * 1.7), @cos(t * 2.3), point_style, null);
        }

        return try canvas.view(ctx.allocator);
    }

    fn renderStaticSnapshot(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        _ = self;
        const ultra = chartsUltraCompact(ctx);
        const compact = ultra or chartsCompact(ctx);

        var chart = zz.Chart.init(ctx.allocator);
        defer chart.deinit();

        chart.setSize(if (ultra) 16 else if (compact) 18 else 20, if (ultra) 5 else 6);
        chart.setMarker(.braille);
        chart.setLegendPosition(if (compact) .hidden else .top);
        chart.x_axis = .{ .title = if (compact) "" else "Quarter", .tick_count = if (ultra) 3 else 4, .show_grid = !ultra };
        chart.y_axis = .{ .title = if (compact) "" else "Revenue", .tick_count = if (ultra) 3 else 4, .show_grid = !ultra };

        var actual = try zz.ChartDataset.init(ctx.allocator, "Actual");
        actual.setStyle((zz.Style{}).fg(zz.Color.hex("#22C55E")).bold(true));
        actual.setInterpolation(.monotone_cubic);
        actual.setInterpolationSteps(10);
        actual.setShowPoints(true);
        try actual.setPoints(&.{
            .{ .x = 1, .y = 18 },
            .{ .x = 2, .y = 24 },
            .{ .x = 3, .y = 21 },
            .{ .x = 4, .y = 29 },
        });

        var forecast = try zz.ChartDataset.init(ctx.allocator, "Forecast");
        forecast.setStyle((zz.Style{}).fg(zz.Color.hex("#38BDF8")));
        forecast.setInterpolation(.step_end);
        try forecast.setPoints(&.{
            .{ .x = 1, .y = 16 },
            .{ .x = 2, .y = 22 },
            .{ .x = 3, .y = 23 },
            .{ .x = 4, .y = 27 },
        });

        try chart.addDataset(actual);
        try chart.addDataset(forecast);
        return try chart.view(ctx.allocator);
    }
};

fn box(ctx: *const zz.Context, title: []const u8, body: []const u8) ![]const u8 {
    var style = zz.Style{};
    style = style.borderAll(zz.Border.rounded);
    style = style.borderForeground(zz.Color.gray(12));
    style = style.paddingLeft(1).paddingRight(1);

    var header_style = zz.Style{};
    header_style = header_style.bold(true);
    header_style = header_style.fg(zz.Color.cyan);
    header_style = header_style.inline_style(true);
    const header = try header_style.render(ctx.allocator, title);

    const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n{s}", .{ header, body });
    return try style.render(ctx.allocator, content);
}

fn inlineStat(ctx: *const zz.Context, label: []const u8, value: []const u8) ![]const u8 {
    var label_style = zz.Style{};
    label_style = label_style.fg(zz.Color.gray(15));
    label_style = label_style.inline_style(true);
    const rendered_label = try label_style.render(ctx.allocator, label);

    var value_style = zz.Style{};
    value_style = value_style.bold(true);
    value_style = value_style.fg(zz.Color.white);
    value_style = value_style.inline_style(true);
    const rendered_value = try value_style.render(ctx.allocator, value);

    return try std.fmt.allocPrint(ctx.allocator, "{s}: {s}", .{ rendered_label, rendered_value });
}

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();
    try program.run();
}
