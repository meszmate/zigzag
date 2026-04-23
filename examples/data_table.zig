//! ZigZag DataTable Example
//! Wide table with a frozen first column and cell-level cursor.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    table: zz.components.DataTable,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    const headers = [_]zz.components.DataColumn{
        .{ .header = "id", .width = 4, .@"align" = .right },
        .{ .header = "name", .width = 12 },
        .{ .header = "team", .width = 10 },
        .{ .header = "city", .width = 12 },
        .{ .header = "role", .width = 14 },
        .{ .header = "tenure", .width = 8, .@"align" = .right },
        .{ .header = "rating", .width = 8, .@"align" = .right },
        .{ .header = "salary", .width = 10, .@"align" = .right },
    };

    const rows = [_][]const []const u8{
        &.{ "01", "Alice",   "Platform", "Berlin",     "Engineer",       "5y",  "4.8", "$120k" },
        &.{ "02", "Bob",     "Growth",   "Lisbon",     "PM",             "3y",  "4.1", "$110k" },
        &.{ "03", "Carol",   "Platform", "Tokyo",      "Staff Eng",      "9y",  "4.9", "$180k" },
        &.{ "04", "Dan",     "Infra",    "Berlin",     "SRE",            "2y",  "4.3", "$130k" },
        &.{ "05", "Eve",     "Growth",   "Lisbon",     "Designer",       "1y",  "4.5", "$95k"  },
        &.{ "06", "Frank",   "Infra",    "Singapore",  "Eng Manager",    "7y",  "4.6", "$160k" },
        &.{ "07", "Grace",   "Platform", "Berlin",     "Engineer",       "4y",  "4.7", "$125k" },
        &.{ "08", "Heidi",   "Sec",      "Tel Aviv",   "Security Eng",   "6y",  "4.4", "$140k" },
        &.{ "09", "Ivan",    "Growth",   "Lisbon",     "Engineer",       "2y",  "4.0", "$105k" },
        &.{ "10", "Judy",    "Platform", "Tokyo",      "Engineer",       "3y",  "4.2", "$118k" },
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        var t = zz.components.DataTable.init(ctx.persistent_allocator);
        t.setColumns(&headers) catch return .quit;
        for (rows) |r| t.addRow(r) catch {};
        t.setSize(60, 15);
        t.setFrozenColumns(2); // id + name stay visible while you scroll right.
        self.* = .{ .table = t };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        else => self.table.handleKey(k),
                    },
                    .escape => return .quit,
                    else => self.table.handleKey(k),
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan());
        title_style = title_style.inline_style(true);
        const title = title_style.render(alloc, "DataTable — frozen columns + cell cursor") catch "";

        var table_mut = @constCast(&self.table);
        const table_view = table_mut.view(alloc) catch "";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(10));
        help_style = help_style.inline_style(true);
        const help_text = std.fmt.allocPrint(
            alloc,
            "cursor row {d}, col {d}   |   ←→↑↓ / hjkl move   home/end col   g/G row   q quit",
            .{ self.table.cursor_row, self.table.cursor_col },
        ) catch "";
        const help = help_style.render(alloc, help_text) catch "";

        return std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}", .{ title, table_view, help }) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.table.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
