//! ZigZag RichLog Example
//! Live log stream with level filtering and search.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    log: zz.components.RichLog,
    counter: u32,
    search_term: std.array_list.Managed(u8),
    typing_search: bool,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        var log = zz.components.RichLog.init(ctx.persistent_allocator, 500);
        log.setSize(80, 14);
        log.show_timestamps = true;

        // Seed with a few entries.
        log.append(.info, "RichLog example started") catch {};
        log.append(.debug, "buffer capacity = 500 entries") catch {};
        log.append(.info, "follow-mode enabled — new entries scroll into view") catch {};
        log.append(.warn, "press '/' to filter, 'l' to cycle min level") catch {};

        self.* = .{
            .log = log,
            .counter = 0,
            .search_term = std.array_list.Managed(u8).init(ctx.persistent_allocator),
            .typing_search = false,
        };
        return .{ .every = 700 * std.time.ns_per_ms };
    }

    pub fn deinit(self: *Model) void {
        self.log.deinit();
        self.search_term.deinit();
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => {
                self.counter += 1;
                self.emit();
            },
            .key => |k| {
                if (self.typing_search) return self.handleSearchKey(k);
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '/' => self.typing_search = true,
                        'c' => {
                            self.search_term.clearRetainingCapacity();
                            self.log.clearSearch();
                        },
                        'l' => self.cycleLevel(),
                        else => self.log.handleKey(k) catch {},
                    },
                    .escape => return .quit,
                    else => self.log.handleKey(k) catch {},
                }
            },
        }
        return .none;
    }

    fn handleSearchKey(self: *Model, k: zz.KeyEvent) zz.Cmd(Msg) {
        switch (k.key) {
            .escape => {
                self.typing_search = false;
                self.search_term.clearRetainingCapacity();
                self.log.clearSearch();
            },
            .enter => {
                self.typing_search = false;
                self.log.setSearch(self.search_term.items) catch {};
            },
            .backspace => {
                if (self.search_term.items.len > 0) _ = self.search_term.pop();
            },
            .char => |c| {
                if (c >= 0x20) {
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(c, &buf) catch return .none;
                    self.search_term.appendSlice(buf[0..n]) catch {};
                }
            },
            else => {},
        }
        return .none;
    }

    fn cycleLevel(self: *Model) void {
        const next: zz.components.RichLogLevel = switch (self.log.min_level) {
            .trace => .debug,
            .debug => .info,
            .info => .warn,
            .warn => .err,
            .err => .trace,
        };
        self.log.setMinLevel(next);
    }

    fn emit(self: *Model) void {
        // Generate one varied log entry per tick. Format strings must be
        // comptime, so dispatch in a switch.
        switch (self.counter % 5) {
            0 => self.log.appendFmt(.trace, "trace: tick {d} fired", .{self.counter}) catch {},
            1 => self.log.appendFmt(.debug, "debug: queue depth {d}", .{self.counter}) catch {},
            2 => self.log.appendFmt(.info, "info: synced {d} records", .{self.counter}) catch {},
            3 => self.log.appendFmt(.warn, "warn: retry {d} after backoff", .{self.counter}) catch {},
            else => self.log.appendFmt(.err, "ERROR: timeout on request {d}", .{self.counter}) catch {},
        }
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;
        var log_mut = @constCast(&self.log);
        const log_view = log_mut.view(alloc) catch "";

        var box = zz.Style{};
        box = box.borderAll(zz.Border.rounded);
        box = box.borderForeground(zz.Color.gray(8));
        const boxed = box.render(alloc, log_view) catch log_view;

        var title = zz.Style{};
        title = title.bold(true);
        title = title.fg(zz.Color.cyan());
        title = title.inline_style(true);
        const t = title.render(alloc, "RichLog — append-only with level filter & search") catch "";

        const status = if (self.typing_search)
            std.fmt.allocPrint(alloc, "search: {s}_  (enter to apply, esc to cancel)", .{self.search_term.items}) catch ""
        else
            std.fmt.allocPrint(
                alloc,
                "follow={s}  level≥{s}  search={s}",
                .{
                    if (self.log.follow) "ON " else "OFF",
                    self.log.min_level.label(),
                    if (self.log.search_term.items.len == 0) "—" else self.log.search_term.items,
                },
            ) catch "";

        var status_style = zz.Style{};
        status_style = status_style.fg(zz.Color.gray(12));
        status_style = status_style.inline_style(true);
        const status_str = status_style.render(alloc, status) catch "";

        var help = zz.Style{};
        help = help.fg(zz.Color.gray(10));
        help = help.inline_style(true);
        const help_text = "↑↓ scroll · g/G top/bottom · / search · c clear · l cycle level · q quit";
        const help_str = help.render(alloc, help_text) catch "";

        return std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}\n{s}", .{ t, boxed, status_str, help_str }) catch "Error";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
