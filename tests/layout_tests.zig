//! Layout system tests

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "measure.width - simple string" {
    try testing.expectEqual(@as(usize, 5), zz.width("hello"));
    try testing.expectEqual(@as(usize, 0), zz.width(""));
    try testing.expectEqual(@as(usize, 3), zz.width("abc"));
}

test "measure.width - with newlines" {
    try testing.expectEqual(@as(usize, 5), zz.width("hello\nworld"));
    try testing.expectEqual(@as(usize, 5), zz.width("hello\nhi"));
    try testing.expectEqual(@as(usize, 3), zz.width("ab\nabc"));
}

test "measure.width - ANSI sequences excluded" {
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b[31mhello\x1b[0m"));
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b[1;32mhello\x1b[0m"));
}

test "measure.width - string sequences carry no width" {
    // OSC, terminated by BEL and by ST.
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b]8;;https://example.com\x07hello"));
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b]8;;https://example.com\x1b\\hello"));

    // A whole hyperlink, opened and closed.
    try testing.expectEqual(
        @as(usize, 5),
        zz.width("\x1b]8;;https://example.com\x07hello\x1b]8;;\x07"),
    );

    // DCS — how tmux passthrough and terminal replies are wrapped.
    try testing.expectEqual(@as(usize, 5), zz.width("\x1bPtmux;\x1b\\hello"));

    // APC — the Kitty graphics protocol. Its payload is base64, which used to
    // be measured character by character and blow the line width apart.
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b_Gf=100,a=T;iVBORw0K\x1b\\hello"));

    // PM and SOS.
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b^private\x1b\\hello"));
    try testing.expectEqual(@as(usize, 5), zz.width("\x1bXstring\x1b\\hello"));
}

test "measure.maxLineWidth - string sequences carry no width" {
    const framed = "\x1b_Gf=100,a=T;iVBORw0KGgoAAAANSUhEUg\x1b\\short\nlonger line";
    try testing.expectEqual(@as(usize, 11), zz.measure.maxLineWidth(framed));
}

test "measure.height - simple" {
    try testing.expectEqual(@as(usize, 1), zz.height("hello"));
    try testing.expectEqual(@as(usize, 0), zz.height(""));
    try testing.expectEqual(@as(usize, 2), zz.height("hello\nworld"));
    try testing.expectEqual(@as(usize, 3), zz.height("a\nb\nc"));
}

test "measure.size" {
    const s = zz.layout.measure.size("hello\nworld!");
    try testing.expectEqual(@as(usize, 6), s.width);
    try testing.expectEqual(@as(usize, 2), s.height);
}

test "measure.padRight" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.padRight(allocator, "hi", 5);
    defer allocator.free(result);
    try testing.expectEqualStrings("hi   ", result);
}

test "measure.padLeft" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.padLeft(allocator, "hi", 5);
    defer allocator.free(result);
    try testing.expectEqualStrings("   hi", result);
}

test "measure.center" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.center(allocator, "hi", 6);
    defer allocator.free(result);
    try testing.expectEqualStrings("  hi  ", result);
}

test "measure.truncate" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.truncate(allocator, "hello world", 8);
    defer allocator.free(result);
    try testing.expectEqualStrings("hello...", result);
}

test "measure.truncate - no truncation needed" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.truncate(allocator, "hi", 10);
    defer allocator.free(result);
    try testing.expectEqualStrings("hi", result);
}

test "join.horizontal - basic" {
    const allocator = testing.allocator;

    const result = try zz.join.horizontal(allocator, .top, &.{ "A", "B", "C" });
    defer allocator.free(result);
    try testing.expectEqualStrings("ABC", result);
}

test "join.horizontal - multiline" {
    const allocator = testing.allocator;

    const result = try zz.join.horizontal(allocator, .top, &.{ "A\nB", "1\n2" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A1\nB2", result);
}

test "join.vertical - basic" {
    const allocator = testing.allocator;

    const result = try zz.join.vertical(allocator, .left, &.{ "A", "B", "C" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A\nB\nC", result);
}

test "join.vertical - different widths" {
    const allocator = testing.allocator;

    const result = try zz.join.vertical(allocator, .left, &.{ "short", "longer text" });
    defer allocator.free(result);
    // First line should be padded
    var iter = std.mem.splitSequence(u8, result, "\n");
    const first = iter.next().?;
    const second = iter.next().?;
    try testing.expectEqual(first.len, second.len);
}

test "place - center" {
    const allocator = testing.allocator;

    const result = try zz.place.place(allocator, 5, 3, .center, .middle, "X");
    defer allocator.free(result);
    try testing.expect(result.len > 0);
}

test "joinHorizontal convenience" {
    const allocator = testing.allocator;

    const result = try zz.joinHorizontal(allocator, &.{ "A", "B" });
    defer allocator.free(result);
    try testing.expectEqualStrings("AB", result);
}

test "joinVertical convenience" {
    const allocator = testing.allocator;

    const result = try zz.joinVertical(allocator, &.{ "A", "B" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A\nB", result);
}

test "layer.LayerStack - multibyte UTF-8 chars occupy one cell" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = zz.layout.layer.LayerStack.init(allocator);
    defer stack.deinit();
    stack.setSize(5, 1);

    try stack.push(.{ .content = "╭─╮", .transparent = false });

    try testing.expectEqualStrings("╭─╮  ", stack.render(allocator));
}

test "layer.LayerStack - styled multibyte border chars stay intact" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = zz.layout.layer.LayerStack.init(allocator);
    defer stack.deinit();
    stack.setSize(4, 1);

    try stack.push(.{ .content = "\x1b[36m─│\x1b[0m", .transparent = false });

    try testing.expectEqualStrings(
        "\x1b[36m─\x1b[0m\x1b[36m│\x1b[0m  ",
        stack.render(allocator),
    );
}

test "layer.LayerStack - overlay aligns on UTF-8 background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = zz.layout.layer.LayerStack.init(allocator);
    defer stack.deinit();
    stack.setSize(6, 1);

    try stack.push(.{ .content = "──────", .z = 0, .transparent = false });
    try stack.push(.{ .content = "AB", .x = 2, .z = 1 });

    try testing.expectEqualStrings("──AB──", stack.render(allocator));
}

test "layer.LayerStack - wide characters cover two cells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = zz.layout.layer.LayerStack.init(allocator);
    defer stack.deinit();
    stack.setSize(4, 1);

    try stack.push(.{ .content = "你a", .transparent = false });

    try testing.expectEqualStrings("你a ", stack.render(allocator));
}
