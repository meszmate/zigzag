//! Streaming input parser tests.
//!
//! Terminal reads are chunked wherever the OS decides, so every sequence has
//! to survive being cut at an arbitrary byte. These tests split known-good
//! sequences at every possible boundary and check the events come out whole.

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const keyboard = zz.input.keyboard;
const InputParser = zz.InputParser;

const ms = std.time.ns_per_ms;

/// Collects everything a parser emits, so a sequence can be fed in pieces.
const Harness = struct {
    arena: std.heap.ArenaAllocator,
    parser: InputParser = .{},
    events: std.array_list.Managed(keyboard.ParseResult),
    now_ns: u64 = 0,

    fn init() Harness {
        return .{
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .events = std.array_list.Managed(keyboard.ParseResult).init(testing.allocator),
        };
    }

    fn deinit(self: *Harness) void {
        self.events.deinit();
        self.arena.deinit();
    }

    fn feed(self: *Harness, data: []const u8) !void {
        const produced = try self.parser.feed(self.arena.allocator(), data, self.now_ns);
        try self.events.appendSlice(produced);
    }

    /// Advance the clock and feed nothing, as the event loop does on an idle
    /// frame.
    fn idle(self: *Harness, ns: u64) !void {
        self.now_ns += ns;
        try self.feed("");
    }

    fn keys(self: *const Harness) usize {
        var n: usize = 0;
        for (self.events.items) |e| {
            if (e == .key) n += 1;
        }
        return n;
    }
};

fn expectSingleMouse(events: []const keyboard.ParseResult, expected: zz.MouseEvent) !void {
    try testing.expectEqual(@as(usize, 1), events.len);
    try testing.expect(events[0] == .mouse);
    const m = events[0].mouse;
    try testing.expectEqual(expected.x, m.x);
    try testing.expectEqual(expected.y, m.y);
    try testing.expectEqual(expected.button, m.button);
    try testing.expectEqual(expected.event_type, m.event_type);
}

test "SGR mouse report split at every byte boundary yields one event" {
    const seq = "\x1b[<64;65;42M";
    const expected = zz.MouseEvent{
        .x = 64,
        .y = 41,
        .button = .wheel_up,
        .event_type = .press,
    };

    for (1..seq.len) |split| {
        var h = Harness.init();
        defer h.deinit();

        try h.feed(seq[0..split]);
        try h.feed(seq[split..]);

        expectSingleMouse(h.events.items, expected) catch |err| {
            std.debug.print("split at {d} produced {d} events\n", .{ split, h.events.items.len });
            return err;
        };
    }
}

test "SGR mouse report split across three reads yields one event" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b[<");
    try h.feed("0;12;");
    try h.feed("34M");

    try expectSingleMouse(h.events.items, .{
        .x = 11,
        .y = 33,
        .button = .left,
        .event_type = .press,
    });
}

test "rapid scroll burst split mid-sequence produces only mouse events" {
    var h = Harness.init();
    defer h.deinit();

    // Twenty wheel reports, chopped into 7-byte reads the way a small read
    // buffer would cut them.
    var stream = std.array_list.Managed(u8).init(testing.allocator);
    defer stream.deinit();
    for (0..20) |i| {
        var buf: [32]u8 = undefined;
        try stream.appendSlice(try std.fmt.bufPrint(&buf, "\x1b[<64;{d};{d}M", .{ i + 1, i + 1 }));
    }

    var offset: usize = 0;
    while (offset < stream.items.len) {
        const end = @min(offset + 7, stream.items.len);
        try h.feed(stream.items[offset..end]);
        offset = end;
    }

    try testing.expectEqual(@as(usize, 20), h.events.items.len);
    for (h.events.items, 0..) |event, i| {
        try testing.expect(event == .mouse);
        try testing.expectEqual(@as(u16, @intCast(i)), event.mouse.x);
        try testing.expectEqual(zz.MouseButton.wheel_up, event.mouse.button);
    }
}

test "arrow key split across reads is not decoded as escape plus text" {
    for (1..3) |split| {
        var h = Harness.init();
        defer h.deinit();

        try h.feed("\x1b[A"[0..split]);
        try h.feed("\x1b[A"[split..]);

        try testing.expectEqual(@as(usize, 1), h.events.items.len);
        try testing.expect(h.events.items[0].key.key == .up);
    }
}

test "multi-byte codepoint split across reads decodes once" {
    const utf8 = "€"; // three bytes
    for (1..utf8.len) |split| {
        var h = Harness.init();
        defer h.deinit();

        try h.feed(utf8[0..split]);
        try h.feed(utf8[split..]);

        try testing.expectEqual(@as(usize, 1), h.events.items.len);
        try testing.expectEqual(@as(u21, '€'), h.events.items[0].key.key.char);
    }
}

