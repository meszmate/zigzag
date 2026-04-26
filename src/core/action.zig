//! Action / command registry — central source of truth for app actions.
//!
//! Inspired by Textual's action system. An `Action` couples a stable string
//! ID, a human label, an optional key binding, and an optional category to a
//! single registry. The same registry feeds:
//!
//!   * the keybinding matcher (key event → action id)
//!   * the auto-footer (one-line key hint bar)
//!   * the command palette (filterable list of all actions)
//!   * the help screen
//!
//! The user's `update` function looks up the matching action by id, eg.:
//!
//!     if (registry.matchKey(key_event)) |action| {
//!         return self.dispatch(action.id);
//!     }
//!
//! and a `dispatch` switch on `action.id` calls the right handler. Optional
//! `handler` callbacks are also supported for fire-and-forget actions.

const std = @import("std");
const Writer = std.Io.Writer;
const keys = @import("../input/keys.zig");
const KeyEvent = keys.KeyEvent;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");
const fuzzy = @import("fuzzy.zig");

/// Optional callback shape. Receives the user-supplied context pointer the
/// registry was created with — typically the app model.
pub const Handler = *const fn (user_ctx: ?*anyopaque) void;

pub const Action = struct {
    /// Stable string identifier, eg. "app.quit", "file.save".
    id: []const u8,
    /// User-facing label, eg. "Quit", "Save File".
    label: []const u8,
    /// Longer description for palette / help.
    description: []const u8 = "",
    /// Optional category for grouping in help / palette, eg. "File", "Edit".
    category: []const u8 = "",
    /// Optional primary key binding. Other bindings can be added via
    /// `addBinding` if you want chord-style or aliases.
    binding: ?KeyEvent = null,
    /// Whether this action shows up in match/footer/palette.
    enabled: bool = true,
    /// Whether this action is shown in the auto-footer hint bar.
    show_in_footer: bool = false,
    /// Optional fire-and-forget callback. The registry calls this when the
    /// matching key fires, in addition to returning the action so the user's
    /// update function can switch on the id.
    handler: ?Handler = null,
};

