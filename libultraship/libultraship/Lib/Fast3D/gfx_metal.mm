#ifdef ENABLE_METAL

#include <vector>
#include <time.h>
#include <math.h>
#include <cmath>
#include <stddef.h>
#include <simd/simd.h>

#ifndef _LANGUAGE_C
#define _LANGUAGE_C
#endif

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "Lib/ImGui/backends/imgui_impl_metal.h"
#include "Lib/SDL/SDL2/SDL_render.h"

#include "PR/ultra64/gbi.h"
#include "PR/ultra64/abi.h"

#include "gfx_cc.h"
#include "gfx_rendering_api.h"

#include "gfx_pc.h"

// MARK: - Structs

struct ShaderProgramMetal {
    uint64_t shader_id0;
    uint32_t shader_id1;

    uint8_t num_inputs;
    uint8_t num_floats;
    bool used_textures[2];
};

struct FrameUniforms {
    simd::float1 frameCount;
    simd::float1 noiseScale;
};

static struct State {
    struct ShaderProgramMetal *shader_program;
    FilteringMode current_filter_mode = THREE_POINT;
    
    uint8_t depth_test_and_mask;
    bool decal_mode;
    
    simd::float2 viewportSize;
    MTLScissorRect scissor;
    
    FrameUniforms frame_uniforms;
} state;

static int current_tile;
static uint32_t current_texture_ids[2];

// MARK: - Objc Helpers

static inline CFTimeInterval GetMachAbsoluteTimeInSeconds() {
    return static_cast<CFTimeInterval>(static_cast<double>(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9);
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

@interface NSString (Shader)
+ (instancetype)stringFromShader:(uint32_t)item withAlpha:(bool)withAlpha onlyAlpha:(bool)onlyAlpha inputsHaveAlpha:(bool)inputsHaveAlpha hintSingleElement:(bool)hintSingleElement;

+ (instancetype)stringHashFromShaderIds:(uint64_t)id1 id2:(uint32_t)id2;
+ (instancetype)stringHashFromShaderProgram:(ShaderProgramMetal)program;
@end

@implementation NSString (Shader)

+ (instancetype)stringFromShader:(uint32_t)item withAlpha:(bool)withAlpha onlyAlpha:(bool)onlyAlpha inputsHaveAlpha:(bool)inputsHaveAlpha hintSingleElement:(bool)hintSingleElement {
    if (!onlyAlpha) {
        switch (item) {
            case SHADER_0:
                return withAlpha ? @"float4(0.0, 0.0, 0.0, 0.0)" : @"float3(0.0, 0.0, 0.0)";
            case SHADER_1:
                return withAlpha ? @"float4(1.0, 1.0, 1.0, 1.0)" : @"float3(1.0, 1.0, 1.0)";
            case SHADER_INPUT_1:
                return withAlpha || !inputsHaveAlpha ? @"in.input1" : @"in.input1.xyz";
            case SHADER_INPUT_2:
                return withAlpha || !inputsHaveAlpha ? @"in.input2" : @"in.input2.xyz";
            case SHADER_INPUT_3:
                return withAlpha || !inputsHaveAlpha ? @"in.input3" : @"in.input3.xyz";
            case SHADER_INPUT_4:
                return withAlpha || !inputsHaveAlpha ? @"in.input4" : @"in.input4.xyz";
            case SHADER_TEXEL0:
                return withAlpha ? @"texVal0" : @"texVal0.xyz";
            case SHADER_TEXEL0A:
                return hintSingleElement ? @"texVal0.w" :
                (withAlpha ? @"float4(texVal0.w, texVal0.w, texVal0.w, texVal0.w)" : @"float3(texVal0.w, texVal0.w, texVal0.w)");
            case SHADER_TEXEL1A:
                return hintSingleElement ? @"texVal1.w" :
                (withAlpha ? @"float4(texVal1.w, texVal1.w, texVal1.w, texVal1.w)" : @"float3(texVal1.w, texVal1.w, texVal1.w)");
            case SHADER_TEXEL1:
                return withAlpha ? @"texVal1" : @"texVal1.xyz";
            case SHADER_COMBINED:
                return withAlpha ? @"texel" : @"texel.xyz";
        }
    } else {
        switch (item) {
            case SHADER_0:
                return @"0.0";
            case SHADER_1:
                return @"1.0";
            case SHADER_INPUT_1:
                return @"in.input1.w";
            case SHADER_INPUT_2:
                return @"in.input2.w";
            case SHADER_INPUT_3:
                return @"in.input3.w";
            case SHADER_INPUT_4:
                return @"in.input4.w";
            case SHADER_TEXEL0:
                return @"texVal0.w";
            case SHADER_TEXEL0A:
                return @"texVal0.w";
            case SHADER_TEXEL1A:
                return @"texVal1.w";
            case SHADER_TEXEL1:
                return @"texVal1.w";
            case SHADER_COMBINED:
                return @"texel.w";
        }
    }
    return @"";
}

+ (instancetype)stringHashFromShaderIds:(uint64_t)id1 id2:(uint32_t)id2 {
    return [NSString stringWithFormat:@"%llu-%i", id1, id2];
}

+ (instancetype)stringHashFromShaderProgram:(struct ShaderProgramMetal)program {
    return [NSString stringWithFormat:@"%llu-%i", program.shader_id0, program.shader_id1];
}

@end

@interface NSMutableString (Formatting)
- (void)appendNewLineString:(NSString *)aString;
- (void)appendFormula:(uint8_t[2][4])c doSingle:(bool)doSingle doMultiply:(bool)doMultiply doMix:(bool)doMix withAlpha:(bool)withAlpha onlyAlpha:(bool)onlyAlpha optAlpha:(bool)optAlpha;
@end

@implementation NSMutableString (Formatting)
- (void)appendNewLineString:(NSString *)aString {
    [self appendFormat:@"%@\n", aString];
}

- (void)appendFormula:(uint8_t [2][4])c doSingle:(bool)doSingle doMultiply:(bool)doMultiply doMix:(bool)doMix withAlpha:(bool)withAlpha onlyAlpha:(bool)onlyAlpha optAlpha:(bool)optAlpha {
    if (doSingle) {
        [self appendString:[NSString stringFromShader:c[onlyAlpha][3] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
    } else if (doMultiply) {
        [self appendString:[NSString stringFromShader:c[onlyAlpha][0] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
        [self appendString:@" * "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][2] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:true]];
    } else if (doMix) {
        [self appendString:@"mix("];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][1] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
        [self appendString:@", "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][0] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
        [self appendString:@", "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][2] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:true]];
        [self appendString:@")"];
    } else {
        [self appendString:@"("];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][0] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
        [self appendString:@" - "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][1] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
        [self appendString:@") * "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][2] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:true]];
        [self appendString:@" + "];
        [self appendString:[NSString stringFromShader:c[onlyAlpha][3] withAlpha:withAlpha onlyAlpha:onlyAlpha inputsHaveAlpha:optAlpha hintSingleElement:false]];
    }
}
@end

