//! Keyboard input parsing for terminal applications.
//! Parses ANSI escape sequences into structured key events.

const std = @import("std");
const keys = @import("keys.zig");
const mouse = @import("mouse.zig");

pub const Key = keys.Key;
pub const KeyEvent = keys.KeyEvent;
pub const Modifiers = keys.Modifiers;
pub const MouseEvent = mouse.MouseEvent;

/// Result of parsing input data
pub const ParseResult = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    none,
};

/// Return type for parse functions
pub const ParseReturn = struct { result: ParseResult, consumed: usize };

/// Outcome of a single streaming parse step.
pub const StreamStep = union(enum) {
    /// A whole sequence was decoded; `consumed` is always greater than zero.
    /// `result` is `.none` for sequences that are well formed but carry no
    /// key or mouse event (device reports, OSC replies, ...) — those bytes
    /// are dropped instead of leaking to the application as text.
    event: ParseReturn,
    /// `data` ends in the middle of a sequence. Keep the bytes and retry once
    /// more input has arrived.
    incomplete,
};

const paste_start = "\x1b[200~";
const paste_end = "\x1b[201~";

/// Parse one event, treating `data` as everything that will ever arrive.
///
/// A sequence truncated by the end of the buffer is decoded as best it can be:
/// a cut-off CSI yields the bare Escape key and its remaining bytes are read
/// as text. When bytes come from a stream — where a sequence is routinely
/// split across two reads — use `InputParser` instead, which holds the tail
/// back until the rest arrives.
pub fn parse(data: []const u8) ParseReturn {
    return switch (parseStream(data)) {
        .event => |e| e,
        .incomplete => parseFlush(data),
    };
}

/// Parse one event, reporting `.incomplete` when `data` stops mid-sequence
/// rather than guessing at the truncated bytes.
pub fn parseStream(data: []const u8) StreamStep {
    if (data.len == 0) return .incomplete;

    if (data[0] == 0x1b) {
        const frame_len = switch (frameEscape(data)) {
            .complete => |n| n,
            .incomplete => return .incomplete,
        };
        return parseFramed(data, frame_len);
    }

    // Control characters
    if (data[0] < 32) {
        return .{ .event = .{ .result = .{ .key = parseControl(data[0]) }, .consumed = 1 } };
    }

    // DEL character
    if (data[0] == 127) {
        return .{ .event = .{ .result = .{ .key = .{ .key = .backspace } }, .consumed = 1 } };
    }

    // UTF-8 character. A multi-byte codepoint split across reads has to wait
    // for its continuation bytes, otherwise it decodes as mojibake.
    const len = std.unicode.utf8ByteSequenceLength(data[0]) catch {
        return .{ .event = .{ .result = .{ .key = .{ .key = .{ .char = data[0] } } }, .consumed = 1 } };
    };
    if (len > data.len) return .incomplete;
    const codepoint = std.unicode.utf8Decode(data[0..len]) catch data[0];
    return .{ .event = .{ .result = .{ .key = .{ .key = .{ .char = codepoint } } }, .consumed = len } };
}

/// Decode `data` as if no further input will arrive. Used to release a partial
/// sequence that has waited long enough to be a real Escape key press.
pub fn parseFlush(data: []const u8) ParseReturn {
    if (data.len == 0) return .{ .result = .none, .consumed = 0 };

    if (data[0] == 0x1b) {
        if (std.mem.startsWith(u8, data, paste_start)) {
            if (parseBracketedPaste(data)) |result| return result;
        }

        // CSI sequence
        if (data.len >= 2 and data[1] == '[') {
            if (parseCsi(data)) |result| return result;
        }

        // SS3 sequence (F1-F4 on some terminals)
        if (data.len >= 2 and data[1] == 'O') {
            if (parseSs3(data)) |result| return result;
        }

        // Alt + key
        if (data.len >= 2 and data[1] != '[' and data[1] != 'O') {
            const inner = parse(data[1..]);
            if (inner.result == .key) {
                var key_event = inner.result.key;
                key_event.modifiers.alt = true;
                return .{ .result = .{ .key = key_event }, .consumed = 1 + inner.consumed };
            }
        }

        return .{ .result = .{ .key = .{ .key = .escape } }, .consumed = 1 };
    }

    // Control characters
    if (data[0] < 32) {
        const key_event = parseControl(data[0]);
        return .{ .result = .{ .key = key_event }, .consumed = 1 };
    }

    // DEL character
    if (data[0] == 127) {
        return .{ .result = .{ .key = .{ .key = .backspace } }, .consumed = 1 };
    }

    // UTF-8 character
    const len = std.unicode.utf8ByteSequenceLength(data[0]) catch 1;
    if (len <= data.len) {
        const codepoint = std.unicode.utf8Decode(data[0..len]) catch data[0];
        return .{ .result = .{ .key = .{ .key = .{ .char = codepoint } } }, .consumed = len };
    }

    return .{ .result = .{ .key = .{ .key = .{ .char = data[0] } } }, .consumed = 1 };
}

