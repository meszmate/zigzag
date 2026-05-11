//! ZigZag DevConsole Example
//! Streams app log events to dev_console.log AND to TCP port 7878.
//! In another terminal: `tail -f dev_console.log`  or  `nc localhost 7878`.

const std = @import("std");
const zz = @import("zigzag");

var console: zz.DevConsole = undefined;

const Model = struct {
    counter: u32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .counter = 0 };
        console.info("DevConsole example started — streaming on file + tcp/7878", .{});
        return .{ .every = 500 * std.time.ns_per_ms };
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => {
                self.counter += 1;
                console.debug("tick #{d}", .{self.counter});
                if (self.counter % 5 == 0) {
                    console.info("milestone: counter reached {d}", .{self.counter});
                }
                if (self.counter == 13) {
                    console.warn("unlucky number reached: {d}", .{self.counter});
                }
                if (self.counter % 17 == 0) {
                    console.err("simulated failure at counter={d}", .{self.counter});
                }
            },
            .key => |k| switch (k.key) {
                .char => |c| switch (c) {
                    'q' => {
                        console.info("user requested quit at counter={d}", .{self.counter});
                        return .quit;
                    },
                    ' ' => {
                        console.warn("manual warn from spacebar (counter={d})", .{self.counter});
                    },
                    'r' => {
                        console.info("counter reset by user (was {d})", .{self.counter});
                        self.counter = 0;
                    },
                    else => {},
                },
                .escape => return .quit,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const alloc = ctx.allocator;

        var title = zz.Style{};
        title = title.bold(true);
        title = title.fg(zz.Color.cyan);
        title = title.inline_style(true);
        const t = title.render(alloc, "DevConsole — log streamer") catch "";

        const body = std.fmt.allocPrint(
            alloc,
            \\Counter: {d}
            \\
            \\Two sinks are active:
            \\  • file ........ ./dev_console.log
            \\  • tcp .......... 127.0.0.1:7878
            \\
            \\Open another terminal and run one of:
            \\  $ tail -f dev_console.log
            \\  $ nc localhost 7878
            \\
            \\You'll see entries stream in as you press keys here.
        ,
            .{self.counter},
        ) catch "";

        var box = zz.Style{};
        box = box.borderAll(zz.Border.rounded);
        box = box.borderForeground(zz.Color.gray(8));
        box = box.paddingAll(1);
        const boxed = box.render(alloc, body) catch body;

        var help = zz.Style{};
        help = help.fg(zz.Color.gray(10));
        help = help.inline_style(true);
        const help_str = help.render(alloc, "space warn · r reset · q quit") catch "";

        return std.fmt.allocPrint(alloc, "{s}\n\n{s}\n\n{s}", .{ t, boxed, help_str }) catch "Error";
    }
};

pub fn main(init: std.process.Init) !void {
    console = zz.DevConsole.init(init.gpa, init.io);
    defer console.deinit();
    try console.addSink(.{ .file = "dev_console.log" });
    try console.addSink(.{ .tcp = .{ .host = "127.0.0.1", .port = 7878 } });

    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
