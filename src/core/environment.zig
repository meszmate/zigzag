//! Process environment values captured at program startup.

const std = @import("std");
const builtin = @import("builtin");
const color_mod = @import("../style/color.zig");
const unicode_mod = @import("../unicode.zig");

pub const Environment = struct {
    term: []const u8 = "",
    term_program: []const u8 = "",
    lc_terminal: []const u8 = "",
    color_term: []const u8 = "",
    color_fg_bg: []const u8 = "",
    term_features: []const u8 = "",
    home_dir: []const u8 = defaultHomeDir(),
    no_color: bool = false,
    has_tmux: bool = false,
    has_zellij: bool = false,
    has_kitty_window: bool = false,
    color_profile: color_mod.ColorProfile = .ansi,
    is_dark_background: bool = true,
    unicode_width_override: ?unicode_mod.WidthStrategy = null,

    pub fn fromEnvMap(environ_map: *const std.process.Environ.Map) Environment {
        const term = environ_map.get("TERM") orelse "";
        const term_program = environ_map.get("TERM_PROGRAM") orelse "";
        const lc_terminal = environ_map.get("LC_TERMINAL") orelse "";
        const color_term = environ_map.get("COLORTERM") orelse "";
        const color_fg_bg = environ_map.get("COLORFGBG") orelse "";
        const term_features = environ_map.get("TERM_FEATURES") orelse "";
        const home_dir = homeDirFromEnvMap(environ_map);
        const no_color = environ_map.get("NO_COLOR") != null;

        return .{
            .term = term,
            .term_program = term_program,
            .lc_terminal = lc_terminal,
            .color_term = color_term,
            .color_fg_bg = color_fg_bg,
            .term_features = term_features,
            .home_dir = home_dir,
            .no_color = no_color,
            .has_tmux = envValuePresent(environ_map, "TMUX"),
            .has_zellij = envValuePresent(environ_map, "ZELLIJ"),
            .has_kitty_window = envValuePresent(environ_map, "KITTY_WINDOW_ID"),
            .color_profile = color_mod.ColorProfile.detect(.{
                .no_color = no_color,
                .color_term = color_term,
                .term = term,
            }),
            .is_dark_background = color_mod.hasDarkBackground(color_fg_bg),
            .unicode_width_override = parseUnicodeWidthOverride(environ_map.get("ZZ_UNICODE_WIDTH") orelse ""),
        };
    }

    pub fn isInsideMultiplexer(self: *const Environment) bool {
        return self.has_tmux or self.has_zellij or self.termContains("screen");
    }

    pub fn isKnownUnicodeWidthTerminal(self: *const Environment) bool {
        return self.termProgramEquals("WezTerm") or
            self.termProgramEquals("iTerm.app") or
            self.termContains("wezterm") or
            self.termContains("ghostty");
    }

    pub fn looksLikeKittyTerminal(self: *const Environment) bool {
        return self.has_kitty_window or self.termContains("kitty");
    }

    pub fn looksLikeIterm2Terminal(self: *const Environment) bool {
        return self.termProgramEquals("iTerm.app") or self.lcTerminalEquals("iTerm2");
    }

    pub fn looksLikeSixelTerminal(self: *const Environment) bool {
        return self.termContains("sixel") or
            self.termContains("mlterm") or
            self.termContains("yaft") or
            self.termContains("contour");
    }

    pub fn termContains(self: *const Environment, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.term, needle) != null;
    }

    pub fn termProgramEquals(self: *const Environment, expected: []const u8) bool {
        return std.ascii.eqlIgnoreCase(self.term_program, expected);
    }

    pub fn lcTerminalEquals(self: *const Environment, expected: []const u8) bool {
        return std.ascii.eqlIgnoreCase(self.lc_terminal, expected);
    }

    fn homeDirFromEnvMap(environ_map: *const std.process.Environ.Map) []const u8 {
        if (comptime builtin.os.tag == .windows) {
            if (environ_map.get("USERPROFILE")) |home| {
                if (home.len > 0) return home;
            }
        } else {
            if (environ_map.get("HOME")) |home| {
                if (home.len > 0) return home;
            }
        }
        return defaultHomeDir();
    }

    fn defaultHomeDir() []const u8 {
        return if (comptime builtin.os.tag == .windows) "C:\\" else "/";
    }

    fn envValuePresent(environ_map: *const std.process.Environ.Map, name: []const u8) bool {
        const value = environ_map.get(name) orelse return false;
        return value.len > 0;
    }

    fn parseUnicodeWidthOverride(raw: []const u8) ?unicode_mod.WidthStrategy {
        if (std.ascii.eqlIgnoreCase(raw, "unicode")) return .unicode;
        if (std.ascii.eqlIgnoreCase(raw, "legacy")) return .legacy_wcwidth;
        if (std.ascii.eqlIgnoreCase(raw, "auto")) return null;
        return null;
    }
};
