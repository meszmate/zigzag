//! ZigZag Menu Bar Example
//! Demonstrates a horizontal menu bar with dropdown menus.

const std = @import("std");
const zz = @import("zigzag");

const MenuAction = enum {
    file_new,
    file_open,
    file_save,
    file_quit,
    edit_undo,
    edit_redo,
    edit_cut,
    edit_copy,
    edit_paste,
    view_fullscreen,
    view_sidebar,
    help_about,
};

const MB = zz.MenuBar(MenuAction);

const Model = struct {
    menu: MB,
    status: []const u8,
    fullscreen: bool,
    sidebar: bool,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.menu = MB.init();
        self.status = "Ready";
        self.fullscreen = false;
        self.sidebar = true;

        self.menu.addMenu("File", 'F', &.{
            MB.action("New", "Ctrl+N", .file_new),
            MB.action("Open", "Ctrl+O", .file_open),
            MB.action("Save", "Ctrl+S", .file_save),
            MB.separator(),
            MB.action("Quit", "Ctrl+Q", .file_quit),
        });

        self.menu.addMenu("Edit", 'E', &.{
            MB.action("Undo", "Ctrl+Z", .edit_undo),
            MB.action("Redo", "Ctrl+Y", .edit_redo),
            MB.separator(),
            MB.action("Cut", "Ctrl+X", .edit_cut),
            MB.action("Copy", "Ctrl+C", .edit_copy),
            MB.action("Paste", "Ctrl+V", .edit_paste),
        });

        self.menu.addMenu("View", 'V', &.{
            MB.checkedAction("Fullscreen", .view_fullscreen, false),
            MB.checkedAction("Sidebar", .view_sidebar, true),
        });

        self.menu.addMenu("Help", 'H', &.{
            MB.action("About", "", .help_about),
        });

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                // Menu gets first crack at keys
                if (self.menu.handleKey(k)) {
                    // Check for menu action
                    if (self.menu.getSelectedAction()) |act| {
                        return self.handleAction(act);
                    }
                    return .none;
                }

                // Global shortcuts
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        else => {},
                    },
                    .escape => {
                        if (self.menu.isOpen()) {
                            self.menu.deactivate();
                        } else {
                            return .quit;
                        }
                    },
                    .f9 => self.menu.activate(),
                    else => {},
                }
            },
        }
        return .none;
    }

    fn handleAction(self: *Model, act: MenuAction) zz.Cmd(Msg) {
        switch (act) {
            .file_new => self.status = "New file created",
            .file_open => self.status = "Open dialog...",
            .file_save => self.status = "File saved",
            .file_quit => return .quit,
            .edit_undo => self.status = "Undo",
            .edit_redo => self.status = "Redo",
            .edit_cut => self.status = "Cut to clipboard",
            .edit_copy => self.status = "Copied to clipboard",
            .edit_paste => self.status = "Pasted from clipboard",
            .view_fullscreen => {
                self.fullscreen = !self.fullscreen;
                self.status = if (self.fullscreen) "Fullscreen: ON" else "Fullscreen: OFF";
            },
            .view_sidebar => {
                self.sidebar = !self.sidebar;
                self.status = if (self.sidebar) "Sidebar: ON" else "Sidebar: OFF";
            },
            .help_about => self.status = "ZigZag Menu Bar v1.0",
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const menu_view = self.menu.view(ctx.allocator, ctx.width) catch "error";

        var content_style = zz.Style{};
        content_style = content_style.fg(zz.Color.gray(16));
        content_style = content_style.inline_style(true);

        const content = content_style.render(
            ctx.allocator,
            "Press F9 or Alt+F/E/V/H to open menus\nUse arrow keys to navigate, Enter to select",
        ) catch "";

        var status_style = zz.Style{};
        status_style = status_style.fg(zz.Color.cyan);
        status_style = status_style.bold(true);
        status_style = status_style.inline_style(true);
        const status = std.fmt.allocPrint(ctx.allocator, "Status: {s}", .{self.status}) catch "?";
        const styled_status = status_style.render(ctx.allocator, status) catch status;

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator, "F9: activate menu | Alt+letter: open menu | q/Esc: quit") catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}\n\n{s}",
            .{ menu_view, content, styled_status, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
