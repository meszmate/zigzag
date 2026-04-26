const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

// ── Easing tests ──

test "Easing linear" {
    try testing.expectEqual(@as(f64, 0.0), zz.Easing.linear.apply(0.0));
    try testing.expectEqual(@as(f64, 0.5), zz.Easing.linear.apply(0.5));
    try testing.expectEqual(@as(f64, 1.0), zz.Easing.linear.apply(1.0));
}

test "Easing ease_in starts slow" {
    const mid = zz.Easing.ease_in.apply(0.5);
    try testing.expect(mid < 0.5); // quadratic: 0.25
}

test "Easing ease_out ends slow" {
    const mid = zz.Easing.ease_out.apply(0.5);
    try testing.expect(mid > 0.5); // 0.75
}

test "Easing boundaries" {
    const easings = [_]zz.Easing{
        .linear,            .ease_in,       .ease_out,
        .ease_in_out,       .ease_in_cubic, .ease_out_cubic,
        .ease_in_out_cubic, .bounce,
    };
    for (easings) |e| {
        try testing.expectEqual(@as(f64, 0.0), e.apply(0.0));
        // All should reach ~1.0 at t=1.0
        const end = e.apply(1.0);
        try testing.expect(@abs(end - 1.0) < 0.01);
    }
}

test "Easing clamps input" {
    try testing.expectEqual(@as(f64, 0.0), zz.Easing.linear.apply(-1.0));
    try testing.expectEqual(@as(f64, 1.0), zz.Easing.linear.apply(2.0));
}

// ── Tween tests ──

test "Tween init defaults" {
    const tw = zz.Tween.init(0, 100, 1000);
    try testing.expectEqual(@as(f64, 0), tw.start_val);
    try testing.expectEqual(@as(f64, 100), tw.end_val);
    try testing.expect(!tw.isRunning());
    try testing.expect(!tw.isFinished());
}

test "Tween start and value" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.start();
    try testing.expect(tw.isRunning());
    try testing.expectEqual(@as(f64, 0), tw.value());
}

test "Tween update progresses value" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.start();

    // 500ms = 50%
    tw.update(500 * std.time.ns_per_ms);
    try testing.expectEqual(@as(f64, 50), tw.value());
}

test "Tween finishes at duration" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.start();

    tw.update(1000 * std.time.ns_per_ms);
    try testing.expect(tw.isFinished());
    try testing.expectEqual(@as(f64, 100), tw.value());
}

test "Tween loop mode wraps" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.setLoop(.loop);
    tw.start();

    tw.update(1500 * std.time.ns_per_ms);
    try testing.expect(tw.isRunning());
    // Should be at 50% of second loop
    try testing.expectEqual(@as(f64, 50), tw.value());
}

test "Tween ping_pong reverses" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.setLoop(.ping_pong);
    tw.start();

    // At 1500ms = 75% through ping-pong cycle (returning)
    tw.update(1500 * std.time.ns_per_ms);
    try testing.expect(tw.isRunning());
    const val = tw.value();
    try testing.expect(val < 100); // Should be heading back
}

test "Tween easing changes curve" {
    var tw_linear = zz.Tween.init(0, 100, 1000);
    tw_linear.start();
    tw_linear.update(500 * std.time.ns_per_ms);

    var tw_ease_in = zz.Tween.init(0, 100, 1000);
    tw_ease_in.setEasing(.ease_in);
    tw_ease_in.start();
    tw_ease_in.update(500 * std.time.ns_per_ms);

    // ease_in should be less than linear at midpoint
    try testing.expect(tw_ease_in.value() < tw_linear.value());
}

test "Tween reset" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.start();
    tw.update(500 * std.time.ns_per_ms);
    tw.reset();

    try testing.expect(!tw.isRunning());
    try testing.expectEqual(@as(f64, 0), tw.value());
}

test "Tween intValue" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.start();
    tw.update(500 * std.time.ns_per_ms);
    try testing.expectEqual(@as(i64, 50), tw.intValue());
}

test "Tween does not update when idle" {
    var tw = zz.Tween.init(0, 100, 1000);
    tw.update(500 * std.time.ns_per_ms);
    try testing.expectEqual(@as(f64, 0), tw.value());
}

// ── Utility tests ──

test "lerp interpolates correctly" {
    try testing.expectEqual(@as(f64, 0), zz.lerp(0, 100, 0));
    try testing.expectEqual(@as(f64, 50), zz.lerp(0, 100, 0.5));
    try testing.expectEqual(@as(f64, 100), zz.lerp(0, 100, 1.0));
}

test "lerp clamps t" {
    try testing.expectEqual(@as(f64, 0), zz.lerp(0, 100, -1.0));
    try testing.expectEqual(@as(f64, 100), zz.lerp(0, 100, 2.0));
}

test "tweenColor interpolates" {
    const c = zz.tweenColor(.red, .blue, 0.5);
    const rgb = c.toRgb();
    try testing.expect(rgb != null);
}