// MARK: - Objc Implementation

@interface GfxMetalBuffer : NSObject
@property (nonatomic, strong) id<MTLBuffer> buffer;
@property (nonatomic, assign) double lastReuseTime;
- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer;
@end

@implementation GfxMetalBuffer
- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer {
    if ((self = [super init])) {
        _buffer = buffer;
        _lastReuseTime = GetMachAbsoluteTimeInSeconds();
    }
    return self;
}
@end

@interface GfxShaderProgram: NSObject
@property (nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong) NSData* shaderProgram;
@end

@implementation GfxShaderProgram
- (instancetype)initWithPipelineState:(id<MTLRenderPipelineState>)pipeline {
    if ((self = [super init])) {
        _pipeline = pipeline;
        _shaderProgram = NULL;
    }
    return self;
}
@end

@interface GfxTexture: NSObject
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) id<MTLSamplerState> sampler;
@property (nonatomic, assign) bool linear_filtering;
@end

@implementation GfxTexture
@end

@interface GfxMetalContext : NSObject
// Elements that only need to be setup once
@property (nonatomic) SDL_Renderer* renderer;
@property (nonatomic, strong) CAMetalLayer* layer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLBuffer> frameUniformBuffer;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, strong) id<MTLRenderCommandEncoder> currentCommandEncoder;
@property (nonatomic, strong) id<MTLCommandBuffer> currentCommandBuffer;
@property (nonatomic, strong) MTLRenderPassDescriptor* currentRenderPass;
@property (nonatomic, strong) id<CAMetalDrawable> currentDrawable;

@property (nonatomic, strong) NSMutableArray<GfxTexture *> *textures;
@property (nonatomic, strong) NSMutableArray<GfxMetalBuffer *> *bufferCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, GfxShaderProgram *> *shaderProgramCache;
@property (nonatomic, assign) NSTimeInterval lastBufferCachePurge;

- (id<MTLDevice>)setupLayerDevice;
- (MTLRenderPassDescriptor*)renderPassForFrame;

- (void)configureDepthBuffer:(bool)hasDepthBuffer msaaCount:(int)msaaCount;
- (id<MTLRenderPipelineState>)pipelineStateWithShader:(CCFeatures)features usingFilteringMode:(FilteringMode)filteringMode stride:(size_t*)stride;
- (id<MTLSamplerState>)sampleStateUsingLinearFilter:(bool)linearFilter filteringMode:(FilteringMode)filteringMode cms:(uint32_t)cms cmt:(uint32_t)cmt;

- (void)startFrame;
- (void)drawTrianglesWithBufferData:(float[])buffer bufferLength:(size_t)bufferLength andTriangleCount:(size_t)triangleCount;
- (void)endFrame;

