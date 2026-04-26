const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");
const Modal = zz.Modal;

// ---------------------------------------------------------------------------
// Preset constructors
// ---------------------------------------------------------------------------

test "info preset — single OK button, cyan border" {
    const m = Modal.info("Notice", "Hello");
    try testing.expectEqualStrings("Notice", m.title);
    try testing.expectEqualStrings("Hello", m.body);
    try testing.expectEqual(@as(usize, 1), m.button_count);
    try testing.expect(!m.visible);
}

test "confirm preset — two buttons" {
    const m = Modal.confirm("Sure?", "Delete file?");
    try testing.expectEqual(@as(usize, 2), m.button_count);
    try testing.expectEqualStrings("Yes", m.buttons[0].?.label);
    try testing.expectEqualStrings("No", m.buttons[1].?.label);
}

test "warning preset" {
    const m = Modal.warning("Caution", "Low disk space");
    try testing.expectEqual(@as(usize, 1), m.button_count);
}

test "err preset" {
    const m = Modal.err("Error", "File not found");
    try testing.expectEqual(@as(usize, 1), m.button_count);
}

test "init — blank modal" {
    const m = Modal.init();
    try testing.expectEqual(@as(usize, 0), m.button_count);
    try testing.expectEqualStrings("", m.title);
    try testing.expectEqualStrings("", m.body);
}

// ---------------------------------------------------------------------------
// State management
// ---------------------------------------------------------------------------

test "show sets visible and resets result" {
    var m = Modal.info("T", "B");
    m.result = .dismissed;
    m.show();
    try testing.expect(m.visible);
    try testing.expect(m.focused);
    try testing.expectEqual(@as(?Modal.Result, null), m.result);
    try testing.expectEqual(@as(usize, 0), m.selected_button);
}

test "hide clears visibility" {
    var m = Modal.info("T", "B");
    m.show();
    m.hide();
    try testing.expect(!m.visible);
    try testing.expect(!m.focused);
}

test "reset clears everything" {
    var m = Modal.info("T", "B");
    m.show();
    m.result = .{ .button_pressed = 0 };
    m.reset();
    try testing.expect(!m.visible);
    try testing.expectEqual(@as(?Modal.Result, null), m.result);
}

// ---------------------------------------------------------------------------
// Focusable protocol
// ---------------------------------------------------------------------------

test "focus / blur protocol" {
    var m = Modal.init();
    try testing.expect(!m.focused);
    m.focus();
    try testing.expect(m.focused);
    m.blur();
    try testing.expect(!m.focused);
}

test "isFocusable check" {
    try testing.expect(zz.isFocusable(Modal));
}

// ---------------------------------------------------------------------------
// Key handling
// ---------------------------------------------------------------------------

test "handleKey — escape dismisses" {
    var m = Modal.info("T", "B");
    m.show();
    m.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expect(!m.visible);
    try testing.expectEqual(Modal.Result.dismissed, m.result.?);
}

test "handleKey — escape does nothing when close_on_escape is false" {
    var m = Modal.info("T", "B");
    m.close_on_escape = false;
    m.show();
    m.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expect(m.visible);
}

test "handleKey — enter confirms selected button" {
    var m = Modal.confirm("T", "B");
    m.show();
    // Default selected = 0 (Yes)
    m.handleKey(.{ .key = .enter, .modifiers = .{} });
    try testing.expect(!m.visible);
    try testing.expectEqual(Modal.Result{ .button_pressed = 0 }, m.result.?);
}

test "handleKey — shortcut triggers specific button" {
    var m = Modal.confirm("T", "B");
    m.show();
    // 'n' is shortcut for No (index 1)
    m.handleKey(.{ .key = .{ .char = 'n' }, .modifiers = .{} });
    try testing.expect(!m.visible);
    try testing.expectEqual(Modal.Result{ .button_pressed = 1 }, m.result.?);
}

test "handleKey — tab cycles buttons forward" {
    var m = Modal.confirm("T", "B");
    m.show();
    try testing.expectEqual(@as(usize, 0), m.selected_button);
    m.handleKey(.{ .key = .tab, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), m.selected_button);
    // Wraps around
    m.handleKey(.{ .key = .tab, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 0), m.selected_button);
}

