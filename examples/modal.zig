//! ZigZag Modal Example
//! Demonstrates the Modal component with different dialog types.
//!
//! Keys:
//!   1  — Show info modal
//!   2  — Show confirm modal
//!   3  — Show warning modal
//!   4  — Show error modal
//!   5  — Show custom modal
//!   q  — Quit

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    modal: zz.Modal,
    last_result: []const u8,
    last_result_buf: [64]u8,
    status: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.modal = zz.Modal.init();
        self.last_result = "None";
        self.last_result_buf = undefined;
        self.status = "Press 1-5 to open a modal";
        return .none;
    }

    pub fn update(self: *Model, m: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (m) {
            .key => |k| {
                // If modal is visible, let it handle keys
                if (self.modal.isVisible()) {
                    self.modal.handleKey(k);

                    // Check for result
                    if (self.modal.getResult()) |res| {
                        self.last_result = switch (res) {
                            .button_pressed => |idx| std.fmt.bufPrint(
                                &self.last_result_buf,
                                "Button {d} pressed",
                                .{idx},
                            ) catch "Button pressed",
                            .dismissed => "Dismissed (Escape)",
                        };
                        self.status = "Press 1-5 to open another modal";
                    }
                    return .none;
                }

                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '1' => {
                            self.modal = zz.Modal.info("Information", "This is an informational message.\nEverything is working correctly.");
                            self.modal.backdrop = .{};
                            self.modal.show();
                            self.status = "Info modal open";
                        },
                        '2' => {
                            self.modal = zz.Modal.confirm("Confirm Action", "Are you sure you want to proceed?\nThis action cannot be undone.");
                            self.modal.backdrop = .{};
                            self.modal.show();
                            self.status = "Confirm modal open";
                        },
                        '3' => {
                            self.modal = zz.Modal.warning("Warning", "Low disk space remaining.\nConsider freeing up some space.");
                            self.modal.backdrop = .{};
                            self.modal.show();
                            self.status = "Warning modal open";
                        },
                        '4' => {
                            self.modal = zz.Modal.err("Error", "Failed to save file.\nPermission denied.");
                            self.modal.backdrop = .{};
                            self.modal.show();
                            self.status = "Error modal open";
                        },
                        '5' => {
                            self.modal = zz.Modal.init();
                            self.modal.title = "Custom Dialog";
                            self.modal.body = "This is a fully customized modal.\nWith multiple lines of content.\nAnd custom buttons below.";
                            self.modal.footer = "Use Tab/arrows to navigate, Enter to select";
                            self.modal.width = .{ .fixed = 50 };
                            self.modal.border_chars = zz.Border.double;
                            self.modal.border_fg = zz.Color.magenta;
                            self.modal.title_style = blk: {
                                var s = zz.Style{};
                                s = s.bold(true).fg(zz.Color.magenta).inline_style(true);
                                break :blk s;
                            };
                            self.modal.content_bg = zz.Color.gray(2);
                            self.modal.backdrop = .{};
                            self.modal.addButton("Save", .{ .char = 's' });
                            self.modal.addButton("Discard", .{ .char = 'd' });
                            self.modal.addButton("Cancel", null);
                            self.modal.show();
                            self.status = "Custom modal open";
                        },
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        // If modal is visible, render it with backdrop
        if (self.modal.isVisible()) {
            return self.modal.viewWithBackdrop(alloc, ctx.width, ctx.height) catch "Error";
        }

        // Main view
        var title_s = zz.Style{};
        title_s = title_s.bold(true).fg(zz.Color.hex("#FF6B6B")).inline_style(true);

        var hint_s = zz.Style{};
        hint_s = hint_s.fg(zz.Color.gray(14)).inline_style(true);

        var result_s = zz.Style{};
        result_s = result_s.fg(zz.Color.cyan).inline_style(true);

        var status_s = zz.Style{};
        status_s = status_s.fg(zz.Color.gray(12)).inline_style(true);

        const title = title_s.render(alloc, "Modal Component Demo") catch "Modal Component Demo";
        const hint = hint_s.render(alloc, "1: Info  2: Confirm  3: Warning  4: Error  5: Custom  q: Quit") catch "";
        const result_label = result_s.render(alloc, std.fmt.allocPrint(alloc, "Last result: {s}", .{self.last_result}) catch "") catch "";
        const status = status_s.render(alloc, self.status) catch "";

        const content = std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}\n{s}", .{
            title, hint, result_label, status,
        }) catch "Error";

        return zz.place.place(alloc, ctx.width, ctx.height, .center, .middle, content) catch content;
    }
};

pub fn main(init: std.process.Init) !void {
    var prog = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer prog.deinit();

    try prog.run();
}
