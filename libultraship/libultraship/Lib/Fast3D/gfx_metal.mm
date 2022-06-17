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

#include "gfx_pc.h"

static SDL_Renderer* _renderer;
static CAMetalLayer* mLayer;
static id<MTLDevice> mDevice;
static id<MTLCommandQueue> mCommandQueue;

static id<MTLRenderPipelineState> mPipelineState;
static MTLRenderPassDescriptor* mCurrentRenderPass;
//static id<MTLCommandBuffer> mCommandBuffer;
//static id <MTLRenderCommandEncoder> mRenderEncoder;
static id<CAMetalDrawable> mCurrentDrawable;

static id<MTLBuffer> frameUniformBuffer;

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

    std::vector<struct GfxTexture> textures;
    int current_tile;
    uint32_t current_texture_ids[2];

    // Current state
    struct ShaderProgramMetal *shader_program;
    FilteringMode current_filter_mode = THREE_POINT;

    uint8_t depth_test_and_mask;
    bool decal_mode;

    MTLViewport viewport;
    MTLScissorRect scissor;

    FrameUniforms frame_uniforms;
} metal_ctx;

// MARK: - Helpers

static void append_str(char *buf, size_t *len, const char *str) {
    while (*str != '\0') buf[(*len)++] = *str++;
}

static void append_line(char *buf, size_t *len, const char *str) {
    while (*str != '\0') buf[(*len)++] = *str++;
    buf[(*len)++] = '\n';
}

static const char *shader_item_to_str(uint32_t item, bool with_alpha, bool only_alpha, bool inputs_have_alpha, bool hint_single_element) {
    if (!only_alpha) {
        switch (item) {
            case SHADER_0:
                return with_alpha ? "float4(0.0, 0.0, 0.0, 0.0)" : "float3(0.0, 0.0, 0.0)";
            case SHADER_1:
                return with_alpha ? "float4(1.0, 1.0, 1.0, 1.0)" : "float3(1.0, 1.0, 1.0)";
            case SHADER_INPUT_1:
                return with_alpha || !inputs_have_alpha ? "in.input1" : "in.input1.xyz";
            case SHADER_INPUT_2:
                return with_alpha || !inputs_have_alpha ? "in.input2" : "in.input2.xyz";
            case SHADER_INPUT_3:
                return with_alpha || !inputs_have_alpha ? "in.input3" : "in.input3.xyz";
            case SHADER_INPUT_4:
                return with_alpha || !inputs_have_alpha ? "in.input4" : "in.input4.xyz";
            case SHADER_TEXEL0:
                return with_alpha ? "texVal0" : "texVal0.xyz";
            case SHADER_TEXEL0A:
                return hint_single_element ? "texVal0.w" :
                    (with_alpha ? "float4(texVal0.w, texVal0.w, texVal0.w, texVal0.w)" : "float3(texVal0.w, texVal0.w, texVal0.w)");
            case SHADER_TEXEL1A:
                return hint_single_element ? "texVal1.w" :
                    (with_alpha ? "float4(texVal1.w, texVal1.w, texVal1.w, texVal1.w)" : "float3(texVal1.w, texVal1.w, texVal1.w)");
            case SHADER_TEXEL1:
                return with_alpha ? "texVal1" : "texVal1.xyz";
            case SHADER_COMBINED:
                return with_alpha ? "texel" : "texel.xyz";
        }
    } else {
        switch (item) {
            case SHADER_0:
                return "0.0";
            case SHADER_1:
                return "1.0";
            case SHADER_INPUT_1:
                return "in.input1.w";
            case SHADER_INPUT_2:
                return "in.input2.w";
            case SHADER_INPUT_3:
                return "in.input3.w";
            case SHADER_INPUT_4:
                return "in.input4.w";
            case SHADER_TEXEL0:
                return "texVal0.w";
            case SHADER_TEXEL0A:
                return "texVal0.w";
            case SHADER_TEXEL1A:
                return "texVal1.w";
            case SHADER_TEXEL1:
                return "texVal1.w";
            case SHADER_COMBINED:
                return "texel.w";
        }
    }
    return "";
}

