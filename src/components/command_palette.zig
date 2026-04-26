//! Command palette component.
//!
//! Fuzzy-filtered command launcher, modeled on VS Code's Ctrl-P. Holds a list
//! of commands (label + description + id) and a filter prompt. Renders a
//! bordered pop-up suitable for placing on top of other content using
//! layout.place or layout.layer. Consumers drive it with handleKey and read
//! back selected().

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");
const fuzzy = @import("../core/fuzzy.zig");
const action_mod = @import("../core/action.zig");
const ActionRegistry = action_mod.ActionRegistry;

pub const Command = struct {
    id: []const u8,
    label: []const u8,
    description: []const u8 = "",
    /// Optional shortcut hint shown on the right ("⌘K", "Ctrl+P", etc).
    shortcut: []const u8 = "",
};

/// Result returned by handleKey so the caller knows whether to dismiss or run.
pub const KeyResult = enum {
    ignored,
    consumed,
    accepted,
    cancelled,
};

pub const CommandPalette = struct {
    allocator: std.mem.Allocator,

    commands: std.array_list.Managed(Command),
    /// Indices into commands, filtered and sorted by fuzzy score.
    filtered: std.array_list.Managed(usize),
    /// Filter text entered by the user.
    query: std.array_list.Managed(u8),

    cursor: usize,
    max_visible: u16,
    width: u16,
    prompt: []const u8,
    /// Placeholder shown in the input when the query is empty.
    placeholder: []const u8,

    border_chars: border_mod.BorderChars,
    prompt_style: style_mod.Style,
    input_style: style_mod.Style,
    placeholder_style: style_mod.Style,
    label_style: style_mod.Style,
    description_style: style_mod.Style,
    shortcut_style: style_mod.Style,
    selected_style: style_mod.Style,
    selected_label_style: style_mod.Style,
    empty_style: style_mod.Style,

    pub fn init(allocator: std.mem.Allocator) !CommandPalette {
        var prompt_s = style_mod.Style{};
        prompt_s = prompt_s.fg(.cyan);
        prompt_s = prompt_s.bold(true);
        prompt_s = prompt_s.inline_style(true);

        var input_s = style_mod.Style{};
        input_s = input_s.inline_style(true);

        var placeholder_s = style_mod.Style{};
        placeholder_s = placeholder_s.fg(.gray(8));
        placeholder_s = placeholder_s.inline_style(true);

        var label_s = style_mod.Style{};
        label_s = label_s.inline_style(true);

        var desc_s = style_mod.Style{};
        desc_s = desc_s.fg(.gray(10));
        desc_s = desc_s.inline_style(true);

        var shortcut_s = style_mod.Style{};
        shortcut_s = shortcut_s.fg(.gray(8));
        shortcut_s = shortcut_s.inline_style(true);

        var selected_s = style_mod.Style{};
        selected_s = selected_s.bg(.gray(4));
        selected_s = selected_s.inline_style(true);

        var selected_label_s = style_mod.Style{};
        selected_label_s = selected_label_s.bg(.gray(4));
        selected_label_s = selected_label_s.fg(.cyan);
        selected_label_s = selected_label_s.bold(true);
        selected_label_s = selected_label_s.inline_style(true);

        var empty_s = style_mod.Style{};
        empty_s = empty_s.fg(.gray(8));
        empty_s = empty_s.italic(true);
        empty_s = empty_s.inline_style(true);

        var palette = CommandPalette{
            .allocator = allocator,
            .commands = std.array_list.Managed(Command).init(allocator),
            .filtered = std.array_list.Managed(usize).init(allocator),
            .query = std.array_list.Managed(u8).init(allocator),
            .cursor = 0,
            .max_visible = 8,
            .width = 60,
            .prompt = "> ",
            .placeholder = "Type a command…",
            .border_chars = .rounded,
            .prompt_style = prompt_s,
            .input_style = input_s,
            .placeholder_style = placeholder_s,
            .label_style = label_s,
            .description_style = desc_s,
            .shortcut_style = shortcut_s,
            .selected_style = selected_s,
            .selected_label_style = selected_label_s,
            .empty_style = empty_s,
        };
        _ = &palette;
        return palette;
    }

    pub fn deinit(self: *CommandPalette) void {
        self.freeAllCommandStrings();
        self.commands.deinit();
        self.filtered.deinit();
        self.query.deinit();
    }

    /// Add a command. The palette clones every string in `cmd` (id, label,
    /// description, shortcut) so the caller is free to pass arena-allocated,
    /// formatted, or otherwise short-lived strings — no lifetime tracking
    /// required.
    pub fn addCommand(self: *CommandPalette, cmd: Command) !void {
        const owned = try self.cloneCommand(cmd);
        errdefer self.freeCommand(owned);
        try self.commands.append(owned);
        try self.rebuildFilter();
    }

    /// Replace all commands. Each input command's strings are cloned. Old
    /// commands are freed.
    pub fn setCommands(self: *CommandPalette, cmds: []const Command) !void {
        self.freeAllCommandStrings();
        self.commands.clearRetainingCapacity();
        for (cmds) |cmd| {
            const owned = try self.cloneCommand(cmd);
            errdefer self.freeCommand(owned);
            try self.commands.append(owned);
        }
        try self.rebuildFilter();
    }

    /// Convenience: load every enabled action from a registry, formatting its
    /// binding as the shortcut hint. Cleaner than building Command structs by
    /// hand and avoids the need to manage shortcut-string lifetimes.
    pub fn setFromRegistry(self: *CommandPalette, registry: *const ActionRegistry) !void {
        self.freeAllCommandStrings();
        self.commands.clearRetainingCapacity();
        for (registry.actions.items) |a| {
            if (!a.enabled) continue;
            const shortcut = if (a.binding) |b|
                try ActionRegistry.formatKey(self.allocator, b)
            else
                try self.allocator.dupe(u8, "");
            // shortcut is heap-owned; cloneCommand will dup again, so free
            // the temporary after.
            defer self.allocator.free(shortcut);

            const owned = try self.cloneCommand(.{
                .id = a.id,
                .label = a.label,
                .description = a.description,
                .shortcut = shortcut,
            });
            errdefer self.freeCommand(owned);
            try self.commands.append(owned);
        }
        try self.rebuildFilter();
    }

    /// Reset the typed query and cursor without touching the command list.
    pub fn clear(self: *CommandPalette) !void {
        self.query.clearRetainingCapacity();
        self.cursor = 0;
        try self.rebuildFilter();
    }

    fn cloneCommand(self: *CommandPalette, cmd: Command) !Command {
        const id = try self.allocator.dupe(u8, cmd.id);
        errdefer self.allocator.free(id);
        const label = try self.allocator.dupe(u8, cmd.label);
        errdefer self.allocator.free(label);
        const description = try self.allocator.dupe(u8, cmd.description);
        errdefer self.allocator.free(description);
        const shortcut = try self.allocator.dupe(u8, cmd.shortcut);
        return .{
            .id = id,
            .label = label,
            .description = description,
            .shortcut = shortcut,
        };
    }

    fn freeCommand(self: *CommandPalette, cmd: Command) void {
        self.allocator.free(cmd.id);
        self.allocator.free(cmd.label);
        self.allocator.free(cmd.description);
        self.allocator.free(cmd.shortcut);
    }

    fn freeAllCommandStrings(self: *CommandPalette) void {
        for (self.commands.items) |c| self.freeCommand(c);
    }

    /// Returns the currently highlighted command, if any.
    pub fn selected(self: *const CommandPalette) ?Command {
        if (self.cursor >= self.filtered.items.len) return null;
        return self.commands.items[self.filtered.items[self.cursor]];
    }

    pub fn handleKey(self: *CommandPalette, key: keys.KeyEvent) !KeyResult {
        switch (key.key) {
            .escape => return .cancelled,
            .enter => {
                if (self.selected() == null) return .consumed;
                return .accepted;
            },
            .up => {
                if (self.cursor > 0) self.cursor -= 1;
                return .consumed;
            },
            .down => {
                if (self.cursor + 1 < self.filtered.items.len) self.cursor += 1;
                return .consumed;
            },
            .backspace => {
                if (self.query.items.len > 0) {
                    _ = self.query.pop();
                    try self.rebuildFilter();
                }
                return .consumed;
            },
            .char => |c| {
                if (c < 0x20) return .ignored;
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(c, &buf) catch return .ignored;
                try self.query.appendSlice(buf[0..n]);
                try self.rebuildFilter();
                return .consumed;
            },
            else => return .ignored,
        }
    }

    fn rebuildFilter(self: *CommandPalette) !void {
        self.filtered.clearRetainingCapacity();
        if (self.query.items.len == 0) {
            for (0..self.commands.items.len) |i| try self.filtered.append(i);
        } else {
            var scored = std.array_list.Managed(fuzzy.Ranked).init(self.allocator);
            defer scored.deinit();

            for (self.commands.items, 0..) |cmd, i| {
                const s = fuzzy.scoreIgnoreCase(cmd.label, self.query.items);
                if (s > 0) try scored.append(.{ .index = i, .score = s });
            }

            std.mem.sort(fuzzy.Ranked, scored.items, {}, struct {
                fn lt(_: void, a: fuzzy.Ranked, b: fuzzy.Ranked) bool {
                    return a.score > b.score;
                }
            }.lt);

            for (scored.items) |r| try self.filtered.append(r.index);
        }

        if (self.cursor >= self.filtered.items.len) {
            self.cursor = self.filtered.items.len -| 1;
        }
    }

    pub fn view(self: *const CommandPalette, allocator: std.mem.Allocator) ![]const u8 {
        var inner: Writer.Allocating = .init(allocator);
        defer inner.deinit();
        const w = &inner.writer;

        // Input row.
        const prompt_styled = try self.prompt_style.render(allocator, self.prompt);
        defer allocator.free(prompt_styled);
        try w.writeAll(prompt_styled);

        if (self.query.items.len == 0) {
            const ph = try self.placeholder_style.render(allocator, self.placeholder);
            defer allocator.free(ph);
            try w.writeAll(ph);
        } else {
            const q = try self.input_style.render(allocator, self.query.items);
            defer allocator.free(q);
            try w.writeAll(q);
        }
        try w.writeByte('\n');

        // Results.
        if (self.filtered.items.len == 0) {
            const empty = try self.empty_style.render(allocator, "No commands match");
            defer allocator.free(empty);
            try w.writeAll(empty);
        } else {
            const visible = @min(@as(usize, self.max_visible), self.filtered.items.len);
            const start = if (self.cursor >= visible) self.cursor - visible + 1 else 0;
            const end = @min(start + visible, self.filtered.items.len);

            for (start..end) |i| {
                if (i > start) try w.writeByte('\n');
                const is_sel = i == self.cursor;
                const cmd = self.commands.items[self.filtered.items[i]];
                try self.renderRow(allocator, w, cmd, is_sel);
            }
        }

        const rendered = try inner.toOwnedSlice();
        defer allocator.free(rendered);

        var box_style = style_mod.Style{};
        box_style = box_style.borderAll(self.border_chars);
        box_style = box_style.width(self.width);
        return try box_style.render(allocator, rendered);
    }

    fn renderRow(
        self: *const CommandPalette,
        allocator: std.mem.Allocator,
        w: *Writer,
        cmd: Command,
        is_sel: bool,
    ) !void {
        const prefix = if (is_sel) "▸ " else "  ";
        if (is_sel) {
            const styled_prefix = try self.selected_label_style.render(allocator, prefix);
            defer allocator.free(styled_prefix);
            try w.writeAll(styled_prefix);

            const styled_label = try self.selected_label_style.render(allocator, cmd.label);
            defer allocator.free(styled_label);
            try w.writeAll(styled_label);
        } else {
            try w.writeAll(prefix);
            const styled_label = try self.label_style.render(allocator, cmd.label);
            defer allocator.free(styled_label);
            try w.writeAll(styled_label);
        }

        if (cmd.description.len > 0) {
            try w.writeByte(' ');
            const desc = try std.fmt.allocPrint(allocator, "— {s}", .{cmd.description});
            defer allocator.free(desc);
            const desc_style = if (is_sel) self.selected_style else self.description_style;
            const styled = try desc_style.render(allocator, desc);
            defer allocator.free(styled);
            try w.writeAll(styled);
        }

        if (cmd.shortcut.len > 0) {
            try w.writeAll("  ");
            const shortcut_style = if (is_sel) self.selected_style else self.shortcut_style;
            const styled = try shortcut_style.render(allocator, cmd.shortcut);
            defer allocator.free(styled);
            try w.writeAll(styled);
        }
    }
};