- (GfxMetalBuffer *)dequeueReusableBufferOfLength:(NSUInteger)length device:(id<MTLDevice>)device;
@end

@implementation GfxMetalContext

- (instancetype)init {
    if ((self = [super init])) {
        _renderer = NULL;
        _layer = NULL;
        _frameUniformBuffer = NULL;
        _commandQueue = NULL;
        
        _currentRenderPass = NULL;
        _currentDrawable = NULL;
        
        _bufferCache = [NSMutableArray array];
        _shaderProgramCache = [NSMutableDictionary dictionary];
        _lastBufferCachePurge = [NSDate date].timeIntervalSince1970;
    }
    return self;
}

- (id<MTLDevice>)setupLayerDevice {
    _layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(_renderer);
    _layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    _device = [_layer device];
    _commandQueue = [_device newCommandQueue];
    
    return _device;
}

- (MTLRenderPassDescriptor*)renderPassForFrame {
    int width, height;
    SDL_GetRendererOutputSize(_renderer, &width, &height);
    _layer.drawableSize = CGSizeMake(width, height);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    
    id<CAMetalDrawable> drawable = _layer.nextDrawable;
    //NSAssert(drawable != nil, @"Could not retrieve drawable from Metal layer");
    
    MTLClearColor clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor = clearColor;
    
    _currentCommandBuffer = [_commandQueue commandBuffer];
    _currentDrawable = drawable;
    _currentRenderPass = renderPassDescriptor;
    
    return _currentRenderPass;
}

- (void)configureDepthBuffer:(bool)hasDepthBuffer msaaCount:(int)msaaCount {
    if (hasDepthBuffer) {
        CGSize drawableSize = [_layer drawableSize];
        MTLTextureDescriptor *depthTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                                width:drawableSize.width
                                                                                               height:drawableSize.height
                                                                                            mipmapped:YES];
        
        depthTexDesc.storageMode = MTLStorageModePrivate;
        depthTexDesc.sampleCount = msaaCount;
        depthTexDesc.arrayLength = 1;
        id<MTLTexture> depthTexture = [_device newTextureWithDescriptor:depthTexDesc];
        
        _currentRenderPass.depthAttachment.texture = depthTexture;
        _currentRenderPass.depthAttachment.loadAction = MTLLoadActionClear;
        _currentRenderPass.depthAttachment.storeAction = MTLStoreActionStore;
        _currentRenderPass.depthAttachment.clearDepth = 1;
    } else {
        _currentRenderPass.depthAttachment = nil;
    }
}

