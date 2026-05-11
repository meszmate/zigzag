//! ZigZag ScreenStack Example
//! Three-screen flow: Home → Settings → modal Confirm dialog.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

// ── Home screen ─────────────────────────────────────────────────────────

const HomeState = struct {
    counter: u32 = 0,

    fn update(ptr: *anyopaque, _: *zz.Context, key: zz.KeyEvent) zz.ScreenAction {
        const self: *HomeState = @ptrCast(@alignCast(ptr));
        switch (key.key) {
            .char => |c| switch (c) {
                'q' => return .quit,
                's' => return .{ .push = settings_screen },
                '+' => self.counter += 1,
                '-' => self.counter -|= 1,
                else => {},
            },
            .escape => return .quit,
            else => {},
        }
        return .none;
    }

    fn view(ptr: *anyopaque, _: *const zz.Context, alloc: std.mem.Allocator) anyerror![]const u8 {
        const self: *HomeState = @ptrCast(@alignCast(ptr));
        return std.fmt.allocPrint(
            alloc,
            \\┌──────────────────────────────────────────┐
            \\│  HOME SCREEN                             │
            \\│                                          │
            \\│  counter = {d: <30}│
            \\│                                          │
            \\│  + / -  adjust counter                   │
            \\│  s      open Settings                    │
            \\│  q      quit                             │
            \\└──────────────────────────────────────────┘
        ,
            .{self.counter},
        );
    }
};

var home_state = HomeState{};
const home_vtable = zz.Screen.VTable{ .update = HomeState.update, .view = HomeState.view };
const home_screen = zz.Screen{ .ptr = &home_state, .vtable = &home_vtable, .title = "Home" };

// ── Settings screen ─────────────────────────────────────────────────────

const SettingsState = struct {
    sound_on: bool = true,
    theme_dark: bool = true,

    fn update(ptr: *anyopaque, _: *zz.Context, key: zz.KeyEvent) zz.ScreenAction {
        const self: *SettingsState = @ptrCast(@alignCast(ptr));
        switch (key.key) {
            .escape => return .pop,
            .char => |c| switch (c) {
                's' => self.sound_on = !self.sound_on,
                't' => self.theme_dark = !self.theme_dark,
                'r' => return .{ .push = confirm_screen },
                'q' => return .quit,
                else => {},
            },
            else => {},
        }
        return .none;
    }

    fn view(ptr: *anyopaque, _: *const zz.Context, alloc: std.mem.Allocator) anyerror![]const u8 {
        const self: *SettingsState = @ptrCast(@alignCast(ptr));
        return std.fmt.allocPrint(
            alloc,
            \\┌──────────────────────────────────────────┐
            \\│  SETTINGS                                │
            \\│                                          │
            \\│  s  sound  [{s}]                         │
            \\│  t  theme  [{s}]                         │
            \\│                                          │
            \\│  r      reset to defaults                │
            \\│  esc    back                             │
            \\│  q      quit                             │
            \\└──────────────────────────────────────────┘
        ,
            .{
                if (self.sound_on) "ON " else "OFF",
                if (self.theme_dark) "DARK " else "LIGHT",
            },
        );
    }
};

var settings_state = SettingsState{};
const settings_vtable = zz.Screen.VTable{ .update = SettingsState.update, .view = SettingsState.view };
const settings_screen = zz.Screen{ .ptr = &settings_state, .vtable = &settings_vtable, .title = "Settings" };

// ── Modal Confirm screen ────────────────────────────────────────────────

const ConfirmState = struct {
    fn update(_: *anyopaque, _: *zz.Context, key: zz.KeyEvent) zz.ScreenAction {
        switch (key.key) {
            .char => |c| switch (c) {
                'y', 'Y' => {
                    settings_state = .{};
                    return .pop;
                },
                'n', 'N' => return .pop,
                else => {},
            },
            .escape => return .pop,
            else => {},
        }
        return .none;
    }

    fn view(_: *anyopaque, _: *const zz.Context, alloc: std.mem.Allocator) anyerror![]const u8 {
        return alloc.dupe(u8,
            \\┌──────────────────┐
            \\│  Reset settings? │
            \\│                  │
            \\│   [y] yes [n] no │
            \\└──────────────────┘
        );
    }
};

var confirm_state = ConfirmState{};
const confirm_vtable = zz.Screen.VTable{ .update = ConfirmState.update, .view = ConfirmState.view };
const confirm_screen = zz.Screen{ .ptr = &confirm_state, .vtable = &confirm_vtable, .title = "Confirm", .modal = true };

// ── Top-level model wrapping the stack ──────────────────────────────────

const Model = struct {
    stack: zz.ScreenStack,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        var stack = zz.ScreenStack.init(ctx.persistent_allocator);
        stack.push(home_screen) catch return .quit;
        self.* = .{ .stack = stack };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                const result = self.stack.handleKey(ctx, k) catch return .none;
                if (result == .quit) return .quit;
                if (self.stack.isEmpty()) return .quit;
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const view_str = self.stack.view(ctx, ctx.allocator) catch "Error";

        var trail: Writer.Allocating = .init(ctx.allocator);
        defer trail.deinit();
        const w = &trail.writer;
        w.writeAll("stack: ") catch {};
        for (self.stack.stack.items, 0..) |s, i| {
            if (i > 0) w.writeAll(" › ") catch {};
            w.writeAll(s.title) catch {};
        }

        var trail_style = zz.Style{};
        trail_style = trail_style.fg(zz.Color.gray(10));
        trail_style = trail_style.inline_style(true);
        const trail_str = trail_style.render(ctx.allocator, trail.writer.buffered()) catch "";

        return std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ trail_str, view_str }) catch view_str;
    }

    pub fn deinit(self: *Model) void {
        self.stack.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
