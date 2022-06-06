#include "gfx_metal.h"
#include "PR/ultra64/abi.h"

#ifdef ENABLE_METAL

#ifndef _LANGUAGE_C
#define _LANGUAGE_C
#endif
#include "PR/ultra64/gbi.h"

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "Lib/SDL/SDL2/SDL_render.h"
#include "Lib/ImGui/backends/imgui_impl_metal.h"
#include "gfx_cc.h"

static SDL_Renderer* _renderer;
static id<MTLCommandQueue> commandQueue;

static id<MTLRenderPipelineState> mPipelineState;
static id<MTLCommandBuffer> mCommandBuffer;
static id <MTLRenderCommandEncoder> mRenderEncoder;

static FilteringMode current_filter_mode = THREE_POINT;

static struct {
    NSMutableArray<id<MTLTexture>> *textures;
    int current_tile;
    uint32_t current_texture_ids[2];
} metal_ctx;

struct Vertex
{
    float position[3];
    float color[3];
};

// MARK: - ImGui & SDL Wrappers

void Metal_SetRenderer(SDL_Renderer* renderer) {
    _renderer = renderer;
}

bool Metal_Init() {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    bool result = ImGui_ImplMetal_Init(layer.device);
    if (!result) return result;

    commandQueue = [layer.device newCommandQueue];

    metal_ctx.textures = [[NSMutableArray alloc] init];

    return result;
}

void Metal_NewFrame() {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);

    int width, height;
    SDL_GetRendererOutputSize(_renderer, &width, &height);
    layer.drawableSize = CGSizeMake(width, height);

    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];

    if (mCommandBuffer != nil) {
        [mCommandBuffer release];
    }

    mCommandBuffer = [commandQueue commandBuffer];
    mCommandBuffer.label = @"SoHCommand";

    id<CAMetalDrawable> drawable = layer.nextDrawable;

    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;

    MTLClearColor clearCol;
    clearCol.red = 0.2;
    clearCol.green = 0.2;
    clearCol.blue = 0.2;
    clearCol.alpha = 1.0;
    renderPassDescriptor.colorAttachments[0].clearColor = clearCol;

    if(renderPassDescriptor != nil) {
        // Create a render command encoder so we can render into something
        mRenderEncoder = [mCommandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        mRenderEncoder.label = @"SoHRenderEncoder";

        [mRenderEncoder setTriangleFillMode: MTLTriangleFillModeFill];
        [mRenderEncoder setCullMode:MTLCullModeNone];
        [mRenderEncoder setFrontFacingWinding: MTLWindingClockwise];
    }

    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
}

void Metal_RenderDrawData(ImDrawData* draw_data) {
    ImGui_ImplMetal_RenderDrawData(draw_data, mCommandBuffer, currentRenderEncoder);
}

// MARK: - Metal Graphics Rendering API

static void gfx_metal_init(void) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
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
    CCFeatures cc_features;
    gfx_cc_get_features(shader_id0, shader_id1, &cc_features);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];

    if (cc_features.opt_alpha) {
        pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorZero;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskAll;
    } else {
        pipelineDescriptor.colorAttachments[0].blendingEnabled = NO;
        pipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskAll;
    }

    NSError* error = nil;
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    mPipelineState = [layer.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    if (!mPipelineState) {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        //  If the Metal API validation is enabled, we can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode)
        NSLog(@"Failed to created pipeline state, error %@", error);
        return;
    }

    [mRenderEncoder setRenderPipelineState: mPipelineState];
}

static struct ShaderProgram* gfx_metal_lookup_shader(uint64_t shader_id0, uint32_t shader_id1) {
    // TODO: implement
}

static void gfx_metal_shader_get_info(struct ShaderProgram *prg, uint8_t *num_inputs, bool used_textures[2]) {
    // TODO: implement
}

static uint32_t gfx_metal_new_texture(void) {
    return [metal_ctx.textures count];
}

static void gfx_metal_delete_texture(uint32_t texID) {
    // TODO: implement
}

