//! Sub-program support for embedding child models inside a parent.
//! Allows composing independent Model-Update-View units with message routing.

const std = @import("std");
const Context = @import("context.zig").Context;
const command = @import("command.zig");

/// A wrapper that embeds a child Model inside a parent, with message mapping.
///
/// - `ChildModel` must have `Msg`, `init`, `update`, `view` like a top-level model.
/// - `ParentMsg` is the parent's message type.
/// - The child's `.quit` command is converted to an optional parent message via `quit_msg`.
pub fn SubProgram(comptime ChildModel: type, comptime ParentMsg: type) type {
    comptime {
        if (!@hasDecl(ChildModel, "Msg")) @compileError("ChildModel must have a 'Msg' type");
        if (!@hasDecl(ChildModel, "init")) @compileError("ChildModel must have an 'init' function");
        if (!@hasDecl(ChildModel, "update")) @compileError("ChildModel must have an 'update' function");
        if (!@hasDecl(ChildModel, "view")) @compileError("ChildModel must have a 'view' function");
    }

    const ChildMsg = ChildModel.Msg;
    const ChildCmd = command.Cmd(ChildMsg);
    const ParentCmd = command.Cmd(ParentMsg);

    return struct {
        model: ChildModel = undefined,
        initialized: bool = false,
        /// Optional message to send to parent when child issues .quit.
        quit_msg: ?ParentMsg = null,

        const Self = @This();

        /// Initialize the child model.
        pub fn init(self: *Self, ctx: *Context) ParentCmd {
            const child_cmd = self.model.init(ctx);
            self.initialized = true;
            return self.translateCmd(child_cmd);
        }

        /// Forward a child message to the child's update, returning a parent command.
        pub fn update(self: *Self, child_msg: ChildMsg, ctx: *Context) ParentCmd {
            if (!self.initialized) return .none;
            const child_cmd = self.model.update(child_msg, ctx);
            return self.translateCmd(child_cmd);
        }

        /// Render the child model.
        pub fn view(self: *const Self, ctx: *const Context) []const u8 {
            if (!self.initialized) return "";
            return self.model.view(ctx);
        }

        /// Translate a child command into a parent command.
        fn translateCmd(self: *const Self, cmd: ChildCmd) ParentCmd {
            return switch (cmd) {
                .none => .none,
                .quit => if (self.quit_msg) |m| .{ .msg = m } else .none,
                .tick => |ns| .{ .tick = ns },
                .every => |ns| .{ .every = ns },
                .msg => |child_msg| blk: {
                    // Child-internal messages: re-dispatch is not possible at parent level,
                    // so we drop them. The parent should call sub.update() with child messages.
                    _ = child_msg;
                    break :blk .none;
                },
                .perform => .none, // Can't translate perform functions across types
                .suspend_process => .suspend_process,
                .enable_mouse => .enable_mouse,
                .disable_mouse => .disable_mouse,
                .show_cursor => .show_cursor,
                .hide_cursor => .hide_cursor,
                .enter_alt_screen => .enter_alt_screen,
                .exit_alt_screen => .exit_alt_screen,
                .set_title => |t| .{ .set_title = t },
                .println => |l| .{ .println = l },
                .repaint => .repaint,
                .batch => .none, // Complex: would need recursive translation
                .sequence => .none,
                .image_file => |img| .{ .image_file = img },
                .kitty_image_file => |img| .{ .kitty_image_file = img },
                .image_data => |img| .{ .image_data = img },
                .cache_image => |c| .{ .cache_image = c },
                .place_cached_image => |p| .{ .place_cached_image = p },
                .delete_image => |d| .{ .delete_image = d },
            };
        }
    };
}
