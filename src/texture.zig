const std = @import("std");
const sdl3 = @cImport({
    @cInclude("SDL3/SDL.h");
});
const sprite = @import("sprite.zig");

pub const TextureError = error{ CreationFailed, ImageLoadFailed };

pub const Texture = struct {
    texture: *sdl3.SDL_GPUTexture,
    sampler: *sdl3.SDL_GPUSampler,
    sheet: sprite.Sheet,

    pub fn create(device: *sdl3.SDL_GPUDevice, filename: [:0]const u8, tile_size: usize, margin: usize) !Texture {
        var texture: Texture = undefined;

        const image_data = try load_bmp_image(filename);
        defer sdl3.SDL_DestroySurface(image_data);

        const texture_transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(device, &sdl3.SDL_GPUTransferBufferCreateInfo{
            .usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = @intCast(image_data.w * image_data.h * 4),
        }) orelse return TextureError.CreationFailed;

        {
            const texture_transfer_ptr = sdl3.SDL_MapGPUTransferBuffer(device, texture_transfer_buffer, false);
            _ = sdl3.SDL_memcpy(texture_transfer_ptr, image_data.pixels, @intCast(image_data.w * image_data.h * 4));
            sdl3.SDL_UnmapGPUTransferBuffer(device, texture_transfer_buffer);
        }

        texture.texture = sdl3.SDL_CreateGPUTexture(device, &sdl3.SDL_GPUTextureCreateInfo{
            .type = sdl3.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .width = @intCast(image_data.w),
            .height = @intCast(image_data.h),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .usage = sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        }) orelse return TextureError.CreationFailed;
        texture.sampler = sdl3.SDL_CreateGPUSampler(device, &sdl3.SDL_GPUSamplerCreateInfo{
            .min_filter = sdl3.SDL_GPU_FILTER_NEAREST,
            .mag_filter = sdl3.SDL_GPU_FILTER_NEAREST,
            .mipmap_mode = sdl3.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse return TextureError.CreationFailed;
        texture.sheet = sprite.Sheet{
            .width = @floatFromInt(image_data.w),
            .height = @floatFromInt(image_data.h),
            .tile_size = @floatFromInt(tile_size),
            .margin = @floatFromInt(margin),
        };

        const upload_command_buffer = sdl3.SDL_AcquireGPUCommandBuffer(device) orelse return TextureError.CreationFailed;
        defer sdl3.SDL_ReleaseGPUTransferBuffer(device, texture_transfer_buffer);

        {
            const copy_pass = sdl3.SDL_BeginGPUCopyPass(upload_command_buffer) orelse return TextureError.CreationFailed;
            defer sdl3.SDL_EndGPUCopyPass(copy_pass);

            sdl3.SDL_UploadToGPUTexture(copy_pass, &sdl3.SDL_GPUTextureTransferInfo{
                .transfer_buffer = texture_transfer_buffer,
                .offset = 0,
            }, &sdl3.SDL_GPUTextureRegion{
                .texture = texture.texture,
                .w = @intCast(image_data.w),
                .h = @intCast(image_data.h),
                .d = 1,
            }, false);
        }
        if (!sdl3.SDL_SubmitGPUCommandBuffer(upload_command_buffer)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}", .{sdl3.SDL_GetError()});
            return TextureError.CreationFailed;
        }
        return texture;
    }
};

fn load_bmp_image(filename: [:0]const u8) !*sdl3.SDL_Surface {
    var result: *sdl3.SDL_Surface = sdl3.SDL_LoadBMP(filename) orelse {
        std.debug.print("failed to load BMP {s}: {s}", .{ filename, sdl3.SDL_GetError() });
        return TextureError.ImageLoadFailed;
    };

    const format = sdl3.SDL_PIXELFORMAT_ABGR8888;
    if (result.format != format) {
        const next = sdl3.SDL_ConvertSurface(result, format);
        sdl3.SDL_DestroySurface(result);
        result = next;
    }
    return result;
}