/// Extent of a leading escape sequence, before interpreting it.
const Frame = union(enum) {
    complete: usize,
    incomplete,
};

/// Measure the escape sequence starting at `data[0]`, which must be ESC.
/// Framing is purely structural (ECMA-48), so an unrecognised sequence still
/// gets a length and can be skipped as a unit.
fn frameEscape(data: []const u8) Frame {
    if (data.len < 2) return .incomplete;

    return switch (data[1]) {
        '[' => frameCsi(data),
        'O' => if (data.len >= 3) Frame{ .complete = 3 } else .incomplete,
        ']' => frameString(data, .bel_or_st),
        'P', '_', '^', 'X' => frameString(data, .st_only),
        // ESC ESC ... — Alt applied to another sequence.
        0x1b => switch (frameEscape(data[1..])) {
            .complete => |n| Frame{ .complete = 1 + n },
            .incomplete => .incomplete,
        },
        else => frameAltKey(data),
    };
}

/// ESC [ <params 0x30-0x3F> <intermediates 0x20-0x2F> <final 0x40-0x7E>
fn frameCsi(data: []const u8) Frame {
    var i: usize = 2;
    while (i < data.len and data[i] >= 0x30 and data[i] <= 0x3f) : (i += 1) {}
    while (i < data.len and data[i] >= 0x20 and data[i] <= 0x2f) : (i += 1) {}
    if (i >= data.len) return .incomplete;
    // Anything else in place of the final byte means the terminal cut the
    // sequence short. Consume what is there so the stream resynchronises on
    // the next byte instead of stalling forever.
    if (data[i] < 0x40 or data[i] > 0x7e) return .{ .complete = i };
    return .{ .complete = i + 1 };
}

const StringTerm = enum { bel_or_st, st_only };

/// OSC/DCS/APC/PM/SOS strings run until ST (ESC \), and OSC also until BEL.
fn frameString(data: []const u8, term: StringTerm) Frame {
    var i: usize = 2;
    while (i < data.len) : (i += 1) {
        if (term == .bel_or_st and data[i] == 0x07) return .{ .complete = i + 1 };
        if (data[i] == 0x1b) {
            if (i + 1 >= data.len) return .incomplete;
            if (data[i + 1] == '\\') return .{ .complete = i + 2 };
            // A bare ESC that is not ST aborts the string.
            return .{ .complete = i };
        }
    }
    return .incomplete;
}

/// ESC followed by one key.
fn frameAltKey(data: []const u8) Frame {
    const b = data[1];
    if (b < 0x80) return .{ .complete = 2 };
    const len = std.unicode.utf8ByteSequenceLength(b) catch return .{ .complete = 2 };
    if (1 + len > data.len) return .incomplete;
    return .{ .complete = 1 + len };
}

