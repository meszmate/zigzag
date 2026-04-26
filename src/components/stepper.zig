//! Stepper (wizard) component.
//!
//! Renders a numbered sequence of steps with state indicators: completed,
//! current, and pending. Supports horizontal and vertical orientations and
//! exposes methods for navigating through the flow.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const Step = struct {
    title: []const u8,
    description: []const u8 = "",
};

pub const Orientation = enum { horizontal, vertical };

pub const StepState = enum { pending, current, completed };

pub const Stepper = struct {
    allocator: std.mem.Allocator,
    steps: std.array_list.Managed(Step),

    current: usize,
    orientation: Orientation,

    completed_marker: []const u8,
    current_marker: []const u8,
    pending_marker: []const u8,
    /// Horizontal connector drawn between steps in horizontal layout.
    connector: []const u8,

    completed_style: style_mod.Style,
    current_style: style_mod.Style,
    pending_style: style_mod.Style,
    connector_style: style_mod.Style,
    title_style: style_mod.Style,
    description_style: style_mod.Style,

    pub fn init(allocator: std.mem.Allocator) Stepper {
        var completed = style_mod.Style{};
        completed = completed.fg(.green);
        completed = completed.inline_style(true);

        var current = style_mod.Style{};
        current = current.fg(.cyan);
        current = current.bold(true);
        current = current.inline_style(true);

        var pending = style_mod.Style{};
        pending = pending.fg(.gray(8));
        pending = pending.inline_style(true);

        var connector = style_mod.Style{};
        connector = connector.fg(.gray(6));
        connector = connector.inline_style(true);

        var title = style_mod.Style{};
        title = title.inline_style(true);

        var desc = style_mod.Style{};
        desc = desc.fg(.gray(10));
        desc = desc.inline_style(true);

        return .{
            .allocator = allocator,
            .steps = std.array_list.Managed(Step).init(allocator),
            .current = 0,
            .orientation = .horizontal,
            .completed_marker = "✓",
            .current_marker = "●",
            .pending_marker = "○",
            .connector = "──",
            .completed_style = completed,
            .current_style = current,
            .pending_style = pending,
            .connector_style = connector,
            .title_style = title,
            .description_style = desc,
        };
    }

    pub fn deinit(self: *Stepper) void {
        self.steps.deinit();
    }

    pub fn addStep(self: *Stepper, step: Step) !void {
        try self.steps.append(step);
    }

    pub fn next(self: *Stepper) void {
        if (self.current + 1 < self.steps.items.len) self.current += 1;
    }

    pub fn prev(self: *Stepper) void {
        if (self.current > 0) self.current -= 1;
    }

    pub fn goto(self: *Stepper, idx: usize) void {
        self.current = @min(idx, self.steps.items.len -| 1);
    }

    pub fn reset(self: *Stepper) void {
        self.current = 0;
    }

    pub fn isComplete(self: *const Stepper) bool {
        return self.steps.items.len > 0 and self.current >= self.steps.items.len - 1;
    }

    pub fn stateOf(self: *const Stepper, idx: usize) StepState {
        if (idx < self.current) return .completed;
        if (idx == self.current) return .current;
        return .pending;
    }

    pub fn handleKey(self: *Stepper, key: keys.KeyEvent) void {
        switch (key.key) {
            .left => self.prev(),
            .right => self.next(),
            .up => if (self.orientation == .vertical) self.prev(),
            .down => if (self.orientation == .vertical) self.next(),
            else => {},
        }
    }

    pub fn view(self: *const Stepper, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.orientation) {
            .horizontal => self.viewHorizontal(allocator),
            .vertical => self.viewVertical(allocator),
        };
    }

    fn viewHorizontal(self: *const Stepper, allocator: std.mem.Allocator) ![]const u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        for (self.steps.items, 0..) |step, i| {
            if (i > 0) {
                const conn = try self.connector_style.render(allocator, self.connector);
                defer allocator.free(conn);
                try w.writeAll(conn);
            }

            const state = self.stateOf(i);
            const marker = switch (state) {
                .completed => self.completed_marker,
                .current => self.current_marker,
                .pending => self.pending_marker,
            };
            const marker_style = switch (state) {
                .completed => self.completed_style,
                .current => self.current_style,
                .pending => self.pending_style,
            };

            const styled_marker = try marker_style.render(allocator, marker);
            defer allocator.free(styled_marker);
            try w.writeAll(styled_marker);
            try w.writeByte(' ');

            const title_style = if (state == .current) self.current_style else self.title_style;
            const styled_title = try title_style.render(allocator, step.title);
            defer allocator.free(styled_title);
            try w.writeAll(styled_title);
        }

        return out.toOwnedSlice();
    }

    fn viewVertical(self: *const Stepper, allocator: std.mem.Allocator) ![]const u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;

        for (self.steps.items, 0..) |step, i| {
            if (i > 0) try w.writeByte('\n');

            const state = self.stateOf(i);
            const marker = switch (state) {
                .completed => self.completed_marker,
                .current => self.current_marker,
                .pending => self.pending_marker,
            };
            const marker_style = switch (state) {
                .completed => self.completed_style,
                .current => self.current_style,
                .pending => self.pending_style,
            };

            const styled_marker = try marker_style.render(allocator, marker);
            defer allocator.free(styled_marker);
            try w.writeAll(styled_marker);
            try w.writeByte(' ');

            const title_style = if (state == .current) self.current_style else self.title_style;
            const styled_title = try title_style.render(allocator, step.title);
            defer allocator.free(styled_title);
            try w.writeAll(styled_title);

            if (step.description.len > 0) {
                try w.writeAll("\n  ");
                const styled_desc = try self.description_style.render(allocator, step.description);
                defer allocator.free(styled_desc);
                try w.writeAll(styled_desc);
            }
        }

        return out.toOwnedSlice();
    }
};

test "stepper step state transitions" {
    const allocator = std.testing.allocator;
    var s = Stepper.init(allocator);
    defer s.deinit();

    try s.addStep(.{ .title = "first" });
    try s.addStep(.{ .title = "second" });
    try s.addStep(.{ .title = "third" });

    try std.testing.expectEqual(StepState.current, s.stateOf(0));
    try std.testing.expectEqual(StepState.pending, s.stateOf(1));

    s.next();
    try std.testing.expectEqual(StepState.completed, s.stateOf(0));
    try std.testing.expectEqual(StepState.current, s.stateOf(1));

    s.next();
    s.next(); // clamped
    try std.testing.expect(s.isComplete());
}

test "stepper prev does not go negative" {
    const allocator = std.testing.allocator;
    var s = Stepper.init(allocator);
    defer s.deinit();
    try s.addStep(.{ .title = "a" });
    s.prev();
    try std.testing.expectEqual(@as(usize, 0), s.current);
}

test "stepper horizontal render contains each title" {
    const allocator = std.testing.allocator;
    var s = Stepper.init(allocator);
    defer s.deinit();
    try s.addStep(.{ .title = "setup" });
    try s.addStep(.{ .title = "review" });
    const out = try s.view(allocator);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "review") != null);
}