static void gfx_metal_select_texture(int tile, uint32_t texture_id) {
    metal_ctx.current_tile = tile;
    metal_ctx.current_texture_ids[tile] = texture_id;
}

static void gfx_metal_upload_texture(const uint8_t *rgba32_buf, uint32_t width, uint32_t height) {
    // TODO: implement
}

static void gfx_metal_set_sampler_parameters(int tile, bool linear_filter, uint32_t cms, uint32_t cmt) {
    // TODO: implement
}

static void gfx_metal_set_depth_test_and_mask(bool depth_test, bool depth_mask) {
    MTLDepthStencilDescriptor* depthDescriptor = [MTLDepthStencilDescriptor new];
    [depthDescriptor setDepthWriteEnabled: depth_test || depth_mask ? YES : NO];
    [depthDescriptor setDepthCompareFunction: depth_test ? MTLCompareFunctionLess : MTLCompareFunctionAlways];

    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    id<MTLDepthStencilState> depthStencilState = [layer.device newDepthStencilStateWithDescriptor: depthDescriptor];
    [currentRenderEncoder setDepthStencilState:depthStencilState];
}

static void gfx_metal_set_zmode_decal(bool zmode_decal) {
    if (zmode_decal) {
        // glPolygonOffset(-2, -2);
        // glEnable(GL_POLYGON_OFFSET_FILL);
        [mRenderEncoder setDepthBias:0 slopeScale:-2 clamp:0];
    } else {
        // glPolygonOffset(0, 0);
        // glDisable(GL_POLYGON_OFFSET_FILL);
        [mRenderEncoder setDepthBias:0 slopeScale:0 clamp:0];
    }
}

static void gfx_metal_set_viewport(int x, int y, int width, int height) {
    [mRenderEncoder setViewport:(MTLViewport){x, y, width, height, 0.0, 1.0 }];
}

static void gfx_metal_set_scissor(int x, int y, int width, int height) {
    [mRenderEncoder setScissorRect:(MTLScissorRect){ x, y, width, height }];
}

static void gfx_metal_set_use_alpha(bool use_alpha) {
    // Already part of the pipeline state from shader info
}

static void gfx_metal_draw_triangles(float buf_vbo[], size_t buf_vbo_len, size_t buf_vbo_num_tris) {
    // TODO: implement
    [mRenderEncoder setVertexBuffer:mUniformBuffer offset:0 atIndex:1];
    [mRenderEncoder setVertexBuffer:mVertexBuffer offset:0 atIndex:0];


    // Create Index Buffer

    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    id <MTLBuffer> indexBuffer = [layer.device newBufferWithLength:sizeof(float) * buf_vbo_len
                                        options:MTLResourceOptionCPUCacheModeDefault];
    [indexBuffer setLabel:@"IBO"];
    memcpy(indexBuffer.contents, buf_vbo, sizeof(float) * buf_vbo_len);

    [mRenderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:3 * buf_vbo_num_tris indexType:MTLIndexTypeUInt32 indexBuffer:indexBuffer indexBufferOffset:0];
}

static void gfx_metal_on_resize(void) {
    // TODO: implement
}

static void gfx_metal_start_frame(void) {
    // TODO: implement
}

void gfx_metal_end_frame(void) {
    [mRenderEncoder endEncoding];

    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    [mCommandBuffer presentDrawable: [layer nextDrawable]];
    [mCommandBuffer commit];
}

static void gfx_metal_finish_render(void) {
    // TODO: implement
}

int gfx_metal_create_framebuffer(void) {
    // Create Vertex Buffer

//    mVertexBuffer = [mDevice newBufferWithLength:sizeof(Vertex) * 3
//                                         options:MTLResourceOptionCPUCacheModeDefault];
//    [mVertexBuffer setLabel:@"VBO"];
//    memcpy(mVertexBuffer.contents, mVertexBufferData, sizeof(Vertex) * 3)

    
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
    return current_filter_mode;
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
