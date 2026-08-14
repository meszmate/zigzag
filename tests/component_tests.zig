//! Tests for components whose logic is pure state: pagination, progress,
//! spinner cadence, and keybinding matching.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

/// Visible width of styled output.
fn plainWidth(text: []const u8) usize {
    return zz.width(text);
}

// ---------------------------------------------------------------------------
// Paginator
// ---------------------------------------------------------------------------

test "paginator derives page count from item count" {
    var p = zz.components.Paginator.init();
    p.setPerPage(10);

    p.setTotalItems(0);
    try testing.expectEqual(@as(usize, 1), p.total_pages);

    p.setTotalItems(1);
    try testing.expectEqual(@as(usize, 1), p.total_pages);

    p.setTotalItems(10);
    try testing.expectEqual(@as(usize, 1), p.total_pages);

    // A partial last page still counts.
    p.setTotalItems(11);
    try testing.expectEqual(@as(usize, 2), p.total_pages);

    p.setTotalItems(95);
    try testing.expectEqual(@as(usize, 10), p.total_pages);
}

test "paginator keeps the cursor in range when the list shrinks" {
    var p = zz.components.Paginator.init();
    p.setPerPage(10);
    p.setTotalItems(100);
    p.lastPage();
    try testing.expectEqual(@as(usize, 9), p.current_page);

    p.setTotalItems(15);
    try testing.expectEqual(@as(usize, 1), p.current_page);
    try testing.expect(p.onLastPage());
}

test "paginator navigation stops at both ends" {
    var p = zz.components.Paginator.init();
    p.setPerPage(10);
    p.setTotalItems(25); // three pages

    try testing.expect(p.onFirstPage());
    p.prevPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);

    p.nextPage();
    p.nextPage();
    try testing.expectEqual(@as(usize, 2), p.current_page);
    try testing.expect(p.onLastPage());

    p.nextPage();
    try testing.expectEqual(@as(usize, 2), p.current_page);

    p.firstPage();
    try testing.expectEqual(@as(usize, 0), p.current_page);
}

test "paginator index range covers a partial last page" {
    var p = zz.components.Paginator.init();
    p.setPerPage(10);
    p.setTotalItems(25);

    try testing.expectEqual(@as(usize, 0), p.startIndex());
    try testing.expectEqual(@as(usize, 10), p.endIndex());
    try testing.expectEqual(@as(usize, 10), p.itemsOnPage());

    p.lastPage();
    try testing.expectEqual(@as(usize, 20), p.startIndex());
    // The last page holds five items, not ten, and must not run past the end.
    try testing.expectEqual(@as(usize, 25), p.endIndex());
    try testing.expectEqual(@as(usize, 5), p.itemsOnPage());
}

test "paginator gotoPage clamps" {
    var p = zz.components.Paginator.init();
    p.setPerPage(10);
    p.setTotalItems(25);

    p.gotoPage(1);
    try testing.expectEqual(@as(usize, 1), p.current_page);

    p.gotoPage(99);
    try testing.expectEqual(@as(usize, 2), p.current_page);
}

test "paginator with no items has one empty page" {
    var p = zz.components.Paginator.init();
    p.setTotalItems(0);

    try testing.expectEqual(@as(usize, 1), p.total_pages);
    try testing.expect(p.onFirstPage());
    try testing.expect(p.onLastPage());
    try testing.expectEqual(@as(usize, 0), p.itemsOnPage());
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

test "progress clamps to its range" {
    var bar = zz.Progress.init();
    bar.setTotal(100);

    // `percent` is a percentage, 0 to 100 — not a fraction.
    bar.setValue(50);
    try testing.expectApproxEqAbs(@as(f64, 50.0), bar.percent(), 0.0001);

    bar.setValue(-10);
    try testing.expectApproxEqAbs(@as(f64, 0.0), bar.percent(), 0.0001);

    bar.setValue(1000);
    try testing.expectApproxEqAbs(@as(f64, 100.0), bar.percent(), 0.0001);
    try testing.expect(bar.isComplete());
}

test "setPercent is the inverse of percent" {
    var bar = zz.Progress.init();
    bar.setTotal(400);

    bar.setPercent(25);
    try testing.expectApproxEqAbs(@as(f64, 100.0), bar.current, 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 25.0), bar.percent(), 0.0001);
}

test "progress with no total reports zero rather than dividing by it" {
    var bar = zz.Progress.init();
    bar.setTotal(0);
    bar.setValue(5);

    try testing.expectApproxEqAbs(@as(f64, 0.0), bar.percent(), 0.0001);
}

test "progress increments accumulate" {
    var bar = zz.Progress.init();
    bar.setTotal(10);
    bar.setValue(0);

    for (0..5) |_| bar.increment(1);
    try testing.expectApproxEqAbs(@as(f64, 50.0), bar.percent(), 0.0001);
    try testing.expect(!bar.isComplete());

    for (0..5) |_| bar.increment(1);
    try testing.expect(bar.isComplete());
}

test "progress renders at the requested width" {
    // Component views allocate scratch strings from the allocator they are
    // handed and leave them to the frame arena to reclaim, so tests give them
    // an arena rather than the leak-checking allocator.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bar = zz.Progress.init();
    bar.useAscii();
    bar.setWidth(20);
    bar.setTotal(100);
    bar.setValue(50);
    bar.show_percent = false;

    const bare = try bar.view(allocator);
    try testing.expectEqual(@as(usize, 20), plainWidth(bare));
    // Half full: nine body characters plus the head marker.
    try testing.expectEqual(@as(usize, 9), std.mem.count(u8, bare, "#"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, bare, ">"));
    try testing.expectEqual(@as(usize, 10), std.mem.count(u8, bare, "-"));

    // The percentage suffix is appended outside the bar width.
    bar.show_percent = true;
    const labelled = try bar.view(allocator);
    // The percentage is styled, so it is followed by a reset sequence.
    try testing.expect(std.mem.indexOf(u8, labelled, "50%") != null);
    try testing.expect(plainWidth(labelled) > 20);
}

