//! Dev console — log streamer to a separate viewer.
//!
//! Solves a fundamental TUI debugging problem: stdout is owned by the
//! renderer, so `std.debug.print` would garble the screen. This module
//! routes structured log events to a separate sink so a developer can run
//! the TUI in one terminal and `tail -f` (or `nc`) the log stream in
//! another.
//!
//! Sinks supported:
//!
//!   * `.file`   — append to a log file. Pair with `tail -f path.log`.
//!   * `.tcp`    — listen on a TCP port. Pair with `nc localhost 9999`.
//!   * `.stderr` — write to stderr. Useful when stderr is redirected.
//!   * `.multi`  — fan-out to several sinks at once.
//!
//! Each event has a level (trace/debug/info/warn/err) and a timestamp.
//! The console is safe to call from any thread; writes are mutex-guarded.

const std = @import("std");
const Writer = std.Io.Writer;

pub const Level = enum {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn label(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
        };
    }

    pub fn rank(self: Level) u8 {
        return switch (self) {
            .trace => 0,
            .debug => 1,
            .info => 2,
            .warn => 3,
            .err => 4,
        };
    }
};

pub const SinkConfig = union(enum) {
    /// Append-mode log file at this path.
    file: []const u8,
    /// TCP listener on the given host:port. The dev console writes to *all*
    /// currently-connected clients; new connections receive future events.
    tcp: struct {
        host: []const u8 = "127.0.0.1",
        port: u16,
    },
    /// Write to stderr (file descriptor 2).
    stderr,
};

