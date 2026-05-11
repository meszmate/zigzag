//! ZigZag Focus Form Example
//! Demonstrates focus management with Tab/Shift+Tab cycling between
//! multiple text inputs, with visual focus indicators (border colors).
//!
//! Keys:
//!   Tab        — move to next field
//!   Shift+Tab  — move to previous field
//!   Enter      — submit form
//!   Escape     — quit

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    name_input: zz.TextInput,
    email_input: zz.TextInput,
    message_input: zz.TextInput,
    focus_group: zz.FocusGroup(3),
    focus_style: zz.FocusStyle,
    submitted: bool,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        // Initialize text inputs
        self.name_input = zz.TextInput.init(ctx.persistent_allocator);
        self.name_input.setPlaceholder("Your name...");
        self.name_input.setPrompt("  ");

        self.email_input = zz.TextInput.init(ctx.persistent_allocator);
        self.email_input.setPlaceholder("you@example.com");
        self.email_input.setPrompt("  ");

        self.message_input = zz.TextInput.init(ctx.persistent_allocator);
        self.message_input.setPlaceholder("Type your message...");
        self.message_input.setPrompt("  ");

        // Set up focus group
        self.focus_group = .{};
        self.focus_group.add(&self.name_input);
        self.focus_group.add(&self.email_input);
        self.focus_group.add(&self.message_input);
        self.focus_group.initFocus();

        // Focus style with cyan/gray borders
        self.focus_style = .{};

        self.submitted = false;

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (self.submitted) {
                    // Any key after submit quits
                    return .quit;
                }

                switch (k.key) {
                    .escape => return .quit,
                    .enter => {
                        self.submitted = true;
                        return .none;
                    },
                    else => {},
                }

                // Try focus cycling first (consumes Tab/Shift+Tab)
                if (self.focus_group.handleKey(k)) return .none;

                // Forward key to all inputs (unfocused ones auto-ignore)
                self.name_input.handleKey(k);
                self.email_input.handleKey(k);
                self.message_input.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Title
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.hex("#FF6B6B"));
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Contact Form") catch "Contact Form";

        // Subtitle
        var sub_style = zz.Style{};
        sub_style = sub_style.fg(zz.Color.gray(15));
        sub_style = sub_style.inline_style(true);
        const subtitle = sub_style.render(ctx.allocator, "Tab/Shift+Tab to navigate • Enter to submit • Esc to quit") catch "";

        // Field labels
        var label_style = zz.Style{};
        label_style = label_style.bold(true);
        label_style = label_style.inline_style(true);

        var focused_label = zz.Style{};
        focused_label = focused_label.bold(true);
        focused_label = focused_label.fg(zz.Color.cyan);
        focused_label = focused_label.inline_style(true);

        // Render each field with focus indicator
        const name_label = if (self.focus_group.isFocused(0))
            focused_label.render(ctx.allocator, "▸ Name") catch "Name"
        else
            label_style.render(ctx.allocator, "  Name") catch "Name";

        const email_label = if (self.focus_group.isFocused(1))
            focused_label.render(ctx.allocator, "▸ Email") catch "Email"
        else
            label_style.render(ctx.allocator, "  Email") catch "Email";

        const message_label = if (self.focus_group.isFocused(2))
            focused_label.render(ctx.allocator, "▸ Message") catch "Message"
        else
            label_style.render(ctx.allocator, "  Message") catch "Message";

        // Render inputs
        const name_view = self.name_input.view(ctx.allocator) catch "";
        const email_view = self.email_input.view(ctx.allocator) catch "";
        const message_view = self.message_input.view(ctx.allocator) catch "";

        // Wrap each input in a focus-styled box
        const name_box = self.renderField(ctx, name_label, name_view, 0);
        const email_box = self.renderField(ctx, email_label, email_view, 1);
        const message_box = self.renderField(ctx, message_label, message_view, 2);

        // Status line
        const status = if (self.submitted) blk: {
            var success_style = zz.Style{};
            success_style = success_style.bold(true);
            success_style = success_style.fg(zz.Color.green);
            success_style = success_style.inline_style(true);

            const name_val = self.name_input.getValue();
            const email_val = self.email_input.getValue();
            const msg_val = self.message_input.getValue();

            const text = std.fmt.allocPrint(
                ctx.allocator,
                "✓ Submitted! Name: {s}, Email: {s}, Message: {s}",
                .{
                    if (name_val.len > 0) name_val else "(empty)",
                    if (email_val.len > 0) email_val else "(empty)",
                    if (msg_val.len > 0) msg_val else "(empty)",
                },
            ) catch "✓ Submitted!";
            break :blk success_style.render(ctx.allocator, text) catch text;
        } else blk: {
            var hint_style = zz.Style{};
            hint_style = hint_style.fg(zz.Color.gray(12));
            hint_style = hint_style.inline_style(true);
            const field_name = switch (self.focus_group.focused()) {
                0 => "Name",
                1 => "Email",
                2 => "Message",
                else => "?",
            };
            const text = std.fmt.allocPrint(
                ctx.allocator,
                "Editing: {s} (field {d}/{d})",
                .{ field_name, self.focus_group.focused() + 1, self.focus_group.len() },
            ) catch "";
            break :blk hint_style.render(ctx.allocator, text) catch text;
        };

        // Get max width
        const box_width = @max(
            zz.measure.maxLineWidth(name_box),
            @max(zz.measure.maxLineWidth(email_box), zz.measure.maxLineWidth(message_box)),
        );
        const max_width = @max(box_width, @max(zz.measure.width(title), zz.measure.width(subtitle)));

        // Center elements
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_sub = zz.place.place(ctx.allocator, max_width, 1, .center, .top, subtitle) catch subtitle;
        const centered_status = zz.place.place(ctx.allocator, max_width, 1, .center, .top, status) catch status;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n\n{s}\n{s}\n{s}\n\n{s}",
            .{ centered_title, centered_sub, name_box, email_box, message_box, centered_status },
        ) catch "Error rendering view";

        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;
    }

    fn renderField(self: *const Model, ctx: *const zz.Context, label: []const u8, input_view: []const u8, index: usize) []const u8 {
        const content = std.fmt.allocPrint(ctx.allocator, "{s}\n{s}", .{ label, input_view }) catch input_view;
        var box = zz.Style{};
        box = box.paddingLeft(1);
        box = box.paddingRight(1);
        box = box.width(40);
        box = self.focus_style.apply(box, self.focus_group.isFocused(index));
        return box.render(ctx.allocator, content) catch content;
    }

    pub fn deinit(self: *Model) void {
        self.name_input.deinit();
        self.email_input.deinit();
        self.message_input.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var prog = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer prog.deinit();

    try prog.run();
}
