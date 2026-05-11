//! ZigZag OSC 52 Clipboard Example
//! Demonstrates clipboard writes and reads with configurable OSC 52 options.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    status: []const u8,
    status_buf: [320]u8,
    terminator: zz.OscTerminator,
    passthrough: zz.Osc52Passthrough,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        paste: []const u8,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{
            .status = "Ready. Press 'c' to copy to clipboard.",
            .status_buf = undefined,
            .terminator = .bel,
            .passthrough = .auto,
        };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .escape => return .quit,
                .char => |c| switch (c) {
                    'q' => return .quit,
                    't' => {
                        self.terminator = switch (self.terminator) {
                            .bel => .st,
                            .st => .bel,
                        };
                        self.setStatus("Terminator set to {s}", .{self.terminatorName()});
                    },
                    'p' => {
                        self.passthrough = switch (self.passthrough) {
                            .auto => .none,
                            .none => .tmux,
                            .tmux => .dcs,
                            .dcs => .auto,
                        };
                        self.setStatus("Passthrough set to {s}", .{self.passthroughName()});
                    },
                    'c' => self.copyWith(ctx, "Copied via default target (clipboard)", null),
                    '1' => self.copyWith(ctx, "Copied to target=c (clipboard)", .clipboard),
                    '2' => self.copyWith(ctx, "Copied to target=p (primary)", .primary),
                    '3' => self.copyWith(ctx, "Copied to target=q (secondary)", .secondary),
                    '4' => self.copyWith(ctx, "Copied to target=s (select)", .select),
                    'g' => self.readClipboard(ctx),
                    else => {},
                },
                else => {},
            },
            .paste => |text| {
                self.setStatusFromBytes("Pasted", text);
            },
        }
        return .none;
    }

    fn copyWith(self: *Model, ctx: *zz.Context, text: []const u8, target: ?zz.Osc52Target) void {
        const result = if (target) |t|
            ctx.setClipboardWithOptions(text, .{
                .target = t,
                .terminator = self.terminator,
                .passthrough = self.passthrough,
            }) catch false
        else
            ctx.setClipboardWithOptions(text, .{
                .terminator = self.terminator,
                .passthrough = self.passthrough,
            }) catch false;

        if (result) {
            self.setStatus("Sent: \"{s}\"", .{text});
        } else {
            self.setStatus("Clipboard write rejected (disabled / guardrail / terminal policy)", .{});
        }
    }

    fn setStatus(self: *Model, comptime fmt: []const u8, args: anytype) void {
        self.status = std.fmt.bufPrint(&self.status_buf, fmt, args) catch "status error";
    }

    fn readClipboard(self: *Model, ctx: *zz.Context) void {
        const result = ctx.getClipboardWithOptions(ctx.allocator, .{
            .terminator = self.terminator,
            .passthrough = self.passthrough,
        }) catch null;

        if (result) |bytes| {
            self.setStatusFromBytes("Read", bytes);
        } else {
            self.setStatus("Clipboard read unavailable (blocked / timeout / terminal policy)", .{});
        }
    }

    fn setStatusFromBytes(self: *Model, label: []const u8, bytes: []const u8) void {
        var out: [220]u8 = undefined;
        var prefix_buf: [32]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buf, "{s}: \"", .{label}) catch "Data: \"";
        const suffix = "\"";
        if (out.len <= prefix.len + suffix.len + 4) {
            self.status = "Read clipboard";
            return;
        }

        var pos: usize = 0;
        @memcpy(out[pos .. pos + prefix.len], prefix);
        pos += prefix.len;

        const max_inner = out.len - prefix.len - suffix.len;
        var shown: usize = 0;
        while (shown < bytes.len and shown < max_inner) : (shown += 1) {
            const b = bytes[shown];
            out[pos] = if (b >= 32 and b <= 126) b else '.';
            pos += 1;
        }
        if (shown < bytes.len and pos + 3 <= out.len - suffix.len) {
            out[pos] = '.';
            out[pos + 1] = '.';
            out[pos + 2] = '.';
            pos += 3;
        }
        @memcpy(out[pos .. pos + suffix.len], suffix);
        pos += suffix.len;

        self.status = std.fmt.bufPrint(&self.status_buf, "{s}", .{out[0..pos]}) catch "read status error";
    }

    fn terminatorName(self: *const Model) []const u8 {
        return switch (self.terminator) {
            .bel => "BEL",
            .st => "ST",
        };
    }

    fn passthroughName(self: *const Model) []const u8 {
        return switch (self.passthrough) {
            .auto => "auto",
            .none => "none",
            .tmux => "tmux",
            .dcs => "dcs",
        };
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);

        var info_style = zz.Style{};
        info_style = info_style.fg(zz.Color.gray(16));
        info_style = info_style.inline_style(true);

        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);

        const title = title_style.render(ctx.allocator, "OSC 52 Clipboard Demo") catch "OSC 52 Clipboard Demo";
        const mode_line = std.fmt.allocPrint(ctx.allocator, "terminator={s}  passthrough={s}", .{
            self.terminatorName(),
            self.passthroughName(),
        }) catch "";
        const mode = info_style.render(ctx.allocator, mode_line) catch mode_line;
        const status = info_style.render(ctx.allocator, self.status) catch self.status;
        const hints = hint_style.render(ctx.allocator, "c copy(default)  g read(query)  paste shortcut sends Msg.paste  1/2/3/4 target(c/p/q/s)  t terminator  p passthrough  q quit") catch "";

        const content = std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}\n{s}\n\n{s}", .{
            title,
            mode,
            status,
            hints,
        }) catch "render error";

        return zz.place.place(ctx.allocator, ctx.width, ctx.height, .center, .middle, content) catch content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).initWithOptions(init.gpa, init.io, init.environ_map, .{
        .title = "ZigZag OSC 52 Clipboard",
        .osc52 = .{
            .enabled = true,
            .query_enabled = true,
            .target = .clipboard,
            .terminator = .bel,
            .passthrough = .auto,
            .max_bytes = 256 * 1024,
            .query_timeout_ms = 250,
            .max_read_bytes = 256 * 1024,
        },
    });
    defer program.deinit();

    try program.run();
}
