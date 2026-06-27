//! Windows terminal implementation using Console API.
//! Provides terminal control for Windows systems.

const std = @import("std");
const Writer = std.Io.Writer;
const windows = std.os.windows;
const ansi = @import("../ansi.zig");

pub const TerminalError = error{
    NotATty,
    GetAttrFailed,
    SetAttrFailed,
    GetConsoleFailed,
    SetConsoleFailed,
    InvalidHandle,
};

/// Terminal size
pub const Size = struct {
    rows: u16,
    cols: u16,
};

/// Console mode flags
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
const ENABLE_VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;
const ENABLE_PROCESSED_INPUT: windows.DWORD = 0x0001;
const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
const ENABLE_MOUSE_INPUT: windows.DWORD = 0x0010;
const ENABLE_WINDOW_INPUT: windows.DWORD = 0x0008;
const ENABLE_EXTENDED_FLAGS: windows.DWORD = 0x0080;
const ENABLE_QUICK_EDIT_MODE: windows.DWORD = 0x0040;
const FILE_TYPE_CHAR: windows.DWORD = 0x0002;
const FILE_TYPE_PIPE: windows.DWORD = 0x0003;
const KEY_EVENT: windows.WORD = 0x0001;
const MOUSE_EVENT: windows.WORD = 0x0002;
const INFINITE: windows.DWORD = 0xFFFFFFFF;
const WAIT_OBJECT_0: windows.DWORD = 0x00000000;
const CP_UTF8: windows.UINT = 65001;

/// Terminal state for Windows
pub const State = struct {
    original_input_mode: windows.DWORD = 0,
    original_output_mode: windows.DWORD = 0,
    original_output_cp: windows.UINT = 0,
    original_input_cp: windows.UINT = 0,
    in_raw_mode: bool = false,
    in_alt_screen: bool = false,
    mouse_enabled: bool = false,
    stdin_handle: windows.HANDLE,
    stdout_handle: windows.HANDLE,

    pub fn init() State {
        return .{
            .stdin_handle = std.Io.File.stdin().handle,
            .stdout_handle = std.Io.File.stdout().handle,
        };
    }
};

