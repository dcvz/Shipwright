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

#include "Lib/SDL/SDL2/SDL_render.h"
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
    metal.layer = (CA::MetalLayer*)SDL_RenderGetMetalLayer(renderer);
    metal.layer->pixelFormat = PixelFormatBGRA8Unorm;
}

bool SDL2_InitForMetal(SDL_Window* window) {
    return ImGui_ImplSDL2_InitForMetal(window);

    // translate to C++ and store these for later use.
    // can we maybe use: SDL_Metal_GetLayer?
    metal.command_queue = metal.layer->device->newCommandQueue;
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

static void gfx_metal_init(void) {
    // TODO: implement
}

static struct GfxClipParameters gfx_metal_get_clip_parameters() {
    // TODO: implement
    return { true, false };
}

static void gfx_metal_unload_shader(struct ShaderProgram *old_prg) {
    // TODO: implement
}

static void gfx_metal_load_shader(struct ShaderProgram *new_prg) {
    // TODO: implement
}

static struct ShaderProgram* gfx_metal_create_and_load_new_shader(uint64_t shader_id0, uint32_t shader_id1) {
    // TODO: implement
}

static struct ShaderProgram* gfx_metal_lookup_shader(uint64_t shader_id0, uint32_t shader_id1) {
    // TODO: implement
}

static void gfx_metal_shader_get_info(struct ShaderProgram *prg, uint8_t *num_inputs, bool used_textures[2]) {
    // TODO: implement
}

static uint32_t gfx_metal_new_texture(void) {
    // TODO: implement
}

static void gfx_metal_delete_texture(uint32_t texID) {
    // TODO: implement
}

static void gfx_metal_select_texture(int tile, uint32_t texture_id) {
    // TODO: implement
}

static void gfx_metal_upload_texture(const uint8_t *rgba32_buf, uint32_t width, uint32_t height) {
    // TODO: implement
}

static void gfx_metal_set_sampler_parameters(int tile, bool linear_filter, uint32_t cms, uint32_t cmt) {
    // TODO: implement
}

static void gfx_metal_set_depth_test_and_mask(bool depth_test, bool depth_mask) {
    // TODO: implement
}

static void gfx_metal_set_zmode_decal(bool zmode_decal) {
    // TODO: implement
}

static void gfx_metal_set_viewport(int x, int y, int width, int height) {
    // TODO: implement
}

static void gfx_metal_set_scissor(int x, int y, int width, int height) {
    // TODO: implement
}

static void gfx_metal_set_use_alpha(bool use_alpha) {
    // TODO: implement
}

static void gfx_metal_draw_triangles(float buf_vbo[], size_t buf_vbo_len, size_t buf_vbo_num_tris) {
    // TODO: implement
}

static void gfx_metal_on_resize(void) {
    // TODO: implement
}

static void gfx_metal_start_frame(void) {
    // TODO: implement
}

void gfx_metal_end_frame(void) {
    // TODO: implement
    renderEncoder->popDebugGroup();
    renderEncoder->endEncoding();

    commandBuffer.presentDrawable(layer.nextDrawable);
    commandBuffer.commit();
}

static void gfx_metal_finish_render(void) {
    // TODO: implement
}

int gfx_metal_create_framebuffer(void) {
    // TODO: implement
}

static void gfx_metal_update_framebuffer_parameters(int fb_id, uint32_t width, uint32_t height, uint32_t msaa_level, bool opengl_invert_y, bool render_target, bool has_depth_buffer, bool can_extract_depth) {
    // TODO: implement
}

void gfx_metal_start_draw_to_framebuffer(int fb_id, float noise_scale) {
    // TODO: implement
}

void gfx_metal_clear_framebuffer(void) {
    // TODO: implement
}

void gfx_metal_resolve_msaa_color_buffer(int fb_id_target, int fb_id_source) {
    // TODO: implement
}

std::map<std::pair<float, float>, uint16_t> gfx_metal_get_pixel_depth(int fb_id, const std::set<std::pair<float, float>>& coordinates) {
    // TODO: implement
}

void *gfx_metal_get_framebuffer_texture_id(int fb_id) {
    // TODO: implement
}

void gfx_metal_select_texture_fb(int fb_id) {
    // TODO: implement
}

void gfx_metal_set_texture_filter(FilteringMode mode) {
    // TODO: implement
}

FilteringMode gfx_metal_get_texture_filter(void) {
    // TODO: implement
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
};
#endif
