//! ZigZag Sortable Table Example
//! Demonstrates column sorting and filtering.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    table: zz.components.sortable_table.SortableTable(4),

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.table = zz.components.sortable_table.SortableTable(4).init(std.heap.page_allocator);
        self.table.setHeaders(.{ "Name", "Role", "City", "Score" });
        self.table.addRow(.{ "Alice", "Engineer", "NYC", "95" }) catch {};
        self.table.addRow(.{ "Bob", "Designer", "London", "87" }) catch {};
        self.table.addRow(.{ "Carol", "Manager", "Tokyo", "92" }) catch {};
        self.table.addRow(.{ "Dave", "Engineer", "Berlin", "78" }) catch {};
        self.table.addRow(.{ "Eve", "Designer", "Paris", "91" }) catch {};
        self.table.addRow(.{ "Frank", "Manager", "NYC", "85" }) catch {};
        self.table.addRow(.{ "Grace", "Engineer", "London", "99" }) catch {};
        self.table.addRow(.{ "Hank", "Designer", "Tokyo", "72" }) catch {};
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| if (c == 'q' and !self.table.filter_active) return .quit,
                    .escape => if (!self.table.filter_active) return .quit,
                    else => {},
                }
                self.table.update(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);

        var box_s = zz.Style{};
        box_s = box_s.borderAll(zz.Border.rounded);
        box_s = box_s.borderForeground(zz.Color.cyan);
        box_s = box_s.paddingAll(1);

        const table_view = self.table.view(alloc);
        const boxed = box_s.render(alloc, table_view) catch table_view;

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(alloc,
            "{s}\n\n{s}\n\n{s}",
            .{
                title_s.render(alloc, "Sortable Table Demo") catch "",
                boxed,
                help_s.render(alloc, "1-4: sort by column  /: filter  Up/Down: navigate  q: quit") catch "",
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