/// External Windows API declarations
extern "kernel32" fn GetConsoleMode(hConsole: windows.HANDLE, lpMode: *windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn SetConsoleMode(hConsole: windows.HANDLE, dwMode: windows.DWORD) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetConsoleScreenBufferInfo(hConsole: windows.HANDLE, lpInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetFileType(hFile: windows.HANDLE) callconv(.winapi) windows.DWORD;
extern "kernel32" fn PeekNamedPipe(
    hNamedPipe: windows.HANDLE,
    lpBuffer: ?*anyopaque,
    nBufferSize: windows.DWORD,
    lpBytesRead: ?*windows.DWORD,
    lpTotalBytesAvail: ?*windows.DWORD,
    lpBytesLeftThisMessage: ?*windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetNumberOfConsoleInputEvents(
    hConsoleInput: windows.HANDLE,
    lpcNumberOfEvents: *windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn PeekConsoleInputW(
    hConsoleInput: windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: windows.DWORD,
    lpNumberOfEventsRead: *windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn ReadConsoleInputW(
    hConsoleInput: windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: windows.DWORD,
    lpNumberOfEventsRead: *windows.DWORD,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn WaitForSingleObject(
    hHandle: windows.HANDLE,
    dwMilliseconds: windows.DWORD,
) callconv(.winapi) windows.DWORD;
extern "kernel32" fn ReadFile(
    hFile: windows.HANDLE,
    lpBuffer: [*]u8,
    nNumberOfBytesToRead: windows.DWORD,
    lpNumberOfBytesRead: ?*windows.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) windows.UINT;
extern "kernel32" fn SetConsoleOutputCP(wCodePageID: windows.UINT) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetConsoleCP() callconv(.winapi) windows.UINT;
extern "kernel32" fn SetConsoleCP(wCodePageID: windows.UINT) callconv(.winapi) windows.BOOL;

const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: windows.WORD,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

const COORD = extern struct {
    X: windows.SHORT,
    Y: windows.SHORT,
};

const SMALL_RECT = extern struct {
    Left: windows.SHORT,
    Top: windows.SHORT,
    Right: windows.SHORT,
    Bottom: windows.SHORT,
};

const INPUT_RECORD = extern struct {
    EventType: windows.WORD,
    Event: INPUT_EVENT,
};

const INPUT_EVENT = extern union {
    KeyEvent: KEY_EVENT_RECORD,
    MouseEvent: [16]u8,
    WindowBufferSizeEvent: [4]u8,
    MenuEvent: [4]u8,
    FocusEvent: [4]u8,
};

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: windows.BOOL,
    wRepeatCount: windows.WORD,
    wVirtualKeyCode: windows.WORD,
    wVirtualScanCode: windows.WORD,
    uChar: extern union {
        UnicodeChar: windows.WCHAR,
        AsciiChar: windows.CHAR,
    },
    dwControlKeyState: windows.DWORD,
};

/// Check if a handle is valid
pub fn isTty(handle: windows.HANDLE) bool {
    if (handle == windows.INVALID_HANDLE_VALUE) return false;
    var mode: windows.DWORD = 0;
    return GetConsoleMode(handle, &mode).toBool();
}

/// Get terminal size
pub fn getSize(handle: windows.HANDLE) !Size {
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (!GetConsoleScreenBufferInfo(handle, &info).toBool()) {
        return TerminalError.GetConsoleFailed;
    }
    return .{
        .rows = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
        .cols = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
    };
}

/// Enable raw mode
pub fn enableRawMode(state: *State) !void {
    if (state.in_raw_mode) return;

    if (state.stdin_handle == windows.INVALID_HANDLE_VALUE or
        state.stdout_handle == windows.INVALID_HANDLE_VALUE)
    {
        return TerminalError.InvalidHandle;
    }

    // Save original modes
    if (!GetConsoleMode(state.stdin_handle, &state.original_input_mode).toBool()) {
        return TerminalError.GetConsoleFailed;
    }
    if (!GetConsoleMode(state.stdout_handle, &state.original_output_mode).toBool()) {
        return TerminalError.GetConsoleFailed;
    }

    // Set input mode for raw input with VT processing.
    // Avoid WINDOW_INPUT because it can signal wait handles without producing bytes for ReadFile.
    const input_mode: windows.DWORD = ENABLE_VIRTUAL_TERMINAL_INPUT;
    if (!SetConsoleMode(state.stdin_handle, input_mode).toBool()) {
        return TerminalError.SetConsoleFailed;
    }

    // Enable VT processing on output
    const output_mode: windows.DWORD = state.original_output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (!SetConsoleMode(state.stdout_handle, output_mode).toBool()) {
        // Restore input mode and fail
        _ = SetConsoleMode(state.stdin_handle, state.original_input_mode);
        return TerminalError.SetConsoleFailed;
    }

    // Switch the console code pages to UTF-8 so multi-byte sequences (box-drawing,
    // emoji, etc.) emitted by the renderer aren't reinterpreted as the OEM codepage.
    state.original_output_cp = GetConsoleOutputCP();
    state.original_input_cp = GetConsoleCP();
    _ = SetConsoleOutputCP(CP_UTF8);
    _ = SetConsoleCP(CP_UTF8);

    state.in_raw_mode = true;
}

/// Disable raw mode
pub fn disableRawMode(state: *State) void {
    if (!state.in_raw_mode) return;

    _ = SetConsoleMode(state.stdin_handle, state.original_input_mode);
    _ = SetConsoleMode(state.stdout_handle, state.original_output_mode);
    if (state.original_output_cp != 0) _ = SetConsoleOutputCP(state.original_output_cp);
    if (state.original_input_cp != 0) _ = SetConsoleCP(state.original_input_cp);

    state.in_raw_mode = false;
}

/// Enter alternate screen buffer
pub fn enterAltScreen(state: *State, writer: *Writer) !void {
    if (state.in_alt_screen) return;

    try writer.writeAll(ansi.alt_screen_enter);
    state.in_alt_screen = true;
}

/// Exit alternate screen buffer
pub fn exitAltScreen(state: *State, writer: *Writer) !void {
    if (!state.in_alt_screen) return;

    try writer.writeAll(ansi.alt_screen_exit);
    state.in_alt_screen = false;
}

/// Enable mouse tracking
pub fn enableMouse(state: *State, writer: *Writer) !void {
    if (state.mouse_enabled) return;

    // Enable mouse input in console mode
    if (state.stdin_handle != windows.INVALID_HANDLE_VALUE) {
        var mode: windows.DWORD = 0;
        if (GetConsoleMode(state.stdin_handle, &mode).toBool()) {
            _ = SetConsoleMode(state.stdin_handle, mode | ENABLE_MOUSE_INPUT);
        }
    }

    // Also send ANSI sequences for VT mode
    try writer.writeAll("\x1b[?1003h\x1b[?1006h");
    state.mouse_enabled = true;
}

/// Disable mouse tracking
pub fn disableMouse(state: *State, writer: *Writer) !void {
    if (!state.mouse_enabled) return;

    try writer.writeAll("\x1b[?1006l\x1b[?1003l");
    state.mouse_enabled = false;
}

/// Read available input (Windows uses std.Io)
pub fn readInput(state: *State, buffer: []u8, timeout_ms: i32) !usize {
    if (state.stdin_handle == windows.INVALID_HANDLE_VALUE) return 0;

    // Match POSIX behavior: wait up to timeout_ms for input, then return 0.
    const wait_ms: windows.DWORD = if (timeout_ms < 0)
        INFINITE
    else
        @intCast(timeout_ms);

    if (WaitForSingleObject(state.stdin_handle, wait_ms) != WAIT_OBJECT_0) return 0;

    const file_type = GetFileType(state.stdin_handle);

    // ConPTY/Windows Terminal can expose stdin as a pipe. Ensure there are bytes before reading.
    if (file_type == FILE_TYPE_PIPE) {
        var available: windows.DWORD = 0;
        if (!PeekNamedPipe(state.stdin_handle, null, 0, null, &available, null).toBool() or available == 0) {
            return 0;
        }
    }

    // Console handles may wake due non-byte events (focus/menu/window-size). Drain those first.
    if (file_type == FILE_TYPE_CHAR and !hasReadableConsoleInput(state.stdin_handle)) {
        return 0;
    }

    // Read from the configured stdin handle after it is signaled as readable.
    var bytes_read: windows.DWORD = 0;
    if (!ReadFile(state.stdin_handle, buffer.ptr, @intCast(buffer.len), &bytes_read, null).toBool()) return 0;
    return bytes_read;
}

fn hasReadableConsoleInput(handle: windows.HANDLE) bool {
    var record_buf: [1]INPUT_RECORD = undefined;

    while (true) {
        var event_count: windows.DWORD = 0;
        if (!GetNumberOfConsoleInputEvents(handle, &event_count).toBool() or event_count == 0) {
            return false;
        }

        var peeked: windows.DWORD = 0;
        if (!PeekConsoleInputW(handle, &record_buf, 1, &peeked).toBool() or peeked == 0) {
            return false;
        }

        const record = record_buf[0];
        switch (record.EventType) {
            KEY_EVENT => {
                if (record.Event.KeyEvent.bKeyDown.toBool()) return true;
            },
            MOUSE_EVENT => return true,
            else => {},
        }

        var consumed: windows.DWORD = 0;
        if (!ReadConsoleInputW(handle, &record_buf, 1, &consumed).toBool() or consumed == 0) {
            return false;
        }
    }
}

/// Flush output
pub fn flush(handle: windows.HANDLE) void {
    _ = handle;
    // Windows typically auto-flushes
}

/// Last observed console window dimensions, used to detect resizes by polling.
/// Windows has no SIGWINCH equivalent, so `checkResize` compares the current
/// size against these cached values. `resize_initialized` guards the first read
/// so startup establishes a baseline without reporting a spurious resize.
var resize_initialized: bool = false;
var cached_cols: windows.SHORT = 0;
var cached_rows: windows.SHORT = 0;

/// Setup signal handlers (Windows uses console events differently)
pub fn setupSignals() !void {
    // Windows has no SIGWINCH. Resize is detected by polling the console screen
    // buffer in `checkResize`, so there is nothing to register here.
}

/// Check whether the terminal was resized since the last call.
///
/// Polls the console window dimensions (via the same handle `getSize` reads) and
/// compares them against the last observed size. `GetConsoleScreenBufferInfo` is
/// a cheap kernel read, so polling each frame is negligible. Polling is used
/// instead of `WINDOW_BUFFER_SIZE_EVENT` because those records are only queued
/// when `ENABLE_WINDOW_INPUT` is set on the input mode, which `enableRawMode`
/// deliberately avoids. Because the size is re-polled every frame, a transiently
/// stale reading under ConPTY self-corrects on a later frame.
pub fn checkResize(handle: windows.HANDLE) bool {
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (!GetConsoleScreenBufferInfo(handle, &info).toBool()) return false;

    const cols = info.srWindow.Right - info.srWindow.Left + 1;
    const rows = info.srWindow.Bottom - info.srWindow.Top + 1;

    // The first successful read establishes the baseline without signaling a
    // resize; the initial size is already reported via `getSize` at startup.
    if (!resize_initialized) {
        resize_initialized = true;
        cached_cols = cols;
        cached_rows = rows;
        return false;
    }

    if (cols != cached_cols or rows != cached_rows) {
        cached_cols = cols;
        cached_rows = rows;
        return true;
    }
    return false;
}
