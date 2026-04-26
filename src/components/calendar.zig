//! Calendar/DatePicker component.
//! Displays a month view grid with date selection and navigation.
//! Fully customizable: styles, labels, symbols, layout.

const std = @import("std");
const Writer = std.Io.Writer;
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const keys = @import("../input/keys.zig");

pub const Calendar = struct {
    year: u16 = 2026,
    month: u8 = 1,
    selected_day: u8 = 1,
    cursor_day: u8 = 1,
    /// Day to highlight as today (0 = none).
    today_day: u8 = 0,
    today_month: u8 = 0,
    today_year: u16 = 0,
    /// Week starts on Monday (true) or Sunday (false).
    week_start_monday: bool = true,
    /// Marked dates with colors.
    marked_days: [31]?Color = .{null} ** 31,
    /// Focused state.
    focused: bool = true,

    // Customizable labels
    /// Month names (12 entries).
    month_names: [12][]const u8 = .{
        "January", "February", "March",     "April",   "May",      "June",
        "July",    "August",   "September", "October", "November", "December",
    },
    /// Day-of-week headers when week starts Monday (7 entries).
    day_headers_mon: [7][]const u8 = .{ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" },
    /// Day-of-week headers when week starts Sunday (7 entries).
    day_headers_sun: [7][]const u8 = .{ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" },

    // Navigation symbols
    /// Previous month indicator in title.
    prev_symbol: []const u8 = "<",
    /// Next month indicator in title.
    next_symbol: []const u8 = ">",
    /// Title format: 0=prev_symbol, 1=month_name, 2=year, 3=next_symbol.
    /// Set to "" to hide title.
    title_prefix: []const u8 = " ",
    title_suffix: []const u8 = " ",

    // Cell layout
    /// Width of each day cell in characters (minimum 2).
    cell_width: u8 = 4,

    // Styles
    title_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bold(true);
        s = s.inline_style(true);
        break :blk s;
    },
    today_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bold(true);
        s = s.fg(.cyan);
        s = s.inline_style(true);
        break :blk s;
    },
    selected_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bold(true);
        s = s.fg(.blue);
        s = s.inline_style(true);
        break :blk s;
    },
    cursor_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bold(true);
        s = s.bg(.blue);
        s = s.fg(.white);
        s = s.inline_style(true);
        break :blk s;
    },
    weekend_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(10));
        s = s.inline_style(true);
        break :blk s;
    },
    header_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.yellow);
        s = s.inline_style(true);
        break :blk s;
    },
    normal_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.inline_style(true);
        break :blk s;
    },
    /// Style for the prev/next symbols in the title.
    nav_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.fg(.gray(10));
        s = s.inline_style(true);
        break :blk s;
    },
    /// Style for marked dates (applied when no custom color is set).
    marked_style: style_mod.Style = blk: {
        var s = style_mod.Style{};
        s = s.bold(true);
        s = s.inline_style(true);
        break :blk s;
    },

    pub fn addMarkedDate(self: *Calendar, day: u8, c: Color) void {
        if (day >= 1 and day <= 31) {
            self.marked_days[day - 1] = c;
        }
    }

    pub fn clearMarkedDates(self: *Calendar) void {
        self.marked_days = .{null} ** 31;
    }

    pub fn update(self: *Calendar, key: keys.KeyEvent) void {
        const dim = daysInMonth(self.year, self.month);
        switch (key.key) {
            .left => {
                if (key.modifiers.shift) {
                    self.prevMonth();
                } else if (self.cursor_day > 1) {
                    self.cursor_day -= 1;
                }
            },
            .right => {
                if (key.modifiers.shift) {
                    self.nextMonth();
                } else if (self.cursor_day < dim) {
                    self.cursor_day += 1;
                }
            },
            .up => {
                if (self.cursor_day > 7) {
                    self.cursor_day -= 7;
                }
            },
            .down => {
                if (self.cursor_day + 7 <= dim) {
                    self.cursor_day += 7;
                }
            },
            .char => |c| switch (c) {
                'h' => self.prevMonth(),
                'l' => self.nextMonth(),
                else => {},
            },
            .enter => {
                self.selected_day = self.cursor_day;
            },
            .page_up => self.prevMonth(),
            .page_down => self.nextMonth(),
            else => {},
        }
    }

    fn prevMonth(self: *Calendar) void {
        if (self.month == 1) {
            self.month = 12;
            if (self.year > 1) self.year -= 1;
        } else {
            self.month -= 1;
        }
        const dim = daysInMonth(self.year, self.month);
        if (self.cursor_day > dim) self.cursor_day = dim;
        if (self.selected_day > dim) self.selected_day = dim;
    }

    fn nextMonth(self: *Calendar) void {
        if (self.month == 12) {
            self.month = 1;
            self.year += 1;
        } else {
            self.month += 1;
        }
        const dim = daysInMonth(self.year, self.month);
        if (self.cursor_day > dim) self.cursor_day = dim;
        if (self.selected_day > dim) self.selected_day = dim;
    }

    pub fn view(self: *const Calendar, allocator: std.mem.Allocator) []const u8 {
        var result: Writer.Allocating = .init(allocator);
        const writer = &result.writer;

        const cw: usize = @max(2, self.cell_width);

        // Title: < month year >
        const mname = if (self.month >= 1 and self.month <= 12) self.month_names[self.month - 1] else "?";
        const nav_prev = self.nav_style.render(allocator, self.prev_symbol) catch self.prev_symbol;
        const nav_next = self.nav_style.render(allocator, self.next_symbol) catch self.next_symbol;
        const title_text = std.fmt.allocPrint(allocator, "{s}{s}{s} {d}{s}{s}", .{
            self.title_prefix, nav_prev, mname, self.year, nav_next, self.title_suffix,
        }) catch "?";
        writer.writeAll(self.title_style.render(allocator, title_text) catch title_text) catch {};
        writer.writeByte('\n') catch {};

        // Day-of-week headers — aligned to cell_width columns
        const headers = if (self.week_start_monday) &self.day_headers_mon else &self.day_headers_sun;
        for (headers) |hdr| {
            const padded = padCenter(allocator, hdr, cw);
            writer.writeAll(self.header_style.render(allocator, padded) catch padded) catch {};
        }
        writer.writeByte('\n') catch {};

        // Calendar grid
        const dim = daysInMonth(self.year, self.month);
        var first_dow = dayOfWeek(self.year, self.month, 1); // 0=Monday
        if (!self.week_start_monday) {
            first_dow = (first_dow + 1) % 7;
        }

        // Leading blanks — same cell width
        for (0..first_dow) |_| {
            for (0..cw) |_| writer.writeByte(' ') catch {};
        }

        var col = first_dow;
        for (1..@as(usize, dim) + 1) |d| {
            const day: u8 = @intCast(d);
            const day_str = std.fmt.allocPrint(allocator, "{d}", .{day}) catch "??";

            const is_today = (day == self.today_day and self.month == self.today_month and self.year == self.today_year);
            const is_selected = (day == self.selected_day);
            const is_cursor = (day == self.cursor_day and self.focused);
            const is_weekend = if (self.week_start_monday) (col >= 5) else (col == 0 or col == 6);

            // Check marked
            const marked_color: ?Color = if (day >= 1 and day <= 31) self.marked_days[day - 1] else null;

            var s: style_mod.Style = undefined;
            if (is_cursor) {
                s = self.cursor_style;
            } else if (is_selected) {
                s = self.selected_style;
            } else if (is_today) {
                s = self.today_style;
            } else if (marked_color) |mc| {
                var ms = self.marked_style;
                ms = ms.fg(mc);
                s = ms;
            } else if (is_weekend) {
                s = self.weekend_style;
            } else {
                s = self.normal_style;
            }

            // Center the day number within cell_width
            const padded = padCenter(allocator, day_str, cw);
            writer.writeAll(s.render(allocator, padded) catch padded) catch {};

            col += 1;
            if (col >= 7) {
                col = 0;
                if (d < dim) writer.writeByte('\n') catch {};
            }
        }

        return result.toArrayList().items;
    }

    fn padCenter(allocator: std.mem.Allocator, text: []const u8, target: usize) []const u8 {
        if (text.len >= target) return text[0..target];
        var buf = std.array_list.Managed(u8).init(allocator);
        const pad = target - text.len;
        const left = pad / 2;
        const right = pad - left;
        for (0..left) |_| buf.append(' ') catch {};
        buf.appendSlice(text) catch {};
        for (0..right) |_| buf.append(' ') catch {};
        return buf.items;
    }

    // Calendar math
    fn isLeapYear(y: u16) bool {
        if (y % 400 == 0) return true;
        if (y % 100 == 0) return false;
        return y % 4 == 0;
    }

    fn daysInMonth(y: u16, m: u8) u8 {
        const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (m < 1 or m > 12) return 30;
        if (m == 2 and isLeapYear(y)) return 29;
        return days[m - 1];
    }

    /// Returns day of week: 0=Monday, 6=Sunday (Tomohiko Sakamoto's algorithm).
    fn dayOfWeek(y_in: u16, m: u8, d: u8) u8 {
        const t = [_]i8{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
        var y: i32 = @intCast(y_in);
        if (m < 3) y -= 1;
        const mi: usize = @intCast(m - 1);
        const r = @mod(y + @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400) + t[mi] + @as(i32, d), 7);
        // r: 0=Sunday. Convert to 0=Monday.
        return @intCast(@mod(r + 6, 7));
    }
};