- (id<MTLRenderPipelineState>)pipelineStateWithShader:(CCFeatures)features usingFilteringMode:(FilteringMode)filteringMode stride:(size_t*)stride {
    NSMutableString *shaderSource = [[NSMutableString alloc] init];
    
    size_t num_floats = 4;
    int vertexIndex = 0;
    
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    
    [shaderSource appendNewLineString:@"#include <metal_stdlib>"];
    [shaderSource appendNewLineString:@"using namespace metal;"];
    
    // Uniforms struct
    [shaderSource appendNewLineString:@"struct FrameUniforms {"];
    [shaderSource appendNewLineString:@"    int noise_frame;"];
    [shaderSource appendNewLineString:@"    float noise_scale;"];
    [shaderSource appendNewLineString:@"};"];
    // end uniforms struct
    
    // Vertex struct
    [shaderSource appendNewLineString:@"struct Vertex {"];
    for (int i = 0; i < 2; i++) {
        if (features.used_textures[i]) {
            [shaderSource appendFormat:@"    float2 texCoord%d [[attribute(%d)]];\n", i, vertexIndex];
            vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat2;
            vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
            vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
            num_floats += 2;
            for (int j = 0; j < 2; j++) {
                if (features.clamp[i][j]) {
                    [shaderSource appendFormat:@"    float texClamp%s%d [[attribute(%d)]];\n", j == 0 ? "S" : "T", i, vertexIndex];
                    vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat;
                    vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
                    vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
                    num_floats += 1;
                }
            }
        }
    }
    if (features.opt_fog) {
        [shaderSource appendFormat:@"    float4 fog [[attribute(%d)]];\n", vertexIndex];
        vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += 4;
    }
    if (features.opt_grayscale) {
        [shaderSource appendFormat:@"    float4 grayscale [[attribute(%d)]];\n", vertexIndex];
        vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += 4;
    }
    for (int i = 0; i < features.num_inputs; i++) {
        [shaderSource appendFormat:@"    float%d input%d [[attribute(%d)]];\n",  features.opt_alpha ? 4 : 3, i + 1, vertexIndex];
        vertexDescriptor.attributes[vertexIndex].format = features.opt_alpha ? MTLVertexFormatFloat4 : MTLVertexFormatFloat3;
        vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
        vertexDescriptor.attributes[vertexIndex++].offset = num_floats * sizeof(float);
        num_floats += features.opt_alpha ? 4 : 3;
    }
    [shaderSource appendFormat:@"    float4 position [[attribute(%d)]];\n", vertexIndex];
    vertexDescriptor.attributes[vertexIndex].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[vertexIndex].bufferIndex = 0;
    vertexDescriptor.attributes[vertexIndex++].offset = 0;
    [shaderSource appendNewLineString:@"};"];
    // end vertex struct
    
    // fragment output struct
    [shaderSource appendNewLineString:@"struct ProjectedVertex {"];
    for (int i = 0; i < 2; i++) {
        if (features.used_textures[i]) {
            [shaderSource appendFormat:@"    float2 texCoord%d;\n", i];
            for (int j = 0; j < 2; j++) {
                if (features.clamp[i][j]) {
                    [shaderSource appendFormat:@"    float texClamp%s%d;\n", j == 0 ? "S" : "T", i];
                }
            }
        }
    }
    
    if (features.opt_fog) {
        [shaderSource appendNewLineString:@"    float4 fog;"];
    }
    if (features.opt_grayscale) {
        [shaderSource appendNewLineString:@"    float4 grayscale;"];
    }
    for (int i = 0; i < features.num_inputs; i++) {
        [shaderSource appendFormat:@"    float%d input%d;\n",  features.opt_alpha ? 4 : 3, i + 1];
    }
    [shaderSource appendNewLineString:@"    float4 position [[position]];"];
    [shaderSource appendNewLineString:@"};"];
    // end fragment output struct
    
    // vertex shader
    [shaderSource appendNewLineString:@"vertex ProjectedVertex vertexShader(Vertex in [[stage_in]], constant float2 *viewportSizePointer [[buffer(1)]]) {"];
    [shaderSource appendNewLineString:@"    ProjectedVertex out;"];
    [shaderSource appendNewLineString:@"    float2 viewportSize = float2(*viewportSizePointer);"];
    for (int i = 0; i < 2; i++) {
        if (features.used_textures[i]) {
            [shaderSource appendFormat:@"    out.texCoord%d = in.texCoord%d;\n", i, i];
            [shaderSource appendFormat:@"    out.texCoord%d.y = viewportSize.y - 1 - in.texCoord%d.y;\n", i, i];
            for (int j = 0; j < 2; j++) {
                if (features.clamp[i][j]) {
                    [shaderSource appendFormat:@"    out.texClamp%s%d = in.texClamp%s%d;\n", j == 0 ? "S" : "T", i, j == 0 ? "S" : "T", i];
                }
            }
        }
    }
    
    if (features.opt_fog) {
        [shaderSource appendNewLineString:@"    out.fog = in.fog;"];
    }
    if (features.opt_grayscale) {
        [shaderSource appendNewLineString:@"    out.grayscale = in.grayscale;"];
    }
    for (int i = 0; i < features.num_inputs; i++) {
        [shaderSource appendFormat:@"    out.input%d = in.input%d;\n", i + 1, i + 1];
    }
    
    [shaderSource appendNewLineString:@"    out.position = in.position;"];
    [shaderSource appendNewLineString:@"    return out;"];
    [shaderSource appendNewLineString:@"}"];
    // end vertex shader
    
    // fragment shader
    
    if (filteringMode == THREE_POINT) {
        [shaderSource appendNewLineString:@"float4 filter3point(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& texCoord, thread const float2& texSize) {"];
        [shaderSource appendNewLineString:@"    float2 offset = fract((texCoord * texSize) - float2(0.5));"];
        [shaderSource appendNewLineString:@"    offset -= float2(step(1.0, offset.x + offset.y));"];
        [shaderSource appendNewLineString:@"    float4 c0 = tex.sample(texSmplr, (texCoord - (offset / texSize)));"];
        [shaderSource appendNewLineString:@"    float4 c1 = tex.sample(texSmplr, (texCoord - (float2(offset.x - sign(offset.x), offset.y) / texSize)));"];
        [shaderSource appendNewLineString:@"    float4 c2 = tex.sample(texSmplr, (texCoord - (float2(offset.x, offset.y - sign(offset.y)) / texSize)));"];
        [shaderSource appendNewLineString:@"    return (c0 + ((c1 - c0) * abs(offset.x))) + ((c2 - c0) * abs(offset.y));"];
        [shaderSource appendNewLineString:@"}"];
        
        
        [shaderSource appendNewLineString:@"float4 hookTexture2D(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& uv, thread const float2& texSize) {"];
        [shaderSource appendNewLineString:@"    return filter3point(tex, texSmplr, uv, texSize);"];
        [shaderSource appendNewLineString:@"}"];
    } else {
        [shaderSource appendNewLineString:@"float4 hookTexture2D(thread const texture2d<float> tex, thread const sampler texSmplr, thread const float2& uv, thread const float2& texSize) {"];
        [shaderSource appendNewLineString:@"   return tex.sample(texSmplr, uv);"];
        [shaderSource appendNewLineString:@"}"];
    }
    
    [shaderSource appendString:@"fragment float4 fragmentShader(ProjectedVertex in [[stage_in]], constant FrameUniforms &frameUniforms [[buffer(0)]]"];
    
    if (features.used_textures[0]) {
        [shaderSource appendString:@", texture2d<float> uTex0 [[texture(0)]], sampler uTex0Smplr [[sampler(0)]]"];
    }
    if (features.used_textures[1]) {
        [shaderSource appendString:@", texture2d<float> uTex1 [[texture(1)]], sampler uTex1Smplr [[sampler(1)]]"];
    }
    [shaderSource appendNewLineString:@") {"];
    
    for (int i = 0; i < 2; i++) {
        if (features.used_textures[i]) {
            bool s = features.clamp[i][0], t = features.clamp[i][1];
            
            [shaderSource appendFormat:@"    float2 texSize%d = float2(int2(uTex%d.get_width(), uTex%d.get_height()));\n", i, i, i];
            
            if (!s && !t) {
                [shaderSource appendFormat:@"    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, in.texCoord%d, texSize%d);\n", i, i, i, i, i];
            } else {
                if (s && t) {
                    [shaderSource appendFormat:@"    float2 uv = fast::clamp(in.texCoord%d, float2(0.5) / texSize%d, float2(in.texClampS%d, in.texClampT%d));\n", i, i, i, i];
                    [shaderSource appendFormat:@"    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i];
                } else if (s) {
                    [shaderSource appendFormat:@"    float2 uv = float2(fast::clamp(in.texCoord%d.x, 0.5 / texSize%d.x, in.texClampS%d), in.texCoord%d.y);\n", i, i, i, i];
                    [shaderSource appendFormat:@"    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i];
                } else {
                    [shaderSource appendFormat:@"    float2 uv = float2(in.texCoord%d.x, fast::clamp(in.texCoord%d.y, 0.5 / texSize%d.y, in.texClampT%d));\n", i, i, i, i];
                    [shaderSource appendFormat:@"    float4 texVal%d = hookTexture2D(uTex%d, uTex%dSmplr, uv, texSize%d);\n", i, i, i, i];
                }
            }
        }
    }
    
    [shaderSource appendNewLineString: features.opt_alpha ? @"    float4 texel;" : @"    float3 texel;"];
    for (int c = 0; c < (features.opt_2cyc ? 2 : 1); c++) {
        [shaderSource appendString:@"    texel = "];
        
        if (!features.color_alpha_same[c] && features.opt_alpha) {
            [shaderSource appendString:@"float4("];
            [shaderSource appendFormula:features.c[c] doSingle:features.do_single[c][0] doMultiply:features.do_multiply[c][0] doMix:features.do_mix[c][0] withAlpha:false onlyAlpha:false optAlpha:true];
            [shaderSource appendString:@", "];
            [shaderSource appendFormula:features.c[c] doSingle:features.do_single[c][1] doMultiply:features.do_multiply[c][1] doMix:features.do_mix[c][1] withAlpha:true onlyAlpha:true optAlpha:true];
            [shaderSource appendString:@")"];
        } else {
            [shaderSource appendFormula:features.c[c] doSingle:features.do_single[c][0] doMultiply:features.do_multiply[c][0] doMix:features.do_mix[c][0] withAlpha:features.opt_alpha onlyAlpha:false optAlpha:features.opt_alpha];
        }
        [shaderSource appendNewLineString:@";"];
    }
    
    if (features.opt_fog) {
        if (features.opt_alpha) {
            [shaderSource appendNewLineString:@"    texel = float4(mix(texel.xyz, in.fog.xyz, in.fog.w), texel.w);"];
        } else {
            [shaderSource appendNewLineString:@"    texel = mix(texel, in.fog.xyz, in.fog.w);"];
        }
    }
    
    if (features.opt_texture_edge && features.opt_alpha) {
        [shaderSource appendNewLineString:@"    if (texel.w > 0.19) texel.w = 1.0; else discard_fragment();"];
    }
    
    if (features.opt_alpha && features.opt_noise) {
        [shaderSource appendNewLineString:@    "texel.w *= floor(fast::clamp(random(float3(floor(in.position.xy * frameUniforms.noise_scale), float(frameUniforms.noise_frame))) + texel.w, 0.0, 1.0));"];
    }
    
    if (features.opt_grayscale) {
        [shaderSource appendNewLineString:@"    float intensity = ((texel.x + texel.y) + texel.z) / 3.0;"];
        [shaderSource appendNewLineString:@"    float3 new_texel = in.grayscale.xyz * intensity;"];
        [shaderSource appendNewLineString:@"    float3 grayscale = mix(texel.xyz, new_texel, float3(in.grayscale.w));"];
        [shaderSource appendNewLineString:@"    texel = float4(grayscale.x, grayscale.y, grayscale.z, texel.w);"];
    }
    
    if (features.opt_alpha) {
        if (features.opt_alpha_threshold) {
            [shaderSource appendNewLineString:@"    if (texel.w < 8.0 / 256.0) discard_fragment();"];
        }
        if (features.opt_invisible) {
            [shaderSource appendNewLineString:@"    texel.w = 0.0;"];
        }
        [shaderSource appendNewLineString:@"    return texel;"];
    } else {
        [shaderSource appendNewLineString:@"    return float4(texel, 1.0);"];
    }
    
    [shaderSource appendNewLineString:@"}"];
    // end fragment shader
    
    *stride = num_floats * sizeof(float);
    vertexDescriptor.layouts[0].stride = num_floats * sizeof(float);
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    NSError* error = nil;
    id <MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    
    if (error != nil) {
        NSLog(@"Failed to compile shader library, error %@", error);
    }
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertexShader"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragmentShader"];
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    if (features.opt_alpha) {
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
    
    return [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
}

- (id<MTLSamplerState>)sampleStateUsingLinearFilter:(bool)linearFilter filteringMode:(FilteringMode)filteringMode cms:(uint32_t)cms cmt:(uint32_t)cmt {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    MTLSamplerMinMagFilter filter = linearFilter && filteringMode == LINEAR ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    samplerDescriptor.minFilter = filter;
    samplerDescriptor.magFilter = filter;
    samplerDescriptor.sAddressMode = gfx_cm_to_metal(cms);
    samplerDescriptor.tAddressMode = gfx_cm_to_metal(cmt);
    samplerDescriptor.rAddressMode = MTLSamplerAddressModeRepeat;
    
    return [_device newSamplerStateWithDescriptor:samplerDescriptor];
}

- (void)startFrame {
    if (!_frameUniformBuffer) {
        _frameUniformBuffer = [_device newBufferWithLength:sizeof(FrameUniforms) options:MTLResourceOptionCPUCacheModeDefault];
    }
    
    memcpy(_frameUniformBuffer.contents, &state.frame_uniforms, sizeof(FrameUniforms));
    
    _currentCommandEncoder = [_currentCommandBuffer renderCommandEncoderWithDescriptor:_currentRenderPass];
}

- (void)drawTrianglesWithBufferData:(float[])buffer bufferLength:(size_t)bufferLength andTriangleCount:(size_t)triangleCount {
    GfxMetalBuffer* vertexBuffer = [self dequeueReusableBufferOfLength:sizeof(float) * bufferLength device:_device];
    memcpy(vertexBuffer.buffer.contents, buffer, sizeof(float) * bufferLength);
    
    [_currentCommandEncoder setVertexBuffer:vertexBuffer.buffer offset:0 atIndex:0];
    [_currentCommandEncoder setVertexBytes:&state.viewportSize length:sizeof(state.viewportSize) atIndex:1];
    [_currentCommandEncoder setFragmentBuffer:_frameUniformBuffer offset:0 atIndex:0];
    
    for (int i = 0; i < 2; i++) {
        if (state.shader_program->used_textures[i]) {
            [_currentCommandEncoder setFragmentTexture:_textures[i].texture atIndex:i];
            [_currentCommandEncoder setFragmentSamplerState:_textures[i].sampler atIndex:i];
        }
    }

    GfxShaderProgram *shaderProgram = _shaderProgramCache[[NSString stringHashFromShaderProgram:*state.shader_program]];

    [_currentCommandEncoder setRenderPipelineState:shaderProgram.pipeline];
    [_currentCommandEncoder setTriangleFillMode:MTLTriangleFillModeFill];
    [_currentCommandEncoder setCullMode:MTLCullModeNone];
    [_currentCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    //    [commandEncoder setViewport:(MTLViewport){0.0, 0.0, state.viewportSize.x, state.viewportSize.y, 0.0, 1.0 }];
    //    [commandEncoder setScissorRect:state.scissor];
    [_currentCommandEncoder setDepthBias:0 slopeScale:state.decal_mode ? -2 : 0 clamp:0];
    
    MTLDepthStencilDescriptor* depthDescriptor = [MTLDepthStencilDescriptor new];
    [depthDescriptor setDepthWriteEnabled: state.depth_test_and_mask ? YES : NO];
    [depthDescriptor setDepthCompareFunction: state.depth_test_and_mask ? MTLCompareFunctionLess : MTLCompareFunctionAlways];
    
    id<MTLDepthStencilState> depthStencilState = [_device newDepthStencilStateWithDescriptor: depthDescriptor];
    [_currentCommandEncoder setDepthStencilState:depthStencilState];
    
    [_currentCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:triangleCount * 3];
    
    __weak id weakSelf = self;
    [_currentCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[weakSelf bufferCache] addObject:vertexBuffer];
        });
    }];
}

