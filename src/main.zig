const std = @import("std");
const helpers = @import("./helper.zig");
const sdl3 = @cImport({
    @cInclude("SDL3/SDL.h");
});
const sprite = @import("sprite.zig");
const Texture = @import("texture.zig").Texture;
const Mat4 = @import("math.zig").Mat4;
const tiled = @import("tiled.zig");

var gDone: bool = false;
const WINDOW_WIDTH = 1920;
const WINDOW_HEIGH = 1080;
const tile_size = 32.0;
const MAX_X = 20;
const MAX_Y = 15;

const ZdbgError = error{
    SdlInitializationFailed,
    CreationFailed,
};
const DEBUG = false;

const SPRITE_COUNT = MAX_X * MAX_Y;

const Context = struct {
    device: *sdl3.SDL_GPUDevice,
    window: *sdl3.SDL_Window,
    present_mode: sdl3.SDL_GPUPresentMode,
    sprite_data_transfer_buffer: *sdl3.SDL_GPUTransferBuffer,
    sprite_data_buffer: *sdl3.SDL_GPUBuffer,
    render_pipeline: *sdl3.SDL_GPUGraphicsPipeline,

    texture: Texture,
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

pub fn main() !void {
    if (!sdl3.SDL_Init(sdl3.SDL_INIT_VIDEO | sdl3.SDL_INIT_EVENTS)) {
        std.debug.print("could not initialized SDL: {s}", .{sdl3.SDL_GetError()});
        return ZdbgError.SdlInitializationFailed;
    }
    sdl3.SDL_srand(0);

    var context: Context = undefined;
    try context_init(&context);
    // defer context_deinit(&context);

    context_set_swapchain_parameters(&context);

    {
        const vertex_shader = try context_load_shader(&context, "assets/shaders/sprite.vert.spv", 0, 1, 1, 0);
        const fragment_shader = try context_load_shader(&context, "assets/shaders/sprite.frag.spv", 1, 0, 0, 0);
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
        sdl3.SDL_ReleaseGPUShader(context.device, vertex_shader);
        sdl3.SDL_ReleaseGPUShader(context.device, fragment_shader);
    }

    context.texture = try Texture.create(context.device, "assets/spritesheets/roguelike_sheet.bmp", 16, 1);

    // load all tiles from map, layer = z
    // if tile value is 0, ignore it.
    const Gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true, .verbose_log = true });
    var gpa = Gpa{};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var sprite_instances = try std.ArrayList(sprite.Instance).initCapacity(gpa.allocator(), SPRITE_COUNT * 4);
    defer sprite_instances.deinit();

    {
        var map_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer map_arena.deinit();
        const map = try tiled.load_tiled_map(map_arena.allocator(), "assets/maps/map1.json");
        const sprite_sheet = &context.texture.sheet;
        for (map.layers, 0..) |layer, layer_z| {
            for (layer.data, 0..) |value, index| {
                if (value == 0) {
                    continue;
                }
                const x = index % layer.width;
                const y = index / layer.width;
                const tile_id = value - 1;
                const tile = sprite_sheet.get_index(tile_id);
                const tint = 1; //sdl3.SDL_randf();
                try sprite_instances.append(sprite.Instance{
                    .x = @as(f32, @floatFromInt(x)) * tile_size,
                    .y = @as(f32, @floatFromInt(y)) * tile_size,
                    .z = @as(f32, @floatFromInt(layer_z)),
                    .rotation = 0,
                    .w = tile_size,
                    .h = tile_size,
                    .tex = tile,
                    .r = tint,
                    .g = tint,
                    .b = tint,
                    .a = 1.0,
                });
            }
        }
    }

    const gpu_buffer_size: u32 = @intCast(sprite_instances.items.len * @sizeOf(sprite.Instance));
    context.sprite_data_transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(context.device, &sdl3.SDL_GPUTransferBufferCreateInfo{ .usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = gpu_buffer_size }) orelse return ZdbgError.CreationFailed;
    context.sprite_data_buffer = sdl3.SDL_CreateGPUBuffer(context.device, &sdl3.SDL_GPUBufferCreateInfo{
        .usage = sdl3.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
        .size = gpu_buffer_size,
    }) orelse return ZdbgError.CreationFailed;

    while (!gDone) {
        gDone = !update();
        try draw(&context, sprite_instances.items);
        sdl3.SDL_Delay(1);
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

fn draw(context: *Context, sprite_instances: []sprite.Instance) !void {
    const camera_matrix = Mat4.CreateOrthographicOffCenter(0, WINDOW_WIDTH, WINDOW_HEIGH, 0, 0, -1);

    const command_buffer = sdl3.SDL_AcquireGPUCommandBuffer(context.device) orelse return ZdbgError.CreationFailed;

    var swapchain_texture: ?*sdl3.SDL_GPUTexture = null;
    if (!sdl3.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, context.window, &swapchain_texture, null, null)) {
        std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}", .{sdl3.SDL_GetError()});
        return ZdbgError.CreationFailed;
    }

    if (swapchain_texture != null) {
        const data_ptr: [*]sprite.Instance = @alignCast(@ptrCast(sdl3.SDL_MapGPUTransferBuffer(context.device, context.sprite_data_transfer_buffer, true) orelse return ZdbgError.CreationFailed));
        for (sprite_instances, 0..) |sprite_instance, i| {
            data_ptr[i].x = sprite_instance.x;
            data_ptr[i].y = sprite_instance.y;
            data_ptr[i].z = sprite_instance.z;
            data_ptr[i].rotation = sprite_instance.rotation;
            data_ptr[i].w = sprite_instance.w;
            data_ptr[i].h = sprite_instance.h;
            data_ptr[i].tex.u = sprite_instance.tex.u;
            data_ptr[i].tex.v = sprite_instance.tex.v;
            data_ptr[i].tex.w = sprite_instance.tex.w;
            data_ptr[i].tex.h = sprite_instance.tex.h;
            data_ptr[i].r = sprite_instance.r;
            data_ptr[i].g = sprite_instance.g;
            data_ptr[i].b = sprite_instance.b;
            data_ptr[i].a = sprite_instance.a;
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
            .size = @intCast(sprite_instances.len * @sizeOf(sprite.Instance)),
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
            .texture = context.texture.texture,
            .sampler = context.texture.sampler,
        }, 1);
        sdl3.SDL_PushGPUVertexUniformData(command_buffer, 0, &camera_matrix, @sizeOf(Mat4));
        sdl3.SDL_DrawGPUPrimitives(render_pass, @intCast(sprite_instances.len * 6), 1, 0, 0);

        sdl3.SDL_EndGPURenderPass(render_pass);
    }
    if (!sdl3.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}", .{sdl3.SDL_GetError()});
    }
}