/// Interpret an escape sequence whose length is already known.
fn parseFramed(data: []const u8, frame_len: usize) StreamStep {
    const dropped = StreamStep{ .event = .{ .result = .none, .consumed = frame_len } };
    if (frame_len < 2) return .{ .event = .{ .result = .{ .key = .{ .key = .escape } }, .consumed = 1 } };

    const seq = data[0..frame_len];

    switch (data[1]) {
        '[' => {
            // An X10 mouse report carries three raw payload bytes past the
            // final byte, which the CSI framing rules know nothing about.
            if (std.mem.eql(u8, seq, "\x1b[M")) {
                if (data.len < mouse.x10_report_len) return .incomplete;
                if (mouse.parseX10(data)) |m| {
                    return .{ .event = .{ .result = .{ .mouse = m }, .consumed = mouse.x10_report_len } };
                }
                return .{ .event = .{ .result = .none, .consumed = mouse.x10_report_len } };
            }

            // The closing marker of a bracketed paste lives past this frame.
            if (std.mem.eql(u8, seq, paste_start)) {
                const content = data[paste_start.len..];
                const end = std.mem.indexOf(u8, content, paste_end) orelse return .incomplete;
                return .{ .event = .{
                    .result = .{ .key = .{ .key = .{ .paste = content[0..end] } } },
                    .consumed = paste_start.len + end + paste_end.len,
                } };
            }
            if (parseCsi(seq)) |result| return .{ .event = result };
            return dropped;
        },
        'O' => {
            if (parseSs3(seq)) |result| return .{ .event = result };
            return dropped;
        },
        // Terminal replies (clipboard, graphics, status). Nothing here is a key
        // press, so the whole string is swallowed rather than echoed as text.
        ']', 'P', '_', '^', 'X' => return dropped,
        else => {},
    }

    // Alt + key. Parsed against the rest of the buffer rather than just this
    // frame, because the inner sequence may reach past it (an X10 report or a
    // paste carries payload the framing rules cannot see).
    switch (parseStream(data[1..])) {
        .event => |inner| switch (inner.result) {
            .key => |k| {
                var key_event = k;
                key_event.modifiers.alt = true;
                return .{ .event = .{ .result = .{ .key = key_event }, .consumed = 1 + inner.consumed } };
            },
            .mouse => |m| return .{ .event = .{ .result = .{ .mouse = m }, .consumed = 1 + inner.consumed } },
            .none => return .{ .event = .{ .result = .none, .consumed = 1 + inner.consumed } },
        },
        .incomplete => return .incomplete,
    }
}

fn parseControl(c: u8) KeyEvent {
    return switch (c) {
        0 => .{ .key = .null_key, .modifiers = .{ .ctrl = true } },
        // 0x08 is BS. Which byte Backspace sends is a terminal setting, not a
        // standard: xterm sends BS unless `backarrowKey` is off, while most
        // other terminals send DEL. A legacy encoding has no room to say which
        // of Backspace and Ctrl+H was pressed, so BS is reported as the key
        // people actually press. Terminals speaking the Kitty protocol send a
        // real Ctrl+H as `CSI 104;5u`, which stays distinct.
        8 => .{ .key = .backspace },
        9 => .{ .key = .tab },
        // In raw mode 0x0a is sent by the terminal itself
        // Some editor-integrated terminals (Zed, possibly VSCode) use this
        // historical CR/LF split to encode Shift+Enter without a richer
        // keyboard protocol -- plain Enter sends 0x0d, Shift+Enter sends
        // 0x0a. Mapping LF onto Enter+Shift recovers the modifier, ensuring
        // consistent behavior to other TUI applications / libraries.
        10 => .{ .key = .enter, .modifiers = .{ .shift = true } },
        13 => .{ .key = .enter },
        27 => .{ .key = .escape },
        1...7, 11, 12, 14...26 => .{
            .key = .{ .char = 'a' + c - 1 },
            .modifiers = .{ .ctrl = true },
        },
        else => .{ .key = .{ .char = c } },
    };
}

/// Append a decimal digit to a CSI parameter, saturating rather than
/// overflowing: nothing stops a terminal (or a corrupted stream) from sending
/// a parameter with more digits than a u16 can hold.
fn accumulateParam(value: u16, digit: u8) u16 {
    const scaled = std.math.mul(u16, value, 10) catch return std.math.maxInt(u16);
    return std.math.add(u16, scaled, digit - '0') catch std.math.maxInt(u16);
}

