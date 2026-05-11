//! ZigZag Async Tasks Example
//! Demonstrates spawning background tasks that report results.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    status: []const u8,
    results: [3][]const u8,
    tasks_launched: u8,
    async_runner: zz.AsyncRunner(Msg),

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
        task_complete: TaskResult,
    };

    const TaskResult = struct {
        id: u8,
        value: []const u8,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.status = "Press 's' to start async tasks";
        self.results = .{ "pending...", "pending...", "pending..." };
        self.tasks_launched = 0;
        self.async_runner = zz.AsyncRunner(Msg).init(std.heap.page_allocator);
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    's' => {
                        // Don't relaunch while tasks are still running — that
                        // confuses the completion counter and can leak threads.
                        if (self.tasks_launched != 0) return .none;
                        self.status = "Tasks running...";
                        self.results = .{ "pending...", "pending...", "pending..." };
                        _ = self.async_runner.spawnWithArg(std.Io, ctx.io, &task1);
                        _ = self.async_runner.spawnWithArg(std.Io, ctx.io, &task2);
                        _ = self.async_runner.spawnWithArg(std.Io, ctx.io, &task3);
                        self.tasks_launched = 3;
                        return zz.Cmd(Msg).everyMs(100);
                    },
                    else => {},
                },
                .escape => return .quit,
                else => {},
            },
            .tick => {
                // Poll for async results
                const results = self.async_runner.poll();
                for (results) |result| {
                    switch (result) {
                        .task_complete => |tr| {
                            if (tr.id < 3) {
                                self.results[tr.id] = tr.value;
                                // Saturating: if a stray duplicate event
                                // arrives we don't underflow.
                                self.tasks_launched -|= 1;
                                if (self.tasks_launched == 0) {
                                    self.status = "All tasks complete!";
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            .task_complete => |tr| {
                if (tr.id < 3) {
                    self.results[tr.id] = tr.value;
                }
            },
        }
        return .none;
    }

    fn sleepNs(io: std.Io, ns: u64) void {
        const duration: std.Io.Clock.Duration = .{
            .raw = std.Io.Duration.fromNanoseconds(@intCast(ns)),
            .clock = .boot,
        };
        duration.sleep(io) catch {};
    }

    fn task1(io: std.Io) ?Msg {
        std.Io.sleep(io, .fromMilliseconds(500), .boot) catch unreachable; // 500ms
        return .{ .task_complete = .{ .id = 0, .value = "Task 1: computed pi = 3.14159" } };
    }

    fn task2(io: std.Io) ?Msg {
        std.Io.sleep(io, .fromMilliseconds(1000), .boot) catch unreachable; // 1s
        return .{ .task_complete = .{ .id = 1, .value = "Task 2: fetched 42 records" } };
    }

    fn task3(io: std.Io) ?Msg {
        std.Io.sleep(io, .fromMilliseconds(750), .boot) catch unreachable; // 750ms
        return .{ .task_complete = .{ .id = 2, .value = "Task 3: file processed OK" } };
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);

        var status_s = zz.Style{};
        status_s = status_s.fg(zz.Color.yellow);
        status_s = status_s.inline_style(true);

        var box_s = zz.Style{};
        box_s = box_s.borderAll(zz.Border.rounded);
        box_s = box_s.borderForeground(zz.Color.cyan);
        box_s = box_s.paddingAll(1);
        box_s = box_s.width(45);

        const results_text = std.fmt.allocPrint(
            alloc,
            "1: {s}\n2: {s}\n3: {s}",
            .{ self.results[0], self.results[1], self.results[2] },
        ) catch "";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(
            alloc,
            "{s}\n\n{s}\n\n{s}\n\n{s}",
            .{
                title_s.render(alloc, "Async Tasks Demo") catch "Async Tasks",
                status_s.render(alloc, self.status) catch self.status,
                box_s.render(alloc, results_text) catch results_text,
                help_s.render(alloc, "s: start tasks  q: quit") catch "",
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