pub const ActionRegistry = struct {
    allocator: std.mem.Allocator,
    actions: std.array_list.Managed(Action),
    /// Optional aliases: extra key events that map to the same action.
    aliases: std.array_list.Managed(Alias),
    /// Pointer passed to `Handler` callbacks. Typically the app model.
    user_ctx: ?*anyopaque,

    pub const Alias = struct {
        id: []const u8,
        binding: KeyEvent,
    };

    pub fn init(allocator: std.mem.Allocator) ActionRegistry {
        return .{
            .allocator = allocator,
            .actions = std.array_list.Managed(Action).init(allocator),
            .aliases = std.array_list.Managed(Alias).init(allocator),
            .user_ctx = null,
        };
    }

    pub fn deinit(self: *ActionRegistry) void {
        self.actions.deinit();
        self.aliases.deinit();
    }

    pub fn setUserContext(self: *ActionRegistry, ctx: *anyopaque) void {
        self.user_ctx = ctx;
    }

    pub fn register(self: *ActionRegistry, action: Action) !void {
        // Detect duplicate ids early — registry is a "single source of truth".
        for (self.actions.items) |existing| {
            if (std.mem.eql(u8, existing.id, action.id)) return error.DuplicateActionId;
        }
        try self.actions.append(action);
    }

    /// Replace an action's binding by id. Returns true if the action existed.
    pub fn rebind(self: *ActionRegistry, id: []const u8, binding: ?KeyEvent) bool {
        for (self.actions.items) |*a| {
            if (std.mem.eql(u8, a.id, id)) {
                a.binding = binding;
                return true;
            }
        }
        return false;
    }

    pub fn setEnabled(self: *ActionRegistry, id: []const u8, enabled: bool) bool {
        for (self.actions.items) |*a| {
            if (std.mem.eql(u8, a.id, id)) {
                a.enabled = enabled;
                return true;
            }
        }
        return false;
    }

    /// Add an additional key alias for an existing action.
    pub fn addAlias(self: *ActionRegistry, id: []const u8, binding: KeyEvent) !void {
        // Validate the action exists.
        for (self.actions.items) |a| {
            if (std.mem.eql(u8, a.id, id)) {
                try self.aliases.append(.{ .id = id, .binding = binding });
                return;
            }
        }
        return error.UnknownAction;
    }

    pub fn get(self: *const ActionRegistry, id: []const u8) ?*const Action {
        for (self.actions.items) |*a| {
            if (std.mem.eql(u8, a.id, id)) return a;
        }
        return null;
    }

    /// Look up the action matching `event`. Returns null when no enabled
    /// action is bound. Calls the action's handler if present.
    pub fn matchKey(self: *const ActionRegistry, event: KeyEvent) ?*const Action {
        for (self.actions.items) |*a| {
            if (!a.enabled) continue;
            if (a.binding) |b| {
                if (b.eql(event)) {
                    if (a.handler) |h| h(self.user_ctx);
                    return a;
                }
            }
        }
        for (self.aliases.items) |alias| {
            if (alias.binding.eql(event)) {
                const a = self.get(alias.id) orelse continue;
                if (!a.enabled) continue;
                if (a.handler) |h| h(self.user_ctx);
                return a;
            }
        }
        return null;
    }

    /// Invoke the action's handler explicitly (eg. selected from the palette).
    /// Returns true if the action exists and is enabled.
    pub fn invoke(self: *const ActionRegistry, id: []const u8) bool {
        const a = self.get(id) orelse return false;
        if (!a.enabled) return false;
        if (a.handler) |h| h(self.user_ctx);
        return true;
    }

    /// Iterate enabled actions matching a fuzzy query. Caller owns the
    /// returned slice. Useful for feeding a CommandPalette.
    pub fn filter(self: *const ActionRegistry, allocator: std.mem.Allocator, query: []const u8) ![]const *const Action {
        var out = std.array_list.Managed(*const Action).init(allocator);
        errdefer out.deinit();
        if (query.len == 0) {
            for (self.actions.items) |*a| {
                if (a.enabled) try out.append(a);
            }
            return out.toOwnedSlice();
        }

        const Scored = struct { ptr: *const Action, score: i32 };
        var scored = std.array_list.Managed(Scored).init(allocator);
        defer scored.deinit();

        for (self.actions.items) |*a| {
            if (!a.enabled) continue;
            const s = fuzzy.scoreIgnoreCase(a.label, query);
            if (s > 0) try scored.append(.{ .ptr = a, .score = s });
        }

        std.mem.sort(Scored, scored.items, {}, struct {
            fn lt(_: void, l: Scored, r: Scored) bool {
                return l.score > r.score;
            }
        }.lt);

        for (scored.items) |s| try out.append(s.ptr);
        return out.toOwnedSlice();
    }

    /// Format a key event for display: "ctrl+s", "esc", "enter", etc.
    pub fn formatKey(allocator: std.mem.Allocator, event: KeyEvent) ![]u8 {
        var out: Writer.Allocating = .init(allocator);
        const w = &out.writer;
        if (event.modifiers.ctrl) try w.writeAll("ctrl+");
        if (event.modifiers.alt) try w.writeAll("alt+");
        if (event.modifiers.shift) try w.writeAll("shift+");
        if (event.modifiers.super) try w.writeAll("super+");
        switch (event.key) {
            .char => |c| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &buf) catch 0;
                try w.writeAll(buf[0..len]);
            },
            .escape => try w.writeAll("esc"),
            .enter => try w.writeAll("⏎"),
            .space => try w.writeAll("space"),
            .tab => try w.writeAll("⇥"),
            .left => try w.writeAll("←"),
            .right => try w.writeAll("→"),
            .up => try w.writeAll("↑"),
            .down => try w.writeAll("↓"),
            else => try w.writeAll(event.key.name()),
        }
        return out.toOwnedSlice();
    }
};