test "command palette filters by fuzzy score" {
    const allocator = std.testing.allocator;
    var p = try CommandPalette.init(allocator);
    defer p.deinit();

    try p.setCommands(&.{
        .{ .id = "open", .label = "Open File" },
        .{ .id = "save", .label = "Save File" },
        .{ .id = "close", .label = "Close Window" },
    });

    try p.query.appendSlice("of");
    try p.rebuildFilter();

    try std.testing.expect(p.filtered.items.len >= 1);
    const sel = p.selected().?;
    try std.testing.expectEqualStrings("open", sel.id);
}

test "enter accepts, escape cancels" {
    const allocator = std.testing.allocator;
    var p = try CommandPalette.init(allocator);
    defer p.deinit();
    try p.setCommands(&.{.{ .id = "a", .label = "Alpha" }});

    const accepted = try p.handleKey(.{ .key = .enter, .modifiers = .{} });
    try std.testing.expectEqual(KeyResult.accepted, accepted);

    const cancelled = try p.handleKey(.{ .key = .escape, .modifiers = .{} });
    try std.testing.expectEqual(KeyResult.cancelled, cancelled);
}

test "typing characters updates the filter" {
    const allocator = std.testing.allocator;
    var p = try CommandPalette.init(allocator);
    defer p.deinit();
    try p.setCommands(&.{
        .{ .id = "alpha", .label = "Alpha" },
        .{ .id = "beta", .label = "Beta" },
    });

    _ = try p.handleKey(.{ .key = .{ .char = 'b' }, .modifiers = .{} });
    try std.testing.expectEqual(@as(usize, 1), p.filtered.items.len);
    try std.testing.expectEqualStrings("beta", p.selected().?.id);
}