test "lone escape is held then released after the timeout" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    try h.idle(49 * ms);
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    try h.idle(1 * ms);
    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expect(h.events.items[0].key.key == .escape);
    try testing.expectEqual(@as(usize, 0), h.parser.pending().len);
}

test "escape followed by typing still resolves to escape then the key" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b");
    try h.idle(60 * ms);
    try h.feed("q");

    try testing.expectEqual(@as(usize, 2), h.events.items.len);
    try testing.expect(h.events.items[0].key.key == .escape);
    try testing.expectEqual(@as(u21, 'q'), h.events.items[1].key.key.char);
}

test "escape immediately followed by a key is alt-modified" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1bq");

    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expect(h.events.items[0].key.modifiers.alt);
    try testing.expectEqual(@as(u21, 'q'), h.events.items[0].key.key.char);
}

test "escape prefixed sequences keep their payload" {
    var h = Harness.init();
    defer h.deinit();

    // ESC ESC [ A — Alt applied to a whole sequence.
    try h.feed("\x1b\x1b[A");
    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expect(h.events.items[0].key.key == .up);
    try testing.expect(h.events.items[0].key.modifiers.alt);

    // The payload bytes of a nested mouse report must not spill out as text.
    try h.feed("\x1b\x1b[M\x20\x21\x21");
    try testing.expectEqual(@as(usize, 2), h.events.items.len);
    try testing.expect(h.events.items[1] == .mouse);
}

test "device attribute reply is swallowed instead of leaking as text" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b[?62;1;2;6;9c");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    // Split the same reply and confirm nothing leaks either way.
    var split_h = Harness.init();
    defer split_h.deinit();
    try split_h.feed("\x1b[?62;1");
    try split_h.feed(";2;6;9c");
    try testing.expectEqual(@as(usize, 0), split_h.events.items.len);
}

test "cursor position report is swallowed" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b[24;80R");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);
}

test "OSC reply is swallowed including its payload" {
    var h = Harness.init();
    defer h.deinit();

    // An OSC 52 clipboard reply carries base64 that would otherwise arrive as
    // a stream of key presses.
    try h.feed("\x1b]52;c;aGVsbG8=\x07");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    try h.feed("\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    // ... and still recognises the key typed right after it.
    try h.feed("x");
    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expectEqual(@as(u21, 'x'), h.events.items[0].key.key.char);
}

test "kitty graphics reply is swallowed" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b_Gi=31;OK\x1b\\");
    try h.feed("a");

    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expectEqual(@as(u21, 'a'), h.events.items[0].key.key.char);
}

test "bracketed paste split across reads arrives as one event" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b[200~hello ");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    try h.feed("world\x1b[20");
    try testing.expectEqual(@as(usize, 0), h.events.items.len);

    try h.feed("1~");
    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expectEqualStrings("hello world", h.events.items[0].key.key.paste);
}

test "paste larger than the buffer streams out in chunks" {
    var h = Harness.init();
    defer h.deinit();

    var content = std.array_list.Managed(u8).init(testing.allocator);
    defer content.deinit();
    for (0..(InputParser.capacity * 3)) |i| {
        try content.append(@intCast('a' + (i % 26)));
    }

    try h.feed("\x1b[200~");
    var offset: usize = 0;
    while (offset < content.items.len) {
        const end = @min(offset + 512, content.items.len);
        try h.feed(content.items[offset..end]);
        offset = end;
    }
    try h.feed("\x1b[201~");

    var joined = std.array_list.Managed(u8).init(testing.allocator);
    defer joined.deinit();
    for (h.events.items) |event| {
        try testing.expect(event.key.key == .paste);
        try joined.appendSlice(event.key.key.paste);
    }

    try testing.expect(h.events.items.len > 1);
    try testing.expectEqualStrings(content.items, joined.items);

    // The stream is usable again straight after the paste.
    try h.feed("z");
    try testing.expectEqual(@as(u21, 'z'), h.events.items[h.events.items.len - 1].key.key.char);
}

test "paste chunking never splits a codepoint" {
    var h = Harness.init();
    defer h.deinit();

    var content = std.array_list.Managed(u8).init(testing.allocator);
    defer content.deinit();
    while (content.items.len < InputParser.capacity * 2) {
        try content.appendSlice("日本語テキスト");
    }

    try h.feed("\x1b[200~");
    var offset: usize = 0;
    while (offset < content.items.len) {
        const end = @min(offset + 300, content.items.len);
        try h.feed(content.items[offset..end]);
        offset = end;
    }
    try h.feed("\x1b[201~");

    var joined = std.array_list.Managed(u8).init(testing.allocator);
    defer joined.deinit();
    for (h.events.items) |event| {
        try testing.expect(std.unicode.utf8ValidateSlice(event.key.key.paste));
        try joined.appendSlice(event.key.key.paste);
    }
    try testing.expectEqualStrings(content.items, joined.items);
}

test "a sequence that never terminates cannot stall the stream" {
    var h = Harness.init();
    defer h.deinit();

    // A CSI whose parameter run is longer than the whole buffer: the parser
    // must give up on it rather than block every later key press.
    var garbage = std.array_list.Managed(u8).init(testing.allocator);
    defer garbage.deinit();
    try garbage.appendSlice("\x1b[");
    try garbage.appendNTimes('1', InputParser.capacity * 2);

    try h.feed(garbage.items);
    try h.feed("k");

    const last = h.events.items[h.events.items.len - 1];
    try testing.expectEqual(@as(u21, 'k'), last.key.key.char);
    try testing.expect(h.parser.pending().len < InputParser.capacity);
}

test "legacy X10 mouse report is decoded instead of leaking three characters" {
    // ESC [ M, button 0, column 33, row 25 (each biased by 32).
    const seq = "\x1b[M\x20\x41\x39";

    for (1..seq.len) |split| {
        var h = Harness.init();
        defer h.deinit();

        try h.feed(seq[0..split]);
        try h.feed(seq[split..]);

        try expectSingleMouse(h.events.items, .{
            .x = 32,
            .y = 24,
            .button = .left,
            .event_type = .press,
        });
    }
}

test "oversized parameters saturate instead of overflowing" {
    var h = Harness.init();
    defer h.deinit();

    // Parameter runs wider than a u16 used to abort the process on a debug
    // build, so any terminal reply with a huge parameter took the app down.
    try h.feed("\x1b[99999999999;99999999999R");
    try h.feed("\x1b[<0;99999999;99999999M");
    try h.feed("\x1b[99999999999u");
    try h.feed("q");

    const last = h.events.items[h.events.items.len - 1];
    try testing.expectEqual(@as(u21, 'q'), last.key.key.char);
}

test "reset drops a partial sequence" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("\x1b[<64;1");
    try testing.expect(h.parser.pending().len > 0);

    h.parser.reset();
    try testing.expectEqual(@as(usize, 0), h.parser.pending().len);

    try h.feed("a");
    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expectEqual(@as(u21, 'a'), h.events.items[0].key.key.char);
}

