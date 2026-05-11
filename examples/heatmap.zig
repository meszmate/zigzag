//! ZigZag Heatmap Example
//! Shows a GitHub-contribution-style heatmap and a server load heatmap.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{};
        return .none;
    }

    pub fn update(_: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .escape => return .quit,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(_: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        // Activity heatmap (7 days x 12 weeks)
        const activity_rows = 7;
        const activity_cols = 12;
        var activity_data: [activity_rows * activity_cols]f64 = undefined;
        // Fill with pseudo-random data
        for (0..activity_data.len) |i| {
            const x = @as(f64, @floatFromInt(i));
            activity_data[i] = @max(0, @mod(x * 7.3 + @sin(x * 0.8) * 5, 10));
        }

        var activity = zz.components.heatmap.Heatmap.init(alloc);
        activity.setData(activity_rows, activity_cols, &activity_data);
        activity.row_labels = &.{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        activity.color_scale = .green_scale;
        activity.cell_width = 3;
        activity.title = "Contribution Activity";
        const activity_view = activity.view(alloc);

        // Server load heatmap (4 servers x 8 time slots)
        const load_rows = 4;
        const load_cols = 8;
        var load_data: [load_rows * load_cols]f64 = undefined;
        for (0..load_data.len) |i| {
            const x = @as(f64, @floatFromInt(i));
            load_data[i] = @mod(x * 13.7 + @cos(x * 0.5) * 30, 100);
        }

        var load = zz.components.heatmap.Heatmap.init(alloc);
        load.setData(load_rows, load_cols, &load_data);
        load.row_labels = &.{ "srv1", "srv2", "srv3", "srv4" };
        load.col_labels = &.{ "00", "03", "06", "09", "12", "15", "18", "21" };
        load.color_scale = .cool_to_hot;
        load.cell_width = 4;
        load.show_values = true;
        load.title = "Server Load (%)";
        const load_view = load.view(alloc);

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const content = std.fmt.allocPrint(alloc, "{s}\n\n\n{s}\n\n{s}", .{
            activity_view,
            load_view,
            help_s.render(alloc, "Press q to quit") catch "",
        }) catch "Error";

        return content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