- (void)endFrame {
    [_currentCommandEncoder endEncoding];
    [_currentCommandBuffer presentDrawable:_currentDrawable];
    [_currentCommandBuffer commit];
}

- (GfxMetalBuffer *)dequeueReusableBufferOfLength:(NSUInteger)length device:(id<MTLDevice>)device {
    uint64_t now = GetMachAbsoluteTimeInSeconds();
    
    // Purge old buffers that haven't been useful for a while
    if (now - self.lastBufferCachePurge > 1.0) {
        NSMutableArray *survivors = [NSMutableArray array];
        for (GfxMetalBuffer *candidate in self.bufferCache) {
            if (candidate.lastReuseTime > self.lastBufferCachePurge) {
                [survivors addObject:candidate];
            }
        }
        self.bufferCache = [survivors mutableCopy];
        self.lastBufferCachePurge = now;
    }
    
    // See if we have a buffer we can reuse
    GfxMetalBuffer *bestCandidate = nil;
    for (GfxMetalBuffer *candidate in self.bufferCache)
        if (candidate.buffer.length >= length && (bestCandidate == nil || bestCandidate.lastReuseTime > candidate.lastReuseTime))
            bestCandidate = candidate;
    
    if (bestCandidate != nil) {
        [self.bufferCache removeObject:bestCandidate];
        bestCandidate.lastReuseTime = now;
        return bestCandidate;
    }
    
    // No luck; make a new buffer
    id<MTLBuffer> backing = [device newBufferWithLength:length options:MTLResourceStorageModeShared];
    return [[GfxMetalBuffer alloc] initWithBuffer:backing];
}

