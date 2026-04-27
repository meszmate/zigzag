//! ZigZag Calendar Example
//! Demonstrates the Calendar component with date selection and navigation.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    cal: zz.components.Calendar,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.cal = .{
            .year = 2026,
            .month = 3,
            .cursor_day = 30,
            .selected_day = 30,
            .today_day = 30,
            .today_month = 3,
            .today_year = 2026,
        };
        // Mark some dates
        self.cal.addMarkedDate(25, .red);
        self.cal.addMarkedDate(1, .green);
        self.cal.addMarkedDate(14, .magenta);
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
                self.cal.update(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        const title = comptime zz.newStyle()
            .bold(true)
            .fg(.cyan)
            .inline_style(true)
            .renderComptime("Calendar Demo");

        const cal_view = self.cal.view(alloc);
        const boxed = zz.newStyle()
            .borderAll(.rounded)
            .borderForeground(.cyan)
            .paddingAll(1)
            .render(alloc, cal_view) catch cal_view;

        const selected_str = std.fmt.allocPrint(alloc, "Selected: {d}/{d}/{d}", .{
            self.cal.selected_day,
            self.cal.month,
            self.cal.year,
        }) catch "";

        const help = comptime zz.newStyle()
            .fg(.gray(10))
            .inline_style(true)
            .renderComptime("Arrows: navigate  Enter: select  Shift+L/R: month  PgUp/Dn: month  q: quit");

        const content = std.fmt.allocPrint(
            alloc,
            "{s}\n\n{s}\n\n{s}\n\n{s}",
            .{ title, boxed, selected_str, help },
        ) catch "Error";

        return zz.place.place(alloc, ctx.width, ctx.height, .center, .middle, content) catch content;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
