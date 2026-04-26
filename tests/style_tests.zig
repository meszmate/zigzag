//! Style system tests

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Color.hex parsing" {
    const color1 = zz.Color.hex("#FF5733");
    try testing.expect(color1 == .rgb);
    try testing.expectEqual(@as(u8, 255), color1.rgb.r);
    try testing.expectEqual(@as(u8, 87), color1.rgb.g);
    try testing.expectEqual(@as(u8, 51), color1.rgb.b);

    const color2 = zz.Color.hex("00FF00");
    try testing.expect(color2 == .rgb);
    try testing.expectEqual(@as(u8, 0), color2.rgb.r);
    try testing.expectEqual(@as(u8, 255), color2.rgb.g);
    try testing.expectEqual(@as(u8, 0), color2.rgb.b);

    const invalid = zz.Color.hex("invalid");
    try testing.expect(invalid == .none);
}

test "Color basic colors" {
    const red = zz.Color.red;
    try testing.expect(red == .ansi);

    const cyan = zz.Color.cyan;
    try testing.expect(cyan == .ansi);

    const rgb = zz.Color.fromRgb(100, 150, 200);
    try testing.expect(rgb == .rgb);
    try testing.expectEqual(@as(u8, 100), rgb.rgb.r);
    try testing.expectEqual(@as(u8, 150), rgb.rgb.g);
    try testing.expectEqual(@as(u8, 200), rgb.rgb.b);
}

test "Style builder pattern" {
    var style = zz.Style{};
    style = style.bold(true);
    style = style.fg(.red);
    style = style.bg(.black);
    style = style.paddingAll(1);
    style = style.marginAll(2);

    try testing.expect(style.bold_attr orelse false);
    try testing.expect(style.foreground == .ansi);
    try testing.expect(style.background == .ansi);
    try testing.expectEqual(@as(u16, 1), style.padding_val.top);
    try testing.expectEqual(@as(u16, 2), style.margin_val.top);
}

test "Style render" {
    const allocator = testing.allocator;

    var style = zz.Style{};
    style = style.bold(true);
    style = style.fg(.cyan);

    const result = try style.render(allocator, "Hello");
    defer allocator.free(result);

    // Result should contain ANSI codes and the text
    try testing.expect(result.len > 5); // "Hello" + ANSI codes
    try testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
    try testing.expect(!std.mem.endsWith(u8, result, "\n"));
}

test "Style render keeps internal newlines but no trailing newline" {
    const allocator = testing.allocator;

    var style = zz.Style{};
    style = style.fg(.cyan);

    const result = try style.render(allocator, "A\nB");
    defer allocator.free(result);

    try testing.expect(std.mem.indexOfScalar(u8, result, '\n') != null);
    try testing.expect(!std.mem.endsWith(u8, result, "\n"));
}

test "Border styles exist" {
    _ = zz.border.BorderChars.normal;
    _ = zz.border.BorderChars.rounded;
    _ = zz.border.BorderChars.double;
    _ = zz.border.BorderChars.thick;
    _ = zz.border.BorderChars.ascii;
    _ = zz.border.BorderChars.none;
}

test "Style with border" {
    var style = zz.Style{};
    style = style.borderAll(.rounded);
    style = style.borderForeground(.cyan);

    try testing.expect(style.border_sides.top);
    try testing.expect(style.border_sides.bottom);
    try testing.expect(style.border_sides.left);
    try testing.expect(style.border_sides.right);
}
