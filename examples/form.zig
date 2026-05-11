//! ZigZag Form Example
//! Demonstrates a form composing TextInput, Checkbox, and Confirm fields.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    name_input: zz.TextInput,
    email_input: zz.TextInput,
    agree_checkbox: zz.Checkbox,
    form: zz.Form(3),
    status: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.name_input = zz.TextInput.init(ctx.persistent_allocator);
        self.name_input.placeholder = "Enter your name...";

        self.email_input = zz.TextInput.init(ctx.persistent_allocator);
        self.email_input.placeholder = "user@example.com";

        self.agree_checkbox = zz.Checkbox.init("I agree to the terms and conditions");

        self.form = zz.Form(3).init();
        self.form.title = "Registration Form";
        self.form.addField("Name", &self.name_input, .{ .required = true });
        self.form.addField("Email", &self.email_input, .{ .required = true });
        self.form.addField("Terms", &self.agree_checkbox, .{});
        self.form.initFocus();

        self.status = "Fill out the form and press Ctrl+S to submit (Ctrl+Enter also works in capable terminals)";

        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                if (k.key == .char) {
                    if (k.key.char == 'q' and k.modifiers.ctrl) return .quit;
                }

                _ = self.form.handleKey(k);

                if (self.form.isSubmitted()) {
                    self.status = "Form submitted successfully!";
                    self.form.reset();
                } else if (self.form.isCancelled()) {
                    return .quit;
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const form_view = self.form.view(ctx.allocator) catch "error";

        var status_style = zz.Style{};
        status_style = status_style.fg(zz.Color.green);
        status_style = status_style.bold(true);
        status_style = status_style.inline_style(true);
        const styled_status = status_style.render(ctx.allocator, self.status) catch self.status;

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}",
            .{ form_view, styled_status },
        ) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.name_input.deinit();
        self.email_input.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
