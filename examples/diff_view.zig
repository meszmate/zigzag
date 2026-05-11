//! ZigZag Diff View Example
//! Demonstrates unified and side-by-side diff display.

const std = @import("std");
const zz = @import("zigzag");

const old_text =
    \\fn greet(name: []const u8) void {
    \\    std.debug.print("Hello, {s}!\n", .{name});
    \\}
    \\
    \\pub fn main() !void {
    \\    greet("World");
    \\    greet("Zig");
    \\}
;

const new_text =
    \\fn greet(name: []const u8, excited: bool) void {
    \\    if (excited) {
    \\        std.debug.print("Hello, {s}!!!\n", .{name});
    \\    } else {
    \\        std.debug.print("Hello, {s}.\n", .{name});
    \\    }
    \\}
    \\
    \\pub fn main() !void {
    \\    greet("World", true);
    \\    greet("Zig", false);
    \\    greet("ZigZag", true);
    \\}
;

const Model = struct {
    side_by_side: bool,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .side_by_side = false };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    'm' => self.side_by_side = !self.side_by_side,
                    else => {},
                },
                .escape => return .quit,
                else => {},
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

        var dv = zz.components.diff_view.DiffView{};
        dv.old_text = old_text;
        dv.new_text = new_text;
        dv.old_label = "greet.zig (before)";
        dv.new_label = "greet.zig (after)";
        dv.mode = if (self.side_by_side) .side_by_side else .unified;

        var box_s = zz.Style{};
        box_s = box_s.borderAll(zz.Border.rounded);
        box_s = box_s.borderForeground(zz.Color.gray(10));
        box_s = box_s.paddingAll(1);

        const diff_output = dv.view(alloc);
        const boxed = box_s.render(alloc, diff_output) catch diff_output;

        const mode_label: []const u8 = if (self.side_by_side) "side-by-side" else "unified";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        return std.fmt.allocPrint(alloc, "{s}  [{s}]\n\n{s}\n\n{s}", .{
            title_s.render(alloc, "Diff Viewer") catch "Diff Viewer",
            mode_label,
            boxed,
            help_s.render(alloc, "m: toggle mode  q: quit") catch "",
        }) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
