#include "gfx_metal.h"

#ifdef ENABLE_METAL

#include <vector>

#ifndef _LANGUAGE_C
#define _LANGUAGE_C
#endif
#include "PR/ultra64/gbi.h"
#include "PR/ultra64/abi.h"

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "Lib/SDL/SDL2/SDL_render.h"
#include "Lib/ImGui/backends/imgui_impl_metal.h"
#include "gfx_cc.h"
#include "gfx_rendering_api.h"

static SDL_Renderer* _renderer;
static id<MTLDevice> mDevice;
static id<MTLCommandQueue> commandQueue;

static id<MTLRenderPipelineState> mPipelineState;
static id<MTLCommandBuffer> mCommandBuffer;
static id <MTLRenderCommandEncoder> mRenderEncoder;

static id<MTLBuffer> uniformBuffer;

struct ShaderProgramMetal {
    uint8_t num_inputs;
    uint8_t num_floats;
    bool used_textures[2];
};

struct GfxTexture {
    id<MTLTexture> texture;
    id<MTLSamplerState> sampler;
    bool linear_filtering;
};

static struct {
    std::map<std::pair<uint64_t, uint32_t>, struct ShaderProgramMetal> shader_program_pool;

    std::vector<GfxTexture> textures;
    int current_tile;
    uint32_t current_texture_ids[2];

    // Current state
    struct ShaderProgramMetal *shader_program;
    FilteringMode current_filter_mode = THREE_POINT;

    FrameUniforms frame_uniforms;
} metal_ctx;

// MARK: - Helpers

static void append_line(char *buf, size_t *len, const char *str) {
    while (*str != '\0') buf[(*len)++] = *str++;
    buf[(*len)++] = '\n';
}

// MARK: - ImGui & SDL Wrappers

void Metal_SetRenderer(SDL_Renderer* renderer) {
    _renderer = renderer;
}

bool Metal_Init() {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    mDevice = layer.device;
    bool result = ImGui_ImplMetal_Init(mDevice);
    if (!result) return result;

    commandQueue = [mDevice newCommandQueue];

    return result;
}

void Metal_NewFrame() {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);

    int width, height;
    SDL_GetRendererOutputSize(_renderer, &width, &height);
    layer.drawableSize = CGSizeMake(width, height);

    mCommandBuffer = [commandQueue commandBuffer];
    mCommandBuffer.label = @"SoHCommand";

    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];

    id<CAMetalDrawable> drawable = [layer nextDrawable];
    //NSAssert(drawable != nil, @"Could not retrieve drawable from Metal layer");

    MTLClearColor clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1.0);
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor = clearColor;

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
    ImGui_ImplMetal_RenderDrawData(draw_data, mCommandBuffer, mRenderEncoder);

    [mRenderEncoder endEncoding];
}

// MARK: - Metal Graphics Rendering API

static void gfx_metal_init(void) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
}

static struct GfxClipParameters gfx_metal_get_clip_parameters() {
    return { true, false };
}

static void gfx_metal_unload_shader(struct ShaderProgram *old_prg) {}

static void gfx_metal_load_shader(struct ShaderProgram *new_prg) {
    metal_ctx.shader_program = (struct ShaderProgramMetal *)new_prg;
}

static struct ShaderProgram* gfx_metal_create_and_load_new_shader(uint64_t shader_id0, uint32_t shader_id1) {
    CCFeatures cc_features;
    gfx_cc_get_features(shader_id0, shader_id1, &cc_features);

