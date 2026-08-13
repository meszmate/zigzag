//! Tests for the headless model harness — and, through it, a worked example of
//! how an application built on ZigZag can test its own model.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

/// A small but complete app: keys, a timer, a quit path, and a title command.
const Counter = struct {
    count: i32 = 0,
    ticks: u32 = 0,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
        window_size: zz.msg.WindowSize,
        bump: i32,
    };

    /// Declared at container scope so the slice `.batch` points at outlives
    /// `init`. A `&.{ ... }` literal built inside the function is a stack
    /// temporary as soon as any element carries a runtime value.
    const startup = [_]zz.Cmd(Msg){
        .{ .set_title = "Counter" },
        .{ .every = 100 * std.time.ns_per_ms },
    };

    pub fn init(self: *Counter, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{};
        return .{ .batch = &startup };
    }

    pub fn update(self: *Counter, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    '+' => self.count += 1,
                    '-' => self.count -= 1,
                    'r' => return .{ .msg = .{ .bump = -self.count } },
                    else => {},
                },
                .up => self.count += 1,
                else => {},
            },
            .tick => self.ticks += 1,
            .window_size => {},
            .bump => |by| self.count += by,
        }
        return .none;
    }

    pub fn view(self: *const Counter, ctx: *const zz.Context) ![]const u8 {
        var style = zz.Style{};
        style = style.bold(true);
        style = style.fg(zz.Color.cyan);
        style = style.inline_style(true);

        const label = try style.render(ctx.allocator, "Count");
        return std.fmt.allocPrint(ctx.allocator, "{s}: {d}\nticks: {d}\nsize: {d}x{d}", .{
            label,
            self.count,
            self.ticks,
            ctx.width,
            ctx.height,
        });
    }
};

fn newHarness() !zz.testing.Harness(Counter) {
    return zz.testing.Harness(Counter).init(testing.allocator, testing.io, .{});
}

test "harness renders the initial view" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try testing.expectEqualStrings("Count: 0\nticks: 0\nsize: 80x24", try h.plainView());
}

test "key presses reach update" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try h.pressChar('+');
    try h.pressChar('+');
    try h.press(.{ .key = .up });

    try testing.expectEqual(@as(i32, 3), h.model.count);
    try testing.expect(try h.viewContains("Count: 3"));
}

test "typeText sends one key per codepoint" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try h.typeText("+++-");

    try testing.expectEqual(@as(i32, 2), h.model.count);
}

test "a quit command is observable" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try testing.expect(!h.hasQuit());
    try h.pressChar('q');
    try testing.expect(h.hasQuit());
}

test "commands that produce messages are followed" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try h.typeText("++++");
    try testing.expectEqual(@as(i32, 4), h.model.count);

    // 'r' returns `.{ .msg = ... }`, which has to be dispatched back into
    // update rather than recorded.
    try h.pressChar('r');
    try testing.expectEqual(@as(i32, 0), h.model.count);
}

test "terminal commands are recorded instead of executed" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try testing.expectEqualStrings("Counter", h.title().?);
    try testing.expectEqual(@as(usize, 1), h.recordedEffects().len);

    h.clearEffects();
    try testing.expectEqual(@as(usize, 0), h.recordedEffects().len);
}

test "advance delivers repeating timers" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try h.advance(50 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u32, 0), h.model.ticks);

    try h.advance(50 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u32, 1), h.model.ticks);

    try h.advance(100 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u32, 2), h.model.ticks);
}

test "resize updates the context and notifies the model" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    try h.resize(120, 40);

    try testing.expectEqual(@as(u16, 120), h.context.width);
    try testing.expect(try h.viewContains("size: 120x40"));
}

test "view keeps its styling; plainView does not" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    const styled = try h.view();
    try testing.expect(std.mem.indexOf(u8, styled, "\x1b[") != null);
    try testing.expect(std.mem.indexOf(u8, try h.plainView(), "\x1b[") == null);
}

test "each frame starts with a fresh allocator" {
    var h = try newHarness();
    defer h.deinit();
    try h.start();

    // Rendering many frames must not grow without bound; the arena is reset
    // rather than accumulating one view per frame.
    for (0..500) |_| {
        h.nextFrame(16 * std.time.ns_per_ms);
        _ = try h.view();
    }

    try testing.expectEqual(@as(u64, 500), h.context.frame);
}

test "harness drives a model with plain (non-fallible) callbacks" {
    const Plain = struct {
        pressed: bool = false,

        pub const Msg = union(enum) { key: zz.KeyEvent };

        pub fn init(self: *@This(), _: *zz.Context) zz.Cmd(Msg) {
            self.* = .{};
            return .none;
        }

        pub fn update(self: *@This(), _: Msg, _: *zz.Context) zz.Cmd(Msg) {
            self.pressed = true;
            return .none;
        }

        pub fn view(self: *const @This(), _: *const zz.Context) []const u8 {
            return if (self.pressed) "pressed" else "idle";
        }
    };

    var h = try zz.testing.Harness(Plain).init(testing.allocator, testing.io, .{});
    defer h.deinit();
    try h.start();

    try testing.expectEqualStrings("idle", try h.view());
    try h.pressChar('x');
    try testing.expectEqualStrings("pressed", try h.view());
}

test "harness size is configurable" {
    var h = try zz.testing.Harness(Counter).init(testing.allocator, testing.io, .{
        .width = 40,
        .height = 10,
    });
    defer h.deinit();
    try h.start();

    try testing.expect(try h.viewContains("size: 40x10"));
}
