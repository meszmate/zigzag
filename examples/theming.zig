//! ZigZag Theming Example
//! Demonstrates the ThemeManager for cycling through built-in palettes,
//! adaptive palettes, and using theme colors in components.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    tm: zz.ThemeManager,
    progress_val: f64,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.tm = zz.ThemeManager.init(ctx.environ_map);
        self.progress_val = 35;
        // Also set the theme on the context so components can read it
        ctx.setTheme(self.tm.current.palette);
        return .{ .every = 100_000_000 };
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'n' => {
                            self.tm.nextBuiltin();
                            ctx.setTheme(self.tm.current.palette);
                        },
                        'p' => {
                            self.tm.prevBuiltin();
                            ctx.setTheme(self.tm.current.palette);
                        },
                        else => {},
                    },
                    .right => {
                        self.tm.nextBuiltin();
                        ctx.setTheme(self.tm.current.palette);
                    },
                    .left => {
                        self.tm.prevBuiltin();
                        ctx.setTheme(self.tm.current.palette);
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
            .tick => {
                self.progress_val += 0.5;
                if (self.progress_val > 100) self.progress_val = 0;
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const t = &self.tm.current;
        const p = &t.palette;

        // Title
        const title_style = zz.Theme.boldStyleWith(p.primary);
        const title = title_style.render(ctx.allocator, "Theme Preview (ThemeManager)") catch "Theme Preview";

        // Theme name and count
        const name_style = zz.Theme.boldStyleWith(p.accent);
        const theme_name = name_style.render(ctx.allocator, self.tm.currentName()) catch "?";
        const theme_line = std.fmt.allocPrint(
            ctx.allocator,
            "Current: {s}  ({d}/{d})",
            .{ theme_name, self.tm.palette_index + 1, zz.ThemeManager.builtinCount() },
        ) catch "?";

        // Color swatches in two rows
        const primary_s = zz.Theme.boldStyleWith(p.primary).render(ctx.allocator, "██ Primary") catch "";
        const secondary_s = zz.Theme.boldStyleWith(p.secondary).render(ctx.allocator, "██ Secondary") catch "";
        const accent_s = zz.Theme.boldStyleWith(p.accent).render(ctx.allocator, "██ Accent") catch "";
        const success_s = zz.Theme.styleWith(p.success).render(ctx.allocator, "██ Success") catch "";
        const warning_s = zz.Theme.styleWith(p.warning).render(ctx.allocator, "██ Warning") catch "";
        const danger_s = zz.Theme.styleWith(p.danger).render(ctx.allocator, "██ Danger") catch "";
        const info_s = zz.Theme.styleWith(p.info).render(ctx.allocator, "██ Info") catch "";

        // Text styles
        const fg_s = zz.Theme.styleWith(p.foreground).render(ctx.allocator, "Foreground text") catch "";
        const muted_s = zz.Theme.styleWith(p.muted).render(ctx.allocator, "Muted text") catch "";
        const subtle_s = zz.Theme.styleWith(p.subtle).render(ctx.allocator, "Subtle text") catch "";

        // Border preview
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(p.border_focus);
        box_style = box_style.paddingAll(1);
        box_style = box_style.fg(p.foreground);
        const box_content = std.fmt.allocPrint(ctx.allocator, "{s}\n{s}\n{s}", .{ fg_s, muted_s, subtle_s }) catch "?";
        const bordered = box_style.render(ctx.allocator, box_content) catch box_content;

        // Surface/overlay preview
        var surface_style = zz.Style{};
        surface_style = surface_style.borderAll(zz.Border.normal);
        surface_style = surface_style.borderForeground(p.border_color);
        surface_style = surface_style.bg(p.surface);
        surface_style = surface_style.fg(p.foreground);
        surface_style = surface_style.paddingLeft(1).paddingRight(1);
        const surface_box = surface_style.render(ctx.allocator, "Surface") catch "Surface";

        var overlay_style = zz.Style{};
        overlay_style = overlay_style.borderAll(zz.Border.normal);
        overlay_style = overlay_style.borderForeground(p.border_color);
        overlay_style = overlay_style.bg(p.overlay);
        overlay_style = overlay_style.fg(p.foreground);
        overlay_style = overlay_style.paddingLeft(1).paddingRight(1);
        const overlay_box = overlay_style.render(ctx.allocator, "Overlay") catch "Overlay";

        // Highlight preview
        var hl_style = zz.Style{};
        hl_style = hl_style.bg(p.highlight);
        hl_style = hl_style.fg(p.highlight_text);
        hl_style = hl_style.inline_style(true);
        const hl_box = hl_style.render(ctx.allocator, " Highlighted ") catch "Highlighted";

        // Progress bar using theme colors
        var prog = zz.Progress.init();
        prog.setValue(self.progress_val);
        prog.width = 30;
        var full_s = zz.Style{};
        full_s = full_s.fg(p.primary);
        full_s = full_s.inline_style(true);
        prog.full_style = full_s;
        var empty_s = zz.Style{};
        empty_s = empty_s.fg(p.subtle);
        empty_s = empty_s.inline_style(true);
        prog.empty_style = empty_s;
        const prog_view = prog.view(ctx.allocator) catch "error";

        // Help
        const help_style = zz.Theme.styleWith(p.muted);
        const help = help_style.render(ctx.allocator,
            \\Left/Right or n/p: switch theme | q: quit
            \\All built-in palettes: Default Dark/Light, Catppuccin,
            \\Dracula, Nord, Tokyo Night, Gruvbox, Solarized, High Contrast
        ) catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n\n{s}  {s}  {s}\n{s}  {s}  {s}  {s}\n\n{s}\n\n{s}  {s}  {s}\n\nProgress: {s}\n\n{s}",
            .{ title, theme_line, primary_s, secondary_s, accent_s, success_s, warning_s, danger_s, info_s, bordered, surface_box, overlay_box, hl_box, prog_view, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
