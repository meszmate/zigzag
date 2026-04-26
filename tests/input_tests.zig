//! Input handling tests

const std = @import("std");
const Writer = std.Io.Writer;
const testing = std.testing;
const zz = @import("zigzag");

fn stripAnsi(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b) {
            i += 1;
            if (i < text.len and text[i] == '[') {
                i += 1;
                while (i < text.len) : (i += 1) {
                    const c = text[i];
                    if (c >= 0x40 and c <= 0x7E) {
                        i += 1;
                        break;
                    }
                }
            }
            continue;
        }

        try out.append(text[i]);
        i += 1;
    }
    return out.toOwnedSlice();
}

test "Key parsing - single character" {
    const result = zz.input.keyboard.parse("a");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .char);
    try testing.expectEqual(@as(u21, 'a'), result.result.key.key.char);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - escape key" {
    const result = zz.input.keyboard.parse("\x1b");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .escape);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - arrow up" {
    const result = zz.input.keyboard.parse("\x1b[A");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .up);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow down" {
    const result = zz.input.keyboard.parse("\x1b[B");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .down);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow right" {
    const result = zz.input.keyboard.parse("\x1b[C");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .right);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow left" {
    const result = zz.input.keyboard.parse("\x1b[D");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .left);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - backspace" {
    const result = zz.input.keyboard.parse("\x7f");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .backspace);
}

test "Key parsing - enter" {
    const result = zz.input.keyboard.parse("\x0d");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .enter);
}

test "Key parsing - function keys" {
    const f1 = zz.input.keyboard.parse("\x1bOP");
    try testing.expect(f1.result == .key);
    try testing.expect(f1.result.key.key == .f1);

    const f2 = zz.input.keyboard.parse("\x1bOQ");
    try testing.expect(f2.result == .key);
    try testing.expect(f2.result.key.key == .f2);
}

test "Key parsing - delete" {
    const result = zz.input.keyboard.parse("\x1b[3~");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .delete);
}

test "Key parsing - home/end" {
    const home = zz.input.keyboard.parse("\x1b[H");
    try testing.expect(home.result == .key);
    try testing.expect(home.result.key.key == .home);

    const end = zz.input.keyboard.parse("\x1b[F");
    try testing.expect(end.result == .key);
    try testing.expect(end.result.key.key == .end);
}

test "Key parsing - page up/down" {
    const pgup = zz.input.keyboard.parse("\x1b[5~");
    try testing.expect(pgup.result == .key);
    try testing.expect(pgup.result.key.key == .page_up);

    const pgdn = zz.input.keyboard.parse("\x1b[6~");
    try testing.expect(pgdn.result == .key);
    try testing.expect(pgdn.result.key.key == .page_down);
}

test "Modifiers struct" {
    const none = zz.Modifiers.none;
    try testing.expect(!none.any());

    const ctrl = zz.Modifiers{ .ctrl = true };
    try testing.expect(ctrl.any());
    try testing.expect(ctrl.ctrl);
    try testing.expect(!ctrl.alt);
}

test "KeyEvent format" {
    const allocator = testing.allocator;

    const event = zz.KeyEvent{
        .key = .{ .char = 'a' },
        .modifiers = .{ .ctrl = true },
    };

    var buf: Writer.Allocating = .init(allocator);
    defer buf.deinit();

    try event.format("", .{}, &buf.writer);
    try testing.expectEqualStrings("ctrl+a", buf.written());
}

test "parseAll multiple keys" {
    const allocator = testing.allocator;

    const events = try zz.input.keyboard.parseAll(allocator, "abc");
    defer allocator.free(events);

    try testing.expectEqual(@as(usize, 3), events.len);
    try testing.expect(events[0] == .key);
    try testing.expectEqual(@as(u21, 'a'), events[0].key.key.char);
}

test "TextInput accepts multi-character paste commits (IME-like)" {
    var input = zz.TextInput.init(testing.allocator);
    defer input.deinit();

    input.handleKey(.{ .key = .{ .paste = "中文输入" } });

    try testing.expectEqualStrings("中文输入", input.getValue());
}

test "TextArea accepts multi-character paste commits (IME-like)" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.handleKey(.{ .key = .{ .paste = "中文输入" } });

    const value = try area.getValue(testing.allocator);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("中文输入", value);
}

