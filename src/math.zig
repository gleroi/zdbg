pub const Mat4 = extern struct {
    m11: f32,
    m12: f32,
    m13: f32,
    m14: f32,
    m21: f32,
    m22: f32,
    m23: f32,
    m24: f32,
    m31: f32,
    m32: f32,
    m33: f32,
    m34: f32,
    m41: f32,
    m42: f32,
    m43: f32,
    m44: f32,

    pub fn CreateOrthographicOffCenter(left: f32, right: f32, bottom: f32, top: f32, z_near_plane: f32, z_far_plane: f32) Mat4 {
        return Mat4{
            .m11 = 2.0 / (right - left),
            .m12 = 0,
            .m13 = 0,
            .m14 = 0,
            .m21 = 0,
            .m22 = 2.0 / (top - bottom),
            .m23 = 0,
            .m24 = 0,
            .m31 = 0,
            .m32 = 0,
            .m33 = 1.0 / (z_near_plane - z_far_plane),
            .m34 = 0,
            .m41 = (left + right) / (left - right),
            .m42 = (top + bottom) / (bottom - top),
            .m43 = z_near_plane / (z_near_plane - z_far_plane),
            .m44 = 1,
        };
    }
};
