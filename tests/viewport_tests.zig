const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "viewport supports wrapped scrolling" {
    const allocator = testing.allocator;

    var viewport = zz.Viewport.init(allocator, 5, 2);
    defer viewport.deinit();

    viewport.setWrap(true);
    viewport.setShowScrollbar(false);
    try viewport.setContent("abcdefghij");

    const first = try viewport.view(allocator);
    defer allocator.free(first);
    try testing.expect(std.mem.indexOf(u8, first, "abcde") != null);
    try testing.expect(std.mem.indexOf(u8, first, "fghij") != null);

    viewport.scrollDown(1);
    const second = try viewport.view(allocator);
    defer allocator.free(second);
    try testing.expect(std.mem.indexOf(u8, second, "fghij") != null);
}

test "viewport clamps horizontal scrolling and supports custom scrollbar chars" {
    const allocator = testing.allocator;

    var viewport = zz.Viewport.init(allocator, 6, 2);
    defer viewport.deinit();

    viewport.setWrap(false);
    viewport.setScrollbarChars(".", "#");
    try viewport.setContent("0123456789\nabcdefghij\nklmnopqrst");
    viewport.scrollRight(4);
    viewport.scrollDown(1);

    const rendered = try viewport.view(allocator);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "efghi") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "#") != null or std.mem.indexOf(u8, rendered, ".") != null);
}

test "viewport slices ANSI styled content without corrupting output" {
    const allocator = testing.allocator;

    var viewport = zz.Viewport.init(allocator, 4, 1);
    defer viewport.deinit();

    var s = zz.Style{};
    s = s.fg(.cyan);
    s = s.inline_style(true);
    const styled = try s.render(allocator, "abcdef");
    defer allocator.free(styled);

    try viewport.setContent(styled);
    viewport.scrollRight(2);

    const rendered = try viewport.view(allocator);
    defer allocator.free(rendered);
    const plain = try stripAnsi(allocator, rendered);
    defer allocator.free(plain);

    try testing.expect(std.mem.indexOf(u8, plain, "cdef") != null);
}

fn stripAnsi(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    defer out.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b) {
            i += 1;
            if (i < input.len and input[i] == '[') {
                i += 1;
                while (i < input.len) : (i += 1) {
                    const c = input[i];
                    if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        i += 1;
                        break;
                    }
                }
                continue;
            }
        }

        try out.append(input[i]);
        i += 1;
    }

    return try out.toOwnedSlice();
}
