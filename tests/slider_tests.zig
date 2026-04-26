const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Slider init defaults" {
    const s = zz.Slider.init(0, 100);
    try testing.expectEqual(@as(f64, 0), s.value);
    try testing.expectEqual(@as(f64, 0), s.min);
    try testing.expectEqual(@as(f64, 100), s.max);
    try testing.expectEqual(@as(f64, 1), s.step);
    try testing.expect(s.focused);
    try testing.expect(s.show_value);
}

test "Slider setValue clamps" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);
    try testing.expectEqual(@as(f64, 50), s.value);

    s.setValue(200);
    try testing.expectEqual(@as(f64, 100), s.value);

    s.setValue(-10);
    try testing.expectEqual(@as(f64, 0), s.value);
}

test "Slider percent" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);
    try testing.expectEqual(@as(f64, 50), s.percent());

    s.setValue(0);
    try testing.expectEqual(@as(f64, 0), s.percent());

    s.setValue(100);
    try testing.expectEqual(@as(f64, 100), s.percent());
}

test "Slider percent with custom range" {
    var s = zz.Slider.init(-50, 50);
    s.setValue(0);
    try testing.expectEqual(@as(f64, 50), s.percent());
}

test "Slider handleKey increments on right arrow" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);

    s.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 51), s.value);

    s.handleKey(.{ .key = .left, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 50), s.value);
}

test "Slider handleKey large step with page up/down" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);

    s.handleKey(.{ .key = .page_up, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 60), s.value);

    s.handleKey(.{ .key = .page_down, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 50), s.value);
}

test "Slider handleKey Home and End" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);

    s.handleKey(.{ .key = .home, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 0), s.value);

    s.handleKey(.{ .key = .end, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 100), s.value);
}

test "Slider ignores keys when not focused" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);
    s.blur();

    s.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 50), s.value);
}

test "Slider view renders" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);
    s.label = "Volume:";

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try s.view(arena.allocator());
    try testing.expect(output.len > 0);
}

test "Slider view with gradient" {
    var s = zz.Slider.init(0, 100);
    s.setValue(50);
    s.setGradient(.red, .green);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try s.view(arena.allocator());
    try testing.expect(output.len > 0);
}

test "Slider presets" {
    const block = zz.SliderStyle.block();
    try testing.expectEqualStrings("█", block.filled_char);

    const ascii = zz.SliderStyle.ascii();
    try testing.expectEqualStrings("=", ascii.filled_char);

    const thin = zz.SliderStyle.thin();
    try testing.expectEqualStrings("◆", thin.thumb_char);
}

test "Slider custom step size" {
    var s = zz.Slider.init(0, 10);
    s.setStep(0.5);
    s.setValue(5);

    s.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(f64, 5.5), s.value);
}