    char buf[4096];
    size_t len = 0;
    size_t num_floats = 4;
    int vertexIndex = 0;

    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];

    append_line(buf, &len, "#include <metal_stdlib>");
    append_line(buf, &len, "using namespace metal;");

    // Uniforms struct
    append_line(buf, &len, "struct FrameUniforms {");
    append_line(buf, &len, "    uint noise_frame;");
    append_line(buf, &len, "    float noise_scale;");
    append_line(buf, &len, "};");
    // end uniforms struct

    // Vertex struct
    append_line(buf, &len, "struct Vertex {");
    len += sprintf(buf + len, "    float4 position [[attribute(%d)]];\n", vertexIndex);
    vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
    vertexDescriptor.attributes[vertexIndex++].offset = 0;

    for (int i = 0; i < 2; i++) {
        if (cc_features.used_textures[i]) {
            len += sprintf(buf + len, "    float2 texCoord%d [[attribute(%d)]];\n", i, vertexIndex);
            vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat2;
            vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
            vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
            num_floats += 2;
            for (int j = 0; j < 2; j++) {
                if (cc_features.clamp[i][j]) {
                    len += sprintf(buf + len, "    float texClamp%s%d [[attribute(%d)]];\n", j == 0 ? "S" : "T", i, vertexIndex);
                    vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat;
                    vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
                    vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
                    num_floats += 1;
                }
            }
        }
    }
    if (cc_features.opt_fog) {
        len += sprintf(buf + len, "    float4 fog [[attribute(%d)]];", vertexIndex);
        vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += 4;
    }
    if (cc_features.opt_grayscale) {
        len += sprintf(buf + len, "    float4 grayscale [[attribute(%d)]];", vertexIndex);
        vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += 4;
    }
    for (int i = 0; i < cc_features.num_inputs; i++) {
        len += sprintf(buf + len, "    float%d input%d [[attribute(%d)]];",  cc_features.opt_alpha ? 4 : 3, i + 1, vertexIndex);
        vertexDescriptor.attributes[vertexIndex].format = cc_features.opt_alpha ? MTLVertexFormatFloat4 : MTLVertexFormatFloat3;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += cc_features.opt_alpha ? 4 : 3;
    }
    append_line(buf, &len, "};");
    // end vertex struct

    // fragment output struct
    append_line(buf, &len, "struct ProjectedVertex {");
    append_line(buf, &len, "    float4 position [[position]];");

    for (int i = 0; i < 2; i++) {
        if (cc_features.used_textures[i]) {
            len += sprintf(buf + len, "    float2 texCoord%d;\n", i);
            for (int j = 0; j < 2; j++) {
                if (cc_features.clamp[i][j]) {
                    len += sprintf(buf + len, "    float texClamp%s%d;\n", j == 0 ? "S" : "T", i);
                }
            }
        }
    }

    if (cc_features.opt_fog) {
        append_line(buf, &len, "    float4 fog;");
    }
    if (cc_features.opt_grayscale) {
        append_line(buf, &len, "    float4 grayscale;");
    }
    for (int i = 0; i < cc_features.num_inputs; i++) {
        len += sprintf(buf + len, "    float%d input%d;",  cc_features.opt_alpha ? 4 : 3, i + 1);
    }
    append_line(buf, &len, "};");
    // end fragment output struct

    // vertex shader
    append_line(buf, &len, "vertex ProjectedVertex vertexShader(Vertex in [[stage_in]]) {");
    append_line(buf, &len, "    ProjectedVertex out;");
    for (int i = 0; i < 2; i++) {
        if (cc_features.used_textures[i]) {
            len += sprintf(buf + len, "    out.texCoord%d = in.texCoord%d;\n", i, i);
            for (int j = 0; j < 2; j++) {
                if (cc_features.clamp[i][j]) {
                    len += sprintf(buf + len, "    out.texClamp%s%d = in.texClamp%s%d;\n", j == 0 ? "S" : "T", i, j == 0 ? "S" : "T", i);
                }
            }
        }
    }

    if (cc_features.opt_fog) {
        append_line(buf, &len, "    out.fog = in.fog;");
    }
    if (cc_features.opt_grayscale) {
        append_line(buf, &len, "    out.grayscale = in.grayscale;");
    }
    for (int i = 0; i < cc_features.num_inputs; i++) {
        len += sprintf(buf + len, "    out.input%d = in.input%d;\n", i + 1, i + 1);
    }

    append_line(buf, &len, "    out.position = in.position;");
    append_line(buf, &len, "    out.position.z = (out.position.z + out.position.w) / 2.0f;");
    append_line(buf, &len, "    return out;");
    append_line(buf, &len, "}");
    // end vertex shader

    // fragment shader
    append_line(buf, &len, "float4 fragmentShader(ShaderInput in [[stage_in]], constant FrameUniforms &frameUniforms [[buffer(0)]], constant DrawUniforms &texture0Uniforms [[buffer(1)]], constant DrawUniforms &texture1Uniforms [[buffer(2)]], texture2d<float> texture0 [[texture(0)]], texture2d<float> texture1 [[texture(1)]], sampler sampler0 [[sampler(0)]], sampler sampler1 [[sampler(1)]]) {");

    for (int i = 0; i < 2; i++) {
        if (cc_features.used_textures[i]) {
            len += sprintf(buf + len, "    float2 texCoord%d = input.texCoord%d;\n", i, i);
            bool s = cc_features.clamp[i][0], t = cc_features.clamp[i][1];
            if (!s && !t) {}
            else {
                len += sprintf(buf + len, "    const auto texSize%d = ushort2(texture%d.get_width(), texture%d.get_height());\n", i, i, i);
                if (s && t) {
                    len += sprintf(buf + len, "    texCoord%d = clamp(texCoord%d, 0.5 / texSize%d, float2(input.texClampS%d, input.texClampT%d));\n", i, i, i, i, i);
                } else if (s) {
                    len += sprintf(buf + len, "    float2(clamp(texCoord%d.x, 0.5 / texSize%d.x, input.texClampS%d), texCoord%d.y);\n", i, i, i, i);
                } else {
                    len += sprintf(buf + len, "    texCoord%d = float2(texCoord%d.x, clamp(texCoord%d.y, 0.5 / texSize%d.y, input.texClampT%d));\n", i, i, i, i, i);
                }
            }
            if (metal_ctx.current_filter_mode == THREE_POINT) {

            } else {
                len += sprintf(buf + len, "    float4 texVal%d = texture%d.sample(sampler%d, texCoord%d);\n", i, i, i, i);
            }
        }
    }

    if (cc_features.opt_alpha) {
        if (cc_features.opt_alpha_threshold) {
            append_line(buf, &len, "    if (texel.a < 8.0 / 256.0) discard_fragment();");
        }
        if (cc_features.opt_invisible) {
            append_line(buf, &len, "    texel.a = 0.0;");
        }
        append_line(buf, &len, "    return texel;");
    } else {
        append_line(buf, &len, "    return float4(texel, 1.0);");
    }
    append_line(buf, &len, "}");
    // end fragment shader

    vertexDescriptor.layouts[0].stride = num_floats * sizeof(float);
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    NSError* error = nil;
    id <MTLLibrary> library = [mDevice newLibraryWithSource:[NSString stringWithUTF8String:buf] options:nil error:&error];

    if (!error) {
        NSLog(@"Failed to compile shader library, error %@", error);
    }

    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertexShader"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragmentShader"];
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;

    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    if (cc_features.opt_alpha) {
        pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorZero;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskAll;
    } else {
        pipelineDescriptor.colorAttachments[0].blendingEnabled = NO;
        pipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMaskAll;
    }

    mPipelineState = [mDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    if (!mPipelineState) {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        //  If the Metal API validation is enabled, we can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode)
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    struct ShaderProgramMetal *prg = &metal_ctx.shader_program_pool[std::make_pair(shader_id0, shader_id1)];
    prg->used_textures[0] = cc_features.used_textures[0];
    prg->used_textures[1] = cc_features.used_textures[1];
    prg->num_floats = num_floats;

    return (struct ShaderProgram *)(metal_ctx.shader_program = prg);
}

static struct ShaderProgram* gfx_metal_lookup_shader(uint64_t shader_id0, uint32_t shader_id1) {
    // TODO: implement
}

static void gfx_metal_shader_get_info(struct ShaderProgram *prg, uint8_t *num_inputs, bool used_textures[2]) {
    struct ShaderProgramMetal *p = (struct ShaderProgramMetal *)prg;

    *num_inputs = p->num_inputs;
    used_textures[0] = p->used_textures[0];
    used_textures[1] = p->used_textures[1];
}

static uint32_t gfx_metal_new_texture(void) {
    metal_ctx.textures.resize(metal_ctx.textures.size() + 1);
    return (uint32_t)(metal_ctx.textures.size() - 1);
}

static void gfx_metal_delete_texture(uint32_t texID) {
    // TODO: implement
}

static void gfx_metal_select_texture(int tile, uint32_t texture_id) {
    metal_ctx.current_tile = tile;
    metal_ctx.current_texture_ids[tile] = texture_id;
}

static void gfx_metal_upload_texture(const uint8_t *rgba32_buf, uint32_t width, uint32_t height) {
    GfxTexture *texture_data = &metal_ctx.textures[metal_ctx.current_texture_ids[metal_ctx.current_tile]];

    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:YES];

    textureDescriptor.usage = MTLTextureUsageShaderRead;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.arrayLength = 1;
    textureDescriptor.mipmapLevelCount = 1;
    textureDescriptor.sampleCount = 1;

    texture_data->texture = [mDevice newTextureWithDescriptor:textureDescriptor];

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    NSUInteger bytesPerPixel = 4;
    [texture_data->texture replaceRegion:region mipmapLevel:1 withBytes:rgba32_buf bytesPerRow:width * bytesPerPixel];
}

