const std = @import("std");
const sdl3 = @cImport({
    @cInclude("SDL3/SDL.h");
});

var gFrameBuffer: []u32 = undefined;
var gSDLWindow: *sdl3.SDL_Window = undefined;
var gSDLRenderer: *sdl3.SDL_Renderer = undefined;
var gSDLTexture: *sdl3.SDL_Texture = undefined;
var gDone: bool = false;
const WINDOW_WIDTH = 1920 / 2;
const WINDOW_HEIGH = 1080 / 2;

const ZdbgError = error{
    SdlInitializationFailed,
    CreationFailed,
};
const DEBUG = false;
const Context = struct { device: *sdl3.SDL_GPUDevice, window: *sdl3.SDL_Window };

fn context_init(context: *Context) !void {
    context.device = sdl3.SDL_CreateGPUDevice(sdl3.SDL_GPU_SHADERFORMAT_SPIRV | sdl3.SDL_GPU_SHADERFORMAT_DXIL | sdl3.SDL_GPU_SHADERFORMAT_MSL, DEBUG, null) orelse return ZdbgError.CreationFailed;
    context.window = sdl3.SDL_CreateWindow("SDL3 window", WINDOW_WIDTH, WINDOW_HEIGH, 0) orelse return ZdbgError.CreationFailed;

    if (!sdl3.SDL_ClaimWindowForGPUDevice(context.device, context.window)) {
        std.debug.print("SDL_ClaimWindowForGPUDevice failed", .{});
        return ZdbgError.CreationFailed;
    }
}

fn context_deinit(context: *Context) void {
    sdl3.SDL_ReleaseWindowFromGPUDevice(context.device, context.window);
    sdl3.SDL_DestroyWindow(context.window);
    sdl3.SDL_DestroyGPUDevice(context.device);
}

fn contains(comptime T: type, haystack: []T, needle: []T) bool {
    for (0..haystack.len) |start_index| {
        const sub_haystack = haystack[start_index..];
        if (std.mem.startsWith(T, sub_haystack, needle)) {
            return true;
        }
    }
    return false;
}

fn context_load_shader(context: *Context, filename: [*:0]const u8, sampler_count: u32, uniform_buffer_count: u32, storage_buffer_count: u32, storage_texture_count: u32) !*sdl3.SDL_GPUShader {
    var stage: sdl3.SDL_GPUShaderStage = undefined;
    if (contains(u8, filename, ".vert")) {
        stage = sdl3.SDL_GPU_SHADERSTAGE_VERTEX;
    } else if (contains(u8, filename, ".frag")) {
        stage = sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT;
    } else {
        std.debug.print("Invalid shader stage: '{}'", .{filename});
        return ZdbgError.CreationFailed;
    }

    const available_backend_formats = sdl3.SDL_GetGPUShaderFormats(context.device);
    var selected_format = sdl3.SDL_GPU_SHADERFORMAT_INVALID;

    if (available_backend_formats | sdl3.SDL_GPU_SHADERFORMAT_SPIRV) {
        selected_format = sdl3.SDL_GPU_SHADERFORMAT_SPIRV;
    } else {
        std.debug.debug("Unsupported backend shader format: {}", .{available_backend_formats});
        return ZdbgError.CreationFailed;
    }

    var code_size: usize = 0;
    const code = sdl3.SDL_LoadFile(filename, &code_size) orelse return ZdbgError.CreationFailed;
    defer sdl3.SDL_free(code);

    var shader_info = sdl3.SDL_GPUShaderCreateInfo{
        .code = code,
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
        std.debug.print("could not initialized SDL", .{});
        return ZdbgError.SdlInitializationFailed;
    }

    var context: Context = undefined;
    try context_init(&context);
    defer context_deinit(&context);

    while (!gDone) {
        gDone = !update();
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
