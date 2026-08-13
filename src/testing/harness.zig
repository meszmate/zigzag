//! Headless driver for a model, for tests.
//!
//! `Program` needs a terminal, which a test does not have. `Harness` runs the
//! same Model-Update-View cycle without one: send messages, render, assert on
//! the frame. Commands the runtime would hand to the terminal are recorded
//! instead of executed, so a test can check that pressing `q` really did
//! return `.quit` or that the title was set.
//!
//!     var h = try zz.testing.Harness(Model).init(testing.allocator, testing.io, .{});
//!     defer h.deinit();
//!
//!     try h.start();
//!     try h.pressChar('+');
//!     try testing.expectEqualStrings("Count: 1", try h.plainView());
//!
//! The frame allocator is reset on every `nextFrame`, exactly as the real
//! runtime resets it every tick, so a model that holds on to a frame-allocated
//! slice across frames shows up here rather than in production.

const std = @import("std");
const Context = @import("../core/context.zig").Context;
const Environment = @import("../core/environment.zig").Environment;
const command = @import("../core/command.zig");
const model_contract = @import("../core/model.zig");
const keys = @import("../input/keys.zig");
const mouse_input = @import("../input/mouse.zig");
const message = @import("../core/message.zig");

pub const Options = struct {
    width: u16 = 80,
    height: u16 = 24,
    /// Terminal environment the context is derived from. The default is a
    /// blank environment, which resolves to a conservative colour profile.
    environment: Environment = .{},
};