@end

static GfxMetalContext* metal_ctx = nil;

// MARK: - ImGui & SDL Wrappers

void Metal_SetRenderer(SDL_Renderer* renderer) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        metal_ctx = [[GfxMetalContext alloc] init];
    });
    
    metal_ctx.renderer = renderer;
}

bool Metal_Init() {
    id<MTLDevice> device = [metal_ctx setupLayerDevice];
    return ImGui_ImplMetal_Init(device);
}

void Metal_NewFrame() {
    MTLRenderPassDescriptor *renderPass = [metal_ctx renderPassForFrame];
    ImGui_ImplMetal_NewFrame(renderPass);
}

void Metal_RenderDrawData(ImDrawData* draw_data) {
    ImGui_ImplMetal_RenderDrawData(draw_data, metal_ctx.currentCommandBuffer, metal_ctx.currentCommandEncoder);
}

// MARK: - Metal Graphics Rendering API

static const char* gfx_metal_get_name() {
    return "Metal";
}

static void gfx_metal_init(void) {}

static struct GfxClipParameters gfx_metal_get_clip_parameters() {
    return { true, false };
}

static void gfx_metal_unload_shader(struct ShaderProgram *old_prg) {}

static void gfx_metal_load_shader(struct ShaderProgram *new_prg) {
    state.shader_program = (struct ShaderProgramMetal *)new_prg;
}

