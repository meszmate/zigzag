//! WebAssembly terminal implementation.
//! Communicates with a JavaScript host via imported/exported functions.
//! The JS host is responsible for rendering output to an xterm.js terminal
//! or similar browser-based terminal emulator.

const std = @import("std");
const Writer = std.Io.Writer;
const ansi = @import("../ansi.zig");

pub const TerminalError = error{
    NotATty,
    GetAttrFailed,
    SetAttrFailed,
};

/// Terminal size
pub const Size = struct {
    rows: u16,
    cols: u16,
};

// ── JS host imports ──────────────────────────────────────────────────
// The JavaScript host must provide these functions.

extern "zigzag" fn jsWrite(ptr: [*]const u8, len: usize) void;
extern "zigzag" fn jsReadInput(ptr: [*]u8, max_len: usize) usize;
extern "zigzag" fn jsGetWidth() u16;
extern "zigzag" fn jsGetHeight() u16;
extern "zigzag" fn jsSetTitle(ptr: [*]const u8, len: usize) void;

/// Terminal state for WASM
pub const State = struct {
    in_raw_mode: bool = false,
    in_alt_screen: bool = false,
    mouse_enabled: bool = false,
    width: u16 = 80,
    height: u16 = 24,
    /// Buffer for batching writes before flush.
    output_buf: std.array_list.Managed(u8) = undefined,
    output_buf_initialized: bool = false,

    pub fn init() State {
        return .{};
    }
};

/// WASM is always considered a TTY (the JS host provides the terminal).
pub fn isTty(_: anytype) bool {
    return true;
}

/// Get terminal size from the JS host.
pub fn getSize(_: anytype) !Size {
    return .{
        .rows = jsGetHeight(),
        .cols = jsGetWidth(),
    };
}

/// Enable raw mode (no-op for WASM, the JS host handles input modes).
pub fn enableRawMode(state: *State) !void {
    state.in_raw_mode = true;
}

/// Disable raw mode.
pub fn disableRawMode(state: *State) void {
    state.in_raw_mode = false;
}

/// Enter alternate screen buffer.
pub fn enterAltScreen(state: *State, writer: *Writer) !void {
    if (state.in_alt_screen) return;
    try writer.writeAll(ansi.alt_screen_enter);
    state.in_alt_screen = true;
}

/// Exit alternate screen buffer.
pub fn exitAltScreen(state: *State, writer: *Writer) !void {
    if (!state.in_alt_screen) return;
    try writer.writeAll(ansi.alt_screen_exit);
    state.in_alt_screen = false;
}

/// Enable mouse tracking.
pub fn enableMouse(state: *State, writer: *Writer) !void {
    if (state.mouse_enabled) return;
    try writer.writeAll("\x1b[?1003h\x1b[?1006h");
    state.mouse_enabled = true;
}

/// Disable mouse tracking.
pub fn disableMouse(state: *State, writer: *Writer) !void {
    if (!state.mouse_enabled) return;
    try writer.writeAll("\x1b[?1006l\x1b[?1003l");
    state.mouse_enabled = false;
}

/// Read available input from the JS host.
pub fn readInput(_: *State, buffer: []u8, _: i32) !usize {
    return jsReadInput(buffer.ptr, buffer.len);
}

/// Flush output to the JS host.
pub fn flush(_: anytype) void {
    // Flushing is handled by the writer calling jsWrite directly.
}

/// Setup signal handlers (no-op for WASM).
pub fn setupSignals() !void {}

/// Check if resize was signaled.
/// The JS host should call the exported `zigzagResize` to signal this.
var resize_signaled: bool = false;

pub fn checkResize() bool {
    if (@atomicLoad(bool, &resize_signaled, .monotonic)) {
        @atomicStore(bool, &resize_signaled, false, .monotonic);
        return true;
    }
    return false;
}

// ── Exported functions for the JS host to call ──────────────────────

/// Called by JS when the terminal is resized.
export fn zigzagResize() void {
    @atomicStore(bool, &resize_signaled, true, .monotonic);
}

/// Called by JS to get a pointer to a write buffer.
/// The JS host writes input bytes here, then calls `jsReadInput` to report count.
var input_ring: [4096]u8 = undefined;
var input_write_pos: usize = 0;

export fn zigzagInputBuffer() [*]u8 {
    return &input_ring;
}

export fn zigzagInputBufferLen() usize {
    return input_ring.len;
}

export fn zigzagPushInput(len: usize) void {
    input_write_pos = @min(len, input_ring.len);
}

/// Unbuffered `std.Io.Writer` adapter that drains bytes to the JS host.
pub const WasmWriter = struct {
    writer: Writer,

    const vtable: Writer.VTable = .{ .drain = drain };

    pub fn init() WasmWriter {
        return .{ .writer = .{ .vtable = &vtable, .buffer = &.{} } };
    }

    fn drain(_: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        // Empty data == pure flush; the splat pattern lives at the last
        // element so we must early-return before indexing.
        if (data.len == 0) return 0;

        var consumed: usize = 0;
        if (data.len > 1) for (data[0 .. data.len - 1]) |chunk| {
            if (chunk.len == 0) continue;
            jsWrite(chunk.ptr, chunk.len);
            consumed += chunk.len;
        };
        const pattern = data[data.len - 1];
        if (pattern.len > 0 and splat > 0) {
            var i: usize = 0;
            while (i < splat) : (i += 1) jsWrite(pattern.ptr, pattern.len);
            consumed += pattern.len * splat;
        }
        return consumed;
    }
};

pub var wasm_writer_instance: WasmWriter = .init();
