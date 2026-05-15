const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Palette default_dark has valid colors" {
    const p = zz.Palette.default_dark;
    // Check that colors are set (non-default)
    try testing.expect(p.primary.toRgb() != null);
    try testing.expect(p.foreground.toRgb() != null);
    try testing.expect(p.background.toRgb() != null);
}

test "Palette all presets are valid" {
    const palettes = [_]zz.Palette{
        zz.Palette.default_dark,
        zz.Palette.default_light,
        zz.Palette.catppuccin_mocha,
        zz.Palette.catppuccin_latte,
        zz.Palette.dracula,
        zz.Palette.nord,
        zz.Palette.high_contrast,
        zz.Palette.tokyo_night,
        zz.Palette.gruvbox_dark,
        zz.Palette.solarized_dark,
        zz.Palette.solarized_light,
    };

    for (palettes) |p| {
        try testing.expect(p.primary.toRgb() != null);
        try testing.expect(p.danger.toRgb() != null);
    }
}

test "Theme fromPalette derives component themes" {
    const t = zz.Theme.fromPalette(.dracula);

    // Text theme inherits from palette
    const p = zz.Palette.dracula;
    try testing.expectEqual(p.foreground, t.text.text_fg);
    try testing.expectEqual(p.subtle, t.text.placeholder_fg);
    try testing.expectEqual(p.primary, t.text.prompt_fg);
    try testing.expectEqual(p.border_color, t.text.border_fg);
    try testing.expectEqual(p.border_focus, t.text.border_focus_fg);

    // List theme
    try testing.expectEqual(p.foreground, t.list.item_fg);
    try testing.expectEqual(p.primary, t.list.selected_fg);

    // Notification theme
    try testing.expectEqual(p.info, t.notification.info_fg);
    try testing.expectEqual(p.success, t.notification.success_fg);
    try testing.expectEqual(p.danger, t.notification.err_fg);
}

test "AdaptivePalette resolves correctly" {
    const adaptive = zz.AdaptivePalette.catppuccin;

    const dark = adaptive.resolve(true);
    try testing.expectEqual(zz.Palette.catppuccin_mocha.primary, dark.primary);

    const light = adaptive.resolve(false);
    try testing.expectEqual(zz.Palette.catppuccin_latte.primary, light.primary);
}

test "Theme styleWith creates inline style" {
    const s = zz.Theme.styleWith(.red);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const rendered = try s.render(arena.allocator(), "hello");
    try testing.expect(rendered.len > 0);
}

test "Theme boldStyleWith creates bold inline style" {
    const s = zz.Theme.boldStyleWith(.green);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const rendered = try s.render(arena.allocator(), "bold");
    try testing.expect(rendered.len > 0);
}

test "ThemeManager init and cycle" {
    var tm = zz.ThemeManager.init(true);

    // Should start at index 0
    try testing.expectEqualStrings("Default Dark", tm.currentName());

    tm.nextBuiltin();
    try testing.expectEqualStrings("Default Light", tm.currentName());

    tm.prevBuiltin();
    try testing.expectEqualStrings("Default Dark", tm.currentName());

    // Wrap around backwards
    tm.prevBuiltin();
    try testing.expectEqualStrings("High Contrast", tm.currentName());
}

test "ThemeManager setBuiltinByIndex" {
    var tm = zz.ThemeManager.init(true);

    tm.setBuiltinByIndex(4); // Dracula
    try testing.expectEqualStrings("Dracula", tm.currentName());
    try testing.expectEqual(zz.Palette.dracula.primary, tm.current.palette.primary);
}

test "ThemeManager setPalette with custom palette" {
    var tm = zz.ThemeManager.init(true);

    const custom = zz.Palette{
        .primary = .red,
        .secondary = .blue,
        .accent = .green,
        .background = .black,
        .surface = .black,
        .overlay = .black,
        .foreground = .white,
        .muted = .gray(14),
        .subtle = .gray(10),
        .success = .green,
        .warning = .yellow,
        .danger = .red,
        .info = .cyan,
        .border_color = .gray(12),
        .border_focus = .red,
        .highlight = .gray(5),
        .highlight_text = .white,
    };

    tm.setPalette(custom);
    try testing.expectEqual(zz.Color.red, tm.current.palette.primary);
}

test "ThemeManager builtinCount" {
    try testing.expectEqual(@as(usize, 11), zz.ThemeManager.builtinCount());
}

test "Palette builtins list matches presets" {
    const builtins = zz.Palette.builtins;
    try testing.expect(builtins.len >= 11);

    // Spot check a few
    try testing.expectEqual(zz.Palette.dracula.primary, builtins[4].palette.primary);
    try testing.expectEqualStrings("Tokyo Night", builtins[6].name);
}

test "AdaptivePalette solarized resolves" {
    const dark = zz.AdaptivePalette.solarized.resolve(true);
    try testing.expectEqual(zz.Palette.solarized_dark.primary, dark.primary);

    const light = zz.AdaptivePalette.solarized.resolve(false);
    try testing.expectEqual(zz.Palette.solarized_light.primary, light.primary);
}

test "Theme can be overridden per-component" {
    var t = zz.Theme.fromPalette(zz.Palette.nord);

    // Override list cursor color
    t.list.cursor_fg = zz.Color.red;
    try testing.expectEqual(zz.Color.red, t.list.cursor_fg);

    // Other fields unchanged
    try testing.expectEqual(zz.Palette.nord.foreground, t.list.item_fg);
}