static struct ShaderProgram* gfx_metal_create_and_load_new_shader(uint64_t shader_id0, uint32_t shader_id1) {
    CCFeatures cc_features;
    gfx_cc_get_features(shader_id0, shader_id1, &cc_features);
    
    size_t stride = 0;
    
    id<MTLRenderPipelineState> pipelineState = [metal_ctx pipelineStateWithShader:cc_features usingFilteringMode:state.current_filter_mode stride:&stride];
    
    if (!pipelineState) {
        // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
        // If the Metal API validation is enabled, we can find out more information about what
        // went wrong.  (Metal API validation is enabled by default when a debug build is run
        // from Xcode)
        NSLog(@"Failed to created pipeline state");
    }

    GfxShaderProgram *program = [[GfxShaderProgram alloc] initWithPipelineState:pipelineState];
    struct ShaderProgramMetal shaderProgram = {
        shader_id0,
        shader_id1,
        stride / sizeof(float),
        cc_features.num_inputs,
        { cc_features.used_textures[0], cc_features.used_textures[1] }
    };
    program.shaderProgram = [NSData dataWithBytes:&shaderProgram length:sizeof(struct ShaderProgramMetal)];
    metal_ctx.shaderProgramCache[[NSString stringHashFromShaderProgram:shaderProgram]] = program;

    gfx_metal_load_shader((struct ShaderProgram *)[program.shaderProgram bytes]);
    return (struct ShaderProgram *)([program.shaderProgram bytes]);
}

static struct ShaderProgram* gfx_metal_lookup_shader(uint64_t shader_id0, uint32_t shader_id1) {
    GfxShaderProgram *shaderProgram = metal_ctx.shaderProgramCache[[NSString stringHashFromShaderIds:shader_id0 id2:shader_id1]];

    return shaderProgram == nil ? nullptr : (struct ShaderProgram *)[shaderProgram.shaderProgram bytes];
}