/// Auto-rendered single-line footer that shows the bindings for actions
/// flagged with `show_in_footer = true`. Useful as a persistent key hint
/// bar at the bottom of the screen, kept in sync with the registry.
pub const Footer = struct {
    registry: *const ActionRegistry,
    width: u16 = 80,
    separator: []const u8 = "  ",
    key_style: style_mod.Style,
    label_style: style_mod.Style,
    base_style: style_mod.Style,

    pub fn init(registry: *const ActionRegistry) Footer {
        var key_s = style_mod.Style{};
        key_s = key_s.fg(.cyan);
        key_s = key_s.bold(true);
        key_s = key_s.inline_style(true);
        var label_s = style_mod.Style{};
        label_s = label_s.fg(.gray(12));
        label_s = label_s.inline_style(true);
        var base = style_mod.Style{};
        base = base.bg(.gray(3));
        base = base.inline_style(true);
        return .{
            .registry = registry,
            .key_style = key_s,
            .label_style = label_s,
            .base_style = base,
        };
    }

    pub fn setWidth(self: *Footer, w: u16) void {
        self.width = w;
    }

    pub fn view(self: *const Footer, allocator: std.mem.Allocator) ![]const u8 {
        var inner: Writer.Allocating = .init(allocator);
        defer inner.deinit();
        const w = &inner.writer;

        var first = true;
        for (self.registry.actions.items) |a| {
            if (!a.enabled or !a.show_in_footer) continue;
            const binding = a.binding orelse continue;
            if (!first) try w.writeAll(self.separator);
            first = false;
            const key_str = try ActionRegistry.formatKey(allocator, binding);
            defer allocator.free(key_str);
            const styled_key = try self.key_style.render(allocator, key_str);
            defer allocator.free(styled_key);
            try w.writeAll(styled_key);
            try w.writeByte(' ');
            const styled_label = try self.label_style.render(allocator, a.label);
            defer allocator.free(styled_label);
            try w.writeAll(styled_label);
        }

        // Pad / truncate to width and apply base background.
        const text = try inner.toOwnedSlice();
        defer allocator.free(text);
        const text_w = measure.width(text);

        var out: Writer.Allocating = .init(allocator);
        const ow = &out.writer;
        try ow.writeAll(text);
        if (text_w < self.width) {
            const pad = self.width - text_w;
            const spaces = try allocator.alloc(u8, pad);
            defer allocator.free(spaces);
            @memset(spaces, ' ');
            const styled_pad = try self.base_style.render(allocator, spaces);
            defer allocator.free(styled_pad);
            try ow.writeAll(styled_pad);
        }
        return out.toOwnedSlice();
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "register and lookup by id" {
    var reg = ActionRegistry.init(testing.allocator);
    defer reg.deinit();

    try reg.register(.{ .id = "app.quit", .label = "Quit" });
    const a = reg.get("app.quit").?;
    try testing.expectEqualStrings("Quit", a.label);
}

test "duplicate id rejected" {
    var reg = ActionRegistry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{ .id = "x", .label = "X" });
    const r = reg.register(.{ .id = "x", .label = "X again" });
    try testing.expectError(error.DuplicateActionId, r);
}

test "matchKey routes by binding" {
    var reg = ActionRegistry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{
        .id = "file.save",
        .label = "Save",
        .binding = .{ .key = .{ .char = 's' }, .modifiers = .{ .ctrl = true } },
    });
    const event: KeyEvent = .{ .key = .{ .char = 's' }, .modifiers = .{ .ctrl = true } };
    const a = reg.matchKey(event).?;
    try testing.expectEqualStrings("file.save", a.id);
}

test "matchKey returns null for unbound" {
    var reg = ActionRegistry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{ .id = "noop", .label = "Noop" });
    const ev: KeyEvent = .{ .key = .{ .char = 'q' } };
    try testing.expectEqual(@as(?*const Action, null), reg.matchKey(ev));
}

test "alias matches same action" {
    var reg = ActionRegistry.init(testing.allocator);
    defer reg.deinit();
    try reg.register(.{
        .id = "view.toggle",
        .label = "Toggle",
        .binding = .{ .key = .{ .char = 't' } },
    });
    try reg.addAlias("view.toggle", .{ .key = .f5 });
    const a = reg.matchKey(.{ .key = .f5 }).?;
    try testing.expectEqualStrings("view.toggle", a.id);
}

test "filter ranks by fuzzy match" {
    const allocator = testing.allocator;
    var reg = ActionRegistry.init(allocator);
    defer reg.deinit();
    try reg.register(.{ .id = "open", .label = "Open File" });
    try reg.register(.{ .id = "save", .label = "Save File" });
    try reg.register(.{ .id = "close", .label = "Close Window" });

    const matches = try reg.filter(allocator, "of");
    defer allocator.free(matches);
    try testing.expect(matches.len >= 1);
    try testing.expectEqualStrings("open", matches[0].id);
}

test "footer shows only flagged actions" {
    const allocator = testing.allocator;
    var reg = ActionRegistry.init(allocator);
    defer reg.deinit();
    try reg.register(.{
        .id = "app.quit",
        .label = "Quit",
        .binding = .{ .key = .{ .char = 'q' } },
        .show_in_footer = true,
    });
    try reg.register(.{
        .id = "internal",
        .label = "Hidden",
        .binding = .{ .key = .{ .char = 'h' } },
        .show_in_footer = false,
    });

    const footer = Footer.init(&reg);
    const out = try footer.view(allocator);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "Quit") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Hidden") == null);
}

test "formatKey produces readable strings" {
    const allocator = testing.allocator;
    const ctrl_s = try ActionRegistry.formatKey(allocator, .{
        .key = .{ .char = 's' },
        .modifiers = .{ .ctrl = true },
    });
    defer allocator.free(ctrl_s);
    try testing.expectEqualStrings("ctrl+s", ctrl_s);

    const escape = try ActionRegistry.formatKey(allocator, .{ .key = .escape });
    defer allocator.free(escape);
    try testing.expectEqualStrings("esc", escape);
}