static MTLSamplerAddressMode gfx_cm_to_metal(uint32_t val) {
    switch (val) {
        case G_TX_NOMIRROR | G_TX_CLAMP:
            return MTLSamplerAddressModeClampToEdge;
        case G_TX_MIRROR | G_TX_WRAP:
            return MTLSamplerAddressModeMirrorRepeat;
        case G_TX_MIRROR | G_TX_CLAMP:
            return MTLSamplerAddressModeMirrorClampToEdge;
        case G_TX_NOMIRROR | G_TX_WRAP:
            return MTLSamplerAddressModeRepeat;
    }

    return MTLSamplerAddressModeClampToEdge;
}

static void gfx_metal_set_sampler_parameters(int tile, bool linear_filter, uint32_t cms, uint32_t cmt) {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    MTLSamplerMinMagFilter filter = linear_filter && metal_ctx.current_filter_mode == LINEAR ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    samplerDescriptor.minFilter = filter;
    samplerDescriptor.magFilter = filter;
    samplerDescriptor.sAddressMode = gfx_cm_to_metal(cms);
    samplerDescriptor.tAddressMode = gfx_cm_to_metal(cmt);
    samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;

    GfxTexture *texture_data = &metal_ctx.textures[metal_ctx.current_texture_ids[metal_ctx.current_tile]];
    texture_data->linear_filtering = linear_filter;

    // This function is called twice per texture, the first one only to set default values.
   // Maybe that could be skipped? Anyway, make sure to release the first default sampler
   // state before setting the actual one.
//   [texture_data->sampler release];

    texture_data->sampler = [mDevice newSamplerStateWithDescriptor:samplerDescriptor];
}