static void gfx_metal_shader_get_info(struct ShaderProgram *prg, uint8_t *num_inputs, bool used_textures[2]) {
    struct ShaderProgramMetal *p = (struct ShaderProgramMetal *)prg;
    
    *num_inputs = p->num_inputs;
    used_textures[0] = p->used_textures[0];
    used_textures[1] = p->used_textures[1];
}

static uint32_t gfx_metal_new_texture(void) {
    GfxTexture *newTexture = [GfxTexture new];
    [metal_ctx.textures addObject:newTexture];
    return [metal_ctx.textures count];
}

static void gfx_metal_delete_texture(uint32_t texID) {
    // TODO: implement
}

static void gfx_metal_select_texture(int tile, uint32_t texture_id) {
    current_tile = tile;
    current_texture_ids[tile] = texture_id;
}

static void gfx_metal_upload_texture(const uint8_t *rgba32_buf, uint32_t width, uint32_t height) {
    GfxTexture *texture_data = metal_ctx.textures[current_texture_ids[current_tile]];
    
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:YES];
    
    textureDescriptor.arrayLength = 1;
    textureDescriptor.mipmapLevelCount = 1;
    textureDescriptor.sampleCount = 1;
    
    texture_data.texture = [metal_ctx.device newTextureWithDescriptor:textureDescriptor];
    
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    NSUInteger bytesPerPixel = 4;
    [texture_data.texture replaceRegion:region mipmapLevel:0 withBytes:rgba32_buf bytesPerRow:width * bytesPerPixel];
}

static void gfx_metal_set_sampler_parameters(int tile, bool linear_filter, uint32_t cms, uint32_t cmt) {
    GfxTexture *texture_data = metal_ctx.textures[current_texture_ids[tile]];
    texture_data.linear_filtering = linear_filter;
    
    // This function is called twice per texture, the first one only to set default values.
    // Maybe that could be skipped? Anyway, make sure to release the first default sampler
    // state before setting the actual one.
    //   [texture_data->sampler release];
    
    texture_data.sampler = [metal_ctx sampleStateUsingLinearFilter:linear_filter filteringMode:state.current_filter_mode cms:cms cmt:cmt];
}

static void gfx_metal_set_depth_test_and_mask(bool depth_test, bool depth_mask) {
    state.depth_test_and_mask = (depth_test ? 1 : 0) | (depth_mask ? 2 : 0);
}

static void gfx_metal_set_zmode_decal(bool zmode_decal) {
    state.decal_mode = zmode_decal;
}

static void gfx_metal_set_viewport(int x, int y, int width, int height) {
    state.viewportSize = { width, height };
    metal_ctx.layer.drawableSize = CGSizeMake(width, height);
}

static void gfx_metal_set_scissor(int x, int y, int width, int height) {
    // TODO: maybe we have to invert the y?
    state.scissor = { x, y, width, height };
}

static void gfx_metal_set_use_alpha(bool use_alpha) {
    // Already part of the pipeline state from shader info
}

static void gfx_metal_draw_triangles(float buf_vbo[], size_t buf_vbo_len, size_t buf_vbo_num_tris) {
    [metal_ctx drawTrianglesWithBufferData:buf_vbo bufferLength:buf_vbo_len andTriangleCount:buf_vbo_num_tris];
}

static void gfx_metal_on_resize(void) {
    // TODO: implement
}

static void gfx_metal_start_frame(void) {
    state.frame_uniforms.frameCount++;
    [metal_ctx startFrame];
}

void gfx_metal_end_frame(void) {
    [metal_ctx endFrame];
}

static void gfx_metal_finish_render(void) {
    // TODO: implement
}

int gfx_metal_create_framebuffer(void) {
    // TODO: implement
}

static void gfx_metal_update_framebuffer_parameters(int fb_id, uint32_t width, uint32_t height, uint32_t msaa_level, bool opengl_invert_y, bool render_target, bool has_depth_buffer, bool can_extract_depth) {
    // TODO: implement
    
    [metal_ctx configureDepthBuffer:has_depth_buffer msaaCount:msaa_level];
}

void gfx_metal_start_draw_to_framebuffer(int fb_id, float noise_scale) {
    // TODO: implement
    if (noise_scale != 0.0f) {
        state.frame_uniforms.noiseScale = 1.0f / noise_scale;
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
    std::map<std::pair<float, float>, uint16_t> res;
    return res;
}

void *gfx_metal_get_framebuffer_texture_id(int fb_id) {
    //return (void *)metal_ctx.textures[metal_ctx.current_tile];
}

void gfx_metal_select_texture_fb(int fb_id) {
    // TODO: implement
}

void gfx_metal_set_texture_filter(FilteringMode mode) {
    state.current_filter_mode = mode;
    gfx_texture_cache_clear();
}

FilteringMode gfx_metal_get_texture_filter(void) {
    return state.current_filter_mode;
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
