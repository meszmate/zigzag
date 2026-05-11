//! ZigZag Dropdown Example
//! Demonstrates single-select and multi-select dropdown components.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    // Single-select: pick a color
    color_dropdown: zz.Dropdown(Color),
    // Multi-select: pick toppings
    topping_dropdown: zz.Dropdown(Topping),
    // Focus management
    focus_group: zz.FocusGroup(2),

    const Color = enum { red, green, blue, yellow, magenta, cyan, white };
    const Topping = enum { cheese, pepperoni, mushrooms, onions, peppers, olives, bacon, pineapple };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.color_dropdown = zz.Dropdown(Color).init(ctx.persistent_allocator);
        self.color_dropdown.label = "Color:";
        self.color_dropdown.placeholder = "Pick a color...";
        self.color_dropdown.addItems(&.{
            .{ .value = .red, .label = "Red", .description = "", .enabled = true },
            .{ .value = .green, .label = "Green", .description = "", .enabled = true },
            .{ .value = .blue, .label = "Blue", .description = "", .enabled = true },
            .{ .value = .yellow, .label = "Yellow", .description = "", .enabled = true },
            .{ .value = .magenta, .label = "Magenta", .description = "", .enabled = true },
            .{ .value = .cyan, .label = "Cyan", .description = "", .enabled = true },
            .{ .value = .white, .label = "White", .description = "", .enabled = false },
        }) catch {};

        self.topping_dropdown = zz.Dropdown(Topping).init(ctx.persistent_allocator);
        self.topping_dropdown.label = "Toppings:";
        self.topping_dropdown.placeholder = "Pick toppings...";
        self.topping_dropdown.multi_select = true;
        self.topping_dropdown.close_on_select = false;
        self.topping_dropdown.max_visible = 5;
        self.topping_dropdown.addItems(&.{
            .{ .value = .cheese, .label = "Cheese", .description = "", .enabled = true },
            .{ .value = .pepperoni, .label = "Pepperoni", .description = "", .enabled = true },
            .{ .value = .mushrooms, .label = "Mushrooms", .description = "", .enabled = true },
            .{ .value = .onions, .label = "Onions", .description = "", .enabled = true },
            .{ .value = .peppers, .label = "Peppers", .description = "", .enabled = true },
            .{ .value = .olives, .label = "Olives", .description = "", .enabled = true },
            .{ .value = .bacon, .label = "Bacon", .description = "", .enabled = true },
            .{ .value = .pineapple, .label = "Pineapple", .description = "", .enabled = true },
        }) catch {};

        self.focus_group = .{};
        self.focus_group.add(&self.color_dropdown);
        self.focus_group.add(&self.topping_dropdown);
        self.focus_group.initFocus();

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| if (c == 'q' and !self.color_dropdown.isExpanded() and !self.topping_dropdown.isExpanded()) return .quit,
                    .escape => if (!self.color_dropdown.isExpanded() and !self.topping_dropdown.isExpanded()) return .quit,
                    else => {},
                }

                // Focus cycling (only when dropdowns are closed)
                if (!self.color_dropdown.isExpanded() and !self.topping_dropdown.isExpanded()) {
                    if (self.focus_group.handleKey(k)) return .none;
                }

                self.color_dropdown.handleKey(k);
                self.topping_dropdown.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Dropdown Example") catch "Dropdown Example";

        const color_view = self.color_dropdown.view(ctx.allocator) catch "error";
        const topping_view = self.topping_dropdown.view(ctx.allocator) catch "error";

        // Selection info
        const color_info = if (self.color_dropdown.selectedItem()) |item|
            std.fmt.allocPrint(ctx.allocator, "Selected color: {s}", .{item.label}) catch "?"
        else
            "No color selected";

        const topping_count = self.topping_dropdown.selected_indices.count();
        const topping_info = std.fmt.allocPrint(ctx.allocator, "Selected toppings: {d}", .{topping_count}) catch "?";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Tab: switch | Enter/Space: open/select | Esc: close | /: filter | q: quit",
        ) catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n{s}\n\n{s}\n{s}\n\n{s}",
            .{ title, color_view, color_info, topping_view, topping_info, help },
        ) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.color_dropdown.deinit();
        self.topping_dropdown.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