static void gfx_metal_set_depth_test_and_mask(bool depth_test, bool depth_mask) {
    MTLDepthStencilDescriptor* depthDescriptor = [MTLDepthStencilDescriptor new];
    [depthDescriptor setDepthWriteEnabled: depth_test || depth_mask ? YES : NO];
    [depthDescriptor setDepthCompareFunction: depth_test ? MTLCompareFunctionLess : MTLCompareFunctionAlways];

    id<MTLDepthStencilState> depthStencilState = [mDevice newDepthStencilStateWithDescriptor: depthDescriptor];
    [mRenderEncoder setDepthStencilState:depthStencilState];
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
    // TODO: maybe we have to invert the y?
    [mRenderEncoder setViewport:(MTLViewport){x, y, width, height, 0.0, 1.0 }];
}

static void gfx_metal_set_scissor(int x, int y, int width, int height) {
    // TODO: maybe we have to invert the y?
    [mRenderEncoder setScissorRect:(MTLScissorRect){ x, y, width, height }];
}

static void gfx_metal_set_use_alpha(bool use_alpha) {
    // Already part of the pipeline state from shader info
}

static void gfx_metal_draw_triangles(float buf_vbo[], size_t buf_vbo_len, size_t buf_vbo_num_tris) {
    // TODO: implement

    id<MTLBuffer> vertexBuffer = [mDevice newBufferWithLength:buf_vbo_len * sizeof(float) options:MTLResourceOptionCPUCacheModeDefault];
    [vertexBuffer setLabel:@"VBO"];
    memcpy(vertexBuffer.contents, buf_vbo, sizeof(float) * buf_vbo_len);

    [mRenderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [mRenderEncoder setVertexBuffer:uniformBuffer offset:0 atIndex:1];
    [mRenderEncoder setFragmentBuffer:uniformBuffer offset:0 atIndex:0];

    for (int i = 0; i < 2; i++) {
        if (metal_ctx.shader_program->used_textures[i]) {
            [mRenderEncoder setFragmentTexture:metal_ctx.textures[i].texture atIndex:i];

            // check and handle three point filter?

            [mRenderEncoder setFragmentSamplerState:metal_ctx.textures[i].sampler atIndex:i];
        }
    }

    [mRenderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:buf_vbo_num_tris * 3];
}

static void gfx_metal_on_resize(void) {
    // TODO: implement
}

static void gfx_metal_start_frame(void) {
    metal_ctx.frame_uniforms.frameCount++;
}

void gfx_metal_end_frame(void) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    [mCommandBuffer presentDrawable: layer.nextDrawable];
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
    if (noise_scale != 0.0f) {
        metal_ctx.frame_uniforms.noiseScale = 1.0f / noise_scale;
    }

    if (!uniformBuffer) {
        uniformBuffer = [mDevice newBufferWithLength:sizeof(FrameUniforms) options:MTLResourceOptionCPUCacheModeDefault];
    }

    memcpy(uniformBuffer.contents, &metal_ctx.frame_uniforms, sizeof(FrameUniforms));
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
    //return (void *)metal_ctx.textures[metal_ctx.current_tile];
}

void gfx_metal_select_texture_fb(int fb_id) {
    // TODO: implement
}

void gfx_metal_set_texture_filter(FilteringMode mode) {
    // TODO: implement
}

FilteringMode gfx_metal_get_texture_filter(void) {
    return metal_ctx.current_filter_mode;
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
