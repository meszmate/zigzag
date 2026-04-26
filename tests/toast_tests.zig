const std = @import("std");
const Writer = std.Io.Writer;
const testing = std.testing;
const zz = @import("zigzag");

test "Toast init defaults" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try testing.expect(!t.hasMessages());
    try testing.expectEqual(@as(usize, 0), t.count());
    try testing.expect(t.show_icons);
    try testing.expect(t.show_border);
    try testing.expectEqual(zz.ToastPosition.top_right, t.position);
}

test "Toast push and count" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Hello", .info, 3000, 0);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expect(t.hasMessages());

    try t.push("World", .success, 3000, 0);
    try testing.expectEqual(@as(usize, 2), t.count());
}

test "Toast copies pushed text" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    var buffer = [_]u8{ 'H', 'e', 'l', 'l', 'o' };
    try t.push(buffer[0..], .info, 3000, 0);
    buffer[0] = 'Y';

    try testing.expectEqualStrings("Hello", t.messages.items[0].text);
}

test "Toast dismiss removes last" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("First", .info, 3000, 0);
    try t.push("Second", .success, 3000, 0);
    try testing.expectEqual(@as(usize, 2), t.count());

    t.dismiss();
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("First", t.messages.items[0].text);
}

test "Toast dismissAll clears everything" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("A", .info, 3000, 0);
    try t.push("B", .warning, 3000, 0);
    try t.push("C", .err, 3000, 0);

    t.dismissAll();
    try testing.expectEqual(@as(usize, 0), t.count());
}

test "Toast dismissOldest removes first" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("A", .info, 3000, 0);
    try t.push("B", .warning, 3000, 0);
    try t.push("C", .err, 3000, 0);

    t.dismissOldest();
    try testing.expectEqual(@as(usize, 2), t.count());
    try testing.expectEqualStrings("B", t.messages.items[0].text);
    try testing.expectEqualStrings("C", t.messages.items[1].text);
}

test "Toast update removes expired messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Short", .info, 1000, 0); // 1 second
    try t.push("Long", .success, 5000, 0); // 5 seconds

    // After 2 seconds, short should be gone
    t.update(2_000_000_000);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("Long", t.messages.items[0].text);
}

test "Toast persistent messages survive update" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.pushPersistent("Sticky", .warning, 0);
    try t.push("Timed", .info, 1000, 0);

    // After 2 seconds
    t.update(2_000_000_000);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("Sticky", t.messages.items[0].text);
}

test "Toast view renders empty when no messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    const output = try t.view(testing.allocator, 0);
    defer testing.allocator.free(output);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "Toast view renders messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Test message", .info, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
}

test "Toast max_visible limits display" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    t.max_visible = 2;

    try t.push("One", .info, 3000, 0);
    try t.push("Two", .info, 3000, 0);
    try t.push("Three", .info, 3000, 0);

    try testing.expectEqual(@as(usize, 3), t.count()); // all stored

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
    // Should contain overflow indicator
    try testing.expect(std.mem.indexOf(u8, output, "+1 more") != null);
}

test "Toast without borders" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    t.show_border = false;

    try t.push("No border", .success, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
}

test "Toast viewPositioned flushes right edge for shorter toasts" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Short", .info, 3000, 0);
    try t.push("This toast is quite a bit longer", .success, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.viewPositioned(arena.allocator(), 40, 8, 0);
    const plain = try stripAnsi(arena.allocator(), output);

    var top_lines: [2][]const u8 = .{ "", "" };
    var found: usize = 0;
    var lines = std.mem.splitScalar(u8, plain, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "╭") != null) {
            if (found < top_lines.len) {
                top_lines[found] = line;
            }
            found += 1;
        }
    }

    try testing.expectEqual(@as(usize, 2), found);
    try testing.expectEqual(rightEdgeDisplay(top_lines[0]), rightEdgeDisplay(top_lines[1]));
}

test "Toast constrains long messages to configured width" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    t.min_width = 16;
    t.max_width = 24;
    try t.push("This is an intentionally long toast message that should be truncated to fit.", .info, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    const plain = try stripAnsi(arena.allocator(), output);

    try testing.expect(zz.measure.maxLineWidth(plain) <= t.max_width);
    try testing.expect(std.mem.indexOf(u8, plain, "...") != null);
}

fn rightEdgeDisplay(line: []const u8) usize {
    const trimmed = std.mem.trimRight(u8, line, " ");
    return zz.measure.width(trimmed);
}

fn stripAnsi(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result: std.array_list.Managed(u8) = .init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == '[') {
            i += 2;
            while (i < text.len and text[i] != 'm' and text[i] != 'H' and
                text[i] != 'J' and text[i] != 'K' and text[i] != 'A' and
                text[i] != 'B' and text[i] != 'C' and text[i] != 'D')
            {
                i += 1;
            }
            if (i < text.len) i += 1;
        } else if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == ']') {
            i += 2;
            while (i < text.len and text[i] != 0x07 and text[i] != 0x1b) {
                i += 1;
            }
            if (i < text.len and text[i] == 0x07) i += 1;
            if (i + 1 < text.len and text[i] == 0x1b and text[i + 1] == '\\') i += 2;
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}
