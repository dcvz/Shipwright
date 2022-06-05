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

static SDL_Renderer* _renderer;
static CA::MetalLayer* layer;
static MTL::CommandQueue* command_queue;
static MTL::RenderPassDescriptor* pass_descriptor;
static MTL::CommandBuffer* current_command_buffer;
static MTL::RenderCommandEncoder* current_render_encoder;

void Metal_SetRenderer(SDL_Renderer* renderer) {
    _renderer = renderer;
}

bool Metal_Init() {
    MTL::Device* device = layer->device();
    bool result = ImGui_ImplMetal_Init(device);
    if (!result) return result;

    command_queue = device->newCommandQueue();
    pass_descriptor = MTL::RenderPassDescriptor::alloc()->init();

    return result;
}

void Metal_NewFrame() {
    int width, height;
    SDL_GetRendererOutputSize(_renderer, &width, &height);
    layer->setWidth(width);
    layer->setHeight(height);

    CA::MetalDrawable* drawable = layer->nextDrawable();

    current_command_buffer = command_queue->commandBuffer();
    pass_descriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor(0.45, 0.55, 0.60, 1.00));
    pass_descriptor->colorAttachments()->object(0)->setTexture(drawable->texture());
    pass_descriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadAction::LoadActionClear);
    pass_descriptor->colorAttachments()->object(0)->setStoreAction(MTL::StoreAction::StoreActionStore);

    current_render_encoder = current_command_buffer->renderCommandEncoder(pass_descriptor);
    current_render_encoder->pushDebugGroup(NS::String::alloc()->init("SoH ImGui", NS::StringEncoding::UTF8StringEncoding));

    ImGui_ImplMetal_NewFrame(pass_descriptor);
}

void Metal_RenderDrawData(ImDrawData* draw_data) {
    ImGui_ImplMetal_RenderDrawData(draw_data, current_command_buffer, current_render_encoder);
}

// create metal renderer based on gfx_opengl.cpp

static void gfx_metal_init(void) {
    layer = (CA::MetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer->setPixelFormat(MTL::PixelFormat.PixelFormatBGRA8Unorm);
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
    current_render_encoder->popDebugGroup();
    current_render_encoder->endEncoding();

    current_command_buffer->presentDrawable(layer->nextDrawable());
    current_command_buffer->commit();
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
