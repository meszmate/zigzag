//! Command tests, focused on the lifetime of `batch`/`sequence` slices.
//!
//! `.{ .batch = &.{ ... } }` puts the array in static memory only when every
//! element is comptime-known. One runtime value and it becomes a stack
//! temporary, which dangles as soon as `update` returns — the runtime then
//! walks freed stack memory. These tests pin down the two ways to build a
//! batch that survives.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const Msg = union(enum) { key: zz.KeyEvent };
const Cmd = zz.Cmd(Msg);

/// Overwrites the stack region a returned-by-value temporary would occupy, so
/// a dangling slice shows up as garbage rather than reading intact.
fn clobberStack(seed: u64) u64 {
    var scratch: [1024]u64 = undefined;
    for (&scratch, 0..) |*slot, i| slot.* = seed +% i;
    return scratch[seed % scratch.len];
}

fn buildWithAlloc(allocator: std.mem.Allocator, interval: u64) !Cmd {
    return Cmd.batchAlloc(allocator, &.{
        .{ .set_title = "built at runtime" },
        .{ .every = interval },
        .{ .tick = interval * 2 },
    });
}

test "batchAlloc survives the frame that built it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A runtime value, so the array cannot be folded into static memory.
    var interval: u64 = 100;
    std.mem.doNotOptimizeAway(&interval);
    interval += 1;

    const cmd = try buildWithAlloc(arena.allocator(), interval);
    _ = clobberStack(3);

    try testing.expect(cmd == .batch);
    try testing.expectEqual(@as(usize, 3), cmd.batch.len);
    try testing.expect(cmd.batch[0] == .set_title);
    try testing.expectEqualStrings("built at runtime", cmd.batch[0].set_title);
    try testing.expectEqual(interval, cmd.batch[1].every);
    try testing.expectEqual(interval * 2, cmd.batch[2].tick);
}

test "sequenceAlloc survives the frame that built it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var ns: u64 = 5;
    ns += 1;

    const cmd = try Cmd.sequenceAlloc(arena.allocator(), &.{
        .{ .tick = ns },
        .quit,
    });
    _ = clobberStack(11);

    try testing.expect(cmd == .sequence);
    try testing.expectEqual(@as(usize, 2), cmd.sequence.len);
    try testing.expectEqual(ns, cmd.sequence[0].tick);
    try testing.expect(cmd.sequence[1] == .quit);
}

/// The allocation-free alternative: storage that belongs to the model, which
/// outlives any single `update` call.
const Holder = struct {
    slots: [2]Cmd = undefined,

    fn build(self: *Holder, interval: u64) Cmd {
        self.slots = .{
            .{ .every = interval },
            .{ .set_title = "from model storage" },
        };
        return .{ .batch = &self.slots };
    }
};

test "model-owned storage survives the frame that built it" {
    var holder = Holder{};

    var interval: u64 = 42;
    interval += 1;

    const cmd = holder.build(interval);
    _ = clobberStack(23);

    try testing.expectEqual(@as(usize, 2), cmd.batch.len);
    try testing.expectEqual(interval, cmd.batch[0].every);
    try testing.expectEqualStrings("from model storage", cmd.batch[1].set_title);
}

test "a comptime-known batch literal lives in static memory" {
    const S = struct {
        fn build() Cmd {
            return .{ .batch = &.{ .{ .set_title = "static" }, .quit } };
        }
    };

    const cmd = S.build();
    _ = clobberStack(31);

    try testing.expectEqual(@as(usize, 2), cmd.batch.len);
    try testing.expectEqualStrings("static", cmd.batch[0].set_title);
    try testing.expect(cmd.batch[1] == .quit);
}

test "batch helpers keep their contents in order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const nested = try Cmd.batchAlloc(arena.allocator(), &.{
        .{ .tick = 1 },
        try Cmd.batchAlloc(arena.allocator(), &.{ .{ .tick = 2 }, .{ .tick = 3 } }),
        .{ .tick = 4 },
    });

    try testing.expectEqual(@as(u64, 1), nested.batch[0].tick);
    try testing.expectEqual(@as(usize, 2), nested.batch[1].batch.len);
    try testing.expectEqual(@as(u64, 3), nested.batch[1].batch[1].tick);
    try testing.expectEqual(@as(u64, 4), nested.batch[2].tick);
}
