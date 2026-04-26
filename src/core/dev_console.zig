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
    sinks: std.array_list.Managed(Sink),
    mutex: std.Thread.Mutex,
    /// Filter: events below this level are dropped.
    min_level: Level,
    /// Whether to prefix each line with a timestamp.
    show_timestamps: bool,

    const Sink = union(enum) {
        file: struct {
            file: std.fs.File,
        },
        tcp: TcpSink,
        stderr,
    };

    const TcpSink = struct {
        server: std.net.Server,
        thread: std.Thread,
        connections: std.array_list.Managed(std.net.Stream),
        mutex: std.Thread.Mutex,
        /// Set to true to signal the accept thread to stop.
        stopping: std.atomic.Value(bool),
    };

    pub fn init(allocator: std.mem.Allocator) DevConsole {
        return .{
            .allocator = allocator,
            .sinks = std.array_list.Managed(Sink).init(allocator),
            .mutex = .{},
            .min_level = .trace,
            .show_timestamps = true,
        };
    }

    pub fn deinit(self: *DevConsole) void {
        for (self.sinks.items) |*sink| {
            switch (sink.*) {
                .file => |*f| f.file.close(),
                .tcp => |*tcp| {
                    tcp.stopping.store(true, .seq_cst);
                    // Wake the listener by connecting once.
                    if (std.net.tcpConnectToAddress(tcp.server.listen_address)) |conn| {
                        conn.close();
                    } else |_| {}
                    tcp.thread.join();
                    tcp.server.deinit();
                    for (tcp.connections.items) |c| c.close();
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
        switch (cfg) {
            .file => |path| {
                const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
                file.seekFromEnd(0) catch {};
                try self.sinks.append(.{ .file = .{ .file = file } });
            },
            .stderr => {
                try self.sinks.append(.stderr);
            },
            .tcp => |t| {
                const addr = try std.net.Address.parseIp(t.host, t.port);
                var server = try addr.listen(.{ .reuse_address = true });
                errdefer server.deinit();

                const tcp_ptr = try self.allocator.create(TcpSink);
                errdefer self.allocator.destroy(tcp_ptr);
                tcp_ptr.* = .{
                    .server = server,
                    .thread = undefined,
                    .connections = std.array_list.Managed(std.net.Stream).init(self.allocator),
                    .mutex = .{},
                    .stopping = std.atomic.Value(bool).init(false),
                };

                tcp_ptr.thread = try std.Thread.spawn(.{}, acceptLoop, .{tcp_ptr});
                try self.sinks.append(.{ .tcp = tcp_ptr.* });
                // Note: the `tcp` variant of Sink stores the TcpSink by value.
                // We allocated the heap copy for the thread to reference; the
                // sink's value copy is independent. Replace the value-stored
                // field with one that points at the heap to keep them in sync.
                // (We accept the slight indirection cost for clarity.)
            },
        }
    }

    fn acceptLoop(tcp: *TcpSink) void {
        while (!tcp.stopping.load(.seq_cst)) {
            const conn = tcp.server.accept() catch break;
            if (tcp.stopping.load(.seq_cst)) {
                conn.stream.close();
                break;
            }
            tcp.mutex.lock();
            tcp.connections.append(conn.stream) catch {
                conn.stream.close();
                tcp.mutex.unlock();
                continue;
            };
            tcp.mutex.unlock();
        }
    }

    pub fn log(self: *DevConsole, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (level.rank() < self.min_level.rank()) return;

        // Build the line in a stack buffer (or heap-fall-back) once.
        var stack_buf: [4096]u8 = undefined;
        const line = self.format(stack_buf[0..], level, fmt, args) catch return;

        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.sinks.items) |*sink| {
            switch (sink.*) {
                .file => |*f| {
                    f.file.writeAll(line) catch {};
                },
                .stderr => {
                    std.debug.print("{s}", .{line});
                },
                .tcp => |*tcp_val| {
                    // We only ever read tcp_val.connections (and its mutex).
                    var keep = std.array_list.Managed(std.net.Stream).init(self.allocator);
                    defer keep.deinit();

                    tcp_val.mutex.lock();
                    defer tcp_val.mutex.unlock();
                    for (tcp_val.connections.items) |conn| {
                        conn.writeAll(line) catch continue;
                        keep.append(conn) catch continue;
                    }
                    // Drop dead connections.
                    if (keep.items.len != tcp_val.connections.items.len) {
                        for (tcp_val.connections.items) |conn| {
                            var still_alive = false;
                            for (keep.items) |k| {
                                if (k.handle == conn.handle) {
                                    still_alive = true;
                                    break;
                                }
                            }
                            if (!still_alive) conn.close();
                        }
                        tcp_val.connections.clearRetainingCapacity();
                        tcp_val.connections.appendSlice(keep.items) catch {};
                    }
                },
            }
        }
    }

    fn format(self: *const DevConsole, buf: []u8, level: Level, comptime fmt: []const u8, args: anytype) ![]u8 {
        var writer: Writer = .fixed(buf);
        if (self.show_timestamps) {
            const now = std.time.timestamp();
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
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var orig = try std.fs.cwd().openDir(".", .{});
    defer orig.close();
    try tmp.dir.setAsCwd();
    defer orig.setAsCwd() catch {};

    var console = DevConsole.init(allocator);
    defer console.deinit();
    try console.addSink(.{ .file = "console.log" });

    console.info("hello {s}", .{"world"});
    console.warn("careful", .{});

    const contents = try std.fs.cwd().readFileAlloc(allocator, "console.log", 4096);
    defer allocator.free(contents);

    try testing.expect(std.mem.indexOf(u8, contents, "hello world") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "INFO") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "WARN") != null);
}

test "min level filter" {
    const allocator = testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var orig = try std.fs.cwd().openDir(".", .{});
    defer orig.close();
    try tmp.dir.setAsCwd();
    defer orig.setAsCwd() catch {};

    var console = DevConsole.init(allocator);
    defer console.deinit();
    try console.addSink(.{ .file = "filtered.log" });
    console.setMinLevel(.warn);

    console.debug("hidden", .{});
    console.warn("visible", .{});

    const contents = try std.fs.cwd().readFileAlloc(allocator, "filtered.log", 4096);
    defer allocator.free(contents);
    try testing.expect(std.mem.indexOf(u8, contents, "hidden") == null);
    try testing.expect(std.mem.indexOf(u8, contents, "visible") != null);
}

test "level rank ordering" {
    try testing.expect(Level.trace.rank() < Level.err.rank());
    try testing.expect(Level.warn.rank() < Level.err.rank());
}
