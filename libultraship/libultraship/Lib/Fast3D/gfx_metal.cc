#include "gfx_metal.h"

#ifdef ENABLE_METAL

#ifndef _LANGUAGE_C
#define _LANGUAGE_C
#endif
#include "PR/ultra64/gbi.h"

#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>

#include "Lib/ImGui/backends/imgui_impl_metal.h"

// ImGui & SDL Wrappers

// this will be used to store the data created between gfx calls
static struct {
    SDL_Renderer* renderer;
    CA::MetalLayer* layer;
    MTL::CommandQueue* command_queue;
} metal;

void Metal_CreateLayer(SDL_Renderer* renderer) {
    metal.renderer = renderer;
    metal.layer = SDL_RenderGetMetalLayer(renderer);
    metal.layer->pixelFormat = PixelFormatBGRA8Unorm;
}

bool SDL2_InitForMetal(SDL_Window* window) {
    return ImGui_ImplSDL2_InitForMetal(window);

    // translate to C++ and store these for later use.
    // can we maybe use: SDL_Metal_GetLayer?
    metal.command_queue = metal.layer.device->newCommandQueue;
    MTL::RenderPassDescriptor* pass_descriptor = MTL::RenderPassDescriptor::alloc()->init();
}

bool Metal_Init() {
    return ImGui_ImplMetal_Init(layer.device);
}

void Metal_NewFrame() {
    int width, height;
    SDL_GetRendererOutputSize(metal.renderer, &width, &height);
    //metal.layer.drawableSize = CGSizeMake(width, height);

    // grab next drawable, grab commmand buffer from command queue.
    // grab render encoder & do something with it?

    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
}

void Metal_RenderDrawData(ImDrawData* draw_data) {
    ImGui_ImplMetal_RenderDrawData(draw_data, metal.commandBuffer, metal.renderEncoder);
}

// create metal renderer based on gfx_opengl.cpp

int gfx_metal_create_framebuffer(void) {}

void gfx_metal_end_frame(void) {
    renderEncoder->popDebugGroup();
    renderEncoder->endEncoding();

    commandBuffer.presentDrawable(layer.nextDrawable);
    commandBuffer.commit();
}

struct GfxRenderingAPI gfx_metal_api = {
    gfx_metal_get_clip_parameters,
    gfx_metal_unload_shader,
    gfx_metal_load_shader,
    gfx_metal_create_and_load_new_shader,
    gfx_metal_lookup_shader,
    gfx_metal_shader_get_info,
    gfx_metal_new_texture,
    gfx_metal_select_texture,
    gfx_metal_upload_texture,
    gfx_metal_set_sampler_parameters,
    gfx_metal_set_depth_test_and_mask,
    gfx_metal_set_zmode_decal,
    gfx_metal_set_viewport,
    gfx_metal_set_scissor,
    gfx_metal_set_use_alpha,
    gfx_metal_draw_triangles,
    gfx_metal_init,
    gfx_metal_on_resize,
    gfx_metal_start_frame,
    gfx_metal_end_frame,
    gfx_metal_finish_render,
    gfx_metal_create_framebuffer,
    gfx_metal_update_framebuffer_parameters,
    gfx_metal_start_draw_to_framebuffer,
    gfx_metal_clear_framebuffer,
    gfx_metal_resolve_msaa_color_buffer,
    gfx_metal_get_pixel_depth,
    gfx_metal_get_framebuffer_texture_id,
    gfx_metal_select_texture_fb,
    gfx_metal_delete_texture,
    gfx_metal_set_texture_filter,
    gfx_metal_get_texture_filter
}
#endif
