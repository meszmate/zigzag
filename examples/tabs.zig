//! TabGroup example with multi-screen routing.

const std = @import("std");
const zz = @import("zigzag");

const ScreenA = struct {
    visits: usize = 0,

    fn onEnter(ctx: *anyopaque) void {
        const self: *ScreenA = @ptrCast(@alignCast(ctx));
        self.visits += 1;
    }

    fn onKey(_: *anyopaque, _: zz.KeyEvent) bool {
        return false;
    }

    fn render(ctx: *anyopaque, allocator: std.mem.Allocator) ![]const u8 {
        const self: *ScreenA = @ptrCast(@alignCast(ctx));
        return std.fmt.allocPrint(
            allocator,
            "Home Screen\n\nVisits: {d}\n\nUse Left/Right or 1..9 to switch tabs.",
            .{self.visits},
        );
    }
};

const ScreenB = struct {
    count: i32 = 0,

    fn onKey(ctx: *anyopaque, key: zz.KeyEvent) bool {
        const self: *ScreenB = @ptrCast(@alignCast(ctx));
        switch (key.key) {
            .char => |c| switch (c) {
                '+', '=' => {
                    self.count += 1;
                    return true;
                },
                '-', '_' => {
                    self.count -= 1;
                    return true;
                },
                else => {},
            },
            .up => {
                self.count += 1;
                return true;
            },
            .down => {
                self.count -= 1;
                return true;
            },
            else => {},
        }
        return false;
    }

    fn render(ctx: *anyopaque, allocator: std.mem.Allocator) ![]const u8 {
        const self: *ScreenB = @ptrCast(@alignCast(ctx));
        return std.fmt.allocPrint(
            allocator,
            "Counter Screen\n\nCount: {d}\n\nPress + / - while this tab is active.",
            .{self.count},
        );
    }
};

const Model = struct {
    tabs: zz.TabGroup,
    home: ScreenA,
    counter: ScreenB,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.tabs = zz.TabGroup.init(ctx.persistent_allocator);
        self.tabs.show_numbers = true;
        self.tabs.max_width = 60;

        self.home = .{};
        self.counter = .{};

        _ = self.tabs.addTab(.{
            .id = "home",
            .title = "Home",
            .route = .{
                .ctx = &self.home,
                .render_fn = ScreenA.render,
                .key_fn = ScreenA.onKey,
                .on_enter_fn = ScreenA.onEnter,
            },
        }) catch {};

        _ = self.tabs.addTab(.{
            .id = "counter",
            .title = "Counter",
            .route = .{
                .ctx = &self.counter,
                .render_fn = ScreenB.render,
                .key_fn = ScreenB.onKey,
            },
        }) catch {};

        return .none;
    }

    pub fn deinit(self: *Model) void {
        self.tabs.deinit();
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (k.key == .char and k.key.char == 'q') return .quit;
                _ = self.tabs.handleKeyAndRoute(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const body = self.tabs.viewWithContent(ctx.allocator, "No active route") catch "render error";

        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);
        const help = hint_style.render(ctx.allocator, "q: quit | ←/→: switch | 1..9: jump | +/- or ↑/↓: counter actions") catch "";

        return std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ body, help }) catch body;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
