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
        self.cal.addMarkedDate(25, zz.Color.red);
        self.cal.addMarkedDate(1, zz.Color.green);
        self.cal.addMarkedDate(14, zz.Color.magenta);
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

        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);

        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(zz.Color.cyan);
        box_style = box_style.paddingAll(1);

        const cal_view = self.cal.view(alloc);
        const boxed = box_style.render(alloc, cal_view) catch cal_view;

        const selected_str = std.fmt.allocPrint(alloc, "Selected: {d}/{d}/{d}", .{
            self.cal.selected_day, self.cal.month, self.cal.year,
        }) catch "";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(alloc,
            "{s}\n\n{s}\n\n{s}\n\n{s}",
            .{
                title_s.render(alloc, "Calendar Demo") catch "Calendar",
                boxed,
                selected_str,
                help_s.render(alloc, "Arrows: navigate  Enter: select  Shift+L/R: month  PgUp/Dn: month  q: quit") catch "",
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