pub const DevConsole = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    sinks: std.array_list.Managed(Sink),
    mutex: std.Io.Mutex,
    /// Filter: events below this level are dropped.
    min_level: Level,
    /// Whether to prefix each line with a timestamp.
    show_timestamps: bool,

    const Sink = union(enum) {
        file: struct {
            file: std.Io.File,
            /// Append cursor. Only advanced after a successful flush — a failed
            /// write leaves it pointing at the truncated record's start, so the
            /// next entry overwrites the partial one. Not safe under concurrent
            /// writers to the same file.
            end_pos: u64,
        },
        tcp: *TcpSink,
        stderr,
    };

    const TcpSink = struct {
        io: std.Io,
        allocator: std.mem.Allocator,
        listen_address: std.Io.net.IpAddress,
        server: std.Io.net.Server,
        thread: std.Thread,
        connections: std.array_list.Managed(std.Io.net.Stream),
        mutex: std.Io.Mutex,
        /// Set to true to signal the accept thread to stop.
        stopping: std.atomic.Value(bool),
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) DevConsole {
        return .{
            .allocator = allocator,
            .io = io,
            .sinks = std.array_list.Managed(Sink).init(allocator),
            .mutex = .init,
            .min_level = .trace,
            .show_timestamps = true,
        };
    }

    pub fn deinit(self: *DevConsole) void {
        const io = self.io;
        for (self.sinks.items) |*sink| {
            switch (sink.*) {
                .file => |*f| f.file.close(io),
                .tcp => |tcp| {
                    tcp.stopping.store(true, .seq_cst);
                    // Wake the listener by connecting once.
                    if (tcp.listen_address.connect(io, .{ .mode = .stream })) |conn| {
                        conn.close(io);
                    } else |_| {}
                    tcp.thread.join();
                    tcp.server.deinit(io);
                    for (tcp.connections.items) |*c| c.close(io);
                    tcp.connections.deinit();
                    self.allocator.destroy(tcp);
                },
                .stderr => {},
            }
        }
        self.sinks.deinit();
    }

    pub fn setMinLevel(self: *DevConsole, lvl: Level) void {
        self.min_level = lvl;
    }

    pub fn addSink(self: *DevConsole, cfg: SinkConfig) !void {
        const io = self.io;
        switch (cfg) {
            .file => |path| {
                const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false });
                const end_pos = std.Io.File.length(file, io) catch 0;
                try self.sinks.append(.{ .file = .{ .file = file, .end_pos = end_pos } });
            },
            .stderr => {
                try self.sinks.append(.stderr);
            },
            .tcp => |t| {
                const addr = try std.Io.net.IpAddress.parse(t.host, t.port);
                var server = try addr.listen(io, .{ .reuse_address = true });
                errdefer server.deinit(io);

                const tcp_ptr = try self.allocator.create(TcpSink);
                errdefer self.allocator.destroy(tcp_ptr);
                tcp_ptr.* = .{
                    .io = io,
                    .allocator = self.allocator,
                    .listen_address = addr,
                    .server = server,
                    .thread = undefined,
                    .connections = std.array_list.Managed(std.Io.net.Stream).init(self.allocator),
                    .mutex = .init,
                    .stopping = std.atomic.Value(bool).init(false),
                };

                tcp_ptr.thread = try std.Thread.spawn(.{}, acceptLoop, .{tcp_ptr});
                try self.sinks.append(.{ .tcp = tcp_ptr });
            },
        }
    }

    fn acceptLoop(tcp: *TcpSink) void {
        const io = tcp.io;
        while (!tcp.stopping.load(.seq_cst)) {
            const conn = tcp.server.accept(io) catch break;
            if (tcp.stopping.load(.seq_cst)) {
                conn.close(io);
                break;
            }
            tcp.mutex.lockUncancelable(io);
            tcp.connections.append(conn) catch {
                conn.close(io);
                tcp.mutex.unlock(io);
                continue;
            };
            tcp.mutex.unlock(io);
        }
    }

    pub fn log(self: *DevConsole, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (level.rank() < self.min_level.rank()) return;

        // Build the line in a stack buffer (or heap-fall-back) once.
        var stack_buf: [4096]u8 = undefined;
        const line = self.format(stack_buf[0..], level, fmt, args) catch return;

        const io = self.io;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        for (self.sinks.items) |*sink| {
            switch (sink.*) {
                .file => |*f| {
                    var write_buf: [1024]u8 = undefined;
                    var w = f.file.writer(io, &write_buf);
                    w.seekTo(f.end_pos) catch continue;
                    w.interface.writeAll(line) catch continue;
                    w.interface.flush() catch continue;
                    f.end_pos = w.logicalPos();
                },
                .stderr => {
                    std.debug.print("{s}", .{line});
                },
                .tcp => |tcp| {
                    var keep = std.array_list.Managed(std.Io.net.Stream).init(self.allocator);
                    defer keep.deinit();

                    tcp.mutex.lockUncancelable(io);
                    defer tcp.mutex.unlock(io);
                    for (tcp.connections.items) |conn| {
                        var write_buf: [1024]u8 = undefined;
                        var w = conn.writer(io, &write_buf);
                        if (w.interface.writeAll(line)) |_| {
                            if (w.interface.flush()) |_| {
                                keep.append(conn) catch continue;
                            } else |_| {}
                        } else |_| {}
                    }
                    // Drop dead connections.
                    if (keep.items.len != tcp.connections.items.len) {
                        for (tcp.connections.items) |conn| {
                            var still_alive = false;
                            for (keep.items) |k| {
                                if (k.socket.handle == conn.socket.handle) {
                                    still_alive = true;
                                    break;
                                }
                            }
                            if (!still_alive) conn.close(io);
                        }
                        // `keep` is a subset of what was just cleared, so the
                        // capacity is already there and this cannot fail.
                        tcp.connections.clearRetainingCapacity();
                        tcp.connections.appendSliceAssumeCapacity(keep.items);
                    }
                },
            }
        }
    }

    fn format(self: *const DevConsole, buf: []u8, level: Level, comptime fmt: []const u8, args: anytype) ![]u8 {
        var writer: Writer = .fixed(buf);
        if (self.show_timestamps) {
            const now = std.Io.Timestamp.now(self.io, .real).toSeconds();
            const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
            const day = epoch.getDaySeconds();
            try writer.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{
                day.getHoursIntoDay(),
                day.getMinutesIntoHour(),
                day.getSecondsIntoMinute(),
            });
        }
        try writer.print("{s} ", .{level.label()});
        try writer.print(fmt, args);
        try writer.writeByte('\n');
        return writer.buffered();
    }

    // Convenience wrappers.
    pub fn trace(self: *DevConsole, comptime fmt: []const u8, args: anytype) void {
        self.log(.trace, fmt, args);
    }
    pub fn debug(self: *DevConsole, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }
    pub fn info(self: *DevConsole, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }
    pub fn warn(self: *DevConsole, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }
    pub fn err(self: *DevConsole, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "file sink writes formatted log lines" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var orig = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer orig.close(io);
    try std.process.setCurrentDir(io, tmp.dir);
    defer std.process.setCurrentDir(io, orig) catch {};

    var console = DevConsole.init(allocator, io);
    defer console.deinit();
    try console.addSink(.{ .file = "console.log" });

    console.info("hello {s}", .{"world"});
    console.warn("careful", .{});

    var buf: [4096]u8 = undefined;
    const contents = try std.Io.Dir.cwd().readFile(io, "console.log", &buf);

    try testing.expect(std.mem.indexOf(u8, contents, "hello world") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "INFO") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "WARN") != null);
}

test "min level filter" {
    const allocator = testing.allocator;
    const io = testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var orig = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer orig.close(io);
    try std.process.setCurrentDir(io, tmp.dir);
    defer std.process.setCurrentDir(io, orig) catch {};

    var console = DevConsole.init(allocator, io);
    defer console.deinit();
    try console.addSink(.{ .file = "filtered.log" });
    console.setMinLevel(.warn);

    console.debug("hidden", .{});
    console.warn("visible", .{});

    var buf: [4096]u8 = undefined;
    const contents = try std.Io.Dir.cwd().readFile(io, "filtered.log", &buf);
    try testing.expect(std.mem.indexOf(u8, contents, "hidden") == null);
    try testing.expect(std.mem.indexOf(u8, contents, "visible") != null);
}

test "level rank ordering" {
    try testing.expect(Level.trace.rank() < Level.err.rank());
    try testing.expect(Level.warn.rank() < Level.err.rank());
}