test "mixed keys and mouse reports keep their order" {
    var h = Harness.init();
    defer h.deinit();

    try h.feed("a\x1b[<0;5;5M");
    try h.feed("\x1b[Bb");

    try testing.expectEqual(@as(usize, 4), h.events.items.len);
    try testing.expectEqual(@as(u21, 'a'), h.events.items[0].key.key.char);
    try testing.expect(h.events.items[1] == .mouse);
    try testing.expect(h.events.items[2].key.key == .down);
    try testing.expectEqual(@as(u21, 'b'), h.events.items[3].key.key.char);
}

test "escape timeout is configurable" {
    var h = Harness.init();
    defer h.deinit();
    h.parser.escape_timeout_ns = 5 * ms;

    try h.feed("\x1b");
    try h.idle(6 * ms);

    try testing.expectEqual(@as(usize, 1), h.events.items.len);
    try testing.expect(h.events.items[0].key.key == .escape);
}

test "parseStream reports incomplete instead of guessing" {
    try testing.expect(keyboard.parseStream("\x1b") == .incomplete);
    try testing.expect(keyboard.parseStream("\x1b[") == .incomplete);
    try testing.expect(keyboard.parseStream("\x1b[<64;65;4") == .incomplete);
    try testing.expect(keyboard.parseStream("\x1bO") == .incomplete);
    try testing.expect(keyboard.parseStream("\x1b]52;c;aGk=") == .incomplete);
    try testing.expect(keyboard.parseStream("\xe2\x82") == .incomplete);

    try testing.expect(keyboard.parseStream("\x1b[A") == .event);
    try testing.expect(keyboard.parseStream("a") == .event);
}

test "parse still resolves truncated input for single-shot callers" {
    // Unchanged behaviour: a caller handing over a complete buffer gets the
    // bare Escape key for a sequence that was cut off.
    const escape = keyboard.parse("\x1b");
    try testing.expect(escape.result.key.key == .escape);
    try testing.expectEqual(@as(usize, 1), escape.consumed);

    const truncated = keyboard.parse("\x1b[");
    try testing.expect(truncated.result.key.key == .escape);
    try testing.expectEqual(@as(usize, 1), truncated.consumed);
}

test "parseAll drops complete sequences it has no event for" {
    const allocator = testing.allocator;

    const events = try keyboard.parseAll(allocator, "a\x1b[?62;1cb");
    defer allocator.free(events);

    try testing.expectEqual(@as(usize, 2), events.len);
    try testing.expectEqual(@as(u21, 'a'), events[0].key.key.char);
    try testing.expectEqual(@as(u21, 'b'), events[1].key.key.char);
}
