//! Colour model tests: parsing, conversion, profile detection and contrast.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const zz = @import("zigzag");

const Color = zz.Color;

/// `Color.none` on its own resolves to the union tag, not a `Color` value.
const none: Color = .none;

fn expectRgb(c: Color, r: u8, g: u8, b: u8) !void {
    const rgb = c.toRgb() orelse return error.TestExpectedRgb;
    try testing.expectEqual(r, rgb.r);
    try testing.expectEqual(g, rgb.g);
    try testing.expectEqual(b, rgb.b);
}

test "hex parses with and without the leading hash" {
    try expectRgb(Color.hex("#FF5733"), 0xFF, 0x57, 0x33);
    try expectRgb(Color.hex("FF5733"), 0xFF, 0x57, 0x33);
    try expectRgb(Color.hex("#ff5733"), 0xFF, 0x57, 0x33);
    try expectRgb(Color.hex("#000000"), 0, 0, 0);
    try expectRgb(Color.hex("#ffffff"), 255, 255, 255);
}

test "hex rejects anything that is not six digits" {
    for ([_][]const u8{ "", "#", "#FFF", "#FF573", "#FF57333", "#GGGGGG", "zzzzzz" }) |input| {
        try testing.expect(Color.hex(input).isNone());
    }
}

test "gray maps onto the 256-colour ramp and clamps" {
    try testing.expectEqual(@as(u8, 232), Color.gray(0).ansi256);
    try testing.expectEqual(@as(u8, 255), Color.gray(23).ansi256);
    // Out of range saturates at the light end rather than wrapping.
    try testing.expectEqual(@as(u8, 255), Color.gray(24).ansi256);
    try testing.expectEqual(@as(u8, 255), Color.gray(200).ansi256);
}

test "none converts to no rgb" {
    try testing.expect(none.isNone());
    try testing.expect(none.toRgb() == null);
    try testing.expect(!Color.red.isNone());
}

test "256-colour cube and ramp convert to rgb" {
    // The first 16 entries mirror the ANSI colours.
    try testing.expect(Color.color256(0).toRgb() != null);
    // 16..231 is a 6x6x6 cube; 16 is black and 231 is white.
    try expectRgb(Color.color256(16), 0, 0, 0);
    try expectRgb(Color.color256(231), 255, 255, 255);
    // 232..255 is the grayscale ramp, which must increase monotonically.
    var prev: u8 = 0;
    var n: u8 = 232;
    while (n < 255) : (n += 1) {
        const rgb = Color.color256(n).toRgb().?;
        try testing.expect(rgb.r == rgb.g and rgb.g == rgb.b);
        try testing.expect(rgb.r > prev);
        prev = rgb.r;
    }
}

test "writeFg and writeBg emit the right sequences" {
    var buf: [64]u8 = undefined;

    var w: std.Io.Writer = .fixed(&buf);
    try Color.fromRgb(1, 2, 3).writeFg(&w);
    try testing.expectEqualStrings("\x1b[38;2;1;2;3m", w.buffered());

    w = .fixed(&buf);
    try Color.fromRgb(1, 2, 3).writeBg(&w);
    try testing.expectEqualStrings("\x1b[48;2;1;2;3m", w.buffered());

    w = .fixed(&buf);
    try Color.color256(200).writeFg(&w);
    try testing.expectEqualStrings("\x1b[38;5;200m", w.buffered());

    w = .fixed(&buf);
    try Color.red.writeFg(&w);
    try testing.expectEqualStrings("\x1b[31m", w.buffered());

    w = .fixed(&buf);
    try Color.red.writeBg(&w);
    try testing.expectEqualStrings("\x1b[41m", w.buffered());

    // `none` writes nothing at all rather than a default-colour sequence.
    w = .fixed(&buf);
    try none.writeFg(&w);
    try testing.expectEqual(@as(usize, 0), w.buffered().len);
}

test "contrast ratio matches the WCAG definition" {
    const white = Color.fromRgb(255, 255, 255);
    const black = Color.fromRgb(0, 0, 0);

    // Black on white is the maximum, 21:1.
    try testing.expectApproxEqAbs(@as(f32, 21.0), white.contrastRatio(black), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 21.0), black.contrastRatio(white), 0.01);

    // A colour against itself is 1:1.
    try testing.expectApproxEqAbs(@as(f32, 1.0), white.contrastRatio(white), 0.001);

    // A colour with no rgb has no meaningful ratio.
    try testing.expectApproxEqAbs(@as(f32, 1.0), none.contrastRatio(white), 0.001);
}

test "profile detection" {
    const P = zz.ColorProfile;

    // NO_COLOR wins over everything else.
    try testing.expectEqual(P.ascii, P.detect(.{
        .no_color = true,
        .color_term = "truecolor",
        .term = "xterm-256color",
    }));

    try testing.expectEqual(P.true_color, P.detect(.{ .color_term = "truecolor" }));
    try testing.expectEqual(P.true_color, P.detect(.{ .color_term = "24bit" }));

    // Windows Terminal speaks true colour regardless of TERM, so the rest of
    // the ladder only applies elsewhere.
    if (builtin.os.tag == .windows) {
        try testing.expectEqual(P.true_color, P.detect(.{ .term = "xterm" }));
        return;
    }

    try testing.expectEqual(P.ansi256, P.detect(.{ .term = "xterm-256color" }));
    try testing.expectEqual(P.ansi256, P.detect(.{ .term = "screen-256color" }));
    try testing.expectEqual(P.ansi, P.detect(.{ .term = "xterm" }));
    try testing.expectEqual(P.ansi, P.detect(.{}));
}

test "profile capabilities are ordered" {
    const P = zz.ColorProfile;

    try testing.expect(P.true_color.supportsTrueColor());
    try testing.expect(!P.ansi256.supportsTrueColor());

    try testing.expect(P.true_color.supports256());
    try testing.expect(P.ansi256.supports256());
    try testing.expect(!P.ansi.supports256());

    try testing.expect(P.ansi.supportsColor());
    try testing.expect(!P.ascii.supportsColor());
}

test "adaptive colour resolves by capability" {
    const adaptive = zz.AdaptiveColor{
        .true_color = Color.hex("#FF8040"),
        .color_256 = Color.color256(208),
        .ansi = Color.red,
    };

    try expectRgb(adaptive.resolve(true, true), 0xFF, 0x80, 0x40);
    try testing.expectEqual(@as(u8, 208), adaptive.resolve(false, true).ansi256);
    try testing.expect(adaptive.resolve(false, false) == .ansi);
}

test "dark background detection from COLORFGBG" {
    // "foreground;background" — a low background number means dark. Honoured
    // on every platform: a terminal that reports it is worth believing.
    try testing.expect(zz.color.hasDarkBackground("15;0"));
    try testing.expect(zz.color.hasDarkBackground("7;0"));
    try testing.expect(!zz.color.hasDarkBackground("0;15"));

    // Unset or unparseable falls back to assuming dark, which is the safer
    // default for a terminal.
    try testing.expect(zz.color.hasDarkBackground(""));
    try testing.expect(zz.color.hasDarkBackground("nonsense"));
}
