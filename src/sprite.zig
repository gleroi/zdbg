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
    tile_x: f32 = 5,
    tile_y: f32 = 0,
    margin: f32 = 1.0,

    pub fn get(sheet: *const Sheet, x: usize, y: usize) TextureTile {
        return TextureTile{
            .w = sheet.tile_size / sheet.width,
            .h = sheet.tile_size / sheet.height,
            .u = @as(f32, @floatFromInt(x)) * (sheet.tile_size + sheet.margin) / sheet.width,
            .v = @as(f32, @floatFromInt(y)) * (sheet.tile_size + sheet.margin) / sheet.height,
        };
    }
};
