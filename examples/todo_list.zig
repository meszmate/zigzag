//! ZigZag Todo List Example
//! Demonstrates the List component with item selection.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const Model = struct {
    list: zz.List(Todo),
    input_mode: bool,
    input: zz.TextInput,
    persistent_allocator: std.mem.Allocator,
    owned_titles: std.array_list.Managed([]const u8),

    const Todo = struct {
        id: u32,
        done: bool,
    };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.list = zz.List(Todo).init(ctx.persistent_allocator);
        self.list.multi_select = true;
        self.list.height = 10;
        self.persistent_allocator = ctx.persistent_allocator;
        self.owned_titles = std.array_list.Managed([]const u8).init(ctx.persistent_allocator);

        // Add some sample items
        const Item = zz.List(Todo).Item;
        self.list.addItem(Item.init(.{ .id = 1, .done = false }, "Learn Zig")) catch {};
        self.list.addItem(Item.init(.{ .id = 2, .done = true }, "Build a TUI app")) catch {};
        self.list.addItem(Item.init(.{ .id = 3, .done = false }, "Write documentation")) catch {};
        self.list.addItem(Item.init(.{ .id = 4, .done = false }, "Add more features")) catch {};
        self.list.addItem(Item.init(.{ .id = 5, .done = false }, "Test everything")) catch {};

        self.input_mode = false;
        self.input = zz.TextInput.init(ctx.persistent_allocator);
        self.input.setPlaceholder("Enter new todo...");
        self.input.setPrompt("> ");

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (self.input_mode) {
                    switch (k.key) {
                        .escape => {
                            self.input_mode = false;
                            self.input.setValue("") catch {};
                        },
                        .enter => {
                            if (self.input.getValue().len > 0) {
                                const new_id: u32 = @intCast(self.list.items.items.len + 1);
                                const title = ctx.persistent_allocator.dupe(u8, self.input.getValue()) catch return .none;
                                const Item = zz.List(Todo).Item;
                                self.list.addItem(Item.init(.{ .id = new_id, .done = false }, title)) catch {
                                    ctx.persistent_allocator.free(title);
                                    return .none;
                                };
                                self.owned_titles.append(title) catch {
                                    _ = self.list.items.pop();
                                    self.list.updateFilter() catch {};
                                    ctx.persistent_allocator.free(title);
                                    return .none;
                                };
                                self.input.setValue("") catch {};
                            }
                            self.input_mode = false;
                        },
                        else => self.input.handleKey(k),
                    }
                } else if (self.list.filter_enabled) {
                    // When filtering, let list handle all keys except escape
                    switch (k.key) {
                        .escape => self.list.disableFilter(),
                        else => self.list.handleKey(k),
                    }
                } else {
                    switch (k.key) {
                        .char => |c| switch (c) {
                            'q' => return .quit,
                            'a' => self.input_mode = true,
                            'd' => self.deleteSelected(),
                            'x' => self.toggleDone(),
                            else => self.list.handleKey(k),
                        },
                        .escape => return .quit,
                        else => self.list.handleKey(k),
                    }
                }
            },
        }
        return .none;
    }

    fn deleteSelected(self: *Model) void {
        // Get the actual item index from filtered_indices
        const visible = self.list.filtered_indices.items;
        if (self.list.cursor >= visible.len) return;

        const item_idx = visible[self.list.cursor];
        const removed = self.list.items.orderedRemove(item_idx);
        self.freeOwnedTitle(removed.title);

        // Update filter to rebuild filtered_indices
        self.list.updateFilter() catch {};

        // Adjust cursor if needed
        if (self.list.cursor >= self.list.filtered_indices.items.len and self.list.cursor > 0) {
            self.list.cursor -= 1;
        }
    }

    fn toggleDone(self: *Model) void {
        // Get the actual item index from filtered_indices
        const visible = self.list.filtered_indices.items;
        if (self.list.cursor >= visible.len) return;

        const item_idx = visible[self.list.cursor];
        self.list.items.items[item_idx].value.done = !self.list.items.items[item_idx].value.done;
    }

    fn freeOwnedTitle(self: *Model, title: []const u8) void {
        for (self.owned_titles.items, 0..) |owned, i| {
            if (owned.ptr == title.ptr and owned.len == title.len) {
                _ = self.owned_titles.orderedRemove(i);
                self.persistent_allocator.free(owned);
                return;
            }
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);

        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.gray(15));
        box_style = box_style.paddingAll(1);

        const title = title_style.render(ctx.allocator, "Todo List") catch "Todo List";

        // Build todo list display using filtered_indices
        var list_content: Writer.Allocating = .init(ctx.allocator);
        const writer = &list_content.writer;

        // Show filter if enabled
        if (self.list.filter_enabled) {
            var filter_style = zz.Style{};
            filter_style = filter_style.fg(zz.Color.yellow);
            filter_style = filter_style.inline_style(true);
            const filter_text = std.fmt.allocPrint(ctx.allocator, "Filter: {s}", .{self.list.filter_text.items}) catch "Filter:";
            const styled_filter = filter_style.render(ctx.allocator, filter_text) catch filter_text;
            writer.writeAll(styled_filter) catch {};
            writer.writeByte('\n') catch {};
        }

        const visible = self.list.filtered_indices.items;

        for (visible, 0..) |item_idx, i| {
            if (i > 0) writer.writeByte('\n') catch {};

            const item = self.list.items.items[item_idx];

            // Cursor indicator
            if (i == self.list.cursor) {
                writer.writeAll("> ") catch {};
            } else {
                writer.writeAll("  ") catch {};
            }

            // Checkbox
            if (item.value.done) {
                writer.writeAll("[x] ") catch {};
            } else {
                writer.writeAll("[ ] ") catch {};
            }

            // Title with strikethrough if done
            if (item.value.done) {
                var done_style = zz.Style{};
                done_style = done_style.strikethrough(true);
                done_style = done_style.fg(zz.Color.gray(12));
                done_style = done_style.inline_style(true);
                const styled = done_style.render(ctx.allocator, item.title) catch item.title;
                writer.writeAll(styled) catch {};
            } else if (i == self.list.cursor) {
                var selected_style = zz.Style{};
                selected_style = selected_style.bold(true);
                selected_style = selected_style.fg(zz.Color.magenta);
                selected_style = selected_style.inline_style(true);
                const styled = selected_style.render(ctx.allocator, item.title) catch item.title;
                writer.writeAll(styled) catch {};
            } else {
                writer.writeAll(item.title) catch {};
            }
        }

        const list_view = list_content.toOwnedSlice() catch "";
        const boxed_list = box_style.render(ctx.allocator, list_view) catch list_view;

        // Input line
        const input_line = if (self.input_mode)
            self.input.view(ctx.allocator) catch ""
        else
            "";

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help_text = if (self.input_mode)
            "Enter: Add  Esc: Cancel"
        else if (self.list.filter_enabled)
            "Type to filter  Esc: Clear filter"
        else
            "j/k: Navigate  Space: Select  x: Toggle  a: Add  d: Delete  /: Filter  q: Quit";
        const help = help_style.render(ctx.allocator, help_text) catch "";

        // Get the max width of all elements for proper centering
        const box_width = zz.measure.maxLineWidth(boxed_list);
        const help_width = zz.measure.width(help);
        const title_width = zz.measure.width(title);
        const max_width = @max(box_width, @max(help_width, title_width));

        // Center all elements to the max width
        const centered_title = zz.place.place(
            ctx.allocator,
            max_width,
            1,
            .center,
            .top,
            title,
        ) catch title;

        const centered_box = zz.place.place(
            ctx.allocator,
            max_width,
            zz.measure.height(boxed_list),
            .center,
            .top,
            boxed_list,
        ) catch boxed_list;

        const centered_help = zz.place.place(
            ctx.allocator,
            max_width,
            1,
            .center,
            .top,
            help,
        ) catch help;

        // Build content
        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}{s}",
            .{ centered_title, centered_box, input_line, centered_help },
        ) catch "Error";

        // Center the content in the terminal
        const centered = zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;

        return centered;
    }

    pub fn deinit(self: *Model) void {
        for (self.owned_titles.items) |title| {
            self.persistent_allocator.free(title);
        }
        self.owned_titles.deinit();
        self.list.deinit();
        self.input.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