test "TextArea keeps cursor on UTF-8 boundaries after vertical move" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.setValue("abcd\n中文") catch unreachable;
    area.handleKey(.{ .key = .end });
    area.handleKey(.{ .key = .down });

    const value = try area.getValue(testing.allocator);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("abcd\n中文", value);

    area.handleKey(.{ .key = .{ .char = 'X' } });
    const updated = try area.getValue(testing.allocator);
    defer testing.allocator.free(updated);
    try testing.expectEqualStrings("abcd\n中X文", updated);
}

test "TextArea cursorDisplayColumn uses visual width for CJK" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.handleKey(.{ .key = .{ .paste = "中a" } });
    area.handleKey(.{ .key = .left });

    try testing.expectEqual(@as(usize, 2), area.cursorDisplayColumn());
}

test "TextArea word_wrap wraps long lines in view" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(5, 3);
    try area.setValue("abcdefghij");
    area.blur();

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    try testing.expectEqualStrings("abcde\nfghij\n     ", plain);
}

test "TextArea word_wrap moves cursor vertically across wrapped segments" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(4, 3);
    try area.setValue("abcdefgh");

    area.handleKey(.{ .key = .right });
    area.handleKey(.{ .key = .down });

    try testing.expectEqual(@as(usize, 0), area.cursor_row);
    try testing.expectEqual(@as(usize, 5), area.cursor_col);

    area.handleKey(.{ .key = .up });
    try testing.expectEqual(@as(usize, 1), area.cursor_col);
}

test "TextArea word_wrap keeps cursor visible by wrapped row" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(5, 2);
    try area.setValue("abcdefghijk");

    area.handleKey(.{ .key = .end });
    area.blur();

    try testing.expectEqual(@as(usize, 1), area.viewport_row);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);
    try testing.expectEqualStrings("fghij\nk    ", plain);
}

// ============================================================================
// Tests for TextArea setSize/view fix - placeholder and empty row padding
// ============================================================================

test "TextArea setSize without setValue pads placeholder to full width" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    // Initialize with placeholder
    area.placeholder = "Type here";

    // Set size WITHOUT calling setValue (the bug scenario)
    area.setSize(50, 3);

    // Render view
    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    // Verify full 50x3 viewport shape
    var lines = std.mem.splitScalar(u8, plain, '\n');
    const line0 = lines.next().?;
    const line1 = lines.next().?;
    const line2 = lines.next().?;
    try testing.expectEqual(@as(usize, 50), line0.len);
    try testing.expect(std.mem.startsWith(u8, line0, "Type here"));
    try testing.expectEqual(@as(usize, 50), line1.len);
    try testing.expectEqual(@as(usize, 50), line2.len);
    for (line1) |c| {
        try testing.expectEqual(@as(u8, ' '), c);
    }
    for (line2) |c| {
        try testing.expectEqual(@as(u8, ' '), c);
    }
    try testing.expect(lines.next() == null);
}

test "TextArea placeholder wider than width is clipped and padded" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.placeholder = "This is a very long placeholder";
    area.setSize(10, 2);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    var lines = std.mem.splitScalar(u8, plain, '\n');
    const line0 = lines.next().?;
    const line1 = lines.next().?;
    try testing.expectEqual(@as(usize, 10), line0.len);
    try testing.expectEqual(@as(usize, 10), line1.len);
    for (line1) |c| {
        try testing.expectEqual(@as(u8, ' '), c);
    }
    try testing.expect(lines.next() == null);
}

test "TextArea wrapped placeholder wider than width is clipped and padded" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.placeholder = "This is a very long placeholder";
    area.setSize(10, 2);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    var lines = std.mem.splitScalar(u8, plain, '\n');
    const line0 = lines.next().?;
    const line1 = lines.next().?;
    try testing.expectEqual(@as(usize, 10), line0.len);
    try testing.expectEqual(@as(usize, 10), line1.len);
    for (line1) |c| {
        try testing.expectEqual(@as(u8, ' '), c);
    }
    try testing.expect(lines.next() == null);
}