fn parseCsi(data: []const u8) ?ParseReturn {
    if (data.len < 3) return null;
    if (data[0] != 0x1b or data[1] != '[') return null;

    // Check for mouse SGR sequence
    if (data.len >= 3 and data[2] == '<') {
        if (mouse.parseSgr(data)) |m| {
            return .{ .result = .{ .mouse = m.event }, .consumed = m.consumed };
        }
    }

    // Check for a legacy X10 mouse report
    if (data[2] == 'M') {
        if (mouse.parseX10(data)) |m| {
            return .{ .result = .{ .mouse = m }, .consumed = mouse.x10_report_len };
        }
    }

    var idx: usize = 2;
    var params: [8]u16 = @splat(0);
    var param_count: usize = 0;
    var has_colon = false;
    var sub_params: [8]u16 = @splat(0);

    // Parse parameters (supports both ; and : separators for Kitty protocol)
    while (idx < data.len and param_count < params.len) {
        const c = data[idx];
        if (c >= '0' and c <= '9') {
            params[param_count] = accumulateParam(params[param_count], c);
            idx += 1;
        } else if (c == ';') {
            param_count += 1;
            idx += 1;
        } else if (c == ':') {
            // Kitty protocol uses : for sub-parameters (e.g., modifiers:event_type)
            has_colon = true;
            sub_params[param_count] = 0;
            idx += 1;
            // Parse the sub-parameter value
            while (idx < data.len and data[idx] >= '0' and data[idx] <= '9') {
                sub_params[param_count] = accumulateParam(sub_params[param_count], data[idx]);
                idx += 1;
            }
        } else {
            break;
        }
    }
    param_count += 1;

    if (idx >= data.len) return null;

    const final_byte = data[idx];
    idx += 1;

    // Kitty keyboard protocol: final byte 'u'
    if (final_byte == 'u') {
        return parseKittyCsi(params[0..param_count], sub_params[0..param_count], has_colon, idx);
    }

    // Determine modifiers from parameter
    var modifiers = Modifiers{};
    if (param_count >= 2 and params[1] > 1) {
        const mod_param = params[1] - 1;
        modifiers.shift = (mod_param & 1) != 0;
        modifiers.alt = (mod_param & 2) != 0;
        modifiers.ctrl = (mod_param & 4) != 0;
    }

    const key: Key = switch (final_byte) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'Z' => {
            modifiers.shift = true;
            return .{ .result = .{ .key = .{ .key = .tab, .modifiers = modifiers } }, .consumed = idx };
        },
        '~' => switch (params[0]) {
            1 => .home,
            2 => .insert,
            3 => .delete,
            4 => .end,
            5 => .page_up,
            6 => .page_down,
            7 => .home,
            8 => .end,
            11 => .f1,
            12 => .f2,
            13 => .f3,
            14 => .f4,
            15 => .f5,
            17 => .f6,
            18 => .f7,
            19 => .f8,
            20 => .f9,
            21 => .f10,
            23 => .f11,
            24 => .f12,
            else => return null,
        },
        else => return null,
    };

    return .{ .result = .{ .key = .{ .key = key, .modifiers = modifiers } }, .consumed = idx };
}

/// Parse Kitty keyboard protocol CSI sequence: CSI keycode;modifiers:event_type u
fn parseKittyCsi(params: []const u16, sub_params: []const u16, has_colon: bool, consumed: usize) ?ParseReturn {
    if (params.len == 0) return null;

    const keycode = params[0];

    // Determine modifiers
    var modifiers = Modifiers{};
    if (params.len >= 2 and params[1] > 1) {
        const mod_param = params[1] - 1;
        modifiers.shift = (mod_param & 1) != 0;
        modifiers.alt = (mod_param & 2) != 0;
        modifiers.ctrl = (mod_param & 4) != 0;
        modifiers.super = (mod_param & 8) != 0;
    }

    // Determine event type from sub-parameter
    var event_type: keys.KeyEventType = .press;
    if (has_colon and params.len >= 2) {
        event_type = switch (sub_params[1]) {
            2 => .repeat,
            3 => .release,
            else => .press,
        };
    }

    // Map keycode to Key
    const key: Key = switch (keycode) {
        // The protocol assigns Backspace the DEL keycode; 8 is accepted too
        // for terminals that report the BS byte they would have sent.
        8 => .backspace,
        9 => .tab,
        13 => .enter,
        27 => .escape,
        32 => .space,
        127 => .backspace,
        57358 => .{ .char = 0 }, // caps_lock etc - map to null
        else => blk: {
            if (keycode >= 32 and keycode < 127) {
                break :blk .{ .char = @intCast(keycode) };
            }
            if (keycode > 127 and keycode <= 0x10FFFF) {
                break :blk .{ .char = @intCast(keycode) };
            }
            break :blk .null_key;
        },
    };

    return .{
        .result = .{ .key = .{
            .key = key,
            .modifiers = modifiers,
            .event_type = event_type,
        } },
        .consumed = consumed,
    };
}

/// Parse bracketed paste: ESC[200~ ... ESC[201~
/// `data` must start with the opening marker.
fn parseBracketedPaste(data: []const u8) ?ParseReturn {
    const content = data[paste_start.len..];

    if (std.mem.indexOf(u8, content, paste_end)) |end_offset| {
        return .{
            .result = .{ .key = .{
                .key = .{ .paste = content[0..end_offset] },
            } },
            .consumed = paste_start.len + end_offset + paste_end.len,
        };
    }

    // End marker not found — consume all available data as paste
    // (paste may span multiple reads)
    return .{
        .result = .{ .key = .{
            .key = .{ .paste = content },
        } },
        .consumed = data.len,
    };
}

