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

test "Program.init context allocator is stable before start and can be rebound to arena" {
    var env_map: std.process.Environ.Map = .init(testing.allocator);
    defer env_map.deinit();
    var program = zz.Program(DummyModel).init(testing.allocator, testing.io, &env_map);
    defer program.deinit();

    const backing_ptr = @intFromPtr(testing.allocator.ptr);
    const init_context_allocator_ptr = @intFromPtr(program.context.allocator.ptr);
    try testing.expectEqual(backing_ptr, init_context_allocator_ptr);

    program.context.allocator = program.arena.allocator();
    const arena_ptr = @intFromPtr(&program.arena);
    const rebound_context_allocator_ptr = @intFromPtr(program.context.allocator.ptr);
    try testing.expectEqual(arena_ptr, rebound_context_allocator_ptr);
}