static void append_formula(char *buf, size_t *len, uint8_t c[2][4], bool do_single, bool do_multiply, bool do_mix, bool with_alpha, bool only_alpha, bool opt_alpha) {
    if (do_single) {
        append_str(buf, len, shader_item_to_str(c[only_alpha][3], with_alpha, only_alpha, opt_alpha, false));
    } else if (do_multiply) {
        append_str(buf, len, shader_item_to_str(c[only_alpha][0], with_alpha, only_alpha, opt_alpha, false));
        append_str(buf, len, " * ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][2], with_alpha, only_alpha, opt_alpha, true));
    } else if (do_mix) {
        append_str(buf, len, "mix(");
        append_str(buf, len, shader_item_to_str(c[only_alpha][1], with_alpha, only_alpha, opt_alpha, false));
        append_str(buf, len, ", ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][0], with_alpha, only_alpha, opt_alpha, false));
        append_str(buf, len, ", ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][2], with_alpha, only_alpha, opt_alpha, true));
        append_str(buf, len, ")");
    } else {
        append_str(buf, len, "(");
        append_str(buf, len, shader_item_to_str(c[only_alpha][0], with_alpha, only_alpha, opt_alpha, false));
        append_str(buf, len, " - ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][1], with_alpha, only_alpha, opt_alpha, false));
        append_str(buf, len, ") * ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][2], with_alpha, only_alpha, opt_alpha, true));
        append_str(buf, len, " + ");
        append_str(buf, len, shader_item_to_str(c[only_alpha][3], with_alpha, only_alpha, opt_alpha, false));
    }
}

// MARK: - ImGui & SDL Wrappers

void Metal_SetRenderer(SDL_Renderer* renderer) {
    _renderer = renderer;
}

bool Metal_Init() {
    mLayer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    mLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    mDevice = mLayer.device;
    return ImGui_ImplMetal_Init(mDevice);
}

void Metal_NewFrame() {
    int width, height;
    SDL_GetRendererOutputSize(_renderer, &width, &height);
    mLayer.drawableSize = CGSizeMake(width, height);

    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];

    id<CAMetalDrawable> drawable = [mLayer nextDrawable];
    //NSAssert(drawable != nil, @"Could not retrieve drawable from Metal layer");

    MTLClearColor clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1.0);
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor = clearColor;

//    renderPass.depthAttachment.texture = self.depthTexture;
//    renderPass.depthAttachment.loadAction = MTLLoadActionClear;
//    renderPass.depthAttachment.storeAction = MTLStoreActionStore;
//    renderPass.depthAttachment.clearDepth = 1;

    mCurrentDrawable = drawable;
    mCurrentRenderPass = renderPassDescriptor;

    ImGui_ImplMetal_NewFrame(mCurrentRenderPass);
}

void Metal_RenderDrawData(ImDrawData* draw_data) {
    id<MTLCommandBuffer> commandBuffer = [mCommandQueue commandBuffer];
    id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:mCurrentRenderPass];
    ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, commandEncoder);

    [commandEncoder endEncoding];
}

// MARK: - Metal Graphics Rendering API

static void gfx_metal_init(void) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    mCommandQueue = [mDevice newCommandQueue];
}