test "handleKey — shift+tab cycles backward" {
    var m = Modal.confirm("T", "B");
    m.show();
    // From 0, shift+tab wraps to last
    m.handleKey(.{ .key = .tab, .modifiers = .{ .shift = true } });
    try testing.expectEqual(@as(usize, 1), m.selected_button);
}

test "handleKey — left/right arrows move between buttons" {
    var m = Modal.confirm("T", "B");
    m.show();
    m.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), m.selected_button);
    m.handleKey(.{ .key = .left, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 0), m.selected_button);
    // Left at 0 stays at 0
    m.handleKey(.{ .key = .left, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 0), m.selected_button);
}

test "handleKey — ignored when not visible" {
    var m = Modal.info("T", "B");
    m.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expectEqual(@as(?Modal.Result, null), m.result);
}

test "handleKey — ignored when not focused" {
    var m = Modal.info("T", "B");
    m.show();
    m.focused = false;
    m.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expect(m.visible);
}

// ---------------------------------------------------------------------------
// Button management
// ---------------------------------------------------------------------------

test "addButton / clearButtons" {
    var m = Modal.init();
    m.addButton("A", null);
    m.addButton("B", .enter);
    try testing.expectEqual(@as(usize, 2), m.button_count);
    try testing.expectEqualStrings("A", m.buttons[0].?.label);
    try testing.expectEqualStrings("B", m.buttons[1].?.label);

    m.clearButtons();
    try testing.expectEqual(@as(usize, 0), m.button_count);
}

test "addButton respects max_buttons limit" {
    var m = Modal.init();
    for (0..10) |_| {
        m.addButton("X", null);
    }
    try testing.expectEqual(@as(usize, 8), m.button_count);
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

test "view returns empty when not visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const m = Modal.info("T", "B");
    const output = try m.view(alloc, 80, 24);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "view produces output when visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.info("Test", "Hello world");
    m.show();
    const output = try m.view(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "viewWithBackdrop produces full-screen output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.info("Test", "Hello");
    m.show();
    const output = try m.viewWithBackdrop(alloc, 40, 12);
    try testing.expect(output.len > 0);
}

test "renderBox respects auto width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.init();
    m.title = "Title";
    m.body = "Short";
    m.width = .auto;
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    try testing.expect(box.len > 0);
    // Auto width should be much less than 80
    const w = zz.measure.maxLineWidth(box);
    try testing.expect(w < 40);
}

test "renderBox respects fixed width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.init();
    m.body = "Test";
    m.width = .{ .fixed = 30 };
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    const w = zz.measure.maxLineWidth(box);
    try testing.expectEqual(@as(usize, 30), w);
}

test "renderBox contains title" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.info("MyTitle", "body");
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    // The box should contain the title text somewhere
    try testing.expect(std.mem.indexOf(u8, box, "MyTitle") != null);
}

test "renderBox with footer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.info("T", "Body");
    m.footer = "Press Enter";
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    try testing.expect(std.mem.indexOf(u8, box, "Press Enter") != null);
}

test "renderBox with no buttons" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.init();
    m.body = "Just text";
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    try testing.expect(box.len > 0);
}

test "renderBox multi-line body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var m = Modal.init();
    m.body = "Line 1\nLine 2\nLine 3";
    m.width = .{ .fixed = 30 };
    m.show();
    const box = try m.renderBox(alloc, 80, 24);
    try testing.expect(std.mem.indexOf(u8, box, "Line 1") != null);
    try testing.expect(std.mem.indexOf(u8, box, "Line 3") != null);
}

// ---------------------------------------------------------------------------
// Backdrop presets
// ---------------------------------------------------------------------------

test "backdrop presets render without error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const presets = [_]Modal.Backdrop{
        Modal.Backdrop.dark,
        Modal.Backdrop.medium,
        Modal.Backdrop.light,
        Modal.Backdrop.clear,
        Modal.Backdrop.shade_light,
        Modal.Backdrop.shade_medium,
        Modal.Backdrop.shade_dense,
        Modal.Backdrop.solid(.blue),
        Modal.Backdrop.custom("*", .red, .black),
    };

    for (presets) |preset| {
        var m = Modal.info("T", "B");
        m.backdrop = preset;
        m.show();
        const output = try m.viewWithBackdrop(alloc, 40, 12);
        try testing.expect(output.len > 0);
    }
}
