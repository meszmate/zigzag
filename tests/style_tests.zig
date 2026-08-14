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

// ---------------------------------------------------------------------------
// Overflow and compression around escape sequences
// ---------------------------------------------------------------------------

const hyperlink = "\x1b]8;;https://example.com\x07";
const link_end = "\x1b]8;;\x07";
const kitty_image = "\x1b_Gf=100,a=T;iVBORw0KGgoAAAANSUhEUg\x1b\\";

test "overflow.hidden measures a hyperlink as zero width" {
    const allocator = testing.allocator;
    const input = hyperlink ++ "Hello, World!" ++ link_end;

    const result = try zz.applyOverflow(allocator, input, 5, .hidden);
    defer allocator.free(result);

    // The link opener is carried through; only five columns of text survive.
    try testing.expectEqualStrings(hyperlink ++ "Hello", result);
}

test "overflow.hidden steps over an image sequence" {
    const allocator = testing.allocator;
    const input = kitty_image ++ "Hello, World!";

    const result = try zz.applyOverflow(allocator, input, 5, .hidden);
    defer allocator.free(result);

    try testing.expectEqualStrings(kitty_image ++ "Hello", result);
}

test "overflow.hidden handles CSI sequences ending in a non-letter" {
    const allocator = testing.allocator;
    // `CSI ? 2 5 h` ends in 'h'; a scan for the first A-Za-z used to run past
    // it and eat the 'H' of the text.
    const input = "\x1b[?25hHello, World!";

    const result = try zz.applyOverflow(allocator, input, 5, .hidden);
    defer allocator.free(result);

    try testing.expectEqualStrings("\x1b[?25hHello", result);
}

test "overflow.ellipsis measures a hyperlink as zero width" {
    const allocator = testing.allocator;
    const input = hyperlink ++ "Hello, World!" ++ link_end;

    const result = try zz.applyOverflow(allocator, input, 6, .ellipsis);
    defer allocator.free(result);

    try testing.expectEqualStrings(hyperlink ++ "Hello\xe2\x80\xa6", result);
}

test "overflow.char_wrap measures a hyperlink as zero width" {
    const allocator = testing.allocator;
    const input = hyperlink ++ "abcdef";

    const result = try zz.applyOverflow(allocator, input, 3, .char_wrap);
    defer allocator.free(result);

    try testing.expectEqualStrings(hyperlink ++ "abc\ndef", result);
}

test "overflow.word_wrap measures a hyperlink as zero width" {
    const allocator = testing.allocator;
    const input = hyperlink ++ "alpha beta";

    const result = try zz.applyOverflow(allocator, input, 5, .word_wrap);
    defer allocator.free(result);

    try testing.expectEqualStrings(hyperlink ++ "alpha\nbeta", result);
}

test "overflow uses shared width tables for wide characters" {
    const allocator = testing.allocator;

    // Two double-width characters fill four columns exactly.
    const fits = try zz.applyOverflow(allocator, "日本語", 4, .hidden);
    defer allocator.free(fits);
    try testing.expectEqualStrings("日本", fits);

    // A combining mark adds no width, so all four base characters survive.
    const combining = try zz.applyOverflow(allocator, "a\u{0301}bcd", 4, .hidden);
    defer allocator.free(combining);
    try testing.expectEqualStrings("a\u{0301}bcd", combining);
}

test "compressAnsi leaves string sequence payloads alone" {
    const allocator = testing.allocator;

    // A tmux passthrough carries SGR bytes inside its payload by design.
    const input = "\x1bPtmux;\x1b\x1b[0m\x1b\\text";
    const result = try zz.compressAnsi(allocator, input);
    defer allocator.free(result);

    try testing.expectEqualStrings(input, result);
}

test "compressAnsi still collapses repeated resets" {
    const allocator = testing.allocator;

    const result = try zz.compressAnsi(allocator, "a\x1b[0m\x1b[0m\x1b[0mb");
    defer allocator.free(result);

    try testing.expectEqualStrings("a\x1b[0mb", result);
}

test "compressAnsi keeps CSI sequences ending in a non-letter intact" {
    const allocator = testing.allocator;

    const input = "\x1b[3~\x1b[0m\x1b[0mtail";
    const result = try zz.compressAnsi(allocator, input);
    defer allocator.free(result);

    try testing.expectEqualStrings("\x1b[3~\x1b[0mtail", result);
}
