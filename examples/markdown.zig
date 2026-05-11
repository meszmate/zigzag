//! ZigZag Markdown Renderer Example
//! Demonstrates rendering markdown to styled terminal output.

const std = @import("std");
const zz = @import("zigzag");

const sample_md =
    \\# ZigZag TUI Framework
    \\
    \\A **modern** TUI library for *Zig* inspired by Bubble Tea and Lipgloss.
    \\
    \\## Features
    \\
    \\- Elm architecture (Model-Update-View)
    \\- Rich **component library**
    \\- `Style` builder with *colors* and borders
    \\- Cross-platform terminal support
    \\
    \\### Getting Started
    \\
    \\1. Add ZigZag to your `build.zig.zon`
    \\2. Import with `const zz = @import("zigzag")`
    \\3. Create a `Model` struct with `init`, `update`, `view`
    \\
    \\> ZigZag makes terminal UI development feel natural and productive.
    \\> Build beautiful TUIs with minimal boilerplate.
    \\
    \\---
    \\
    \\```
    \\const std = @import("std");
    \\const zz = @import("zigzag");
    \\
    \\pub fn main() !void {
    \\    var program = zz.Program(Model).init(allocator);
    \\    try program.run();
    \\}
    \\```
    \\
    \\Check out the [documentation](https://github.com/meszmate/zigzag) for more.
;

const Model = struct {
    md: zz.Markdown,
    viewport: zz.components.Viewport,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.md = zz.Markdown.init();
        self.md.width = @min(ctx.width -| 4, 80);

        self.viewport = zz.components.Viewport.init(ctx.persistent_allocator, self.md.width, ctx.height -| 4);
        // Viewport.setContent dupes; render output is ephemeral.
        if (self.md.render(ctx.persistent_allocator, sample_md)) |rendered| {
            defer ctx.persistent_allocator.free(rendered);
            self.viewport.setContent(rendered) catch {};
        } else |_| {
            self.viewport.setContent("render error") catch {};
        }

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
                self.viewport.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const content = self.viewport.view(ctx.allocator) catch "error";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator, "j/k or Up/Down: scroll | q: quit") catch "";

        return std.fmt.allocPrint(ctx.allocator, "{s}\n{s}", .{ content, help }) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.viewport.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