fn parseSs3(data: []const u8) ?ParseReturn {
    if (data.len < 3) return null;
    if (data[0] != 0x1b or data[1] != 'O') return null;

    const key: Key = switch (data[2]) {
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        else => return null,
    };

    return .{ .result = .{ .key = .{ .key = key } }, .consumed = 3 };
}

/// Parse all available input events from a buffer.
///
/// The buffer is treated as self-contained; see `parse`. Reading from a live
/// terminal should go through `InputParser` so that sequences split across
/// reads survive.
pub fn parseAll(allocator: std.mem.Allocator, data: []const u8) ![]ParseResult {
    var results = std.array_list.Managed(ParseResult).init(allocator);
    errdefer results.deinit();

    var offset: usize = 0;
    while (offset < data.len) {
        const parsed = parse(data[offset..]);
        if (parsed.consumed == 0) break;

        if (parsed.result != .none) {
            try results.append(parsed.result);
        }
        offset += parsed.consumed;
    }

    return results.toOwnedSlice();
}

/// Incremental parser for terminal input that arrives in arbitrary chunks.
///
/// The OS hands over whatever bytes happen to be ready, so a single sequence
/// is regularly split in two: an SGR mouse report like `ESC [ < 64;65;42 M`
/// straddles the read boundary constantly while scrolling. Parsing each chunk
/// on its own turns the leading `ESC` into an Escape key press and spills the
/// rest into the application as literal characters. `InputParser` keeps the
/// tail of an unfinished sequence until the remaining bytes show up.
///
/// A lone `ESC` cannot be told apart from the start of a sequence, so it is
/// held as well and released as the Escape key once `escape_timeout_ns` has
/// passed without further input — the same disambiguation vim and tmux use.
/// That requires `feed` to be called on every event-loop iteration, including
/// the ones where no bytes were read.
pub const InputParser = struct {
    /// Bytes retained between reads. Large enough for any single sequence plus
    /// a healthy burst of mouse reports.
    pub const capacity = 4096;

    /// A paste is normally emitted as one event once its closing marker
    /// arrives. Past this many buffered bytes it is streamed out in chunks so
    /// the buffer cannot fill up.
    pub const paste_chunk_threshold = capacity / 2;

    pub const default_escape_timeout_ns: u64 = 50 * std.time.ns_per_ms;

    buf: [capacity]u8 = undefined,
    len: usize = 0,
    /// Inside a bracketed paste, waiting for the closing marker.
    in_paste: bool = false,
    /// Set while an unfinished non-paste sequence is buffered.
    holding: bool = false,
    /// Timestamp passed to `feed` when the current partial sequence appeared.
    holding_since_ns: u64 = 0,
    /// How long a partial sequence waits before being read as a bare Escape.
    escape_timeout_ns: u64 = default_escape_timeout_ns,

    /// Feed one read's worth of bytes and collect the events they complete.
    ///
    /// `now_ns` is any monotonically increasing clock reading; it only drives
    /// the escape timeout. Pass an empty `data` when a read returned nothing
    /// so a pending Escape can still be released.
    ///
    /// The returned slice and any paste payloads it references are owned by
    /// `allocator`.
    pub fn feed(
        self: *InputParser,
        allocator: std.mem.Allocator,
        data: []const u8,
        now_ns: u64,
    ) ![]ParseResult {
        var results = std.array_list.Managed(ParseResult).init(allocator);
        errdefer results.deinit();

        var rest = data;
        while (true) {
            const take = @min(self.buf.len - self.len, rest.len);
            @memcpy(self.buf[self.len..][0..take], rest[0..take]);
            self.len += take;
            rest = rest[take..];

            // Bytes still waiting means the buffer is full: whatever is held
            // cannot be completed by waiting, so release it now.
            try self.drain(allocator, &results, now_ns, rest.len > 0);
            if (rest.len == 0) break;

            // A forced drain always empties the buffer; this only guards
            // against a future parse step that refuses to make progress.
            if (self.len == self.buf.len) self.clearBuffer();
        }

        return results.toOwnedSlice();
    }

    /// Bytes held back from previous feeds, waiting to be completed.
    pub fn pending(self: *const InputParser) []const u8 {
        return self.buf[0..self.len];
    }

    /// Drop any partial sequence. Use when the input stream is interrupted,
    /// such as across a suspend/resume.
    pub fn reset(self: *InputParser) void {
        self.clearBuffer();
        self.in_paste = false;
    }

    fn clearBuffer(self: *InputParser) void {
        self.len = 0;
        self.holding = false;
    }

    fn drain(
        self: *InputParser,
        allocator: std.mem.Allocator,
        results: *std.array_list.Managed(ParseResult),
        now_ns: u64,
        force: bool,
    ) !void {
        var offset: usize = 0;

        while (offset < self.len) {
            const chunk = self.buf[offset..self.len];

            if (self.in_paste) {
                const consumed = try self.drainPaste(allocator, results, chunk, force);
                if (consumed == 0) break;
                offset += consumed;
                continue;
            }

            if (std.mem.startsWith(u8, chunk, paste_start)) {
                self.in_paste = true;
                offset += paste_start.len;
                continue;
            }

            switch (parseStream(chunk)) {
                .event => |parsed| {
                    if (parsed.consumed == 0) break;
                    try appendResult(allocator, results, parsed.result);
                    offset += parsed.consumed;
                },
                .incomplete => {
                    const waited = now_ns -| self.holding_since_ns;
                    const timed_out = self.holding and waited >= self.escape_timeout_ns;
                    if (!force and !timed_out) break;

                    const parsed = parseFlush(chunk);
                    if (parsed.consumed == 0) break;
                    try appendResult(allocator, results, parsed.result);
                    offset += parsed.consumed;
                },
            }
        }

        if (offset > 0) {
            if (offset < self.len) {
                std.mem.copyForwards(u8, self.buf[0 .. self.len - offset], self.buf[offset..self.len]);
            }
            self.len -= offset;
        }

        if (self.len == 0 or self.in_paste) {
            self.holding = false;
        } else if (!self.holding or offset > 0) {
            // A newly buffered partial starts its own timeout.
            self.holding = true;
            self.holding_since_ns = now_ns;
        }
    }

    /// Consume paste content from the front of `chunk`, returning how many
    /// bytes were taken (zero means "wait for more").
    fn drainPaste(
        self: *InputParser,
        allocator: std.mem.Allocator,
        results: *std.array_list.Managed(ParseResult),
        chunk: []const u8,
        force: bool,
    ) !usize {
        if (std.mem.indexOf(u8, chunk, paste_end)) |end| {
            try appendPaste(allocator, results, chunk[0..end]);
            self.in_paste = false;
            return end + paste_end.len;
        }

        // The closing marker may be split across reads, so never touch the
        // bytes that could still be its beginning.
        const holdback = @min(paste_end.len - 1, chunk.len);
        const ready = chunk.len - holdback;
        if (!force and ready < paste_chunk_threshold) return 0;

        const cut = utf8BoundaryFloor(chunk[0..ready]);
        if (cut == 0) return 0;
        try appendPaste(allocator, results, chunk[0..cut]);
        return cut;
    }

    fn appendResult(
        allocator: std.mem.Allocator,
        results: *std.array_list.Managed(ParseResult),
        result: ParseResult,
    ) !void {
        switch (result) {
            .none => return,
            // Paste payloads point into the buffer, which is compacted as
            // events are consumed, so they have to be copied out.
            .key => |k| switch (k.key) {
                .paste => |content| return appendPaste(allocator, results, content),
                else => {},
            },
            else => {},
        }
        try results.append(result);
    }

    fn appendPaste(
        allocator: std.mem.Allocator,
        results: *std.array_list.Managed(ParseResult),
        content: []const u8,
    ) !void {
        const owned = try allocator.dupe(u8, content);
        try results.append(.{ .key = .{ .key = .{ .paste = owned } } });
    }
};

/// Length of the longest prefix of `bytes` that ends on a UTF-8 boundary.
fn utf8BoundaryFloor(bytes: []const u8) usize {
    var i = bytes.len;
    var back: usize = 0;
    while (i > 0 and back < 4) : (back += 1) {
        i -= 1;
        if (bytes[i] & 0xc0 == 0x80) continue; // continuation byte
        const need = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return bytes.len;
        return if (i + need <= bytes.len) bytes.len else i;
    }
    return bytes.len;
}
