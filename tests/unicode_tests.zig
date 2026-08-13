const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "charWidth: ASCII" {
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth('A'));
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth('z'));
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth(' '));
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth('0'));
}

test "charWidth: CJK ideographs are wide" {
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x4E2D)); // 中
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x6587)); // 文
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x5B57)); // 字
}

test "charWidth: emoji are wide" {
    zz.unicode.setWidthStrategy(.unicode);
    defer zz.unicode.setWidthStrategy(.legacy_wcwidth);
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x1F600)); // grinning face
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x1F680)); // rocket
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0x2615)); // hot beverage
}

test "charWidth: combining marks are zero-width" {
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0x0300)); // combining grave
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0x0301)); // combining acute
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0x20D0)); // combining symbol
}

test "charWidth: fullwidth forms are wide" {
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0xFF01)); // fullwidth !
    try testing.expectEqual(@as(usize, 2), zz.unicode.charWidth(0xFF21)); // fullwidth A
}

test "charWidth: halfwidth Katakana is normal" {
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth(0xFF61)); // halfwidth Katakana
    try testing.expectEqual(@as(usize, 1), zz.unicode.charWidth(0xFF9F));
}

test "charWidth: zero-width format chars" {
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0x200B)); // ZWSP
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0x200D)); // ZWJ
    try testing.expectEqual(@as(usize, 0), zz.unicode.charWidth(0xFEFF)); // BOM
}

test "strWidth: mixed content" {
    // "中文" = 2 wide chars = 4 columns
    try testing.expectEqual(@as(usize, 4), zz.unicode.strWidth("中文"));
    // "hello" = 5 ASCII chars
    try testing.expectEqual(@as(usize, 5), zz.unicode.strWidth("hello"));
    // "hi中文" = 2 + 4 = 6
    try testing.expectEqual(@as(usize, 6), zz.unicode.strWidth("hi中文"));
}

test "strWidth: combining characters" {
    // e + combining acute accent = 1 display column
    try testing.expectEqual(@as(usize, 1), zz.unicode.strWidth("e\xcc\x81"));
    // a + combining ring above = 1
    try testing.expectEqual(@as(usize, 1), zz.unicode.strWidth("a\xcc\x8a"));
}

test "measure.width with CJK" {
    try testing.expectEqual(@as(usize, 4), zz.measure.width("中文"));
}

test "measure.width with combining" {
    try testing.expectEqual(@as(usize, 1), zz.measure.width("e\xcc\x81"));
}

test "measure.width with ANSI + CJK" {
    try testing.expectEqual(@as(usize, 4), zz.measure.width("\x1b[31m中文\x1b[0m"));
}

test "measure.truncate with wide chars" {
    const alloc = testing.allocator;

    // "中文字" = 6 columns. Truncate to 5 should fit within 5
    const result = try zz.measure.truncate(alloc, "中文字", 5);
    defer alloc.free(result);

    // The truncated result width should be <= 5
    const w = zz.measure.width(result);
    try testing.expect(w <= 5);
}

test "measure.truncate ASCII unchanged" {
    const alloc = testing.allocator;
    const result = try zz.measure.truncate(alloc, "hello", 10);
    defer alloc.free(result);
    try testing.expectEqualStrings("hello", result);
}
