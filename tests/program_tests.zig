const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const DummyModel = struct {
    pub const Msg = union(enum) {
        nop: void,
    };

    pub fn init(_: *DummyModel, _: *zz.Context) zz.Cmd(Msg) {
        return .none;
    }

    pub fn update(_: *DummyModel, _: Msg, _: *zz.Context) zz.Cmd(Msg) {
        return .none;
    }

    pub fn view(_: *const DummyModel, _: *const zz.Context) []const u8 {
        return "";
    }
};

/// The same model written with fallible callbacks: no `catch "Error"` needed.
const FallibleModel = struct {
    count: i32 = 0,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *FallibleModel, _: *zz.Context) !zz.Cmd(Msg) {
        self.* = .{};
        return .none;
    }

    pub fn update(self: *FallibleModel, _: Msg, _: *zz.Context) !zz.Cmd(Msg) {
        self.count += 1;
        return .none;
    }

    pub fn view(self: *const FallibleModel, ctx: *const zz.Context) ![]const u8 {
        return std.fmt.allocPrint(ctx.allocator, "Count: {d}", .{self.count});
    }
};

test "Program accepts models whose callbacks return error unions" {
    // Forces the runtime's tick/render/dispatch paths to be analysed against a
    // fallible model, which is where the `try` has to line up.
    testing.refAllDecls(zz.Program(FallibleModel));
    testing.refAllDecls(zz.Program(DummyModel));

    try testing.expect(zz.model.returnsError(@TypeOf(FallibleModel.view)));
    try testing.expect(!zz.model.returnsError(@TypeOf(DummyModel.view)));
}

test "SubProgram mirrors the fallibility of its child" {
    const Fallible = zz.SubProgram(FallibleModel, FallibleModel.Msg);
    const Plain = zz.SubProgram(DummyModel, DummyModel.Msg);
    testing.refAllDecls(Fallible);
    testing.refAllDecls(Plain);

    try testing.expect(zz.model.returnsError(@TypeOf(Fallible.view)));
    try testing.expect(!zz.model.returnsError(@TypeOf(Plain.view)));
}

test "Program.init context allocator is stable before start and can be rebound to arena" {
    var env_map: std.process.Environ.Map = .init(testing.allocator);
    defer env_map.deinit();
    var program = zz.Program(DummyModel).init(
        testing.allocator,
        testing.io,
        &env_map,
    );
    defer program.deinit();

    const backing_ptr = @intFromPtr(testing.allocator.ptr);
    const init_context_allocator_ptr = @intFromPtr(program.context.allocator.ptr);
    try testing.expectEqual(backing_ptr, init_context_allocator_ptr);

    program.context.allocator = program.arena.allocator();
    const arena_ptr = @intFromPtr(&program.arena);
    const rebound_context_allocator_ptr = @intFromPtr(program.context.allocator.ptr);
    try testing.expectEqual(arena_ptr, rebound_context_allocator_ptr);
}
