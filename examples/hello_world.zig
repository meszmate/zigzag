//! ZigZag Hello World Example
//! A minimal example showing the basic structure of a ZigZag application.
//!
//! Demonstrates image rendering features:
//!   'i' — draw image from file (auto protocol detection)
//!   'c' — cache image and place via Kitty virtual placement
//!   'z' — toggle z-index (render image behind text, Kitty only)
//!   'd' — delete all cached images
//!   'p' — cycle protocol: auto → kitty → iterm2 → sixel

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    image_supported: bool,
    image_visible: bool,
    image_attempted: bool,
    image_cached: bool,
    image_behind_text: bool,
    image_size_cells: u16,
    image_path: []const u8,
    protocol: zz.ImageProtocol,
    caps: zz.ImageCapabilities,

    const image_gap_lines: u16 = 1;
    const cache_id: u32 = 42;

    const ImageLayout = struct {
        size_cells: u16,
        row: u16,
        col: u16,
    };

    /// The message type for this model
    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        window_size: zz.msg.WindowSize,
    };

    /// Initialize the model
    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.* = .{
            .image_supported = ctx.supportsImages(),
            .image_visible = false,
            .image_attempted = false,
            .image_cached = false,
            .image_behind_text = false,
            .image_size_cells = 0,
            .image_path = "assets/cat.png",
            .protocol = .auto,
            .caps = ctx.getImageCapabilities(),
        };
        return .none;
    }

    /// Handle messages and update state
    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        // Draw image from file
                        'i' => {
                            self.image_attempted = true;
                            if (self.image_supported) {
                                self.image_visible = true;
                                return self.imageCommand(ctx);
                            }
                        },
                        // Cache image and display via Kitty virtual placement
                        'c' => {
                            if (self.caps.kitty_graphics) {
                                self.image_attempted = true;
                                self.image_visible = true;
                                self.image_cached = true;
                                const layout = self.computeImageLayout(ctx);
                                return .{ .batch = &.{
                                    .{ .cache_image = .{
                                        .source = .{ .file = self.image_path },
                                        .image_id = cache_id,
                                    } },
                                    .{ .place_cached_image = .{
                                        .image_id = cache_id,
                                        .width_cells = layout.size_cells,
                                        .height_cells = layout.size_cells,
                                        .placement = .top_left,
                                        .row = layout.row,
                                        .col = layout.col,
                                        .move_cursor = false,
                                    } },
                                } };
                            }
                        },
                        // Toggle z-index (behind text)
                        'z' => {
                            self.image_behind_text = !self.image_behind_text;
                            if (self.image_visible) {
                                return self.imageCommand(ctx);
                            }
                        },
                        // Delete cached images
                        'd' => {
                            if (self.image_cached) {
                                self.image_cached = false;
                                return .{ .delete_image = .all };
                            }
                        },
                        // Cycle protocol
                        'p' => {
                            self.protocol = switch (self.protocol) {
                                .auto => .kitty,
                                .kitty => .iterm2,
                                .iterm2 => .sixel,
                                .sixel => .auto,
                            };
                            if (self.image_visible) {
                                return self.imageCommand(ctx);
                            }
                        },
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
            .window_size => {
                if (self.image_supported and self.image_visible) {
                    return self.imageCommand(ctx);
                }
            },
        }
        return .none;
    }

    fn imageCommand(self: *Model, ctx: *const zz.Context) zz.Cmd(Msg) {
        const layout = self.computeImageLayout(ctx);
        return .{ .image_file = .{
            .path = self.image_path,
            .width_cells = layout.size_cells,
            .height_cells = layout.size_cells,
            .placement = .top_left,
            .row = layout.row,
            .col = layout.col,
            .move_cursor = false,
            .protocol = self.protocol,
            .z_index = if (self.image_behind_text) @as(?i32, -1) else null,
        } };
    }

    fn pickImageSize(_: *const Model, ctx: *const zz.Context) u16 {
        return @max(
            @as(u16, 6),
            @min(@as(u16, 16), @min(ctx.width -| 2, ctx.height -| 2)),
        );
    }

    fn textBlockLineCount(_: *const Model) u16 {
        // title + blank + subtitle + blank + hints (4) + status
        return 9;
    }

    fn computeImageLayout(self: *Model, ctx: *const zz.Context) ImageLayout {
        const size_cells = self.pickImageSize(ctx);
        self.image_size_cells = size_cells;

        const text_lines = self.textBlockLineCount();
        const slot_height = size_cells +| image_gap_lines;
        const container_height = text_lines +| slot_height;
        const container_top: u16 = if (ctx.height > container_height)
            (ctx.height - container_height) / 2
        else
            0;

        const row = @min(container_top +| text_lines +| image_gap_lines, ctx.height -| 1);
        const col: u16 = if (ctx.width > size_cells) (ctx.width - size_cells) / 2 else 0;

        return .{
            .size_cells = size_cells,
            .row = row,
            .col = @min(col, ctx.width -| 1),
        };
    }

    fn protocolName(self: *const Model) []const u8 {
        return switch (self.protocol) {
            .auto => "auto",
            .kitty => "kitty",
            .iterm2 => "iterm2",
            .sixel => "sixel",
        };
    }

    fn capsString(self: *const Model, allocator: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(allocator, "kitty={s} iterm2={s} sixel={s}", .{
            if (self.caps.kitty_graphics) "yes" else "no",
            if (self.caps.iterm2_inline_image) "yes" else "no",
            if (self.caps.sixel) "yes" else "no",
        }) catch "?";
    }

    /// Render the view
    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan);
        title_style = title_style.inline_style(true);

        var subtitle_style = zz.Style{};
        subtitle_style = subtitle_style.fg(zz.Color.gray(18));
        subtitle_style = subtitle_style.inline_style(true);

        var hint_style = zz.Style{};
        hint_style = hint_style.italic(true);
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);

        var image_hint_style = zz.Style{};
        image_hint_style = image_hint_style.fg(zz.Color.gray(16));
        image_hint_style = image_hint_style.inline_style(true);

        const title = title_style.render(ctx.allocator, "Hello, ZigZag!") catch "Hello, ZigZag!";
        const subtitle = subtitle_style.render(ctx.allocator, "A TUI library for Zig") catch "";
        const hint = hint_style.render(ctx.allocator, "Press 'q' to quit") catch "";

        const image_hint_text = if (self.image_supported)
            "'i' draw  'c' cache  'z' z-index  'd' delete  'p' protocol"
        else
            "Inline image protocol not detected in this terminal";
        const image_hint = image_hint_style.render(ctx.allocator, image_hint_text) catch image_hint_text;

        const caps_text = self.capsString(ctx.allocator);
        const caps_line = image_hint_style.render(ctx.allocator, caps_text) catch caps_text;

        const protocol_text = std.fmt.allocPrint(ctx.allocator, "protocol: {s}  z-index: {s}  cached: {s}", .{
            self.protocolName(),
            if (self.image_behind_text) "behind" else "normal",
            if (self.image_cached) "yes" else "no",
        }) catch "";
        const protocol_line = image_hint_style.render(ctx.allocator, protocol_text) catch protocol_text;

        const status_text = if (self.image_attempted and self.image_supported)
            "Image command sent (check assets/cat.png path)"
        else if (self.image_attempted and !self.image_supported)
            "Image skipped: unsupported terminal protocol"
        else
            "";
        const status = hint_style.render(ctx.allocator, status_text) catch status_text;

        // Get max width for centering
        const max_width = @max(
            zz.measure.width(title),
            @max(
                zz.measure.width(subtitle),
                @max(zz.measure.width(hint), @max(
                    zz.measure.width(image_hint),
                    @max(zz.measure.width(caps_line), @max(zz.measure.width(protocol_line), zz.measure.width(status))),
                )),
            ),
        );

        // Center each element
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_subtitle = zz.place.place(ctx.allocator, max_width, 1, .center, .top, subtitle) catch subtitle;
        const centered_hint = zz.place.place(ctx.allocator, max_width, 1, .center, .top, hint) catch hint;
        const centered_image_hint = zz.place.place(ctx.allocator, max_width, 1, .center, .top, image_hint) catch image_hint;
        const centered_caps = zz.place.place(ctx.allocator, max_width, 1, .center, .top, caps_line) catch caps_line;
        const centered_protocol = zz.place.place(ctx.allocator, max_width, 1, .center, .top, protocol_line) catch protocol_line;
        const centered_status = zz.place.place(ctx.allocator, max_width, 1, .center, .top, status) catch status;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}\n{s}\n{s}\n{s}\n{s}",
            .{ centered_title, centered_subtitle, centered_hint, centered_image_hint, centered_caps, centered_protocol, centered_status },
        ) catch "Error rendering view";

        if (self.image_supported and self.image_visible) {
            const image_size = if (self.image_size_cells > 0) self.image_size_cells else self.pickImageSize(ctx);
            const slot_height = @as(usize, image_size) + image_gap_lines;
            const container_width = @max(max_width, @as(usize, image_size));
            const text_height = zz.measure.height(content);

            const centered_text = zz.place.place(
                ctx.allocator,
                container_width,
                text_height,
                .center,
                .top,
                content,
            ) catch content;

            const image_slot = zz.place.place(
                ctx.allocator,
                container_width,
                slot_height,
                .left,
                .top,
                "",
            ) catch "";

            const container = zz.joinVertical(
                ctx.allocator,
                &.{ centered_text, image_slot },
            ) catch centered_text;

            return zz.place.place(
                ctx.allocator,
                ctx.width,
                ctx.height,
                .center,
                .middle,
                container,
            ) catch container;
        }

        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;
    }
};

pub fn main(init: std.process.Init) !void {
    var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
    defer program.deinit();

    try program.run();
}
