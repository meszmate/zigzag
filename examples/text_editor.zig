//! ZigZag Text Editor Example
//! Demonstrates the TextArea component for multi-line editing.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    editor: zz.components.TextArea,
    status_message: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.editor = zz.components.TextArea.init(ctx.persistent_allocator);
        self.editor.setSize(ctx.width -| 4, ctx.height -| 8);
        self.editor.line_numbers = true;
        self.editor.placeholder = "Start typing...";

        // Sample text
        self.editor.setValue(
            \\// Welcome to ZigZag Text Editor!
            \\//
            \\// This is a demo of the TextArea component.
            \\// You can edit this text using standard editor controls.
            \\
            \\const std = @import("std");
            \\
            \\pub fn main() !void {
            \\    std.debug.print("Hello, World!\n", .{});
            \\}
        ) catch {};

        self.status_message = "";
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                // Handle Ctrl+Q to quit
                if (k.modifiers.ctrl) {
                    switch (k.key) {
                        .char => |c| {
                            switch (c) {
                                'q' => return .quit,
                                's' => {
                                    self.status_message = "Saved! (not really)";
                                    return .none;
                                },
                                else => {},
                            }
                        },
                        else => {},
                    }
                }

                // Handle escape to quit
                if (k.key == .escape) {
                    return .quit;
                }

                // Pass to editor
                self.editor.handleKey(k);
                self.status_message = "";

                // Update size based on context
                self.editor.setSize(ctx.width -| 4, ctx.height -| 8);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Title
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "ZigZag Text Editor") catch "Text Editor";

        // Editor with border
        var editor_style = zz.Style{};
        editor_style = editor_style.borderAll(zz.Border.rounded);
        editor_style = editor_style.borderForeground(zz.Color.gray(12));

        const editor_content = self.editor.view(ctx.allocator) catch "";
        const editor_box = editor_style.render(ctx.allocator, editor_content) catch editor_content;

        // Status bar
        const cursor_info = std.fmt.allocPrint(
            ctx.allocator,
            "Ln {d}, Col {d} | {d} lines",
            .{ self.editor.cursor_row + 1, self.editor.cursorDisplayColumn() + 1, self.editor.lineCount() },
        ) catch "";

        var status_style = zz.Style{};
        status_style = status_style.fg(zz.Color.gray(18));
        status_style = status_style.inline_style(true);
        const status = status_style.render(ctx.allocator, cursor_info) catch "";

        // Status message
        var msg_style = zz.Style{};
        msg_style = msg_style.fg(zz.Color.green);
        msg_style = msg_style.inline_style(true);
        const msg = msg_style.render(ctx.allocator, self.status_message) catch "";

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Ctrl+S: Save  Ctrl+Q: Quit  Arrow keys: Navigate",
        ) catch "";

        // Get max width for centering
        const editor_width = zz.measure.maxLineWidth(editor_box);
        const title_width = zz.measure.width(title);
        const help_width = zz.measure.width(help);
        const max_width = @max(editor_width, @max(title_width, help_width));

        // Center title and help relative to editor width
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_help = zz.place.place(ctx.allocator, max_width, 1, .center, .top, help) catch help;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}  {s}\n{s}",
            .{ centered_title, editor_box, status, msg, centered_help },
        ) catch "Error";

        // Center horizontally, keep at top vertically (editor needs space)
        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .top,
            content,
        ) catch content;
    }

    pub fn deinit(self: *Model) void {
        self.editor.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
