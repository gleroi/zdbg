const std = @import("std");
const json = std.json;

pub const Layer = struct {
    height: u32,
    width: u32,
    data: []u32,
};
pub const Map = struct { layers: []Layer };

pub fn load_tiled_map(allocator: std.mem.Allocator, filename: []const u8) !Map {
    const data = try std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024);
    defer allocator.free(data);
    return (try json.parseFromSlice(Map, allocator, data, .{ .allocate = .alloc_always, .ignore_unknown_fields = true })).value;
}

test "load json map" {
    _ = try load_tiled_map(std.testing.allocator_instance, "assets/maps/map1.json");
}
