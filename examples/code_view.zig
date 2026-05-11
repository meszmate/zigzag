//! ZigZag Code View Example
//! Demonstrates syntax-highlighted code display.

const std = @import("std");
const zz = @import("zigzag");

const zig_source =
    \\const std = @import("std");
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    const allocator = init.gpa;
    \\    var list = std.std.array_list.Managed(u32).init(allocator);
    \\    defer list.deinit();
    \\
    \\    // Add some numbers
    \\    for (0..10) |i| {
    \\        try list.append(@intCast(i * 42));
    \\    }
    \\
    \\    std.debug.print("Count: {d}\n", .{list.items.len});
    \\}
;

const py_source =
    \\import json
    \\from pathlib import Path
    \\
    \\class DataProcessor:
    \\    """Process data files."""
    \\
    \\    def __init__(self, path: str):
    \\        self.path = Path(path)
    \\        self.count = 0
    \\
    \\    def process(self) -> list:
    \\        # Read and parse JSON data
    \\        data = json.loads(self.path.read_text())
    \\        return [x for x in data if x > 0]
;

const Model = struct {
    lang_idx: u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .lang_idx = 0 };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    '1' => self.lang_idx = 0,
                    '2' => self.lang_idx = 1,
                    else => {},
                },
                .escape => return .quit,
                .tab => self.lang_idx = (self.lang_idx + 1) % 2,
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

        var cv = zz.components.code_view.CodeView{};
        const lang_name: []const u8 = if (self.lang_idx == 0) "Zig" else "Python";
        if (self.lang_idx == 0) {
            cv.source = zig_source;
            cv.language = .zig;
            cv.highlight_line = 12;
        } else {
            cv.source = py_source;
            cv.language = .python;
            cv.highlight_line = 7;
        }

        var box_s = zz.Style{};
        box_s = box_s.borderAll(zz.Border.rounded);
        box_s = box_s.borderForeground(zz.Color.gray(10));
        box_s = box_s.paddingAll(1);

        const code_output = cv.view(alloc);
        const boxed = box_s.render(alloc, code_output) catch code_output;

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(10));
        help_s = help_s.inline_style(true);

        const header = std.fmt.allocPrint(alloc, "{s}  [{s}]", .{
            title_s.render(alloc, "Code Viewer") catch "Code Viewer",
            lang_name,
        }) catch "";

        return std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}", .{
            header,
            boxed,
            help_s.render(alloc, "1: Zig  2: Python  Tab: switch  q: quit") catch "",
        }) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
