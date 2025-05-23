const assert = @import("std").debug.assert;
const std = @import("std");

pub const Instance = extern struct {
    x: f32,
    y: f32,
    z: f32,
    rotation: f32,
    w: f32,
    h: f32,
    padding_a: f32 = 0,
    padding_b: f32 = 0,
    tex: TextureTile,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const TextureTile = extern struct {
    u: f32 = 0.0,
    v: f32 = 0.0,
    w: f32 = 0.0,
    h: f32 = 0.0,
};

pub const Sheet = struct {
    width: f32 = 968.0,
    height: f32 = 526.0,
    tile_size: f32 = 16.0,
    margin: f32 = 1.0,

    pub fn get(sheet: Sheet, x: usize, y: usize) TextureTile {
        const tile_x = @as(f32, @floatFromInt(x)) * (sheet.tile_size + sheet.margin);
        const tile_y = @as(f32, @floatFromInt(y)) * (sheet.tile_size + sheet.margin);
        assert(tile_x < sheet.width);
        assert(tile_y < sheet.height);

        return TextureTile{
            .w = sheet.tile_size / sheet.width,
            .h = sheet.tile_size / sheet.height,
            .u = tile_x / sheet.width,
            .v = tile_y / sheet.height,
        };
    }

    pub fn get_index(sheet: Sheet, index: usize) TextureTile {
        const ftiles_by_width = std.math.round(sheet.width / (sheet.tile_size + sheet.margin));
        const tiles_by_width = @as(usize, @intFromFloat(ftiles_by_width));
        const y = index / tiles_by_width;
        const x = index % tiles_by_width;
        return sheet.get(x, y);
    }
};
