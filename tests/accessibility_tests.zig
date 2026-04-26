const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "checkContrast white on black is AAA" {
    const level = zz.a11y.checkContrast(.white, .black);
    try testing.expectEqual(zz.ContrastLevel.aaa, level);
}

test "checkContrast similar colors fail" {
    const fg = zz.Color.fromRgb(100, 100, 100);
    const bg = zz.Color.fromRgb(110, 110, 110);
    const level = zz.a11y.checkContrast(fg, bg);
    try testing.expectEqual(zz.ContrastLevel.fail, level);
}

test "meetsAA white on dark blue" {
    const fg = zz.Color.white;
    const bg = zz.Color.fromRgb(0, 0, 100);
    try testing.expect(zz.a11y.meetsAA(fg, bg));
}

test "meetsAAA white on black" {
    try testing.expect(zz.a11y.meetsAAA(.white, .black));
}

test "suggestForeground picks white for dark bg" {
    const bg = zz.Color.fromRgb(20, 20, 20);
    const suggested = zz.a11y.suggestForeground(bg);
    try testing.expectEqual(zz.Color.white, suggested);
}

test "suggestForeground picks black for light bg" {
    const bg = zz.Color.fromRgb(240, 240, 240);
    const suggested = zz.a11y.suggestForeground(bg);
    try testing.expectEqual(zz.Color.black, suggested);
}

test "Role label" {
    try testing.expectEqualStrings("button", zz.a11y.Role.button.label());
    try testing.expectEqualStrings("checkbox", zz.a11y.Role.checkbox.label());
    try testing.expectEqualStrings("", zz.a11y.Role.none.label());
}

test "AccessibleLabel format" {
    const label = zz.AccessibleLabel{
        .role = .button,
        .name = "Submit",
        .state = "focused",
    };

    const formatted = try label.format(testing.allocator);
    defer testing.allocator.free(formatted);

    try testing.expect(std.mem.indexOf(u8, formatted, "button") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Submit") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "focused") != null);
}

test "AccessibleLabel format with all fields" {
    const label = zz.AccessibleLabel{
        .role = .slider,
        .name = "Volume",
        .value = "75%",
        .state = "enabled",
        .description = "Adjust the volume level",
    };

    const formatted = try label.format(testing.allocator);
    defer testing.allocator.free(formatted);

    try testing.expect(std.mem.indexOf(u8, formatted, "slider") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Volume") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "75%") != null);
}

test "announceViaTitle generates OSC sequence" {
    const seq = try zz.a11y.announceViaTitle(testing.allocator, "File saved");
    defer testing.allocator.free(seq);

    try testing.expect(std.mem.startsWith(u8, seq, "\x1b]0;"));
    try testing.expect(std.mem.endsWith(u8, seq, "\x07"));
    try testing.expect(std.mem.indexOf(u8, seq, "File saved") != null);
}

test "bell returns BEL character" {
    try testing.expectEqualStrings("\x07", zz.a11y.bell());
}

test "progressDescription formats percentage" {
    const desc = try zz.a11y.progressDescription(testing.allocator, 75, 100);
    defer testing.allocator.free(desc);

    try testing.expectEqualStrings("75% complete", desc);
}

test "progressDescription zero max" {
    const desc = try zz.a11y.progressDescription(testing.allocator, 50, 0);
    defer testing.allocator.free(desc);

    try testing.expectEqualStrings("0% complete", desc);
}