static const char* gfx_metal_get_name() {
    return "Metal";
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

    memset(buf, 0, sizeof(buf));
    append_line(buf, &len, "#include <metal_stdlib>");
    append_line(buf, &len, "#include <simd/simd.h>");
    append_line(buf, &len, "using namespace metal;");

    // Uniforms struct
    append_line(buf, &len, "struct FrameUniforms {");
    append_line(buf, &len, "    int noise_frame;");
    append_line(buf, &len, "    float noise_scale;");
    append_line(buf, &len, "};");
    // end uniforms struct

    // DrawUniforms struct
    append_line(buf, &len, "struct DrawUniforms {");
    append_line(buf, &len, "    uint16_t width;");
    append_line(buf, &len, "    uint16_t height;");
    append_line(buf, &len, "    bool linearFiltering;");
    append_line(buf, &len, "};");
    // end draw uniforms struct


    // Vertex struct
    append_line(buf, &len, "struct Vertex {");
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
    len += sprintf(buf + len, "    float4 position [[attribute(%d)]];\n", vertexIndex);
    vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
    vertexDescriptor.attributes[vertexIndex++].offset = 0;
    append_line(buf, &len, "};");
    // end vertex struct

    // fragment output struct
    append_line(buf, &len, "struct ProjectedVertex {");
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
    append_line(buf, &len, "    float4 position [[position]];");
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

    if (metal_ctx.current_filter_mode == THREE_POINT) {
        append_line(buf, &len, "float4 filter3point(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& texCoord, thread const float2& texSize) {");
        append_line(buf, &len, "    float2 offset = fract((texCoord * texSize) - float2(0.5));");
        append_line(buf, &len, "    offset -= float2(step(1.0, offset.x + offset.y));");
        append_line(buf, &len, "    float4 c0 = tex.sample(texSmplr, (texCoord - (offset / texSize)));");
        append_line(buf, &len, "    float4 c1 = tex.sample(texSmplr, (texCoord - (float2(offset.x - sign(offset.x), offset.y) / texSize)));");
        append_line(buf, &len, "    float4 c2 = tex.sample(texSmplr, (texCoord - (float2(offset.x, offset.y - sign(offset.y)) / texSize)));");
        append_line(buf, &len, "    return (c0 + ((c1 - c0) * abs(offset.x))) + ((c2 - c0) * abs(offset.y));");
        append_line(buf, &len, "}");


        append_line(buf, &len, "float4 hookTexture2D(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& uv, thread const float2& texSize) {");
        append_line(buf, &len, "    return filter3point(tex, texSmplr, uv, texSize);");
        append_line(buf, &len, "}");
    } else {
        append_line(buf, &len, "float4 hookTexture2D(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& uv, thread const float2& texSize) {");
        append_line(buf, &len, "   return tex.sample(texSmplr, uv);");
        append_line(buf, &len, "}");
    }

    append_str(buf, &len, "fragment float4 fragmentShader(ProjectedVertex in [[stage_in]], constant FrameUniforms &frameUniforms [[buffer(0)]]");

    if (cc_features.used_textures[0]) {
        append_str(buf, &len, ", texture2d<float> uTex0 [[texture(0)]], sampler uTex0Smplr [[sampler(0)]]");
    }
    if (cc_features.used_textures[1]) {
        append_str(buf, &len, ", texture2d<float> uTex1 [[texture(1)]], sampler uTex1Smplr [[sampler(1)]]");
    }
    append_str(buf, &len, ") {");

    for (int i = 0; i < 2; i++) {
        if (cc_features.used_textures[i]) {
            bool s = cc_features.clamp[i][0], t = cc_features.clamp[i][1];

            len += sprintf(buf + len, "    float2 texSize%d = float2(int2(uTex%d.get_width(), uTex%d.get_height()));\n", i, i, i);

            if (!s && !t) {
                len += sprintf(buf + len, "    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, in.texCoord%d, texSize%d);\n", i, i, i, i, i);
            } else {
                if (s && t) {
                    len += sprintf(buf + len, "    float2 uv = fast::clamp(in.texCoord%d, float2(0.5) / texSize%d, float2(in.texClampS%d, in.texClampT%d));\n", i, i, i, i);
                    len += sprintf(buf + len, "    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i);
                } else if (s) {
                    len += sprintf(buf + len, "    float2 uv = float2(fast::clamp(in.texCoord%d.x, 0.5 / texSize%d.x, in.texClampS%d), in.texCoord%d.y);\n", i, i, i, i);
                    len += sprintf(buf + len, "    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i);
                } else {
                    len += sprintf(buf + len, "    float2 uv = float2(in.texCoord%d.x, fast::clamp(in.texCoord%d.y, 0.5 / texSize%d.y, in.texClampT%d));\n", i, i, i, i);
                    len += sprintf(buf + len, "    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i);
                }
            }
        }
    }

    append_line(buf, &len, cc_features.opt_alpha ? "    float4 texel;" : "float3 texel;");
    for (int c = 0; c < (cc_features.opt_2cyc ? 2 : 1); c++) {
        append_str(buf, &len, "     texel = ");
        if (!cc_features.color_alpha_same[c] && cc_features.opt_alpha) {
            append_str(buf, &len, "float4(");
            append_formula(buf, &len, cc_features.c[c], cc_features.do_single[c][0], cc_features.do_multiply[c][0], cc_features.do_mix[c][0], false, false, true);
            append_str(buf, &len, ", ");
            append_formula(buf, &len, cc_features.c[c], cc_features.do_single[c][1], cc_features.do_multiply[c][1], cc_features.do_mix[c][1], true, true, true);
            append_str(buf, &len, ")");
        } else {
            append_formula(buf, &len, cc_features.c[c], cc_features.do_single[c][0], cc_features.do_multiply[c][0], cc_features.do_mix[c][0], cc_features.opt_alpha, false, cc_features.opt_alpha);
        }
        append_line(buf, &len, ";");
    }

    if (cc_features.opt_fog) {
        if (cc_features.opt_alpha) {
            append_line(buf, &len, "    texel = float4(mix(texel.xyz, in.fog.xyz, in.fog.w), texel.w);");
        } else {
            append_line(buf, &len, "    texel = mix(texel, in.fog.xyz, in.fog.w);");
        }
    }

    if (cc_features.opt_texture_edge && cc_features.opt_alpha) {
        append_line(buf, &len, "    if (texel.w > 0.19) texel.w = 1.0; else discard_fragment();");
    }

    if (cc_features.opt_alpha && cc_features.opt_noise) {
        append_line(buf, &len,     "texel.w *= floor(fast::clamp(random(float3(floor(in.position.xy * frameUniforms.noise_scale), float(frameUniforms.noise_frame))) + texel.w, 0.0, 1.0));");
    }

    if (cc_features.opt_grayscale) {
        append_line(buf, &len, "    float intensity = ((texel.x + texel.y) + texel.z) / 3.0;");
        append_line(buf, &len, "    float3 new_texel = in.grayscale.xyz * intensity;");
        append_line(buf, &len, "    float3 grayscale = mix(texel.xyz, new_texel, float3(in.grayscale.w));");
        append_line(buf, &len, "    texel = float4(grayscale.x, grayscale.y, grayscale.z, texel.w);");
    }

    if (cc_features.opt_alpha) {
       if (cc_features.opt_alpha_threshold) {
           append_line(buf, &len, "    if (texel.w < 8.0 / 256.0) discard_fragment();");
       }
       if (cc_features.opt_invisible) {
           append_line(buf, &len, "    texel.w = 0.0;");
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
        auto it = metal_ctx.shader_program_pool.find(std::make_pair(shader_id0, shader_id1));
        return it == metal_ctx.shader_program_pool.end() ? nullptr : (struct ShaderProgram *)&it->second;
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
    metal_ctx.depth_test_and_mask = (depth_test ? 1 : 0) | (depth_mask ? 2 : 0);
}

static void gfx_metal_set_zmode_decal(bool zmode_decal) {
    metal_ctx.decal_mode = zmode_decal;
}

static void gfx_metal_set_viewport(int x, int y, int width, int height) {
    metal_ctx.viewport = { x, y, width, height, 0, 1 };
}

static void gfx_metal_set_scissor(int x, int y, int width, int height) {
    // TODO: maybe we have to invert the y?
    metal_ctx.scissor = { x, y, width, height };
}

static void gfx_metal_set_use_alpha(bool use_alpha) {
    // Already part of the pipeline state from shader info
}

static void gfx_metal_draw_triangles(float buf_vbo[], size_t buf_vbo_len, size_t buf_vbo_num_tris) {
    if (!frameUniformBuffer) {
        frameUniformBuffer = [mDevice newBufferWithLength:sizeof(FrameUniforms) options:MTLResourceOptionCPUCacheModeDefault];
    }

    memcpy(frameUniformBuffer.contents, &metal_ctx.frame_uniforms, sizeof(FrameUniforms));

    id<MTLCommandBuffer> commandBuffer = [mCommandQueue commandBuffer];
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:mCurrentRenderPass];

    id<MTLBuffer> vertexBuffer = [mDevice newBufferWithLength:buf_vbo_len * sizeof(float) options:MTLResourceOptionCPUCacheModeDefault];
    [vertexBuffer setLabel:@"VBO"];
    memcpy(vertexBuffer.contents, buf_vbo, sizeof(float) * buf_vbo_len);

    [commandEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [commandEncoder setFragmentBuffer:frameUniformBuffer offset:0 atIndex:0];

    for (int i = 0; i < 2; i++) {
        if (metal_ctx.shader_program->used_textures[i]) {
            [commandEncoder setFragmentTexture:metal_ctx.textures[i].texture atIndex:i];
            [commandEncoder setFragmentSamplerState:metal_ctx.textures[i].sampler atIndex:i];
        }
    }

    [commandEncoder setRenderPipelineState:mPipelineState];
    [commandEncoder setTriangleFillMode:MTLTriangleFillModeFill];
    [commandEncoder setCullMode:MTLCullModeNone];
    [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [commandEncoder setViewport:metal_ctx.viewport];
    [commandEncoder setScissorRect:metal_ctx.scissor];
    [commandEncoder setDepthBias:0 slopeScale:metal_ctx.decal_mode ? -2 : 0 clamp:0];

    MTLDepthStencilDescriptor* depthDescriptor = [MTLDepthStencilDescriptor new];
    [depthDescriptor setDepthWriteEnabled: metal_ctx.depth_test_and_mask ? YES : NO];
    [depthDescriptor setDepthCompareFunction: metal_ctx.depth_test_and_mask ? MTLCompareFunctionLess : MTLCompareFunctionAlways];

    id<MTLDepthStencilState> depthStencilState = [mDevice newDepthStencilStateWithDescriptor: depthDescriptor];
    [commandEncoder setDepthStencilState:depthStencilState];

    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:buf_vbo_num_tris * 3];

    [commandEncoder endEncoding];
    [commandBuffer commit];
}

static void gfx_metal_on_resize(void) {
    // TODO: implement
}

static void gfx_metal_start_frame(void) {
    metal_ctx.frame_uniforms.frameCount++;
}

void gfx_metal_end_frame(void) {
    id<MTLCommandBuffer> commandBuffer = [mCommandQueue commandBuffer];
    [commandBuffer presentDrawable:mCurrentDrawable];
    [commandBuffer commit];
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
    if (noise_scale != 0.0f) {
        metal_ctx.frame_uniforms.noiseScale = 1.0f / noise_scale;
    }
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
    metal_ctx.current_filter_mode = mode;
    gfx_texture_cache_clear();
}

FilteringMode gfx_metal_get_texture_filter(void) {
    return metal_ctx.current_filter_mode;
}

struct GfxRenderingAPI gfx_metal_api = {
    gfx_metal_get_name,
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
