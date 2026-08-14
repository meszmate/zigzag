//! ZigZag Checkbox & RadioGroup Example
//! Demonstrates standalone checkboxes, checkbox groups, and radio groups.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    // Standalone checkboxes
    agree_terms: zz.Checkbox,
    newsletter: zz.Checkbox,

    // Checkbox group: pick languages
    languages: zz.CheckboxGroup(Language),

    // Radio group: pick experience
    experience: zz.RadioGroup(Experience),

    // Focus
    focus_group: zz.FocusGroup(4),

    const Language = enum { zig, rust, go, python, javascript, c };
    const Experience = enum { beginner, intermediate, advanced, expert };

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) !zz.Cmd(Msg) {
        self.agree_terms = zz.Checkbox.init("I agree to the terms");
        self.newsletter = zz.Checkbox.init("Subscribe to newsletter");
        self.newsletter.checked = true;

        self.languages = zz.CheckboxGroup(Language).init(ctx.persistent_allocator);
        self.languages.height = 6;
        try self.languages.addItems(&.{
            .{ .value = .zig, .label = "Zig", .description = "Systems programming", .enabled = true, .checked = false },
            .{ .value = .rust, .label = "Rust", .description = "Memory safe", .enabled = true, .checked = false },
            .{ .value = .go, .label = "Go", .description = "Concurrency", .enabled = true, .checked = false },
            .{ .value = .python, .label = "Python", .description = "Scripting", .enabled = true, .checked = false },
            .{ .value = .javascript, .label = "JavaScript", .description = "Web", .enabled = true, .checked = false },
            .{ .value = .c, .label = "C", .description = "Classic", .enabled = true, .checked = false },
        });

        self.experience = zz.RadioGroup(Experience).init(ctx.persistent_allocator);
        self.experience.height = 4;
        try self.experience.addOptions(&.{
            .{ .value = .beginner, .label = "Beginner", .description = "", .enabled = true },
            .{ .value = .intermediate, .label = "Intermediate", .description = "", .enabled = true },
            .{ .value = .advanced, .label = "Advanced", .description = "", .enabled = true },
            .{ .value = .expert, .label = "Expert", .description = "", .enabled = true },
        });

        self.focus_group = .{};
        self.focus_group.add(&self.agree_terms);
        self.focus_group.add(&self.newsletter);
        self.focus_group.add(&self.languages);
        self.focus_group.add(&self.experience);
        self.focus_group.initFocus();

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

                if (self.focus_group.handleKey(k)) return .none;

                self.agree_terms.handleKey(k);
                self.newsletter.handleKey(k);
                self.languages.handleKey(k);
                self.experience.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta);
        title_style = title_style.inline_style(true);

        var section_style = zz.Style{};
        section_style = section_style.bold(true);
        section_style = section_style.fg(zz.Color.cyan);
        section_style = section_style.inline_style(true);

        const title = try title_style.render(ctx.allocator, "Checkbox & Radio Example");

        // Standalone checkboxes
        const cb_title = try section_style.render(ctx.allocator, "Preferences:");
        const terms_view = try self.agree_terms.view(ctx.allocator);
        const news_view = try self.newsletter.view(ctx.allocator);

        // Checkbox group
        const lang_title = try section_style.render(ctx.allocator, "Languages (Space to toggle, a/n/i: all/none/invert):");
        const lang_view = try self.languages.view(ctx.allocator);
        const lang_count = try std.fmt.allocPrint(ctx.allocator, "Selected: {d}", .{self.languages.checkedCount()});

        // Radio group
        const exp_title = try section_style.render(ctx.allocator, "Experience Level (Space/Enter to select):");
        const exp_view = try self.experience.view(ctx.allocator);
        const exp_val = if (self.experience.selectedItem()) |item| try std.fmt.allocPrint(ctx.allocator, "Selected: {s}", .{item.label}) else "None selected";

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = try help_style.render(ctx.allocator, "Tab: switch focus | Space/Enter: toggle/select | q: quit");

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n{s}\n{s}\n\n{s}\n{s}\n{s}\n\n{s}\n{s}\n{s}\n\n{s}",
            .{ title, cb_title, terms_view, news_view, lang_title, lang_view, lang_count, exp_title, exp_view, exp_val, help },
        );
    }

    pub fn deinit(self: *Model) void {
        self.languages.deinit();
        self.experience.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
