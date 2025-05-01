const std = @import("std");
const helpers = @import("./helper.zig");
const sdl3 = @cImport({
    @cInclude("SDL3/SDL.h");
});

var gDone: bool = false;
const WINDOW_WIDTH = 640;
const WINDOW_HEIGH = 480;

const ZdbgError = error{
    SdlInitializationFailed,
    CreationFailed,
};
const DEBUG = false;

const SPRITE_COUNT = 8192;

const SpriteInstance = extern struct {
    x: f32,
    y: f32,
    z: f32,
    rotation: f32,
    w: f32,
    h: f32,
    padding_a: f32,
    padding_b: f32,
    tex_u: f32,
    tex_v: f32,
    tex_w: f32,
    tex_h: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const Context = struct {
    device: *sdl3.SDL_GPUDevice,
    window: *sdl3.SDL_Window,
    present_mode: sdl3.SDL_GPUPresentMode,
    sprite_data_transfer_buffer: *sdl3.SDL_GPUTransferBuffer,
    sprite_data_buffer: *sdl3.SDL_GPUBuffer,
    render_pipeline: *sdl3.SDL_GPUGraphicsPipeline,
    texture: *sdl3.SDL_GPUTexture,
    sampler: *sdl3.SDL_GPUSampler,
};

fn context_init(context: *Context) !void {
    context.device = sdl3.SDL_CreateGPUDevice(sdl3.SDL_GPU_SHADERFORMAT_SPIRV | sdl3.SDL_GPU_SHADERFORMAT_DXIL | sdl3.SDL_GPU_SHADERFORMAT_MSL, DEBUG, null) orelse return ZdbgError.CreationFailed;
    context.window = sdl3.SDL_CreateWindow("SDL3 window", WINDOW_WIDTH, WINDOW_HEIGH, 0) orelse return ZdbgError.CreationFailed;

    if (!sdl3.SDL_ClaimWindowForGPUDevice(context.device, context.window)) {
        std.debug.print("SDL_ClaimWindowForGPUDevice failed", .{});
        return ZdbgError.CreationFailed;
    }
    context.present_mode = sdl3.SDL_GPU_PRESENTMODE_VSYNC;
}

fn context_deinit(context: *Context) void {
    sdl3.SDL_ReleaseGPUGraphicsPipeline(context.device, context.render_pipeline);
    sdl3.SDL_ReleaseGPUSampler(context.device, context.sampler);
    sdl3.SDL_ReleaseGPUTexture(context.device, context.texture);
    sdl3.SDL_ReleaseGPUTransferBuffer(context.device, context.sprite_data_transfer_buffer);
    sdl3.SDL_ReleaseGPUBuffer(context.device, context.sprite_data_buffer);
    sdl3.SDL_ReleaseWindowFromGPUDevice(context.device, context.window);
    sdl3.SDL_DestroyWindow(context.window);
    sdl3.SDL_DestroyGPUDevice(context.device);
}

fn context_set_swapchain_parameters(context: *Context) void {
    if (sdl3.SDL_WindowSupportsGPUPresentMode(context.device, context.window, sdl3.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
        context.present_mode = sdl3.SDL_GPU_PRESENTMODE_IMMEDIATE;
    } else if (sdl3.SDL_WindowSupportsGPUPresentMode(context.device, context.window, sdl3.SDL_GPU_PRESENTMODE_MAILBOX)) {
        context.present_mode = sdl3.SDL_GPU_PRESENTMODE_MAILBOX;
    }
    if (!sdl3.SDL_SetGPUSwapchainParameters(context.device, context.window, sdl3.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, context.present_mode)) {
        const error_msg = sdl3.SDL_GetError();
        std.debug.print("SDL_SetGPUSwapchainParameters failed: {s}", .{error_msg});
    }
}

fn context_load_shader(context: *Context, filename: [*:0]const u8, sampler_count: u32, uniform_buffer_count: u32, storage_buffer_count: u32, storage_texture_count: u32) !*sdl3.SDL_GPUShader {
    var stage: sdl3.SDL_GPUShaderStage = undefined;
    if (helpers.contains(u8, filename, ".vert")) {
        stage = sdl3.SDL_GPU_SHADERSTAGE_VERTEX;
    } else if (helpers.contains(u8, filename, ".frag")) {
        stage = sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT;
    } else {
        std.debug.print("Invalid shader stage: '{s}'", .{filename});
        return ZdbgError.CreationFailed;
    }

    const available_backend_formats = sdl3.SDL_GetGPUShaderFormats(context.device);
    var selected_format: u32 = sdl3.SDL_GPU_SHADERFORMAT_INVALID;

    if (available_backend_formats | sdl3.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        selected_format = sdl3.SDL_GPU_SHADERFORMAT_SPIRV;
    } else {
        std.debug.print("Unsupported backend shader format: {}", .{available_backend_formats});
        return ZdbgError.CreationFailed;
    }

    var code_size: usize = 0;
    const code = sdl3.SDL_LoadFile(filename, &code_size);
    if (code == null) {
        std.debug.print("SDL_LoadFile failed for '{s}': {s}", .{ filename, sdl3.SDL_GetError() });
        return ZdbgError.CreationFailed;
    }
    defer sdl3.SDL_free(code);

    var shader_info = sdl3.SDL_GPUShaderCreateInfo{
        .code = @ptrCast(code),
        .code_size = code_size,
        .entrypoint = "main",
        .format = selected_format,
        .stage = stage,
        .num_samplers = sampler_count,
        .num_uniform_buffers = uniform_buffer_count,
        .num_storage_buffers = storage_buffer_count,
        .num_storage_textures = storage_texture_count,
    };
    const shader = sdl3.SDL_CreateGPUShader(context.device, &shader_info) orelse return ZdbgError.CreationFailed;
    return shader;
}

fn load_image(filename: [*:0]const u8) !*sdl3.SDL_Surface {
    var result: *sdl3.SDL_Surface = sdl3.SDL_LoadBMP(filename) orelse {
        std.debug.print("failed to load BMP {s}: {s}", .{ filename, sdl3.SDL_GetError() });
        return ZdbgError.CreationFailed;
    };

    const format = sdl3.SDL_PIXELFORMAT_ABGR8888;
    if (result.format != format) {
        const next = sdl3.SDL_ConvertSurface(result, format);
        sdl3.SDL_DestroySurface(result);
        result = next;
    }
    return result;
}

pub fn main() !void {
    if (!sdl3.SDL_Init(sdl3.SDL_INIT_VIDEO | sdl3.SDL_INIT_EVENTS)) {
        std.debug.print("could not initialized SDL: {s}", .{sdl3.SDL_GetError()});
        return ZdbgError.SdlInitializationFailed;
    }

    var context: Context = undefined;
    try context_init(&context);
    // defer context_deinit(&context);

    context_set_swapchain_parameters(&context);

    {
        const vertex_shader = try context_load_shader(&context, "assets/shaders/sprite.vert.spv", 1, 0, 0, 0);
        const fragment_shader = try context_load_shader(&context, "assets/shaders/sprite.frag.spv", 1, 0, 0, 0);
        defer sdl3.SDL_ReleaseGPUShader(context.device, vertex_shader);
        defer sdl3.SDL_ReleaseGPUShader(context.device, fragment_shader);

        context.render_pipeline = sdl3.SDL_CreateGPUGraphicsPipeline(context.device, &sdl3.SDL_GPUGraphicsPipelineCreateInfo{
            .target_info = sdl3.SDL_GPUGraphicsPipelineTargetInfo{ .num_color_targets = 1, .color_target_descriptions = &[_]sdl3.SDL_GPUColorTargetDescription{sdl3.SDL_GPUColorTargetDescription{ .format = sdl3.SDL_GetGPUSwapchainTextureFormat(context.device, context.window), .blend_state = sdl3.SDL_GPUColorTargetBlendState{
                .enable_blend = true,
                .color_blend_op = sdl3.SDL_GPU_BLENDOP_ADD,
                .alpha_blend_op = sdl3.SDL_GPU_BLENDOP_ADD,
                .src_color_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_color_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .src_alpha_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_alpha_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            } }} },
            .primitive_type = sdl3.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
        }) orelse return ZdbgError.CreationFailed;
    }

    const image_data = try load_image("assets/spritesheets/roguelike_sheet.bmp");
    const texture_transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(context.device, &sdl3.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(image_data.w * image_data.h * 4),
    }) orelse return ZdbgError.CreationFailed;

    {
        const texture_transfer_ptr = sdl3.SDL_MapGPUTransferBuffer(context.device, texture_transfer_buffer, false);
        defer sdl3.SDL_UnmapGPUTransferBuffer(context.device, texture_transfer_buffer);
        _ = sdl3.SDL_memcpy(texture_transfer_ptr, image_data.pixels, @intCast(image_data.w * image_data.h * 4));
    }

    context.texture = sdl3.SDL_CreateGPUTexture(context.device, &sdl3.SDL_GPUTextureCreateInfo{
        .type = sdl3.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .width = @intCast(image_data.w),
        .height = @intCast(image_data.h),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .usage = sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    }) orelse return ZdbgError.CreationFailed;
    context.sampler = sdl3.SDL_CreateGPUSampler(context.device, &sdl3.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl3.SDL_GPU_FILTER_NEAREST,
        .mag_filter = sdl3.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = sdl3.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    }) orelse return ZdbgError.CreationFailed;

    const upload_command_buffer = sdl3.SDL_AcquireGPUCommandBuffer(context.device) orelse return ZdbgError.CreationFailed;
    const copy_pass = sdl3.SDL_BeginGPUCopyPass(upload_command_buffer) orelse return ZdbgError.CreationFailed;

    sdl3.SDL_UploadToGPUTexture(copy_pass, &sdl3.SDL_GPUTextureTransferInfo{
        .transfer_buffer = texture_transfer_buffer,
        .offset = 0,
    }, &sdl3.SDL_GPUTextureRegion{
        .texture = context.texture,
        .w = @intCast(image_data.w),
        .h = @intCast(image_data.h),
        .d = 1,
    }, false);

    sdl3.SDL_EndGPUCopyPass(copy_pass);
    if (!sdl3.SDL_SubmitGPUCommandBuffer(upload_command_buffer)) {
        std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}", .{sdl3.SDL_GetError()});
    }
    sdl3.SDL_DestroySurface(image_data);
    sdl3.SDL_ReleaseGPUTransferBuffer(context.device, texture_transfer_buffer);

    context.sprite_data_transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(context.device, &sdl3.SDL_GPUTransferBufferCreateInfo{ .usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = SPRITE_COUNT * @sizeOf(SpriteInstance) }) orelse return ZdbgError.CreationFailed;
    context.sprite_data_buffer = sdl3.SDL_CreateGPUBuffer(context.device, &sdl3.SDL_GPUBufferCreateInfo{
        .usage = sdl3.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
        .size = SPRITE_COUNT * @sizeOf(SpriteInstance),
    }) orelse return ZdbgError.CreationFailed;

    while (!gDone) {
        gDone = !update();
        try draw(&context);
    }

    sdl3.SDL_Quit();
}

