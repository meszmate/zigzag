//! Accessibility utilities for ZigZag TUI applications.
//! Provides WCAG contrast checking, screen reader announcements,
//! and semantic role annotations for terminal UIs.

const std = @import("std");
const Writer = std.Io.Writer;
const Color = @import("style/color.zig").Color;

/// WCAG 2.1 contrast ratio levels.
pub const ContrastLevel = enum {
    /// Fails WCAG minimum requirements (< 3:1)
    fail,
    /// Passes large text / UI component requirement (>= 3:1)
    aa_large,
    /// Passes normal text requirement (>= 4.5:1)
    aa,
    /// Passes enhanced contrast for normal text (>= 7:1)
    aaa,
};

/// Check the WCAG compliance level for a foreground/background color pair.
pub fn checkContrast(fg: Color, bg: Color) ContrastLevel {
    const ratio = fg.contrastRatio(bg);
    if (ratio >= 7.0) return .aaa;
    if (ratio >= 4.5) return .aa;
    if (ratio >= 3.0) return .aa_large;
    return .fail;
}

/// Returns true if the color pair meets WCAG AA for normal text (4.5:1).
pub fn meetsAA(fg: Color, bg: Color) bool {
    return fg.contrastRatio(bg) >= 4.5;
}

/// Returns true if the color pair meets WCAG AAA for normal text (7:1).
pub fn meetsAAA(fg: Color, bg: Color) bool {
    return fg.contrastRatio(bg) >= 7.0;
}

/// Suggest a foreground color (white or black) that has better contrast
/// against the given background.
pub fn suggestForeground(bg: Color) Color {
    const white = Color.white;
    const black = Color.black;
    const white_ratio = white.contrastRatio(bg);
    const black_ratio = black.contrastRatio(bg);
    return if (white_ratio >= black_ratio) white else black;
}

/// Semantic roles for UI components, useful for screen reader hints
/// and accessible descriptions.
pub const Role = enum {
    button,
    checkbox,
    radio,
    textbox,
    listbox,
    option,
    menu,
    menuitem,
    dialog,
    alert,
    status,
    progressbar,
    slider,
    tab,
    tabpanel,
    tree,
    treeitem,
    heading,
    separator,
    tooltip,
    form,
    list,
    listitem,
    link,
    img,
    none,

    /// Get a human-readable label for this role.
    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .button => "button",
            .checkbox => "checkbox",
            .radio => "radio button",
            .textbox => "text field",
            .listbox => "list box",
            .option => "option",
            .menu => "menu",
            .menuitem => "menu item",
            .dialog => "dialog",
            .alert => "alert",
            .status => "status",
            .progressbar => "progress bar",
            .slider => "slider",
            .tab => "tab",
            .tabpanel => "tab panel",
            .tree => "tree",
            .treeitem => "tree item",
            .heading => "heading",
            .separator => "separator",
            .tooltip => "tooltip",
            .form => "form",
            .list => "list",
            .listitem => "list item",
            .link => "link",
            .img => "image",
            .none => "",
        };
    }
};

/// An accessible label attached to a UI element.
pub const AccessibleLabel = struct {
    role: Role = .none,
    name: []const u8 = "",
    description: []const u8 = "",
    value: []const u8 = "",
    state: []const u8 = "",

    /// Format an accessible description string for screen readers.
    pub fn format(self: AccessibleLabel, allocator: std.mem.Allocator) ![]const u8 {
        var parts: Writer.Allocating = .init(allocator);
        const w = &parts.writer;

        if (self.role != .none) {
            try w.writeAll(self.role.label());
        }

        if (self.name.len > 0) {
            if (parts.writer.buffered().len > 0) try w.writeAll(": ");
            try w.writeAll(self.name);
        }

        if (self.value.len > 0) {
            if (parts.writer.buffered().len > 0) try w.writeAll(", ");
            try w.writeAll(self.value);
        }

        if (self.state.len > 0) {
            if (parts.writer.buffered().len > 0) try w.writeAll(", ");
            try w.writeAll(self.state);
        }

        if (self.description.len > 0) {
            if (parts.writer.buffered().len > 0) try w.writeAll(" - ");
            try w.writeAll(self.description);
        }

        return parts.toOwnedSlice();
    }
};

/// Generate a terminal announcement using the window title (OSC 0).
/// Some screen readers pick up title changes as announcements.
pub fn announceViaTitle(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "\x1b]0;{s}\x07", .{message});
}

/// Generate a terminal bell (BEL) to alert the user audibly.
pub fn bell() []const u8 {
    return "\x07";
}

/// Format a progress value as an accessible string.
pub fn progressDescription(allocator: std.mem.Allocator, value: f64, max: f64) ![]const u8 {
    const pct = if (max > 0) (value / max) * 100.0 else 0.0;
    return std.fmt.allocPrint(allocator, "{d:.0}% complete", .{pct});
}
