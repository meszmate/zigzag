//! ZigZag Sub-Program Example
//! Demonstrates embedding independent sub-programs inside a parent.

const std = @import("std");
const zz = @import("zigzag");

// Child model: a simple counter
const Counter = struct {
    count: i32 = 0,
    label: []const u8 = "Counter",

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Counter, _: *zz.Context) zz.Cmd(Msg) {
        self.count = 0;
        return .none;
    }

    pub fn update(self: *Counter, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .up => self.count += 1,
                .down => self.count -= 1,
                .char => |c| if (c == 'r') {
                    self.count = 0;
                },
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Counter, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        return std.fmt.allocPrint(alloc, "{s}: {d}", .{ self.label, self.count }) catch "?";
    }
};

// Parent model with two sub-programs
const Model = struct {
    counter_a: zz.SubProgram(Counter, Msg),
    counter_b: zz.SubProgram(Counter, Msg),
    active: u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.active = 0;
        self.counter_a = .{};
        self.counter_a.model.label = "Counter A";
        _ = self.counter_a.init(ctx);
        self.counter_b = .{};
        self.counter_b.model.label = "Counter B";
        _ = self.counter_b.init(ctx);
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        else => {},
                    },
                    .escape => return .quit,
                    .tab => {
                        self.active = (self.active + 1) % 2;
                        return .none;
                    },
                    else => {},
                }

                // Forward to active sub-program
                if (self.active == 0) {
                    return self.counter_a.update(.{ .key = k }, ctx);
                } else {
                    return self.counter_b.update(.{ .key = k }, ctx);
                }
            },
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);

        // Sub-program views
        var box_a = zz.Style{};
        box_a = box_a.borderAll(zz.Border.rounded);
        box_a = box_a.borderForeground(if (self.active == 0) zz.Color.green else zz.Color.gray(8));
        box_a = box_a.paddingAll(1);
        box_a = box_a.width(30);

        var box_b = zz.Style{};
        box_b = box_b.borderAll(zz.Border.rounded);
        box_b = box_b.borderForeground(if (self.active == 1) zz.Color.green else zz.Color.gray(8));
        box_b = box_b.paddingAll(1);
        box_b = box_b.width(30);

        const view_a = box_a.render(alloc, self.counter_a.view(ctx)) catch "";
        const view_b = box_b.render(alloc, self.counter_b.view(ctx)) catch "";

        const panels = zz.join.horizontal(alloc, .top, &.{ view_a, view_b }) catch "";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const active_label = if (self.active == 0) "A" else "B";

        const content = std.fmt.allocPrint(alloc,
            "{s}\n\nActive: {s}\n\n{s}\n\n{s}",
            .{
                title_s.render(alloc, "Sub-Program Demo") catch "Sub-Program",
                active_label,
                panels,
                help_s.render(alloc, "Tab: switch  Up/Down: count  r: reset  q: quit") catch "",
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
