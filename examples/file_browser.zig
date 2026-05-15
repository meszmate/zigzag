//! ZigZag File Browser Example
//! Demonstrates the FilePicker component for file system navigation.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    file_picker: zz.components.FilePicker,
    preview: std.array_list.Managed(u8),
    error_message: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.file_picker = zz.components.FilePicker.init(ctx.persistent_allocator);
        self.file_picker.height = ctx.height -| 10;
        self.file_picker.setHomePath(ctx.home_dir);

        // Start at home directory
        self.file_picker.navigateHome(ctx.io) catch {
            self.file_picker.navigate(ctx.io, "/") catch {};
        };

        self.preview = std.array_list.Managed(u8).init(ctx.persistent_allocator);
        self.error_message = "";
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        else => {
                            const selected = self.file_picker.handleKey(ctx.io, k) catch false;
                            if (selected) {
                                self.loadPreview(ctx.io);
                            }
                        },
                    },
                    .escape => return .quit,
                    else => {
                        const selected = self.file_picker.handleKey(ctx.io, k) catch false;
                        if (selected) {
                            self.loadPreview(ctx.io);
                        }
                    },
                }

                // Update height based on context
                self.file_picker.height = ctx.height -| 10;
            },
        }
        return .none;
    }

    fn loadPreview(self: *Model, io: std.Io) void {
        if (self.file_picker.getSelected()) |path| {
            // Try to read file preview
            const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch {
                self.error_message = "Cannot open file";
                self.preview.clearRetainingCapacity();
                return;
            };
            defer file.close(io);

            // Read first 500 bytes
            var buf: [500]u8 = undefined;
            const bytes_read = file.readPositionalAll(io, &buf, 0) catch {
                self.error_message = "Cannot read file";
                self.preview.clearRetainingCapacity();
                return;
            };

            self.preview.clearRetainingCapacity();
            self.preview.appendSlice(buf[0..bytes_read]) catch {
                self.error_message = "Out of memory";
                self.preview.clearRetainingCapacity();
                return;
            };
            self.error_message = "";
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Title
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "File Browser") catch "File Browser";

        // File picker
        const picker_view = self.file_picker.view(ctx.allocator) catch "";

        // Preview section
        var preview_section: []const u8 = "";
        if (self.file_picker.getSelected()) |path| {
            var path_style = zz.Style{};
            path_style = path_style.fg(zz.Color.green);
            path_style = path_style.inline_style(true);
            const path_display = path_style.render(ctx.allocator, path) catch path;

            var preview_style = zz.Style{};
            preview_style = preview_style.borderAll(zz.Border.normal);
            preview_style = preview_style.borderForeground(zz.Color.gray(12));

            const preview_content = if (self.preview.items.len > 0)
                self.preview.items
            else if (self.error_message.len > 0)
                self.error_message
            else
                "(empty file)";

            const preview_box = preview_style.render(ctx.allocator, preview_content) catch preview_content;

            preview_section = std.fmt.allocPrint(
                ctx.allocator,
                "\nSelected: {s}\n\n{s}",
                .{ path_display, preview_box },
            ) catch "";
        }

        // Help
        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(
            ctx.allocator,
            "Up/Down: Navigate  Enter: Open/Select  Backspace: Parent  h: Toggle hidden  ~: Home  q: Quit",
        ) catch "";

        // Get max width for centering title and help
        const picker_width = zz.measure.maxLineWidth(picker_view);
        const title_width = zz.measure.width(title);
        const help_width = zz.measure.width(help);
        const max_width = @max(picker_width, @max(title_width, help_width));

        // Center title and help
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_help = zz.place.place(ctx.allocator, max_width, 1, .center, .top, help) catch help;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}{s}\n\n{s}",
            .{ centered_title, picker_view, preview_section, centered_help },
        ) catch "Error";

        // Center horizontally, but keep at top vertically (file browser needs vertical space)
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
        self.file_picker.deinit();
        self.preview.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
