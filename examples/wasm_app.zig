//! ZigZag WASM Example
//! A minimal app designed to be compiled to WASM and run in a browser
//! with an xterm.js terminal. Build with: zig build wasm
//!
//! The JS host must provide these imports (module "zigzag"):
//!   - jsWrite(ptr, len)     - write bytes to the terminal
//!   - jsReadInput(ptr, len) - read pending input bytes
//!   - jsGetWidth()          - get terminal width in columns
//!   - jsGetHeight()         - get terminal height in rows
//!   - jsSetTitle(ptr, len)  - set the browser tab title
//!
//! And can call these exports:
//!   - zigzagResize()        - notify that the terminal was resized
//!   - zigzagInputBuffer()   - get pointer to the input ring buffer
//!   - zigzagPushInput(len)  - push input bytes into the ring buffer

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    count: i32,
    last_key: []const u8,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.count = 0;
        self.last_key = "none";
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => return .quit,
                    else => {
                        self.last_key = k.key.name();
                    },
                },
                .up => {
                    self.count += 1;
                    self.last_key = "up";
                },
                .down => {
                    self.count -= 1;
                    self.last_key = "down";
                },
                else => {
                    self.last_key = k.key.name();
                },
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_s = zz.Style{};
        title_s = title_s.bold(true);
        title_s = title_s.fg(zz.Color.cyan);
        title_s = title_s.inline_style(true);
        const title = title_s.render(ctx.allocator, "ZigZag WASM Demo") catch "ZigZag WASM";

        var count_s = zz.Style{};
        count_s = count_s.fg(zz.Color.green);
        count_s = count_s.bold(true);
        count_s = count_s.inline_style(true);
        const count_text = std.fmt.allocPrint(ctx.allocator, "{d}", .{self.count}) catch "?";
        const count_styled = count_s.render(ctx.allocator, count_text) catch count_text;

        const size_info = std.fmt.allocPrint(
            ctx.allocator,
            "Terminal: {d}x{d}",
            .{ ctx.width, ctx.height },
        ) catch "";

        var help_s = zz.Style{};
        help_s = help_s.fg(zz.Color.gray(12));
        help_s = help_s.inline_style(true);
        const help = help_s.render(ctx.allocator, "Up/Down: change count | q: quit") catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\nCount: {s}\nLast key: {s}\n{s}\n\n{s}",
            .{ title, count_styled, self.last_key, size_info, help },
        ) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