fn update() bool {
    var e = sdl3.SDL_Event{ .type = 0 };
    if (sdl3.SDL_PollEvent(&e)) {
        if (e.type == sdl3.SDL_EVENT_QUIT) {
            return false;
        }
        if (e.type == sdl3.SDL_EVENT_KEY_UP and e.key.key == sdl3.SDLK_ESCAPE) {
            return false;
        }
    }
    return true;
}

const Matrix4x4 = extern struct {
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

    fn CreateOrthographicOffCenter(left: f32, right: f32, bottom: f32, top: f32, z_near_plane: f32, z_far_plane: f32) Matrix4x4 {
        return Matrix4x4{
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

const uCoords = [4]f32{ 0.0, 0.5, 0.0, 0.5 };
const vCoords = [4]f32{ 0.0, 0.0, 0.5, 0.5 };

fn draw(context: *Context) !void {
    const camera_matrix = Matrix4x4.CreateOrthographicOffCenter(0, WINDOW_WIDTH, WINDOW_HEIGH, 0, 0, -1);

    const command_buffer = sdl3.SDL_AcquireGPUCommandBuffer(context.device) orelse return ZdbgError.CreationFailed;

    var swapchain_texture: ?*sdl3.SDL_GPUTexture = null;
    if (!sdl3.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, context.window, &swapchain_texture, null, null)) {
        std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}", .{sdl3.SDL_GetError()});
        return ZdbgError.CreationFailed;
    }

    if (swapchain_texture != null) {
        const data_ptr: [*]SpriteInstance = @alignCast(@ptrCast(sdl3.SDL_MapGPUTransferBuffer(context.device, context.sprite_data_transfer_buffer, true) orelse return ZdbgError.CreationFailed));
        for (0..SPRITE_COUNT) |i| {
            const ravioli: usize = @intCast(sdl3.SDL_rand(4));
            data_ptr[i].x = @floatFromInt(sdl3.SDL_rand(640));
            data_ptr[i].y = @floatFromInt(sdl3.SDL_rand(480));
            data_ptr[i].z = 0;
            data_ptr[i].rotation = sdl3.SDL_randf() * sdl3.SDL_PI_F * 2;
            data_ptr[i].w = 32;
            data_ptr[i].h = 32;
            data_ptr[i].tex_u = uCoords[ravioli];
            data_ptr[i].tex_v = vCoords[ravioli];
            data_ptr[i].tex_w = 0.5;
            data_ptr[i].tex_h = 0.5;
            data_ptr[i].r = 1.0;
            data_ptr[i].g = 1.0;
            data_ptr[i].b = 1.0;
            data_ptr[i].a = 1.0;
        }
        sdl3.SDL_UnmapGPUTransferBuffer(context.device, context.sprite_data_transfer_buffer);

        // upload instance data
        const copy_pass = sdl3.SDL_BeginGPUCopyPass(command_buffer) orelse return ZdbgError.CreationFailed;
        sdl3.SDL_UploadToGPUBuffer(copy_pass, &sdl3.SDL_GPUTransferBufferLocation{
            .transfer_buffer = context.sprite_data_transfer_buffer,
            .offset = 0,
        }, &sdl3.SDL_GPUBufferRegion{
            .buffer = context.sprite_data_buffer,
            .offset = 0,
            .size = SPRITE_COUNT * @sizeOf(SpriteInstance),
        }, true);
        sdl3.SDL_EndGPUCopyPass(copy_pass);

        // render sprites
        const render_pass = sdl3.SDL_BeginGPURenderPass(command_buffer, &sdl3.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .cycle = false,
            .load_op = sdl3.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl3.SDL_GPU_STOREOP_STORE,
            .clear_color = sdl3.SDL_FColor{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        }, 1, null) orelse return ZdbgError.CreationFailed;
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, context.render_pipeline);
        sdl3.SDL_BindGPUVertexStorageBuffers(render_pass, 0, &context.sprite_data_buffer, 1);
        sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, &sdl3.SDL_GPUTextureSamplerBinding{
            .texture = context.texture,
            .sampler = context.sampler,
        }, 1);
        sdl3.SDL_PushGPUVertexUniformData(command_buffer, 0, &camera_matrix, @sizeOf(Matrix4x4));
        sdl3.SDL_DrawGPUPrimitives(render_pass, SPRITE_COUNT * 6, 1, 0, 0);

        sdl3.SDL_EndGPURenderPass(render_pass);
    }
    if (!sdl3.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}", .{sdl3.SDL_GetError()});
    }
}