test "TextArea pads empty rows to full width" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    // Set content to just one line
    try area.setValue("Single line");
    area.setSize(30, 5);

    // Render view
    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    // Split into lines
    var lines = std.mem.splitScalar(u8, plain, '\n');

    // First line should have content padded to 30 chars
    const line0 = lines.next().?;
    try testing.expectEqual(@as(usize, 30), line0.len);
    try testing.expect(std.mem.startsWith(u8, line0, "Single line"));

    // Remaining lines should be padded to 30 chars of spaces
    for (0..4) |_| {
        const line = lines.next().?;
        try testing.expectEqual(@as(usize, 30), line.len);
        for (line) |c| {
            try testing.expectEqual(@as(u8, ' '), c);
        }
    }
    try testing.expect(lines.next() == null);
}

test "TextArea renders at correct width after setSize without setValue" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    // Initialize with placeholder (common usage pattern)
    area.placeholder = "Enter text...";
    area.placeholder_style = blk: {
        var s = zz.style.Style{};
        s = s.fg(zz.Color.gray(12));
        s = s.inline_style(true);
        break :blk s;
    };

    // Simulate resize to 80x24 terminal
    area.setSize(80, 24);

    // Render without calling setValue
    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);

    // Strip ANSI and verify dimensions
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    var lines = std.mem.splitScalar(u8, plain, '\n');
    for (0..24) |_| {
        const line = lines.next().?;
        try testing.expectEqual(@as(usize, 80), line.len);
    }
    try testing.expect(lines.next() == null);
}

test "TextArea multiple resize operations maintain correct width" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.placeholder = "Test";

    // First resize to small
    area.setSize(20, 5);
    const rendered1 = try area.view(testing.allocator);
    defer testing.allocator.free(rendered1);
    const plain1 = try stripAnsi(testing.allocator, rendered1);
    defer testing.allocator.free(plain1);

    var lines1 = std.mem.splitScalar(u8, plain1, '\n');
    const first_line1 = lines1.next().?;
    try testing.expectEqual(@as(usize, 20), first_line1.len);

    // Then resize to large
    area.setSize(100, 10);
    const rendered2 = try area.view(testing.allocator);
    defer testing.allocator.free(rendered2);
    const plain2 = try stripAnsi(testing.allocator, rendered2);
    defer testing.allocator.free(plain2);

    var lines2 = std.mem.splitScalar(u8, plain2, '\n');
    const first_line2 = lines2.next().?;
    try testing.expectEqual(@as(usize, 100), first_line2.len);

    // Then resize back to medium
    area.setSize(50, 3);
    const rendered3 = try area.view(testing.allocator);
    defer testing.allocator.free(rendered3);
    const plain3 = try stripAnsi(testing.allocator, rendered3);
    defer testing.allocator.free(plain3);

    var lines3 = std.mem.splitScalar(u8, plain3, '\n');
    const first_line3 = lines3.next().?;
    try testing.expectEqual(@as(usize, 50), first_line3.len);
}

test "TextArea empty content renders all rows at correct width" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    // Don't set any content or placeholder
    area.setSize(40, 10);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    // All 10 rows should be 40 spaces
    var lines = std.mem.splitScalar(u8, plain, '\n');
    var line_count: usize = 0;
    while (lines.next()) |line| : (line_count += 1) {
        if (line_count >= 10) break;
        try testing.expectEqual(@as(usize, 40), line.len);
        // Verify all spaces
        for (line) |c| {
            try testing.expectEqual(@as(u8, ' '), c);
        }
    }
    try testing.expectEqual(@as(usize, 10), line_count);
}

test "TextArea partial content fills remaining rows" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    // Set 3 lines of content
    try area.setValue("Line 1\nLine 2\nLine 3");
    area.setSize(25, 10);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    var lines = std.mem.splitScalar(u8, plain, '\n');

    // First 3 lines have content
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "Line 1"));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "Line 2"));
    try testing.expect(std.mem.startsWith(u8, lines.next().?, "Line 3"));

    // Next 7 lines should be empty (spaces)
    var empty_count: usize = 0;
    while (lines.next()) |line| {
        if (empty_count >= 7) break;
        try testing.expectEqual(@as(usize, 25), line.len);
        var all_spaces = true;
        for (line) |c| {
            if (c != ' ') all_spaces = false;
        }
        try testing.expect(all_spaces);
        empty_count += 1;
    }
    try testing.expectEqual(@as(usize, 7), empty_count);
}
