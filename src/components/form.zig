//! Form component.
//! Composes multiple input fields with focus management, labels, and validation.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const focus_mod = @import("focus.zig");

/// Universally-supported submit bindings. Ctrl+S works in every terminal
/// (no encoding ambiguity). Ctrl+Enter is included for terminals that
/// implement the Kitty keyboard protocol — most don't (notably macOS
/// Terminal.app, basic xterm), so it's a bonus, not the primary binding.
const default_submit_keys = [_]keys.KeyEvent{
    keys.KeyEvent.ctrl('s'),
    .{ .key = .enter, .modifiers = .{ .ctrl = true } },
};

const default_cancel_keys = [_]keys.KeyEvent{
    .{ .key = .escape },
};

pub fn Form(comptime max_fields: usize) type {
    return struct {
        // Fields
        fields: [max_fields]?Field,
        field_count: usize,

        // Focus
        focus_group: focus_mod.FocusGroup(max_fields),

        // State
        submitted: bool,
        cancelled: bool,

        // Layout
        label_width: u16,
        spacing: u16,
        show_required_marker: bool,

        // Submit bindings. Multiple keys can submit the form. Default
        // includes Ctrl+S (works in every terminal) and Ctrl+Enter (only
        // works in terminals that implement the Kitty keyboard protocol —
        // Terminal.app and most basic xterms cannot tell Ctrl+Enter from
        // plain Enter, so we don't rely on it).
        submit_keys: []const keys.KeyEvent,
        cancel_keys: []const keys.KeyEvent,
        /// Human-readable description of submit/cancel bindings shown in the
        /// footer hint. Override if you change submit_keys/cancel_keys.
        hint_text: []const u8,

        // Styling
        label_style: style_mod.Style,
        required_style: style_mod.Style,
        error_style: style_mod.Style,
        border_chars: border_mod.BorderChars,
        border_fg: Color,
        border_focus_fg: Color,
        title: []const u8,
        title_style: style_mod.Style,

        const Self = @This();

        pub const Field = struct {
            label: []const u8,
            required: bool,
            error_msg: ?[]const u8,
            // Type-erased component
            ptr: *anyopaque,
            view_fn: *const fn (*anyopaque, std.mem.Allocator) anyerror![]const u8,
            handle_key_fn: *const fn (*anyopaque, keys.KeyEvent) void,
            validate_fn: ?*const fn (*anyopaque) ?[]const u8,
        };

        pub fn init() Self {
            return .{
                .fields = [_]?Field{null} ** max_fields,
                .field_count = 0,
                .focus_group = .{},
                .submitted = false,
                .cancelled = false,
                .label_width = 15,
                .spacing = 1,
                .show_required_marker = true,
                .submit_keys = &default_submit_keys,
                .cancel_keys = &default_cancel_keys,
                .hint_text = "Tab: next field | Ctrl+S: submit | Esc: cancel",
                .label_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .required_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.red);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .error_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(.red);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .border_chars = .rounded,
                .border_fg = .gray(10),
                .border_focus_fg = .cyan,
                .title = "",
                .title_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.fg(.cyan);
                    s = s.inline_style(true);
                    break :blk s;
                },
            };
        }

        /// Add a focusable component as a form field.
        pub fn addField(self: *Self, label: []const u8, component: anytype, options: struct {
            required: bool = false,
            validate_fn: ?*const fn (*anyopaque) ?[]const u8 = null,
        }) void {
            if (self.field_count >= max_fields) return;

            const Ptr = @TypeOf(component);
            const T = @typeInfo(Ptr).pointer.child;

            self.fields[self.field_count] = .{
                .label = label,
                .required = options.required,
                .error_msg = null,
                .ptr = @ptrCast(component),
                .view_fn = @ptrCast(&struct {
                    fn call(raw_ptr: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8 {
                        const ptr: *T = @ptrCast(@alignCast(raw_ptr));
                        return ptr.view(allocator);
                    }
                }.call),
                .handle_key_fn = @ptrCast(&struct {
                    fn call(raw_ptr: *anyopaque, key: keys.KeyEvent) void {
                        const ptr: *T = @ptrCast(@alignCast(raw_ptr));
                        ptr.handleKey(key);
                    }
                }.call),
                .validate_fn = options.validate_fn,
            };

            self.focus_group.add(component);
            self.field_count += 1;
        }

        /// Initialize focus on first field.
        pub fn initFocus(self: *Self) void {
            self.focus_group.initFocus();
        }

        /// Check if form was submitted.
        pub fn isSubmitted(self: *const Self) bool {
            return self.submitted;
        }

        /// Check if form was cancelled.
        pub fn isCancelled(self: *const Self) bool {
            return self.cancelled;
        }

        /// Reset submission state.
        pub fn reset(self: *Self) void {
            self.submitted = false;
            self.cancelled = false;
            for (0..self.field_count) |i| {
                if (self.fields[i]) |*field| {
                    field.error_msg = null;
                }
            }
        }

        /// Validate all fields. Returns true if all pass.
        pub fn validate(self: *Self) bool {
            var all_valid = true;
            for (0..self.field_count) |i| {
                if (self.fields[i]) |*field| {
                    if (field.validate_fn) |vfn| {
                        field.error_msg = vfn(field.ptr);
                        if (field.error_msg != null) all_valid = false;
                    }
                }
            }
            return all_valid;
        }

        /// Get current focused field index.
        pub fn focusedIndex(self: *const Self) usize {
            return self.focus_group.focused();
        }

        /// Handle key events.
        pub fn handleKey(self: *Self, key: keys.KeyEvent) bool {
            // Submit on any configured submit key.
            for (self.submit_keys) |sk| {
                if (sk.eql(key)) {
                    if (self.validate()) {
                        self.submitted = true;
                    }
                    return true;
                }
            }

            // Cancel on any configured cancel key.
            for (self.cancel_keys) |ck| {
                if (ck.eql(key)) {
                    self.cancelled = true;
                    return true;
                }
            }

            // Tab/Shift+Tab for focus cycling
            if (self.focus_group.handleKey(key)) {
                return true;
            }

            // Forward to active field
            const active = self.focus_group.focused();
            if (active < self.field_count) {
                if (self.fields[active]) |field| {
                    field.handle_key_fn(field.ptr, key);
                    return true;
                }
            }

            return false;
        }

        /// Render the form.
        pub fn view(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result: Writer.Allocating = .init(allocator);
            const writer = &result.writer;

            // Title
            if (self.title.len > 0) {
                const styled_title = try self.title_style.render(allocator, self.title);
                try writer.writeAll(styled_title);
                try writer.writeByte('\n');
                try writer.writeByte('\n');
            }

            // Fields
            for (0..self.field_count) |i| {
                const field = self.fields[i] orelse continue;

                if (i > 0) {
                    for (0..self.spacing) |_| try writer.writeByte('\n');
                }

                // Label
                const label_text = if (field.required and self.show_required_marker)
                    try std.fmt.allocPrint(allocator, "{s} *", .{field.label})
                else
                    field.label;

                const is_focused = self.focus_group.isFocused(i);
                const lbl_style = if (is_focused) blk: {
                    var s = self.label_style;
                    s = s.fg(self.border_focus_fg);
                    break :blk s;
                } else self.label_style;

                const styled_label = try lbl_style.render(allocator, label_text);
                try writer.writeAll(styled_label);
                try writer.writeByte('\n');

                // Component view
                const component_view = field.view_fn(field.ptr, allocator) catch try allocator.dupe(u8, "render error");
                try writer.writeAll(component_view);

                // Error message
                if (field.error_msg) |err_msg| {
                    try writer.writeByte('\n');
                    const styled_err = try self.error_style.render(allocator, err_msg);
                    try writer.writeAll(styled_err);
                }
            }

            // Footer
            try writer.writeAll("\n\n");
            var hint_style = style_mod.Style{};
            hint_style = hint_style.fg(.gray(12));
            hint_style = hint_style.inline_style(true);
            const hint = try hint_style.render(allocator, self.hint_text);
            try writer.writeAll(hint);

            return result.toOwnedSlice();
        }
    };
}
