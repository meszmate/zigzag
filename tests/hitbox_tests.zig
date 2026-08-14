//! Hit testing and mouse interaction state.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const HitBox = zz.HitBox;
const MouseState = zz.MouseState;

fn at(x: u16, y: u16, button: zz.MouseButton, event_type: zz.MouseEventType) zz.MouseEvent {
    return .{ .x = x, .y = y, .button = button, .event_type = event_type };
}

fn press(x: u16, y: u16) zz.MouseEvent {
    return at(x, y, .left, .press);
}

fn release(x: u16, y: u16) zz.MouseEvent {
    return at(x, y, .left, .release);
}

fn move(x: u16, y: u16) zz.MouseEvent {
    return at(x, y, .none, .move);
}

test "contains covers the box and excludes the far edges" {
    const box = HitBox.init(10, 5, 4, 3); // columns 10..13, rows 5..7

    try testing.expect(box.containsPoint(10, 5));
    try testing.expect(box.containsPoint(13, 7));
    try testing.expect(!box.containsPoint(14, 7));
    try testing.expect(!box.containsPoint(13, 8));
    try testing.expect(!box.containsPoint(9, 5));
    try testing.expect(!box.containsPoint(10, 4));
}

test "a zero-sized box contains nothing" {
    const box = HitBox.init(3, 3, 0, 0);
    try testing.expect(!box.containsPoint(3, 3));
    try testing.expect(!box.containsPoint(0, 0));
}

test "a box past the coordinate limit saturates rather than wrapping" {
    // The bounds are computed with saturating arithmetic, so a box whose right
    // edge would exceed u16 clamps there instead of wrapping to a low number
    // and matching the wrong side of the screen.
    const box = HitBox.init(std.math.maxInt(u16) - 1, 0, 10, 1);
    try testing.expect(box.containsPoint(std.math.maxInt(u16) - 1, 0));
    try testing.expect(!box.containsPoint(0, 0));
    try testing.expect(!box.containsPoint(5, 0));
}

test "clicked and rightClicked discriminate button and event type" {
    const box = HitBox.init(0, 0, 5, 5);

    try testing.expect(box.clicked(press(2, 2)));
    try testing.expect(!box.clicked(release(2, 2)));
    try testing.expect(!box.clicked(at(2, 2, .right, .press)));
    try testing.expect(!box.clicked(press(9, 9)));

    try testing.expect(box.rightClicked(at(2, 2, .right, .press)));
    try testing.expect(!box.rightClicked(press(2, 2)));
}

test "localCoords are relative to the origin" {
    const box = HitBox.init(10, 5, 4, 3);

    const inside = box.localCoords(press(12, 6)).?;
    try testing.expectEqual(@as(u16, 2), inside.x);
    try testing.expectEqual(@as(u16, 1), inside.y);

    const origin = box.localCoords(press(10, 5)).?;
    try testing.expectEqual(@as(u16, 0), origin.x);
    try testing.expectEqual(@as(u16, 0), origin.y);

    try testing.expect(box.localCoords(press(0, 0)) == null);
}

test "expand grows on all sides and clamps at the origin" {
    const box = HitBox.init(10, 10, 4, 4).expand(2);
    try testing.expectEqual(@as(u16, 8), box.x);
    try testing.expectEqual(@as(u16, 8), box.y);
    try testing.expectEqual(@as(u16, 8), box.width);
    try testing.expectEqual(@as(u16, 8), box.height);

    // Padding larger than the offset stops at zero instead of wrapping.
    const clamped = HitBox.init(1, 1, 2, 2).expand(5);
    try testing.expectEqual(@as(u16, 0), clamped.x);
    try testing.expectEqual(@as(u16, 0), clamped.y);
}

test "overlaps is symmetric and excludes touching edges" {
    const a = HitBox.init(0, 0, 5, 5);
    const b = HitBox.init(4, 4, 5, 5); // shares one cell
    const c = HitBox.init(5, 0, 5, 5); // starts where a ends
    const d = HitBox.init(20, 20, 1, 1);

    try testing.expect(a.overlaps(b));
    try testing.expect(b.overlaps(a));
    try testing.expect(!a.overlaps(c));
    try testing.expect(!c.overlaps(a));
    try testing.expect(!a.overlaps(d));
}

test "MouseState reports a full click cycle" {
    const box = HitBox.init(0, 0, 10, 10);
    var state = MouseState{};

    try testing.expectEqual(zz.MouseInteraction.press, state.update(box, press(5, 5)));
    try testing.expect(state.pressed);

    try testing.expectEqual(zz.MouseInteraction.click, state.update(box, release(5, 5)));
    try testing.expect(!state.pressed);
}

test "MouseState does not click when the release lands outside" {
    const box = HitBox.init(0, 0, 10, 10);
    var state = MouseState{};

    _ = state.update(box, press(5, 5));
    const result = state.update(box, release(50, 50));

    try testing.expect(result != .click);
    try testing.expect(!state.pressed);
    try testing.expect(!state.hover);
}

test "MouseState reports crossing the boundary" {
    const box = HitBox.init(10, 10, 5, 5);
    var state = MouseState{};

    try testing.expectEqual(zz.MouseInteraction.none, state.update(box, move(0, 0)));
    try testing.expectEqual(zz.MouseInteraction.enter, state.update(box, move(11, 11)));
    try testing.expect(state.hover);
    try testing.expectEqual(zz.MouseInteraction.hover, state.update(box, move(12, 12)));
    try testing.expectEqual(zz.MouseInteraction.leave, state.update(box, move(0, 0)));
    try testing.expect(!state.hover);
}

test "MouseState tracks the last position even outside the box" {
    const box = HitBox.init(0, 0, 2, 2);
    var state = MouseState{};

    _ = state.update(box, move(40, 12));
    try testing.expectEqual(@as(u16, 40), state.last_x);
    try testing.expectEqual(@as(u16, 12), state.last_y);
}

test "MouseState reports wheel events inside the box" {
    const box = HitBox.init(0, 0, 10, 10);
    var state = MouseState{};

    // Enter first, so the boundary crossing is out of the way.
    _ = state.update(box, move(5, 5));

    try testing.expectEqual(
        zz.MouseInteraction.scroll_up,
        state.update(box, at(5, 5, .wheel_up, .press)),
    );
    try testing.expectEqual(
        zz.MouseInteraction.scroll_down,
        state.update(box, at(5, 5, .wheel_down, .press)),
    );

    // ... and not outside it.
    try testing.expectEqual(
        zz.MouseInteraction.leave,
        state.update(box, at(50, 50, .wheel_up, .press)),
    );
    try testing.expectEqual(
        zz.MouseInteraction.none,
        state.update(box, at(50, 50, .wheel_up, .press)),
    );
}

test "a wheel event that enters the box still reports the scroll" {
    // Scrolling with a trackpad moves the pointer and scrolls in one event.
    // Reporting `enter` and dropping the scroll loses the user's input; the
    // crossing is still visible in `state.hover`.
    const box = HitBox.init(0, 0, 10, 10);
    var state = MouseState{};

    const result = state.update(box, at(5, 5, .wheel_down, .press));

    try testing.expectEqual(zz.MouseInteraction.scroll_down, result);
    try testing.expect(state.hover);
}

test "a left press inside is not mistaken for a scroll" {
    const box = HitBox.init(0, 0, 10, 10);
    var state = MouseState{};

    try testing.expectEqual(zz.MouseInteraction.press, state.update(box, press(1, 1)));
}
