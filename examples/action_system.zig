//! ZigZag ActionRegistry Example
//! One registry feeding both an auto-rendered footer and a fuzzy command palette.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    registry: zz.ActionRegistry,
    palette: zz.CommandPalette,
    palette_open: bool,
    counter: i32,
    last_action: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) !zz.Cmd(Msg) {
        const persistent = ctx.persistent_allocator;
        var reg = zz.ActionRegistry.init(persistent);

        try // Footer-visible actions.
        reg.register(.{
            .id = "app.quit",
            .label = "Quit",
            .description = "Exit the program",
            .binding = .{ .key = .{ .char = 'q' } },
            .show_in_footer = true,
        });
        try reg.register(.{
            .id = "counter.inc",
            .label = "Increment",
            .description = "Add one to the counter",
            .binding = .{ .key = .{ .char = '+' } },
            .show_in_footer = true,
        });
        try reg.register(.{
            .id = "counter.dec",
            .label = "Decrement",
            .description = "Subtract one from the counter",
            .binding = .{ .key = .{ .char = '-' } },
            .show_in_footer = true,
        });
        try reg.register(.{
            .id = "palette.open",
            .label = "Command Palette",
            .description = "Open the searchable command list",
            .binding = .{ .key = .{ .char = 'p' }, .modifiers = .{ .ctrl = true } },
            .show_in_footer = true,
        });

        try // Hidden-from-footer actions still show up in the palette.
        reg.register(.{
            .id = "counter.reset",
            .label = "Reset counter",
            .description = "Set the counter back to zero",
            .category = "Counter",
        });
        try reg.register(.{
            .id = "counter.times_ten",
            .label = "Multiply by 10",
            .description = "Multiply the counter by ten",
            .category = "Counter",
        });
        try reg.register(.{
            .id = "counter.negate",
            .label = "Negate",
            .description = "Flip the counter sign",
            .category = "Counter",
        });
        try reg.register(.{
            .id = "help.about",
            .label = "About this demo",
            .description = "Show what this example illustrates",
            .category = "Help",
        });

        try // Aliases let multiple keys map to the same action.
        reg.addAlias("counter.inc", .{ .key = .up });
        try reg.addAlias("counter.dec", .{ .key = .down });

        var palette = zz.CommandPalette.init(persistent) catch return .quit;
        palette.placeholder = "Search commands…";

        self.* = .{
            .registry = reg,
            .palette = palette,
            .palette_open = false,
            .counter = 0,
            .last_action = "(none yet)",
        };

        // One-shot integration: pull every registered action into the
        // palette, formatting bindings as shortcut hints. The palette owns
        // the strings, so no lifetime tracking on our side.
        try self.palette.setFromRegistry(&self.registry);

        return .none;
    }

    pub fn deinit(self: *Model) void {
        self.registry.deinit();
        self.palette.deinit();
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (self.palette_open) {
                    const result = self.palette.handleKey(k) catch return .none;
                    switch (result) {
                        .accepted => {
                            if (self.palette.selected()) |cmd| {
                                _ = self.dispatch(cmd.id);
                            }
                            self.palette_open = false;
                            self.palette.clear() catch {};
                        },
                        .cancelled => {
                            self.palette_open = false;
                            self.palette.clear() catch {};
                        },
                        else => {},
                    }
                    return .none;
                }

                if (self.registry.matchKey(k)) |action| {
                    return self.dispatchAction(action);
                }

                if (k.key == .escape) return .quit;
            },
        }
        return .none;
    }

    fn dispatchAction(self: *Model, action: *const zz.Action) zz.Cmd(Msg) {
        return self.dispatch(action.id);
    }

    fn dispatch(self: *Model, id: []const u8) zz.Cmd(Msg) {
        self.last_action = id;
        if (std.mem.eql(u8, id, "app.quit")) return .quit;
        if (std.mem.eql(u8, id, "counter.inc")) self.counter += 1;
        if (std.mem.eql(u8, id, "counter.dec")) self.counter -= 1;
        if (std.mem.eql(u8, id, "counter.reset")) self.counter = 0;
        if (std.mem.eql(u8, id, "counter.times_ten")) self.counter *= 10;
        if (std.mem.eql(u8, id, "counter.negate")) self.counter = -self.counter;
        if (std.mem.eql(u8, id, "palette.open")) self.palette_open = true;
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        const alloc = ctx.allocator;

        var title = zz.Style{};
        title = title.bold(true);
        title = title.fg(zz.Color.cyan);
        title = title.inline_style(true);
        const title_str = try title.render(alloc, "ActionRegistry — one source of truth");

        const body = try std.fmt.allocPrint(
            alloc,
            \\Counter        {d}
            \\Last action    {s}
            \\Footer below auto-renders bindings flagged show_in_footer.
            \\
            \\Press ctrl+p to open the palette and search any registered action,
            \\including ones with no key binding (try "negate" or "ten").
        ,
            .{ self.counter, self.last_action },
        );

        var box = zz.Style{};
        box = box.borderAll(zz.Border.rounded);
        box = box.borderForeground(zz.Color.gray(8));
        box = box.paddingAll(1);
        const boxed = try box.render(alloc, body);

        var footer = zz.ActionFooter.init(&self.registry);
        footer.setWidth(@intCast(ctx.width));
        const footer_str = try footer.view(alloc);

        const main_view = try std.fmt.allocPrint(
            alloc,
            "{s}\n\n{s}\n\n{s}",
            .{ title_str, boxed, footer_str },
        );

        if (!self.palette_open) return main_view;

        // Overlay the palette centered on top of the main view.
        const palette_view = try self.palette.view(alloc);
        return zz.place.placeFloat(
            alloc,
            ctx.width,
            ctx.height,
            0.5,
            0.5,
            palette_view,
        );
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