test "progress fills nothing at zero and everything at full" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bar = zz.Progress.init();
    bar.useAscii();
    bar.setWidth(10);
    bar.setTotal(100);
    bar.show_percent = false;

    bar.setValue(0);
    const empty = try bar.view(allocator);
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, empty, "#"));
    try testing.expectEqual(@as(usize, 10), std.mem.count(u8, empty, "-"));

    // Full: no room left for a head marker, so every cell is a body character.
    bar.setValue(100);
    const full = try bar.view(allocator);
    try testing.expectEqual(@as(usize, 10), std.mem.count(u8, full, "#"));
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, full, "-"));
}

// ---------------------------------------------------------------------------
// Spinner
// ---------------------------------------------------------------------------

test "spinner cycles through its frames" {
    var s = zz.Spinner.init();
    s.setFrames(zz.Spinner.Styles.line); // four frames

    try testing.expectEqualStrings("|", s.currentFrame());
    s.tick();
    try testing.expectEqualStrings("/", s.currentFrame());
    s.tick();
    s.tick();
    try testing.expectEqualStrings("\\", s.currentFrame());
    s.tick();
    try testing.expectEqualStrings("|", s.currentFrame());
}

test "spinner advances on the fps interval, not on every update" {
    var s = zz.Spinner.init();
    s.setFrames(zz.Spinner.Styles.line);
    s.setFps(10); // one frame per 100ms

    try testing.expect(!s.update(50 * std.time.ns_per_ms));
    try testing.expectEqualStrings("|", s.currentFrame());

    try testing.expect(s.update(100 * std.time.ns_per_ms));
    try testing.expectEqualStrings("/", s.currentFrame());

    try testing.expect(!s.update(150 * std.time.ns_per_ms));
    try testing.expect(s.update(200 * std.time.ns_per_ms));
    try testing.expectEqualStrings("-", s.currentFrame());
}

test "changing frames restarts the cycle" {
    var s = zz.Spinner.init();
    s.setFrames(zz.Spinner.Styles.line);
    s.tick();
    s.tick();

    s.setFrames(zz.Spinner.Styles.circle);
    try testing.expectEqualStrings("◐", s.currentFrame());
}

// ---------------------------------------------------------------------------
// Keybinding
// ---------------------------------------------------------------------------

test "a binding matches only its own key and modifiers" {
    const binding = zz.KeyBinding{
        .key_event = .{ .key = .{ .char = 's' }, .modifiers = .{ .ctrl = true } },
        .description = "save",
    };

    try testing.expect(binding.matches(.{ .key = .{ .char = 's' }, .modifiers = .{ .ctrl = true } }));
    try testing.expect(!binding.matches(.{ .key = .{ .char = 's' } }));
    try testing.expect(!binding.matches(.{ .key = .{ .char = 'x' }, .modifiers = .{ .ctrl = true } }));
    try testing.expect(!binding.matches(.{
        .key = .{ .char = 's' },
        .modifiers = .{ .ctrl = true, .shift = true },
    }));
}

test "a disabled binding matches nothing" {
    const binding = zz.KeyBinding{
        .key_event = .{ .key = .escape },
        .description = "cancel",
        .enabled = false,
    };

    try testing.expect(!binding.matches(.{ .key = .escape }));
}

test "keyDisplay spells out modifiers" {
    const allocator = testing.allocator;

    const cases = [_]struct { binding: zz.KeyBinding, expected: []const u8 }{
        .{
            .binding = .{ .key_event = .{ .key = .{ .char = 'q' } }, .description = "quit" },
            .expected = "q",
        },
        .{
            .binding = .{
                .key_event = .{ .key = .{ .char = 'c' }, .modifiers = .{ .ctrl = true } },
                .description = "copy",
            },
            .expected = "ctrl+c",
        },
        .{
            .binding = .{ .key_event = .{ .key = .enter }, .description = "confirm" },
            .expected = "enter",
        },
        .{
            .binding = .{
                .key_event = .{ .key = .tab, .modifiers = .{ .shift = true } },
                .description = "back",
            },
            .expected = "shift+tab",
        },
    };

    for (cases) |case| {
        const out = try case.binding.keyDisplay(allocator);
        defer allocator.free(out);
        try testing.expectEqualStrings(case.expected, out);
    }
}

test "KeyMap returns the first matching binding and honours enabled" {
    const allocator = testing.allocator;

    var map = zz.KeyMap.init(allocator);
    defer map.deinit();

    try map.addChar('j', "down");
    try map.addChar('k', "up");
    try map.addCtrl('c', "quit");

    try testing.expect(map.match(.{ .key = .{ .char = 'j' } }) != null);
    try testing.expectEqualStrings("down", map.match(.{ .key = .{ .char = 'j' } }).?.description);
    try testing.expectEqualStrings(
        "quit",
        map.match(.{ .key = .{ .char = 'c' }, .modifiers = .{ .ctrl = true } }).?.description,
    );

    // A plain 'c' is not the ctrl binding.
    try testing.expect(map.match(.{ .key = .{ .char = 'c' } }) == null);
    try testing.expect(map.match(.{ .key = .{ .char = 'z' } }) == null);

    map.setEnabled("down", false);
    try testing.expect(map.match(.{ .key = .{ .char = 'j' } }) == null);

    map.setEnabled("down", true);
    try testing.expect(map.match(.{ .key = .{ .char = 'j' } }) != null);
}
