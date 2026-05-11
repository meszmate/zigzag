//! ZigZag Virtual List Example
//! Demonstrates efficient rendering of a 100,000 item list.

const std = @import("std");
const zz = @import("zigzag");

const TOTAL_ITEMS = 100_000;

const Model = struct {
    vlist: zz.components.virtual_list.VirtualList(usize),

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.vlist = .{};
        self.vlist.viewport_height = 20;
        self.vlist.render_fn = &renderItem;
        self.vlist.items = &items_array;
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| if (c == 'q') return .quit,
                    .escape => return .quit,
                    else => {},
                }
                self.vlist.update(k);
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

        const list_view = self.vlist.view(alloc);
        const boxed = box_s.render(alloc, list_view) catch list_view;

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(alloc,
            "{s}\n\n{s}\n\n{s}",
            .{
                title_s.render(alloc, std.fmt.allocPrint(alloc, "Virtual List - {d} items", .{TOTAL_ITEMS}) catch "Virtual List") catch "Virtual List",
                boxed,
                help_s.render(alloc, "Up/Down: navigate  PgUp/PgDn: page  Home/End: jump  q: quit") catch "",
            },
        ) catch "Error";

        return zz.place.place(alloc, ctx.width, ctx.height, .center, .middle, content) catch content;
    }

    fn renderItem(item: usize, _: usize, _: bool, allocator: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(allocator, "Row #{d:<6} - Data: 0x{X:0>8}", .{ item + 1, item *% 0xDEADBEEF }) catch "?";
    }
};

// Static array of indices
const items_array = blk: {
    @setEvalBranchQuota(TOTAL_ITEMS + 100);
    var arr: [TOTAL_ITEMS]usize = undefined;
    for (0..TOTAL_ITEMS) |i| arr[i] = i;
    break :blk arr;
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
