//! ZigZag Context Menu Example
//! Demonstrates a popup context menu triggered by keyboard.

const std = @import("std");
const Writer = std.Io.Writer;
const zz = @import("zigzag");

const Action = enum { cut, copy, paste, delete, select_all, properties };
const CM = zz.ContextMenu(Action);

const Model = struct {
    menu: CM,
    status: []const u8,
    items: [6][]const u8,
    selected: usize,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.menu = CM.init();
        self.menu.addItem("Cut", "Ctrl+X", .cut);
        self.menu.addItem("Copy", "Ctrl+C", .copy);
        self.menu.addItem("Paste", "Ctrl+V", .paste);
        self.menu.addSeparator();
        self.menu.addItem("Delete", "Del", .delete);
        self.menu.addItem("Select All", "Ctrl+A", .select_all);
        self.menu.addSeparator();
        self.menu.addDisabledItem("Properties", .properties);

        self.status = "Press Space or Enter to open context menu";
        self.items = .{ "Document.txt", "Image.png", "Notes.md", "Config.json", "Script.sh", "Data.csv" };
        self.selected = 0;
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                // Menu gets priority
                if (self.menu.handleKey(k)) {
                    if (self.menu.getSelectedAction()) |act| {
                        self.status = switch (act) {
                            .cut => "Cut selected item",
                            .copy => "Copied to clipboard",
                            .paste => "Pasted from clipboard",
                            .delete => "Item deleted",
                            .select_all => "All items selected",
                            .properties => "Properties (disabled)",
                        };
                    }
                    return .none;
                }

                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        else => {},
                    },
                    .up => {
                        if (self.selected > 0) self.selected -= 1;
                    },
                    .down => {
                        if (self.selected < self.items.len - 1) self.selected += 1;
                    },
                    .space, .enter => {
                        // Open context menu at selected item position
                        self.menu.show(4, self.selected + 4);
                    },
                    .escape => {
                        if (self.menu.isVisible()) {
                            self.menu.hide();
                        } else {
                            return .quit;
                        }
                    },
                    else => {},
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Context Menu Example") catch "Context Menu";

        // File list
        var list_buf: Writer.Allocating = .init(ctx.allocator);
        const lw = &list_buf.writer;
        for (self.items, 0..) |item, i| {
            if (i > 0) lw.writeByte('\n') catch {};
            if (i == self.selected) {
                var sel_style = zz.Style{};
                sel_style = sel_style.bold(true);
                sel_style = sel_style.fg(zz.Color.cyan);
                sel_style = sel_style.inline_style(true);
                const line = std.fmt.allocPrint(ctx.allocator, "  > {s}", .{item}) catch "";
                const styled = sel_style.render(ctx.allocator, line) catch line;
                lw.writeAll(styled) catch {};
            } else {
                const line = std.fmt.allocPrint(ctx.allocator, "    {s}", .{item}) catch "";
                lw.writeAll(line) catch {};
            }
        }
        const file_list = list_buf.toOwnedSlice() catch "";

        // Status
        var status_style = zz.Style{};
        status_style = status_style.fg(zz.Color.green);
        status_style = status_style.inline_style(true);
        const styled_status = status_style.render(ctx.allocator, self.status) catch self.status;

        // Context menu overlay
        const menu_view = self.menu.view(ctx.allocator) catch "";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator, "Up/Down: navigate | Space/Enter: context menu | Esc: close | q: quit") catch "";

        if (self.menu.isVisible()) {
            return std.fmt.allocPrint(
                ctx.allocator,
                "{s}\n\n{s}\n\n{s}\n\n{s}\n\n{s}",
                .{ title, file_list, menu_view, styled_status, help },
            ) catch "Error";
        }

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}\n\n{s}",
            .{ title, file_list, styled_status, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
