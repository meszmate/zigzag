//! ZigZag Showcase Example
//! Comprehensive multi-tab application demonstrating ALL framework features.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const Tab = enum {
    dashboard,
    charts,
    data,
    files,
    editor,
    unicode,

    pub fn name(self: Tab) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .charts => "Charts",
            .data => "Data",
            .files => "Files",
            .editor => "Editor",
            .unicode => "Unicode",
        };
    }

    pub fn index(self: Tab) usize {
        return @intFromEnum(self);
    }
};

const Model = struct {
    // Tab state
    active_tab: Tab,

    // Dashboard components
    spinner: zz.Spinner,
    progress: zz.Progress,
    timer: zz.components.Timer,
    sparkline: zz.Sparkline,
    chart: zz.Chart,
    bars: zz.BarChart,
    chart_sample_gate: u8,
    notifications: zz.Notification,
    frame_count: u64,
    paused: bool,
    last_elapsed: u64,

    // Data tab components
    table: zz.Table(4),
    tree: zz.Tree(void),
    styled_list: zz.StyledList,
    data_focus: DataFocus,

    // Files tab
    // (simplified - just show a viewport with directory listing)
    file_viewport: zz.components.Viewport,

    // Editor tab
    text_area: zz.TextArea,

    // Global
    confirm: zz.Confirm,
    help: zz.components.Help,
    show_quit_confirm: bool,

    const DataFocus = enum { table_focus, tree_focus };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
        window_size: struct { width: u16, height: u16 },
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        // Dashboard
        self.spinner = zz.Spinner.init();
        self.spinner.setFrames(zz.Spinner.Styles.dots);

        self.progress = zz.Progress.init();
        self.progress.setWidth(30);
        self.progress.setGradient(zz.Color.hex("#FF6B6B"), zz.Color.hex("#4ECDC4"));

        self.timer = zz.components.Timer.stopwatch();
        self.timer.start();

        self.sparkline = zz.Sparkline.init(ctx.persistent_allocator);
        self.sparkline.setWidth(30);
        self.sparkline.setGradient(zz.Color.hex("#F97316"), zz.Color.hex("#22C55E"));

        self.chart = zz.Chart.init(ctx.persistent_allocator);
        self.chart.setSize(42, 13);
        self.chart.setMarker(.braille);
        self.chart.setLegendPosition(.top);
        self.chart.x_axis = .{
            .title = "Time",
            .tick_count = 5,
            .show_grid = true,
        };
        self.chart.y_axis = .{
            .title = "Utilization",
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
            cpu.appendPoint(.{ .x = x, .y = 52.0 + @sin(x / 3.0) * 15.0 }) catch unreachable;
            mem.appendPoint(.{ .x = x, .y = 44.0 + @cos(x / 4.0) * 12.0 }) catch unreachable;
            backlog.appendPoint(.{ .x = x, .y = 18.0 + @sin(x / 2.6) * 7.0 + 3.0 }) catch unreachable;
        }

        self.chart.addDataset(cpu) catch unreachable;
        self.chart.addDataset(mem) catch unreachable;
        self.chart.addDataset(backlog) catch unreachable;

        self.bars = zz.BarChart.init(ctx.persistent_allocator);
        self.bars.setSize(28, 8);
        self.bars.setOrientation(.horizontal);
        self.bars.show_values = true;
        self.bars.label_style = (zz.Style{}).fg(zz.Color.gray(18)).inline_style(true);
        self.bars.positive_style = (zz.Style{}).fg(zz.Color.green).inline_style(true);
        self.bars.negative_style = (zz.Style{}).fg(zz.Color.red).inline_style(true);
        self.bars.axis_style = (zz.Style{}).fg(zz.Color.gray(10)).inline_style(true);
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "api", 22) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "db", -10) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "queue", 15) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "cache", 9) catch unreachable) catch unreachable;

        self.notifications = zz.Notification.init(ctx.persistent_allocator);

        self.frame_count = 0;
        self.paused = false;
        self.last_elapsed = 0;
        self.chart_sample_gate = 0;

        // Data tab
        self.table = zz.Table(4).init(ctx.persistent_allocator);
        self.table.setHeaders(.{ "Server", "Status", "Uptime", "Load" });
        self.table.setBorder(zz.Border.rounded);
        var alt_style = zz.Style{};
        alt_style = alt_style.fg(zz.Color.gray(18));
        alt_style = alt_style.inline_style(true);
        self.table.alt_row_style = alt_style;
        self.table.visible_rows = 8;

        self.table.addRow(.{ "web-01", "online", "45d 3h", "0.42" }) catch {};
        self.table.addRow(.{ "web-02", "online", "45d 3h", "0.38" }) catch {};
        self.table.addRow(.{ "db-01", "online", "120d 7h", "0.71" }) catch {};
        self.table.addRow(.{ "db-02", "standby", "120d 7h", "0.12" }) catch {};
        self.table.addRow(.{ "cache-01", "online", "30d 2h", "0.55" }) catch {};
        self.table.addRow(.{ "cache-02", "warning", "30d 2h", "0.89" }) catch {};
        self.table.addRow(.{ "worker-01", "online", "15d 8h", "0.63" }) catch {};
        self.table.addRow(.{ "worker-02", "offline", "0d 0h", "0.00" }) catch {};
        self.table.addRow(.{ "monitor", "online", "60d 1h", "0.22" }) catch {};
        self.table.addRow(.{ "lb-01", "online", "90d 5h", "0.45" }) catch {};
        self.table.focus();

        // Tree
        self.tree = zz.Tree(void).init(ctx.persistent_allocator);
        self.tree.enumerator = .{
            .item_prefix = "\u{251c}\u{2500}\u{2500} ",
            .last_prefix = "\u{2570}\u{2500}\u{2500} ",
            .indent_prefix = "\u{2502}   ",
            .empty_prefix = "    ",
        };
        const root = self.tree.addRoot({}, "project/") catch 0;
        const src = self.tree.addChild(root, {}, "src/") catch 0;
        _ = self.tree.addChild(src, {}, "main.zig") catch {};
        _ = self.tree.addChild(src, {}, "lib.zig") catch {};
        const comp = self.tree.addChild(src, {}, "components/") catch 0;
        _ = self.tree.addChild(comp, {}, "button.zig") catch {};
        _ = self.tree.addChild(comp, {}, "input.zig") catch {};
        const tests = self.tree.addChild(root, {}, "tests/") catch 0;
        _ = self.tree.addChild(tests, {}, "unit_test.zig") catch {};
        _ = self.tree.addChild(root, {}, "build.zig") catch {};
        _ = self.tree.addChild(root, {}, "README.md") catch {};

        // Styled list
        self.styled_list = zz.StyledList.init(ctx.persistent_allocator);
        self.styled_list.setEnumerator(.roman);
        self.styled_list.addItem("Setup development environment") catch {};
        self.styled_list.addItem("Implement core features") catch {};
        self.styled_list.addItemNested("Style system", 1) catch {};
        self.styled_list.addItemNested("Component library", 1) catch {};
        self.styled_list.addItem("Write tests") catch {};
        self.styled_list.addItem("Deploy to production") catch {};

        self.data_focus = .table_focus;

        // Files tab - viewport
        self.file_viewport = zz.components.Viewport.init(ctx.persistent_allocator, 60, 15);
        self.file_viewport.setContent(
            \\  Directory listing:
            \\
            \\  drwxr-xr-x  src/
            \\  drwxr-xr-x  examples/
            \\  drwxr-xr-x  tests/
            \\  -rw-r--r--  build.zig
            \\  -rw-r--r--  README.md
            \\  -rw-r--r--  LICENSE
            \\  drwxr-xr-x  .git/
            \\  -rw-r--r--  .gitignore
            \\
            \\  Use j/k to scroll, Tab to switch tabs.
        ) catch {};

        // Editor tab
        self.text_area = zz.TextArea.init(ctx.persistent_allocator);
        self.text_area.setSize(@min(ctx.width -| 4, 70), @min(ctx.height -| 8, 20));
        self.text_area.line_numbers = true;
        self.text_area.word_wrap = true;
        self.text_area.setValue(
            \\const std = @import("std");
            \\
            \\pub fn main() !void {
            \\    const stdout = std.Io.getStdOut().writer();
            \\    try stdout.print("Hello, {s}!\n", .{"world"});
            \\}
            \\
            \\// Edit this code with the text area component.
            \\// Supports line numbers, word wrap, and full
            \\// cursor navigation.
        ) catch {};

        // Global
        self.active_tab = .dashboard;
        self.confirm = zz.Confirm.init("Are you sure you want to quit?");
        self.show_quit_confirm = false;

        self.help = zz.components.Help.init(ctx.persistent_allocator);
        self.help.addBinding("1-6", "tabs") catch {};
        self.help.addBinding("Tab", "next tab") catch {};
        self.help.addBinding("Ctrl+Q", "quit") catch {};

        return zz.Cmd(Msg).tickMs(16);
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => |t| {
                self.last_elapsed = ctx.elapsed;
                if (!self.paused) {
                    self.frame_count = ctx.frame;
                    _ = self.spinner.update(@intCast(ctx.elapsed));
                    self.timer.update(t.delta);

                    // Simulate progress
                    if (self.progress.percent() < 100) {
                        self.progress.increment(0.05);
                    }

                    // Update sparkline with FPS
                    self.sparkline.push(ctx.fps()) catch {};

                    self.chart_sample_gate +%= 1;
                    if (self.chart_sample_gate >= 20) {
                        self.chart_sample_gate = 0;

                        var cpu = &self.chart.datasets.items[0];
                        var mem = &self.chart.datasets.items[1];
                        var backlog = &self.chart.datasets.items[2];
                        if (cpu.points.items.len >= 32) _ = cpu.points.orderedRemove(0);
                        if (mem.points.items.len >= 32) _ = mem.points.orderedRemove(0);
                        if (backlog.points.items.len >= 32) _ = backlog.points.orderedRemove(0);

                        const next_x = if (cpu.points.items.len == 0) 0.0 else cpu.points.items[cpu.points.items.len - 1].x + 1.0;
                        const phase = @as(f64, @floatFromInt(ctx.elapsed));
                        cpu.appendPoint(.{ .x = next_x, .y = 52.0 + @sin((phase / 2_000_000.0 + next_x) / 3.0) * 15.0 }) catch {};
                        mem.appendPoint(.{ .x = next_x, .y = 44.0 + @cos((phase / 2_000_000.0 + next_x) / 4.0) * 12.0 }) catch {};
                        backlog.appendPoint(.{ .x = next_x, .y = 18.0 + @sin((phase / 2_000_000.0 + next_x) / 2.6) * 7.0 + 3.0 }) catch {};
                        self.chart.x_axis.bounds = .{ .min = @max(0.0, next_x - 31.0), .max = next_x };

                        self.bars.bars.items[0].value = 20.0 + @sin(phase / 800_000_000.0) * 11.0;
                        self.bars.bars.items[1].value = -7.0 - @cos(phase / 900_000_000.0) * 8.0;
                        self.bars.bars.items[2].value = 12.0 + @sin(phase / 700_000_000.0) * 9.0;
                        self.bars.bars.items[3].value = 8.0 + @cos(phase / 600_000_000.0) * 6.0;
                    }

                    // Update notifications
                    self.notifications.update(ctx.elapsed);
                }

                return zz.Cmd(Msg).tickMs(16);
            },
            .window_size => {
                self.text_area.setSize(@min(ctx.width -| 4, 70), @min(ctx.height -| 8, 20));
                return .none;
            },
            .key => |k| {
                // Handle quit confirm first
                if (self.show_quit_confirm) {
                    self.confirm.handleKey(k);
                    if (self.confirm.result()) |confirmed| {
                        self.show_quit_confirm = false;
                        if (confirmed) return .quit;
                    }
                    return .none;
                }

                // Global keys
                if (k.modifiers.ctrl) {
                    switch (k.key) {
                        .char => |c| switch (c) {
                            'q' => {
                                self.show_quit_confirm = true;
                                self.confirm.show();
                                return .none;
                            },
                            else => {},
                        },
                        else => {},
                    }
                    // Pass to editor if active
                    if (self.active_tab == .editor) {
                        self.text_area.handleKey(k);
                    }
                    return .none;
                }

                switch (k.key) {
                    .char => |c| switch (c) {
                        '1' => self.active_tab = .dashboard,
                        '2' => self.active_tab = .charts,
                        '3' => self.active_tab = .data,
                        '4' => self.active_tab = .files,
                        '5' => self.active_tab = .editor,
                        '6' => self.active_tab = .unicode,
                        else => self.handleTabKey(k),
                    },
                    .tab => {
                        if (k.modifiers.shift) {
                            self.active_tab = switch (self.active_tab) {
                                .dashboard => .unicode,
                                .charts => .dashboard,
                                .data => .charts,
                                .files => .data,
                                .editor => .files,
                                .unicode => .editor,
                            };
                        } else {
                            self.active_tab = switch (self.active_tab) {
                                .dashboard => .charts,
                                .charts => .data,
                                .data => .files,
                                .files => .editor,
                                .editor => .unicode,
                                .unicode => .dashboard,
                            };
                        }
                    },
                    .escape => {
                        // Do nothing (reserved)
                    },
                    else => self.handleTabKey(k),
                }
                return .none;
            },
        }
        return .none;
    }

    fn handleTabKey(self: *Model, k: zz.KeyEvent) void {
        switch (self.active_tab) {
            .dashboard => {
                switch (k.key) {
                    .char => |c| switch (c) {
                        ' ' => {
                            self.paused = !self.paused;
                            if (self.paused) self.timer.stop() else self.timer.start();
                        },
                        'r' => {
                            self.progress.setPercent(0);
                            self.timer.reset();
                            self.timer.start();
                            self.paused = false;
                        },
                        'n' => {
                            const texts = [_][]const u8{
                                "Build completed successfully",
                                "New deployment ready",
                                "Warning: high CPU usage",
                                "Error: connection timeout",
                            };
                            const levels = [_]zz.components.notification.Level{
                                .success,
                                .info,
                                .warning,
                                .err,
                            };
                            const idx = self.frame_count % 4;
                            self.notifications.push(
                                texts[idx],
                                levels[idx],
                                3000,
                                self.last_elapsed,
                            ) catch {};
                        },
                        else => {},
                    },
                    else => {},
                }
            },
            .charts => {},
            .data => {
                switch (k.key) {
                    .char => |c| switch (c) {
                        '\t' => {
                            // Switch focus between table and tree
                            if (self.data_focus == .table_focus) {
                                self.data_focus = .tree_focus;
                                self.table.blur();
                            } else {
                                self.data_focus = .table_focus;
                                self.table.focus();
                            }
                        },
                        else => {
                            if (self.data_focus == .table_focus) {
                                self.table.handleKey(k);
                            }
                        },
                    },
                    else => {
                        if (self.data_focus == .table_focus) {
                            self.table.handleKey(k);
                        }
                    },
                }
            },
            .files => {
                self.file_viewport.handleKey(k);
            },
            .editor => {
                self.text_area.handleKey(k);
            },
            .unicode => {},
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Build layout
        const tab_bar = self.renderTabBar(ctx) catch return "Error rendering tab bar";
        const content = self.renderActiveTab(ctx) catch return "Error rendering content";
        const status = self.renderStatusBar(ctx) catch return "Error rendering status";

        // Confirmation overlay
        const confirm_view = if (self.show_quit_confirm)
            self.confirm.view(ctx.allocator) catch ""
        else
            "";

        // Compose full view
        const main_view = if (self.show_quit_confirm)
            zz.joinVertical(ctx.allocator, &.{ tab_bar, "", content, "", confirm_view, "", status }) catch tab_bar
        else
            zz.joinVertical(ctx.allocator, &.{ tab_bar, "", content, "", status }) catch tab_bar;

        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .top,
            main_view,
        ) catch main_view;
    }

    fn chartsCompact(ctx: *const zz.Context) bool {
        return ctx.height <= 34 or ctx.width <= 120;
    }

    fn chartsUltraCompact(ctx: *const zz.Context) bool {
        return ctx.height <= 28 or ctx.width <= 96;
    }

    fn syncChartsLayout(self: *Model, ctx: *const zz.Context) void {
        const ultra = chartsUltraCompact(ctx);
        const compact = ultra or chartsCompact(ctx);

        self.chart.setSize(
            if (ultra) 34 else if (compact) 38 else 42,
            if (ultra) 8 else if (compact) 10 else 13,
        );
        self.chart.setLegendPosition(if (ultra) .hidden else .top);
        self.chart.x_axis.title = if (compact) "" else "Time";
        self.chart.x_axis.tick_count = if (ultra) 4 else 5;
        self.chart.y_axis.title = if (compact) "" else "Utilization";
        self.chart.y_axis.tick_count = if (ultra) 4 else 5;

        self.bars.setSize(if (ultra) 22 else 26, if (ultra) 4 else 5);
        self.bars.setBarWidth(1);
        self.bars.setGap(0);
        self.bars.show_values = !compact;
    }

    fn renderTabBar(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var result: Writer.Allocating = .init(ctx.allocator);
        const writer = &result.writer;

        const tabs = [_]Tab{ .dashboard, .charts, .data, .files, .editor, .unicode };
        for (tabs, 0..) |tab, i| {
            if (i > 0) try writer.writeAll("  ");

            if (tab == self.active_tab) {
                var active_style = zz.Style{};
                active_style = active_style.bold(true);
                active_style = active_style.fg(zz.Color.hex("#4ECDC4"));
                active_style = active_style.underline(true);
                active_style = active_style.inline_style(true);
                const label = try std.fmt.allocPrint(ctx.allocator, "{d}:{s}", .{ i + 1, tab.name() });
                const styled = try active_style.render(ctx.allocator, label);
                try writer.writeAll(styled);
            } else {
                var tab_style = zz.Style{};
                tab_style = tab_style.fg(zz.Color.gray(12));
                tab_style = tab_style.inline_style(true);
                const label = try std.fmt.allocPrint(ctx.allocator, "{d}:{s}", .{ i + 1, tab.name() });
                const styled = try tab_style.render(ctx.allocator, label);
                try writer.writeAll(styled);
            }
        }

        // Wrap in border
        const bar_content = try result.toOwnedSlice();
        var bar_style = zz.Style{};
        bar_style = bar_style.borderAll(zz.Border.rounded);
        bar_style = bar_style.borderForeground(zz.Color.gray(8));
        bar_style = bar_style.paddingLeft(1).paddingRight(1);
        bar_style = bar_style.width(@min(ctx.width -| 2, 60));

        return bar_style.render(ctx.allocator, bar_content);
    }

    fn renderActiveTab(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        return switch (self.active_tab) {
            .dashboard => self.renderDashboard(ctx),
            .charts => self.renderChartsTab(ctx),
            .data => self.renderDataTab(ctx),
            .files => self.renderFilesTab(ctx),
            .editor => self.renderEditorTab(ctx),
            .unicode => renderUnicodeTab(ctx),
        };
    }

    fn renderDashboard(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        // Left column: Stats
        const stats = try self.renderDashboardStats(ctx);

        // Right column: Progress + Timer
        const progress_box = try self.renderDashboardProgress(ctx);

        // Top row
        const top_row = try zz.joinHorizontal(ctx.allocator, &.{ stats, "  ", progress_box });

        // Bottom: Sparkline
        const sparkline_view = try self.sparkline.view(ctx.allocator);
        var spark_label_style = zz.Style{};
        spark_label_style = spark_label_style.fg(zz.Color.gray(15));
        spark_label_style = spark_label_style.inline_style(true);
        const spark_label = try spark_label_style.render(ctx.allocator, "FPS: ");
        const sparkline_row = try std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ spark_label, sparkline_view });

        // Spinner
        const spinner_view = if (self.progress.isComplete()) blk: {
            var done_style = zz.Style{};
            done_style = done_style.fg(zz.Color.green);
            done_style = done_style.inline_style(true);
            break :blk try done_style.render(ctx.allocator, "* All tasks complete!");
        } else try self.spinner.viewWithTitle(ctx.allocator, "Processing...");

        // Notifications
        const notif_view = try self.notifications.view(ctx.allocator);
        const has_notifs = self.notifications.hasMessages();

        // Bottom box
        var bottom_style = zz.Style{};
        bottom_style = bottom_style.borderAll(zz.Border.rounded);
        bottom_style = bottom_style.borderForeground(zz.Color.green);
        bottom_style = bottom_style.paddingAll(1);

        const bottom_content = if (has_notifs)
            try std.fmt.allocPrint(ctx.allocator, "{s}\n{s}\n\n{s}", .{ sparkline_row, spinner_view, notif_view })
        else
            try std.fmt.allocPrint(ctx.allocator, "{s}\n{s}", .{ sparkline_row, spinner_view });

        const bottom_box = try bottom_style.render(ctx.allocator, bottom_content);

        return zz.joinVertical(ctx.allocator, &.{ top_row, "", bottom_box });
    }

    fn renderDashboardStats(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.cyan);
        box_style = box_style.borderTopForeground(zz.Color.hex("#4ECDC4"));
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
        const frame_label = try label_style.render(ctx.allocator, " Frames");
        const fps_val = try value_style.render(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{d:.0}", .{ctx.fps()}));
        const fps_label = try label_style.render(ctx.allocator, " FPS");

        var paused_style = zz.Style{};
        paused_style = paused_style.fg(zz.Color.yellow);
        paused_style = paused_style.inline_style(true);
        const status = if (self.paused)
            try paused_style.render(ctx.allocator, "PAUSED")
        else blk: {
            var run_style = zz.Style{};
            run_style = run_style.fg(zz.Color.green);
            run_style = run_style.inline_style(true);
            break :blk try run_style.render(ctx.allocator, "RUNNING");
        };

        const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}{s}\n{s}{s}\n\n{s}", .{
            header, frame_val, frame_label, fps_val, fps_label, status,
        });

        return box_style.render(ctx.allocator, content);
    }

    fn renderDashboardProgress(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.double);
        box_style = box_style.borderForeground(zz.Color.magenta);
        box_style = box_style.paddingAll(1);
        box_style = box_style.width(35);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.magenta);
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, "Progress");

        const progress_bar = try self.progress.view(ctx.allocator);

        var timer_label_style = zz.Style{};
        timer_label_style = timer_label_style.fg(zz.Color.gray(15));
        timer_label_style = timer_label_style.inline_style(true);
        const timer_label = try timer_label_style.render(ctx.allocator, "Elapsed: ");
        const timer_view = try self.timer.view(ctx.allocator);

        const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}\n\n{s}{s}", .{
            header, progress_bar, timer_label, timer_view,
        });

        return box_style.render(ctx.allocator, content);
    }

    fn renderDataTab(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        // Left: Interactive table
        const table_view = try self.table.view(ctx.allocator);
        var table_box_style = zz.Style{};
        table_box_style = table_box_style.borderAll(zz.Border.normal);
        if (self.data_focus == .table_focus) {
            table_box_style = table_box_style.borderForeground(zz.Color.cyan);
        } else {
            table_box_style = table_box_style.borderForeground(zz.Color.gray(8));
        }
        table_box_style = table_box_style.paddingAll(0);
        const table_boxed = try table_box_style.render(ctx.allocator, table_view);

        // Right top: Tree
        const tree_view = try self.tree.view(ctx.allocator);
        var tree_box_style = zz.Style{};
        tree_box_style = tree_box_style.borderAll(zz.Border.rounded);
        if (self.data_focus == .tree_focus) {
            tree_box_style = tree_box_style.borderForeground(zz.Color.cyan);
        } else {
            tree_box_style = tree_box_style.borderForeground(zz.Color.gray(8));
        }
        tree_box_style = tree_box_style.paddingLeft(1).paddingRight(1);

        var tree_header_style = zz.Style{};
        tree_header_style = tree_header_style.bold(true);
        tree_header_style = tree_header_style.fg(zz.Color.yellow);
        tree_header_style = tree_header_style.inline_style(true);
        const tree_header = try tree_header_style.render(ctx.allocator, "Project Structure");
        const tree_content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ tree_header, tree_view });
        const tree_boxed = try tree_box_style.render(ctx.allocator, tree_content);

        // Right bottom: Styled list
        const list_view = try self.styled_list.view(ctx.allocator);
        var list_box_style = zz.Style{};
        list_box_style = list_box_style.borderAll(zz.Border.rounded);
        list_box_style = list_box_style.borderForeground(zz.Color.gray(8));
        list_box_style = list_box_style.paddingLeft(1).paddingRight(1);

        var list_header_style = zz.Style{};
        list_header_style = list_header_style.bold(true);
        list_header_style = list_header_style.fg(zz.Color.green);
        list_header_style = list_header_style.inline_style(true);
        const list_header = try list_header_style.render(ctx.allocator, "TODO Items");
        const list_content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ list_header, list_view });
        const list_boxed = try list_box_style.render(ctx.allocator, list_content);

        // Right column
        const right_col = try zz.joinVertical(ctx.allocator, &.{ tree_boxed, list_boxed });

        // Data tab hint
        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(10));
        hint_style = hint_style.italic(true);
        hint_style = hint_style.inline_style(true);
        const focus_hint = if (self.data_focus == .table_focus)
            try hint_style.render(ctx.allocator, "j/k: navigate table  Tab(in data): switch focus")
        else
            try hint_style.render(ctx.allocator, "Tab(in data): switch focus to table");

        const main_row = try zz.joinHorizontal(ctx.allocator, &.{ table_boxed, " ", right_col });

        return zz.joinVertical(ctx.allocator, &.{ main_row, "", focus_hint });
    }

    fn renderChartsTab(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        @constCast(self).syncChartsLayout(ctx);

        const trend_view = try self.chart.view(ctx.allocator);
        const bars_view = try self.bars.view(ctx.allocator);
        const snapshot_view = try self.renderStaticSnapshot(ctx);
        const canvas_view = try self.renderChartCanvas(ctx);

        var trend_style = zz.Style{};
        trend_style = trend_style.borderAll(zz.Border.rounded);
        trend_style = trend_style.borderForeground(zz.Color.cyan);
        trend_style = trend_style.paddingLeft(1).paddingRight(1);

        var bars_style = zz.Style{};
        bars_style = bars_style.borderAll(zz.Border.rounded);
        bars_style = bars_style.borderForeground(zz.Color.green);
        bars_style = bars_style.paddingLeft(1).paddingRight(1);

        var aux_style = zz.Style{};
        aux_style = aux_style.borderAll(zz.Border.rounded);
        aux_style = aux_style.borderForeground(zz.Color.yellow);
        aux_style = aux_style.paddingLeft(1).paddingRight(1);

        const trend_box = try trend_style.render(ctx.allocator, try self.section(ctx, "Interpolated Lines + Area", trend_view));
        const bars_box = try bars_style.render(ctx.allocator, try self.section(ctx, "Horizontal Bars", bars_view));
        const snapshot_box = try aux_style.render(ctx.allocator, try self.section(ctx, "Static Snapshot", snapshot_view));
        const canvas_box = try aux_style.render(ctx.allocator, try self.section(ctx, "Canvas Plot", canvas_view));

        if (chartsUltraCompact(ctx)) {
            return zz.join.vertical(ctx.allocator, .center, &.{ trend_box, "", bars_box });
        }

        const bottom = if (chartsCompact(ctx))
            try zz.join.horizontal(ctx.allocator, .middle, &.{ bars_box, "  ", snapshot_box })
        else
            try zz.join.horizontal(ctx.allocator, .middle, &.{ bars_box, "  ", snapshot_box, "  ", canvas_box });

        return zz.join.vertical(ctx.allocator, .center, &.{ trend_box, "", bottom });
    }

    fn renderFilesTab(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        const viewport_view = try self.file_viewport.view(ctx.allocator);

        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.thick);
        box_style = box_style.borderForeground(zz.Color.blue);
        box_style = box_style.paddingAll(1);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.blue);
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, "File Browser");

        const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ header, viewport_view });

        return box_style.render(ctx.allocator, content);
    }

    fn renderChartCanvas(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        _ = self;
        const compact = chartsCompact(ctx);
        const ultra = chartsUltraCompact(ctx);
        var canvas = zz.Canvas.init(ctx.allocator);
        defer canvas.deinit();

        canvas.setSize(if (ultra) 16 else if (compact) 18 else 20, if (ultra) 5 else if (compact) 6 else 8);
        canvas.setMarker(.braille);
        canvas.setRanges(.{ .min = -1.2, .max = 1.2 }, .{ .min = -1.2, .max = 1.2 });

        var style = zz.Style{};
        style = style.fg(zz.Color.yellow);
        style = style.inline_style(true);

        for (0..64) |i| {
            const t = @as(f64, @floatFromInt(i)) / 10.0;
            try canvas.drawPointStyled(@sin(t * 1.5), @cos(t * 2.1), style, null);
        }

        return try canvas.view(ctx.allocator);
    }

    fn renderStaticSnapshot(_: *const Model, ctx: *const zz.Context) ![]const u8 {
        const compact = chartsCompact(ctx);
        const ultra = chartsUltraCompact(ctx);
        var chart = zz.Chart.init(ctx.allocator);
        defer chart.deinit();

        chart.setSize(if (ultra) 16 else if (compact) 18 else 20, if (ultra) 6 else if (compact) 7 else 8);
        chart.setMarker(.braille);
        chart.setLegendPosition(if (compact) .hidden else .top);
        chart.x_axis = .{ .title = if (compact) "" else "Quarter", .tick_count = if (ultra) 3 else 4, .show_grid = !ultra };
        chart.y_axis = .{ .title = if (compact) "" else "Score", .tick_count = if (ultra) 3 else 4, .show_grid = !ultra };

        var actual = try zz.ChartDataset.init(ctx.allocator, "A");
        actual.setStyle((zz.Style{}).fg(zz.Color.hex("#22C55E")).bold(true));
        actual.setInterpolation(.monotone_cubic);
        actual.setInterpolationSteps(10);
        try actual.setPoints(&.{
            .{ .x = 1, .y = 18 },
            .{ .x = 2, .y = 24 },
            .{ .x = 3, .y = 21 },
            .{ .x = 4, .y = 29 },
        });

        var target = try zz.ChartDataset.init(ctx.allocator, "T");
        target.setStyle((zz.Style{}).fg(zz.Color.hex("#38BDF8")));
        target.setInterpolation(.step_end);
        try target.setPoints(&.{
            .{ .x = 1, .y = 16 },
            .{ .x = 2, .y = 22 },
            .{ .x = 3, .y = 23 },
            .{ .x = 4, .y = 27 },
        });

        try chart.addDataset(actual);
        try chart.addDataset(target);
        return try chart.view(ctx.allocator);
    }

    fn section(self: *const Model, ctx: *const zz.Context, title: []const u8, body: []const u8) ![]const u8 {
        _ = self;
        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.white);
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, title);
        return try std.fmt.allocPrint(ctx.allocator, "{s}\n{s}", .{ header, body });
    }

    fn renderEditorTab(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        const editor_view = try self.text_area.view(ctx.allocator);

        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.normal);
        box_style = box_style.borderForeground(zz.Color.hex("#FF6B6B"));
        box_style = box_style.paddingLeft(1).paddingRight(1);

        var header_style = zz.Style{};
        header_style = header_style.bold(true);
        header_style = header_style.fg(zz.Color.hex("#FF6B6B"));
        header_style = header_style.inline_style(true);
        const header = try header_style.render(ctx.allocator, "Text Editor");

        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(10));
        hint_style = hint_style.italic(true);
        hint_style = hint_style.inline_style(true);
        const hint = try hint_style.render(ctx.allocator, "Type to edit. Arrow keys to navigate.");

        const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}\n\n{s}", .{ header, editor_view, hint });

        return box_style.render(ctx.allocator, content);
    }

    fn renderUnicodeTab(ctx: *const zz.Context) ![]const u8 {
        const alloc = ctx.allocator;

        // -- CJK Box --
        var cjk_header_style = zz.Style{};
        cjk_header_style = cjk_header_style.bold(true);
        cjk_header_style = cjk_header_style.fg(zz.Color.hex("#FF6B6B"));
        cjk_header_style = cjk_header_style.inline_style(true);
        const cjk_header = try cjk_header_style.render(alloc, "CJK Characters");

        var cjk_style = zz.Style{};
        cjk_style = cjk_style.borderAll(zz.Border.rounded);
        cjk_style = cjk_style.borderForeground(zz.Color.hex("#FF6B6B"));
        cjk_style = cjk_style.paddingLeft(1).paddingRight(1);
        cjk_style = cjk_style.width(30);

        const cjk_content = try std.fmt.allocPrint(alloc, "{s}\n\n  \u{4F60}\u{597D}\u{4E16}\u{754C}    (Chinese)\n  \u{3053}\u{3093}\u{306B}\u{3061}\u{306F}  (Japanese)\n  \u{C548}\u{B155}\u{D558}\u{C138}\u{C694}  (Korean)", .{cjk_header});

        const cjk_box = try cjk_style.render(alloc, cjk_content);

        // -- Symbol Box --
        var symbol_header_style = zz.Style{};
        symbol_header_style = symbol_header_style.bold(true);
        symbol_header_style = symbol_header_style.fg(zz.Color.hex("#4ECDC4"));
        symbol_header_style = symbol_header_style.inline_style(true);
        const symbol_header = try symbol_header_style.render(alloc, "Symbols");

        var symbol_style = zz.Style{};
        symbol_style = symbol_style.borderAll(zz.Border.rounded);
        symbol_style = symbol_style.borderForeground(zz.Color.hex("#4ECDC4"));
        symbol_style = symbol_style.paddingLeft(1).paddingRight(1);
        symbol_style = symbol_style.width(30);

        const symbol_content = try std.fmt.allocPrint(alloc, "{s}\n\n  \u{03B1}\u{03B2}\u{03B3}\u{03B4}\u{03B5}  Greek letters\n  \u{2211}\u{221A}\u{2260}\u{2264}\u{2265}  Math symbols\n  \u{2605}\u{2606}\u{00A7}\u{00B6}\u{00B0}  Misc symbols", .{symbol_header});

        const symbol_box = try symbol_style.render(alloc, symbol_content);

        // -- Top row --
        const top_row = try zz.joinHorizontal(alloc, &.{ cjk_box, "  ", symbol_box });

        // -- Fullwidth/Halfwidth comparison box --
        var fw_header_style = zz.Style{};
        fw_header_style = fw_header_style.bold(true);
        fw_header_style = fw_header_style.fg(zz.Color.yellow);
        fw_header_style = fw_header_style.inline_style(true);
        const fw_header = try fw_header_style.render(alloc, "Width Comparison");

        var fw_style = zz.Style{};
        fw_style = fw_style.borderAll(zz.Border.rounded);
        fw_style = fw_style.borderForeground(zz.Color.yellow);
        fw_style = fw_style.paddingLeft(1).paddingRight(1);

        const fw_content = try std.fmt.allocPrint(alloc, "{s}\n\n  Fullwidth : \u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}   (5 chars = 10 cols)\n  Halfwidth : ABCDE        (5 chars =  5 cols)\n  Mixed     : A\u{FF22}C\u{FF24}E        (5 chars =  7 cols)", .{fw_header});

        const fw_box = try fw_style.render(alloc, fw_content);

        // -- Combining characters box --
        var comb_header_style = zz.Style{};
        comb_header_style = comb_header_style.bold(true);
        comb_header_style = comb_header_style.fg(zz.Color.magenta);
        comb_header_style = comb_header_style.inline_style(true);
        const comb_header = try comb_header_style.render(alloc, "Combining Characters");

        var comb_style = zz.Style{};
        comb_style = comb_style.borderAll(zz.Border.rounded);
        comb_style = comb_style.borderForeground(zz.Color.magenta);
        comb_style = comb_style.paddingLeft(1).paddingRight(1);

        const comb_content = try std.fmt.allocPrint(alloc, "{s}\n\n  e\u{0301} = e + combining acute   (1 col)\n  a\u{030A} = a + combining ring     (1 col)\n  o\u{0308} = o + combining diaeresis (1 col)\n  n\u{0303} = n + combining tilde     (1 col)", .{comb_header});

        const comb_box = try comb_style.render(alloc, comb_content);

        // -- Alignment demo --
        var align_header_style = zz.Style{};
        align_header_style = align_header_style.bold(true);
        align_header_style = align_header_style.fg(zz.Color.green);
        align_header_style = align_header_style.inline_style(true);
        const align_header = try align_header_style.render(alloc, "Alignment Demo");

        var align_style = zz.Style{};
        align_style = align_style.borderAll(zz.Border.double);
        align_style = align_style.borderForeground(zz.Color.green);
        align_style = align_style.paddingLeft(1).paddingRight(1);

        const align_content = try std.fmt.allocPrint(alloc, "{s}\n\n  |hello     |  5 cols\n  |\u{4F60}\u{597D}      |  4 cols (2 wide chars)\n  |\u{03B1}\u{03B2}\u{03B3}\u{03B4}      |  4 cols (Greek)\n  |caf\u{00E9}      |  4 cols (precomposed)\n  |cafe\u{0301}      |  4 cols (combining)", .{align_header});

        const align_box = try align_style.render(alloc, align_content);

        // -- Middle row --
        const mid_row = try zz.joinHorizontal(alloc, &.{ fw_box, "  ", comb_box });

        // -- Hint --
        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(10));
        hint_style = hint_style.italic(true);
        hint_style = hint_style.inline_style(true);
        const hint = try hint_style.render(alloc, "Unicode width is terminal-dependent; this tab uses width-stable samples.");

        return zz.joinVertical(alloc, &.{ top_row, "", mid_row, "", align_box, "", hint });
    }

    fn renderStatusBar(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        _ = self;
        var help_comp = zz.components.Help.init(ctx.allocator);
        try help_comp.addBinding("1-6", "tabs");
        try help_comp.addBinding("Tab", "next");
        try help_comp.addBinding("Ctrl+Q", "quit");
        help_comp.setMaxWidth(ctx.width);

        const help_view = try help_comp.view(ctx.allocator);

        var status_style = zz.Style{};
        status_style = status_style.borderAll(zz.Border.rounded);
        status_style = status_style.borderForeground(zz.Color.gray(6));
        status_style = status_style.paddingLeft(1).paddingRight(1);
        status_style = status_style.width(@min(ctx.width -| 2, 60));

        return status_style.render(ctx.allocator, help_view);
    }

    pub fn deinit(self: *Model) void {
        self.sparkline.deinit();
        self.chart.deinit();
        self.bars.deinit();
        self.notifications.deinit();
        self.table.deinit();
        self.tree.deinit();
        self.styled_list.deinit();
        self.file_viewport.deinit();
        self.text_area.deinit();
        self.help.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).initWithOptions(init.gpa, init.io, init.environ_map, .{
        .mouse = true,
        .title = "ZigZag Showcase",
    });
    defer program.deinit();

    try program.run();
}