/// Drives `Model` through the Elm cycle with no terminal attached.
pub fn Harness(comptime Model: type) type {
    model_contract.validate(Model, "Model");

    const init_fallible = model_contract.returnsError(@TypeOf(Model.init));
    const update_fallible = model_contract.returnsError(@TypeOf(Model.update));
    const view_fallible = model_contract.returnsError(@TypeOf(Model.view));

    const UserMsg = Model.Msg;
    const UserCmd = command.Cmd(UserMsg);

    return struct {
        allocator: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,
        environment: Environment,
        context: Context,
        model: Model,

        /// Set once the model has returned `.quit`.
        quit: bool = false,
        /// Commands the runtime would have handed to the terminal, in order.
        effects: std.array_list.Managed(UserCmd),

        /// Pending one-shot timer, as a `context.elapsed` deadline.
        pending_tick: ?u64 = null,
        pending_tick_scheduled_at: u64 = 0,
        /// Repeating timer interval, if one was requested.
        every_interval: ?u64 = null,
        last_every_tick: u64 = 0,

        started: bool = false,

        const Self = @This();

        /// Everything a harness call can fail with: the model's own errors,
        /// plus allocation. Named explicitly because `send` and `process` call
        /// each other, and Zig cannot infer two error sets that depend on one
        /// another.
        pub const Error = std.mem.Allocator.Error ||
            error{InvalidUtf8} ||
            model_contract.ErrorSet(@TypeOf(Model.init)) ||
            model_contract.ErrorSet(@TypeOf(Model.update)) ||
            model_contract.ErrorSet(@TypeOf(Model.view));

        pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !Self {
            var self = Self{
                .allocator = allocator,
                .arena = std.heap.ArenaAllocator.init(allocator),
                .environment = options.environment,
                .context = undefined,
                .model = undefined,
                .effects = std.array_list.Managed(UserCmd).init(allocator),
            };

            // Bind the frame allocator lazily: `self` is returned by value, so
            // an arena allocator taken here would point at this stack copy.
            self.context = Context.init(allocator, allocator, io, &self.environment);
            self.context.width = options.width;
            self.context.height = options.height;

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.started and @hasDecl(Model, "deinit")) {
                self.model.deinit();
            }
            self.effects.deinit();
            self.arena.deinit();
        }

        /// Run `Model.init` and process the command it returns.
        pub fn start(self: *Self) Error!void {
            self.bindFrameAllocator();
            const cmd = if (comptime init_fallible)
                try self.model.init(&self.context)
            else
                self.model.init(&self.context);
            self.started = true;
            try self.process(cmd);
        }

        /// Begin a new frame: advances the clock by `delta_ns` and resets the
        /// frame allocator, dropping everything the previous frame allocated.
        pub fn nextFrame(self: *Self, delta_ns: u64) void {
            _ = self.arena.reset(.retain_capacity);
            self.bindFrameAllocator();
            self.context.frame += 1;
            self.context.delta = delta_ns;
            self.context.elapsed += delta_ns;
        }

        /// Deliver a message to `Model.update` and process the command it
        /// returns, including any messages that command produces.
        pub fn send(self: *Self, user_msg: UserMsg) Error!void {
            self.bindFrameAllocator();
            const cmd = if (comptime update_fallible)
                try self.model.update(user_msg, &self.context)
            else
                self.model.update(user_msg, &self.context);
            try self.process(cmd);
        }

        /// Send a key press. Requires `Msg` to have a `key` field.
        pub fn press(self: *Self, key: keys.KeyEvent) Error!void {
            comptime requireField("key", "press");
            try self.send(@unionInit(UserMsg, "key", key));
        }

        /// Send a bare character key press.
        pub fn pressChar(self: *Self, c: u21) Error!void {
            try self.press(.{ .key = .{ .char = c } });
        }

        /// Send each codepoint of `text` as its own key press.
        pub fn typeText(self: *Self, text: []const u8) Error!void {
            var it = (try std.unicode.Utf8View.init(text)).iterator();
            while (it.nextCodepoint()) |c| {
                try self.pressChar(c);
            }
        }

        /// Send a mouse event. Requires `Msg` to have a `mouse` field.
        pub fn mouse(self: *Self, event: mouse_input.MouseEvent) Error!void {
            comptime requireField("mouse", "mouse");
            try self.send(@unionInit(UserMsg, "mouse", event));
        }

        /// Resize the terminal. Sends `window_size` when `Msg` has that field.
        pub fn resize(self: *Self, width: u16, height: u16) Error!void {
            self.context.width = width;
            self.context.height = height;
            if (@hasField(UserMsg, "window_size")) {
                try self.send(@unionInit(UserMsg, "window_size", .{
                    .width = width,
                    .height = height,
                }));
            }
        }

        /// Advance time and deliver whatever timers came due, the way a run of
        /// the real event loop would. Requires `Msg` to have a `tick` field.
        pub fn advance(self: *Self, delta_ns: u64) Error!void {
            comptime requireField("tick", "advance");
            self.nextFrame(delta_ns);

            if (self.pending_tick) |deadline| {
                if (self.context.elapsed >= deadline) {
                    self.pending_tick = null;
                    try self.sendTick(self.context.elapsed -| self.pending_tick_scheduled_at);
                }
            }

            if (self.every_interval) |interval| {
                if (self.context.elapsed - self.last_every_tick >= interval) {
                    const tick_delta = self.context.elapsed -| self.last_every_tick;
                    self.last_every_tick = self.context.elapsed;
                    try self.sendTick(tick_delta);
                }
            }
        }

        /// Render the current frame. The result lives until the next
        /// `nextFrame`/`advance`.
        pub fn view(self: *Self) Error![]const u8 {
            self.bindFrameAllocator();
            return if (comptime view_fallible)
                try self.model.view(&self.context)
            else
                self.model.view(&self.context);
        }

        /// Render the current frame with ANSI escape sequences removed, which
        /// is usually what an assertion wants to look at.
        pub fn plainView(self: *Self) Error![]const u8 {
            return stripAnsi(self.context.allocator, try self.view());
        }

        /// Whether the view contains `needle`, ignoring styling.
        pub fn viewContains(self: *Self, needle: []const u8) Error!bool {
            return std.mem.indexOf(u8, try self.plainView(), needle) != null;
        }

        /// Whether the model has asked to quit.
        pub fn hasQuit(self: *const Self) bool {
            return self.quit;
        }

        /// Commands that were recorded rather than executed.
        pub fn recordedEffects(self: *const Self) []const UserCmd {
            return self.effects.items;
        }

        /// The most recent `.set_title`, if any.
        pub fn title(self: *const Self) ?[]const u8 {
            var i = self.effects.items.len;
            while (i > 0) {
                i -= 1;
                if (self.effects.items[i] == .set_title) return self.effects.items[i].set_title;
            }
            return null;
        }

        /// Forget the recorded effects, so a later assertion only sees what
        /// happened after this point.
        pub fn clearEffects(self: *Self) void {
            self.effects.clearRetainingCapacity();
        }

        fn sendTick(self: *Self, delta: u64) Error!void {
            try self.send(@unionInit(UserMsg, "tick", .{
                .timestamp = @intCast(self.context.elapsed),
                .delta = delta,
            }));
        }

        fn process(self: *Self, cmd: UserCmd) Error!void {
            switch (cmd) {
                .none => {},
                .quit => self.quit = true,
                .tick => |ns| {
                    self.pending_tick = self.context.elapsed + ns;
                    self.pending_tick_scheduled_at = self.context.elapsed;
                },
                .every => |ns| {
                    self.every_interval = ns;
                    self.last_every_tick = self.context.elapsed;
                },
                .batch, .sequence => |cmds| {
                    for (cmds) |c| try self.process(c);
                },
                .msg => |m| try self.send(m),
                .perform => |func| {
                    if (func()) |m| try self.send(m);
                },
                // Everything else only means something to a terminal.
                else => try self.effects.append(cmd),
            }
        }

        fn bindFrameAllocator(self: *Self) void {
            self.context.allocator = self.arena.allocator();
        }

        fn requireField(comptime name: []const u8, comptime method: []const u8) void {
            if (!@hasField(UserMsg, name)) {
                @compileError("Harness." ++ method ++ "() needs '" ++ @typeName(UserMsg) ++
                    "' to have a '" ++ name ++ "' field");
            }
        }
    };
}

/// Copy `input` with ANSI escape sequences removed.
pub fn stripAnsi(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = try std.array_list.Managed(u8).initCapacity(allocator, input.len);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] != 0x1b) {
            try out.append(input[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= input.len) break;

        switch (input[i]) {
            '[' => {
                i += 1;
                while (i < input.len) {
                    const b = input[i];
                    i += 1;
                    if (b >= 0x40 and b <= 0x7e) break;
                }
            },
            ']' => {
                i += 1;
                while (i < input.len) {
                    if (input[i] == 0x07) {
                        i += 1;
                        break;
                    }
                    if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            },
            else => i += 1,
        }
    }

    return out.toOwnedSlice();
}

test "stripAnsi drops CSI and OSC sequences" {
    const allocator = std.testing.allocator;
    const out = try stripAnsi(allocator, "\x1b[1;31mred\x1b[0m \x1b]0;title\x07tail");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("red tail", out);
}
