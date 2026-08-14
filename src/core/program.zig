//! Program runtime for the ZigZag TUI framework.
//! Implements the Model-Update-View pattern with an event loop.

const std = @import("std");
const builtin = @import("builtin");
const Terminal = @import("../terminal/terminal.zig").Terminal;
const ansi = @import("../terminal/ansi.zig");
const keyboard = @import("../input/keyboard.zig");
const Context = @import("context.zig").Context;
const Options = @import("context.zig").Options;
const message = @import("message.zig");
const command = @import("command.zig");
const Logger = @import("log.zig").Logger;
const unicode = @import("../unicode.zig");
const Environment = @import("environment.zig").Environment;
const frame = @import("../terminal/frame.zig");
const model_contract = @import("model.zig");

pub const Cmd = command.Cmd;
pub const Msg = message;

const PendingImage = union(enum) {
    auto: command.ImageFile,
    kitty: command.KittyImageFile,
    data: command.ImageData,
    place_cached: command.PlaceCachedImage,
};

/// Bytes pulled from the terminal per read.
const read_chunk_size = 1024;

/// Upper bound on reads per tick, so a firehose on stdin cannot starve
/// rendering.
const max_reads_per_tick = 8;

/// Program runtime that manages the application lifecycle
pub fn Program(comptime Model: type) type {
    model_contract.validate(Model, "Model");

    // `init`, `update` and `view` may each return an error union; the runtime
    // propagates it instead of the model having to swallow it.
    const init_fallible = model_contract.returnsError(@TypeOf(Model.init));
    const update_fallible = model_contract.returnsError(@TypeOf(Model.update));
    const view_fallible = model_contract.returnsError(@TypeOf(Model.view));

    const UserMsg = Model.Msg;
    const UserCmd = Cmd(UserMsg);

    return struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        environment: Environment,
        arena: std.heap.ArenaAllocator,
        model: Model,
        terminal: ?Terminal,
        context: Context,
        options: Options,
        running: bool,
        /// Boot-clock epoch from which `last_frame_time` and `context.elapsed` are measured.
        /// `.boot` includes time the system was suspended, giving a monotonic reading
        /// without gaps on resume.
        clock_epoch: std.Io.Clock.Timestamp,
        last_frame_time: u64,
        /// Anchor for absolute frame pacing. Separate from `clock_epoch` so we can
        /// rebase after suspend/resume or a long-overrun frame without disturbing
        /// user-visible `context.elapsed` / `context.frame` (which `pending_tick`
        /// and `every` depend on).
        pacing_epoch: std.Io.Clock.Timestamp,
        pacing_frame_offset: u64,
        pending_tick: ?u64,
        /// `context.elapsed` captured when the active one-shot `pending_tick` was
        /// scheduled, so the delivered `Tick.delta` reflects the time since the
        /// tick was requested rather than the per-frame render delta.
        pending_tick_scheduled_at: u64,
        every_interval: ?u64,
        last_every_tick: u64,
        renderer: frame.Renderer,
        pending_image: ?PendingImage,
        logger: ?Logger,
        /// Retains escape sequences that a read cut in half.
        input_parser: keyboard.InputParser,

        /// Message filter function
        filter: ?*const fn (UserMsg) ?UserMsg,

        const Self = @This();

        /// Initialize the program.
        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            environ_map: *const std.process.Environ.Map,
        ) Self {
            return initWithOptions(allocator, io, environ_map, .{});
        }

        /// Initialize with custom options.
        pub fn initWithOptions(
            allocator: std.mem.Allocator,
            io: std.Io,
            environ_map: *const std.process.Environ.Map,
            options: Options,
        ) Self {
            const arena = std.heap.ArenaAllocator.init(allocator);
            const clock_epoch = std.Io.Clock.Timestamp.now(io, .boot);
            var self = Self{
                .allocator = allocator,
                .io = io,
                .environment = .fromEnvMap(environ_map),
                .arena = arena,
                .model = undefined,
                .terminal = null,
                .context = undefined,
                .options = options,
                .running = false,
                .clock_epoch = clock_epoch,
                .last_frame_time = 0,
                .pacing_epoch = clock_epoch,
                .pacing_frame_offset = 0,
                .pending_tick = null,
                .pending_tick_scheduled_at = 0,
                .every_interval = null,
                .last_every_tick = 0,
                .renderer = frame.Renderer.init(allocator, options.render_mode),
                .pending_image = null,
                .logger = null,
                .input_parser = .{},
                .filter = null,
            };

            // `self` is returned by value, so don't capture an arena allocator here.
            // It would point at this function's stack copy and dangle after return.
            self.context = Context.init(allocator, allocator, io, &self.environment);

            return self;
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            if (self.terminal) |*term| {
                term.deinit();
            }
            if (self.logger) |*l| {
                l.deinit();
            }
            self.renderer.deinit();
            self.arena.deinit();

            // Call model's deinit if it exists
            if (@hasDecl(Model, "deinit")) {
                self.model.deinit();
            }
        }

        /// Set a message filter function
        pub fn setFilter(self: *Self, f: ?*const fn (UserMsg) ?UserMsg) void {
            self.filter = f;
        }

        /// Run the program with the built-in event loop.
        /// For custom event loops, use `start()` + `tick()` instead.
        pub fn run(self: *Self) !void {
            try self.start();

            // Main event loop
            while (self.running) {
                try self.tick();
            }
        }

        /// Initialize the terminal and model without entering the event loop.
        /// After calling this, drive the program manually by calling `tick()`
        /// in your own loop. Check `isRunning()` to know when to stop.
        ///
        /// Example:
        /// ```
        /// try program.start();
        /// while (program.isRunning()) {
        ///     try program.tick();
        ///     // ... do other work between frames ...
        /// }
        /// ```
        pub fn start(self: *Self) !void {
            // Initialize logger if configured
            if (self.options.log_file) |log_path| {
                self.logger = Logger.init(self.io, log_path) catch null;
                if (self.logger != null) {
                    self.context._logger = &self.logger.?;
                }
            }

            // Initialize terminal
            self.terminal = try Terminal.init(self.io, &self.environment, .{
                .alt_screen = self.options.alt_screen,
                .hide_cursor = !self.options.cursor,
                .mouse = self.options.mouse,
                .bracketed_paste = self.options.bracketed_paste,
                .input = self.options.input,
                .output = self.options.output,
                .kitty_keyboard = self.options.kitty_keyboard,
                .osc52 = self.options.osc52,
            });

            self.input_parser.escape_timeout_ns =
                @as(u64, self.options.escape_timeout_ms) * std.time.ns_per_ms;

            // Set title if provided
            if (self.options.title) |title| {
                try self.terminal.?.setTitle(title);
            }

            // Get initial size
            const size = try self.terminal.?.getSize();
            self.context.width = size.cols;
            self.context.height = size.rows;
            self.context._terminal = &self.terminal.?;

            const width_caps = self.terminal.?.getUnicodeWidthCapabilities();
            const effective_width_strategy = self.resolveUnicodeWidthStrategy(width_caps.strategy);
            self.context.unicode_width_strategy = effective_width_strategy;
            self.context.terminal_mode_2027 = width_caps.mode_2027;
            self.context.kitty_text_sizing = width_caps.kitty_text_sizing;
            unicode.setWidthStrategy(effective_width_strategy);

            self.clock_epoch = std.Io.Clock.Timestamp.now(self.io, .boot);
            self.last_frame_time = self.elapsedNs();
            self.pacing_epoch = self.clock_epoch;
            self.pacing_frame_offset = 0;
            self.context.elapsed = 0;
            self.context.delta = 0;
            self.context.frame = 0;

            self.resetFrameAllocator();

            // Initialize the model
            const init_cmd = if (comptime init_fallible)
                try self.model.init(&self.context)
            else
                self.model.init(&self.context);
            try self.processCommand(init_cmd);

            self.running = true;
        }

        /// Returns true if the program is still running.
        pub fn isRunning(self: *const Self) bool {
            return self.running;
        }

        /// Execute a single frame: poll input, process events, render.
        pub fn tick(self: *Self) !void {
            const tick_start = self.elapsedNs();
            const actual_delta: u64 = if (self.context.frame == 0) 0 else tick_start - self.last_frame_time;
            self.last_frame_time = tick_start;

            self.context.delta = actual_delta;
            self.context.elapsed = tick_start;
            self.context.frame += 1;

            self.resetFrameAllocator();

            // Check for resize
            if (self.terminal.?.checkResize()) {
                const size = try self.terminal.?.getSize();
                self.context.width = size.cols;
                self.context.height = size.rows;

                // The terminal reflows on resize, so the previous frame no
                // longer describes what is on screen.
                self.renderer.invalidate();

                // Only send window_size message if the user model supports it
                if (@hasField(UserMsg, "window_size")) {
                    const cmd = try self.dispatchToModel(.{ .window_size = .{
                        .width = size.cols,
                        .height = size.rows,
                    } });
                    try self.processCommand(cmd);
                }
            }

            try self.drainInput();

            // Handle pending tick
            if (self.pending_tick) |tick_ns| {
                if (self.context.elapsed >= tick_ns) {
                    self.pending_tick = null;
                    // Deliver tick to user's update if Model.Msg has a tick variant
                    if (@hasField(UserMsg, "tick")) {
                        // Time since the tick was scheduled, not the frame delta.
                        const tick_delta = self.context.elapsed -| self.pending_tick_scheduled_at;
                        const user_msg = UserMsg{ .tick = .{
                            .timestamp = @intCast(tick_start),
                            .delta = tick_delta,
                        } };
                        const cmd = try self.dispatchToModel(user_msg);
                        try self.processCommand(cmd);
                    }
                }
            }

            // Handle repeating tick
            if (self.every_interval) |interval| {
                if (self.context.elapsed - self.last_every_tick >= interval) {
                    // Time since the previous repeating tick, not the frame delta.
                    const tick_delta = self.context.elapsed -| self.last_every_tick;
                    self.last_every_tick = self.context.elapsed;
                    if (@hasField(UserMsg, "tick")) {
                        const user_msg = UserMsg{ .tick = .{
                            .timestamp = @intCast(tick_start),
                            .delta = tick_delta,
                        } };
                        const cmd = try self.dispatchToModel(user_msg);
                        try self.processCommand(cmd);
                    }
                }
            }

            // Render
            try self.render();
            try self.flushPendingImage();

            // Pace at end of tick; first tick skips so initial paint is immediate.
            const min_frame_time_ns: u64 = if (self.options.fps > 0)
                @divFloor(std.time.ns_per_s, self.options.fps)
            else
                16_666_666; // ~60fps default
            const frames_since_anchor = self.context.frame - self.pacing_frame_offset;
            if (frames_since_anchor > 1) {
                const deadline_offset_ns: u64 = frames_since_anchor * min_frame_time_ns;
                // If we've fallen far behind the schedule (long-overrun frame, or
                // boot-clock advanced past the anchor while suspended), rebase the
                // anchor instead of burst-rendering frames to "catch up."
                const elapsed_since_anchor = self.pacingElapsedNs();
                if (elapsed_since_anchor > deadline_offset_ns + 4 * min_frame_time_ns) {
                    self.pacing_epoch = std.Io.Clock.Timestamp.now(self.io, .boot);
                    self.pacing_frame_offset = self.context.frame;
                } else {
                    // Absolute deadline so sleep overshoot doesn't compound.
                    const deadline: std.Io.Clock.Timestamp = self.pacing_epoch.addDuration(.{
                        .raw = .{ .nanoseconds = @intCast(deadline_offset_ns) },
                        .clock = .boot,
                    });
                    // A wait that fails (a cancelled or interrupted sleep)
                    // just means this frame is not paced; `unreachable` here
                    // would be undefined behaviour in a release build.
                    deadline.wait(self.io) catch {};
                }
            }
        }

        /// Read whatever the terminal has ready and dispatch the events it
        /// decodes into.
        ///
        /// Reads are non-blocking, so a burst that outgrows one buffer (paste,
        /// or a trackpad producing mouse reports faster than a frame) is
        /// picked up within the same tick instead of trickling in over the
        /// following ones. `InputParser` stitches sequences back together when
        /// a read lands in the middle of one.
        fn drainInput(self: *Self) !void {
            var input_buf: [read_chunk_size]u8 = undefined;

            var reads: usize = 0;
            while (reads < max_reads_per_tick) : (reads += 1) {
                const bytes_read = try self.terminal.?.readInput(&input_buf, 0);

                const events = try self.input_parser.feed(
                    self.context.allocator,
                    input_buf[0..bytes_read],
                    self.context.elapsed,
                );
                for (events) |event| {
                    const user_cmd = switch (event) {
                        .key => |k| try self.processKeyEvent(k),
                        .mouse => |m| try self.processMouseEvent(m),
                        .none => null,
                    };
                    if (user_cmd) |cmd| {
                        try self.processCommand(cmd);
                    }
                }

                // A short read means the terminal has nothing left for now.
                if (bytes_read < input_buf.len) break;
            }
        }

        /// Dispatch a message to the model, applying the filter if set
        fn dispatchToModel(self: *Self, user_msg: UserMsg) !UserCmd {
            const delivered = if (self.filter) |f|
                f(user_msg) orelse return .none
            else
                user_msg;

            return if (comptime update_fallible)
                try self.model.update(delivered, &self.context)
            else
                self.model.update(delivered, &self.context);
        }

        fn processKeyEvent(self: *Self, key: keyboard.KeyEvent) !?UserCmd {
            // Check for Ctrl+C to quit
            if (key.modifiers.ctrl) {
                switch (key.key) {
                    .char => |c| {
                        if (c == 'c') {
                            self.running = false;
                            return null;
                        }
                        // Handle Ctrl+Z for suspend
                        if (c == 'z' and self.options.suspend_enabled) {
                            self.performSuspend();
                            return null;
                        }
                    },
                    else => {},
                }
            }

            // Handle paste events
            if (key.key == .paste) {
                if (@hasField(UserMsg, "paste")) {
                    const user_msg = UserMsg{ .paste = key.key.paste };
                    return try self.dispatchToModel(user_msg);
                }
                // If model doesn't handle paste, send as individual key events
                if (@hasField(UserMsg, "key")) {
                    const user_msg = UserMsg{ .key = key };
                    return try self.dispatchToModel(user_msg);
                }
                return null;
            }

            // Convert to user message if Model.Msg has a key variant
            if (@hasField(UserMsg, "key")) {
                const user_msg = UserMsg{ .key = key };
                return try self.dispatchToModel(user_msg);
            }

            return null;
        }

        fn resolveUnicodeWidthStrategy(self: *const Self, detected: unicode.WidthStrategy) unicode.WidthStrategy {
            if (self.options.unicode_width_strategy) |forced| {
                return forced;
            }
            if (self.environment.unicode_width_override) |from_env| {
                return from_env;
            }
            return detected;
        }

        fn processMouseEvent(self: *Self, mouse_event: keyboard.MouseEvent) !?UserCmd {
            if (@hasField(UserMsg, "mouse")) {
                const user_msg = UserMsg{ .mouse = mouse_event };
                return try self.dispatchToModel(user_msg);
            }

            return null;
        }

        /// Perform suspend (Ctrl+Z) — POSIX only
        fn performSuspend(self: *Self) void {
            if (builtin.os.tag == .windows) return;

            // Cleanup terminal
            if (self.terminal) |*term| {
                term.cleanup();
            }

            // Raise SIGTSTP to suspend process. If the signal cannot be
            // raised we simply never stop; carrying on is better than dying.
            if (builtin.os.tag != .windows) {
                const posix = std.posix;
                _ = posix.raise(posix.SIG.TSTP) catch {};
            }

            // When we resume (after `fg`), re-setup terminal. A failure here
            // leaves the terminal in the shell's mode, which renders badly but
            // still runs -- and there is no caller to report it to.
            if (self.terminal) |*term| {
                term.setup() catch {};
            }

            // Whatever was mid-sequence when we stopped will never be
            // completed; drop it instead of merging it with post-resume input.
            self.input_parser.reset();

            // Avoid a large post-resume delta, and rebase the pacing anchor so we
            // don't burst-render to "catch up" the suspended interval. Advance the
            // user-visible clock to "now" so the timer checks below run against a
            // consistent post-resume `elapsed`.
            const resume_elapsed = self.elapsedNs();
            self.last_frame_time = resume_elapsed;
            self.context.elapsed = resume_elapsed;
            self.pacing_epoch = std.Io.Clock.Timestamp.now(self.io, .boot);
            self.pacing_frame_offset = self.context.frame;

            // Re-anchor the timers to "now" so the first post-resume Tick.delta is a
            // normal interval rather than the whole suspended span (mirrors the
            // last_frame_time and pacing resets above: we resume the cadence from
            // here instead of bursting to catch up the suspended time). The
            // repeating timer fires one interval after resume; an already-overdue
            // one-shot fires next with a ~zero delta. Anchoring to `resume_elapsed`
            // (== context.elapsed) also keeps the later `elapsed - last_every_tick`
            // subtraction from underflowing.
            self.last_every_tick = resume_elapsed;
            self.pending_tick_scheduled_at = resume_elapsed;

            // The terminal was handed back to the shell in between, so nothing
            // about the previous frame can be relied on.
            self.renderer.invalidate();

            // Dispatch resumed message if model supports it
            if (@hasField(UserMsg, "resumed")) {
                if (self.dispatchToModel(.{ .resumed = {} })) |cmd| {
                    self.processCommand(cmd) catch {};
                } else |_| {}
            }
        }

        fn processCommand(self: *Self, cmd: UserCmd) !void {
            switch (cmd) {
                .none => {},
                .quit => {
                    self.running = false;
                },
                .tick => |ns| {
                    self.pending_tick = self.context.elapsed + ns;
                    self.pending_tick_scheduled_at = self.context.elapsed;
                },
                .every => |ns| {
                    self.every_interval = ns;
                    self.last_every_tick = self.context.elapsed;
                },
                .batch => |cmds| {
                    for (cmds) |c| {
                        try self.processCommand(c);
                    }
                },
                .sequence => |cmds| {
                    for (cmds) |c| {
                        try self.processCommand(c);
                    }
                },
                .msg => |m| {
                    const new_cmd = try self.dispatchToModel(m);
                    try self.processCommand(new_cmd);
                },
                .perform => |func| {
                    if (func()) |m| {
                        const new_cmd = try self.dispatchToModel(m);
                        try self.processCommand(new_cmd);
                    }
                },
                .suspend_process => {
                    self.performSuspend();
                },
                .enable_mouse => {
                    if (self.terminal) |*term| {
                        try term.enableMouse();
                    }
                },
                .disable_mouse => {
                    if (self.terminal) |*term| {
                        try term.disableMouse();
                    }
                },
                .show_cursor => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_show);
                        try term.flush();
                    }
                },
                .hide_cursor => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_hide);
                        try term.flush();
                    }
                },
                .enter_alt_screen => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.alt_screen_enter);
                        try term.flush();
                    }
                    // Switching buffers swaps out everything on screen.
                    self.renderer.invalidate();
                },
                .exit_alt_screen => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.alt_screen_exit);
                        try term.flush();
                    }
                    self.renderer.invalidate();
                },
                .repaint => {
                    self.renderer.invalidate();
                },
                .set_title => |title| {
                    if (self.terminal) |*term| {
                        try term.setTitle(title);
                    }
                },
                .println => |line| {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_save);
                        try writer.writeAll(ansi.cursor_home);
                        try writer.writeAll(line);
                        try writer.writeAll("\n");
                        try writer.writeAll(ansi.cursor_restore);
                        try term.flush();
                    }
                    // This wrote over the frame area.
                    self.renderer.invalidate();
                },
                .image_file => |image| {
                    self.pending_image = .{ .auto = image };
                },
                .kitty_image_file => |image| {
                    self.pending_image = .{ .kitty = image };
                },
                .image_data => |image| {
                    self.pending_image = .{ .data = image };
                },
                .cache_image => |cache| {
                    if (self.terminal) |*term| {
                        // An unsupported protocol returns false rather than an
                        // error, so anything that does surface here is a real
                        // I/O failure, the same as in `flushPendingImage`.
                        switch (cache.source) {
                            .file => |path| {
                                _ = try term.transmitKittyImageFromFile(path, .{
                                    .image_id = cache.image_id,
                                    .format = @enumFromInt(@intFromEnum(cache.format)),
                                    .quiet = cache.quiet,
                                    .pixel_width = cache.pixel_width,
                                    .pixel_height = cache.pixel_height,
                                });
                            },
                            .data => |data| {
                                _ = try term.transmitKittyImage(data, .{
                                    .image_id = cache.image_id,
                                    .format = @enumFromInt(@intFromEnum(cache.format)),
                                    .quiet = cache.quiet,
                                    .pixel_width = cache.pixel_width,
                                    .pixel_height = cache.pixel_height,
                                });
                            },
                        }
                        try term.flush();
                    }
                },
                .place_cached_image => |place| {
                    self.pending_image = .{ .place_cached = place };
                },
                .delete_image => |del| {
                    if (self.terminal) |*term| {
                        const target: @import("../terminal/terminal.zig").KittyDeleteTarget = switch (del) {
                            .by_id => |id| .{ .by_id = id },
                            .by_placement => |bp| .{ .by_placement = .{ .image_id = bp.image_id, .placement_id = bp.placement_id } },
                            .all => .all,
                        };
                        _ = try term.deleteKittyImage(target);
                        try term.flush();
                    }
                },
            }
        }

        fn flushPendingImage(self: *Self) !void {
            const TerminalMod = @import("../terminal/terminal.zig");
            const pending = self.pending_image orelse return;
            self.pending_image = null;
            if (self.terminal) |*term| {
                switch (pending) {
                    .auto => |image| {
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_save);
                        }
                        try self.positionPendingImage(term, image);
                        const protocol: TerminalMod.ImageProtocol = switch (image.protocol) {
                            .auto => .auto,
                            .kitty => .kitty,
                            .iterm2 => .iterm2,
                            .sixel => .sixel,
                        };
                        _ = try term.drawImageFromFileWithProtocol(image.path, .{
                            .width_cells = image.width_cells,
                            .height_cells = image.height_cells,
                            .preserve_aspect_ratio = image.preserve_aspect_ratio,
                            .image_id = image.image_id,
                            .placement_id = image.placement_id,
                            .move_cursor = image.move_cursor,
                            .quiet = image.quiet,
                            .z_index = image.z_index,
                            .unicode_placeholder = image.unicode_placeholder,
                        }, protocol);
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_restore);
                        }
                    },
                    .kitty => |image| {
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_save);
                        }
                        try self.positionPendingImage(term, image);
                        _ = try term.drawKittyImageFromFile(image.path, .{
                            .width_cells = image.width_cells,
                            .height_cells = image.height_cells,
                            .image_id = image.image_id,
                            .placement_id = image.placement_id,
                            .move_cursor = image.move_cursor,
                            .quiet = image.quiet,
                            .z_index = image.z_index,
                            .unicode_placeholder = image.unicode_placeholder,
                        });
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_restore);
                        }
                    },
                    .data => |image| {
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_save);
                        }
                        try self.positionPendingImageData(term, image);
                        const protocol: TerminalMod.ImageProtocol = switch (image.protocol) {
                            .auto => .auto,
                            .kitty => .kitty,
                            .iterm2 => .iterm2,
                            .sixel => .sixel,
                        };
                        _ = try term.drawImageDataWithProtocol(image.data, .{
                            .format = @enumFromInt(@intFromEnum(image.format)),
                            .pixel_width = image.pixel_width,
                            .pixel_height = image.pixel_height,
                            .width_cells = image.width_cells,
                            .height_cells = image.height_cells,
                            .image_id = image.image_id,
                            .placement_id = image.placement_id,
                            .move_cursor = image.move_cursor,
                            .quiet = image.quiet,
                            .z_index = image.z_index,
                            .unicode_placeholder = image.unicode_placeholder,
                        }, protocol);
                        if (!image.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_restore);
                        }
                    },
                    .place_cached => |place| {
                        if (!place.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_save);
                        }
                        try self.positionPendingCachedImage(term, place);
                        _ = try term.placeKittyImage(.{
                            .image_id = place.image_id,
                            .placement_id = place.placement_id,
                            .width_cells = place.width_cells,
                            .height_cells = place.height_cells,
                            .move_cursor = place.move_cursor,
                            .quiet = place.quiet,
                            .z_index = place.z_index,
                            .unicode_placeholder = place.unicode_placeholder,
                        });
                        if (!place.move_cursor) {
                            try term.writer().writeAll(ansi.cursor_restore);
                        }
                    },
                }
                try term.flush();
                // An image covers cells the renderer thinks it owns; the next
                // frame repaints over it the way a full redraw always did.
                self.renderer.invalidate();
            }
        }

        fn positionPendingImage(self: *Self, term: *Terminal, image: command.ImageFile) !void {
            try self.positionByPlacement(term, image.placement, image.width_cells, image.height_cells, image.row, image.col, image.row_offset, image.col_offset);
        }

        fn positionPendingImageData(self: *Self, term: *Terminal, image: command.ImageData) !void {
            try self.positionByPlacement(term, image.placement, image.width_cells, image.height_cells, image.row, image.col, image.row_offset, image.col_offset);
        }

        fn positionPendingCachedImage(self: *Self, term: *Terminal, place: command.PlaceCachedImage) !void {
            try self.positionByPlacement(term, place.placement, place.width_cells, place.height_cells, place.row, place.col, place.row_offset, place.col_offset);
        }

        fn positionByPlacement(
            self: *Self,
            term: *Terminal,
            placement: command.ImagePlacement,
            width_cells: ?u16,
            height_cells: ?u16,
            opt_row: ?u16,
            opt_col: ?u16,
            row_offset: i16,
            col_offset: i16,
        ) !void {
            var row: u16 = 0;
            var col: u16 = 0;

            switch (placement) {
                .cursor => return,
                .top_left => {
                    row = 0;
                    col = 0;
                },
                .top_center => {
                    if (width_cells) |w_cells| {
                        const term_width = @as(usize, self.context.width);
                        const image_width = @as(usize, w_cells);
                        if (term_width > image_width) {
                            col = @intCast((term_width - image_width) / 2);
                        }
                    }
                    row = 0;
                },
                .center => {
                    if (width_cells) |w_cells| {
                        const term_width = @as(usize, self.context.width);
                        const image_width = @as(usize, w_cells);
                        if (term_width > image_width) {
                            col = @intCast((term_width - image_width) / 2);
                        }
                    }
                    if (height_cells) |h_cells| {
                        const term_height = @as(usize, self.context.height);
                        const image_height = @as(usize, h_cells);
                        if (term_height > image_height) {
                            row = @intCast((term_height - image_height) / 2);
                        }
                    }
                },
            }

            if (opt_row) |r| row = r;
            if (opt_col) |c| col = c;

            const max_row = if (height_cells) |h| self.context.height -| h else self.context.height -| 1;
            const max_col = if (width_cells) |w| self.context.width -| w else self.context.width -| 1;
            row = applySignedOffsetClamped(row, row_offset, max_row);
            col = applySignedOffsetClamped(col, col_offset, max_col);

            try term.moveTo(row, col);
        }

        fn applySignedOffsetClamped(base: u16, offset: i16, max: u16) u16 {
            const base_i32 = @as(i32, @intCast(base));
            const offset_i32 = @as(i32, offset);
            const max_i32 = @as(i32, @intCast(max));
            var value = base_i32 + offset_i32;
            if (value < 0) value = 0;
            if (value > max_i32) value = max_i32;
            return @intCast(value);
        }

        /// Nanoseconds elapsed on the boot clock since `clock_epoch`.
        fn elapsedNs(self: *const Self) u64 {
            const dur = self.clock_epoch.untilNow(self.io);
            const ns = dur.raw.nanoseconds;
            if (ns <= 0) return 0;
            return @intCast(ns);
        }

        /// Nanoseconds elapsed on the boot clock since `pacing_epoch`.
        fn pacingElapsedNs(self: *const Self) u64 {
            const dur = self.pacing_epoch.untilNow(self.io);
            const ns = dur.raw.nanoseconds;
            if (ns <= 0) return 0;
            return @intCast(ns);
        }

        fn resetFrameAllocator(self: *Self) void {
            _ = self.arena.reset(.retain_capacity);
            self.context.allocator = self.arena.allocator();
        }

        fn render(self: *Self) !void {
            const view_output = if (comptime view_fallible)
                try self.model.view(&self.context)
            else
                self.model.view(&self.context);

            const wrote = try self.renderer.render(
                self.terminal.?.writer(),
                view_output,
                .{ .width = self.context.width, .height = self.context.height },
            );
            if (wrote) try self.terminal.?.flush();
        }

        /// Repaint the whole frame on the next render, discarding what the
        /// renderer believes is on screen. Needed after anything else writes to
        /// the terminal.
        pub fn invalidate(self: *Self) void {
            self.renderer.invalidate();
        }

        /// Send a message to the model
        pub fn send(self: *Self, m: UserMsg) !void {
            const cmd = try self.dispatchToModel(m);
            try self.processCommand(cmd);
        }

        /// Stop the program
        pub fn quit(self: *Self) void {
            self.running = false;
        }
    };
}
