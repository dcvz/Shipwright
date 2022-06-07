#version 120 // 130 on non-macos

// loop: over used textures and add one per used texture - for (int i = 0; i < 2; i++) - if (cc_features.used_textures[i])
varying vec2 vTexCoord0;
varying vec2 vTexCoord1;

// loop: over 0, 2 and check if we should clamp - for (int j = 0; j < 2; j++) - if (cc_features.clamp[i][j])
varying float vTexClampS0;
varying float vTexClampT0;
varying float vTexClampS1;
varying float vTexClampT1;
// end loop
// end loop

// if fog features
varying vec4 vFog;

// if grayscale feature
varying vec4 vGrayscaleColor;

// loop: over num_inputs (setting alpha) - for (int i = 0; i < cc_features.num_inputs; i++)
varying vec4 vInput1; // attribute vec3 vInput1; if alpha disabled - index is i + 1 (does not start at 0)

// if used_textures[0]
uniform sampler2D uTex0;
//uniform vec2 texSize0; // we use this for older opengl versions since we cannot get the texture size

// if used_textures[1]
uniform sampler2D uTex1;
//uniform vec2 texSize1; // we use this for older opengl versions since we cannot get the texture size

// if alpha feature && noise feature
uniform int frame_count;
uniform float noise_scale;

float random(in vec3 value) {
    float random = dot(sin(value), vec3(12.9898, 78.233, 37.719));
    return fract(sin(random) * 143758.5453);
}

// if filter mode is THREE_POINT
#define TEX_OFFSET(off) texture2D(tex, texCoord - (off)/texSize)
vec4 filter3point(in sampler2D tex, in vec2 texCoord, in vec2 texSize) {
    vec2 offset = fract(texCoord*texSize - vec2(0.5));
    offset -= step(1.0, offset.x + offset.y);
    vec4 c0 = TEX_OFFSET(offset);
    vec4 c1 = TEX_OFFSET(vec2(offset.x - sign(offset.x), offset.y));
    vec4 c2 = TEX_OFFSET(vec2(offset.x, offset.y - sign(offset.y)));
    return c0 + abs(offset.x)*(c1-c0) + abs(offset.y)*(c2-c0);
}

vec4 hookTexture2D(in sampler2D tex, in vec2 uv, in vec2 texSize) {
    return filter3point(tex, uv, texSize);
}

// else if filter mode is not THREE_POINT
vec4 hookTexture2D(in sampler2D tex, in vec2 uv, in vec2 texSize) {
    return texture2D(tex, uv);
}

void main() {
    // loop: over used textures and add one per texture - for (int i = 0; i < 2; i++) - if (cc_features.used_textures[i])
    // bool s = cc_features.clamp[i][0], t = cc_features.clamp[i][1]; - used in the conditionals below

    vec2 texSize0 = textureSize(uTex0, 0); // added if not apple platform
    vec2 texSize1 = textureSize(uTex1, 0); // added if not apple platform

    // if (!s || !t)
    vec4 texVal0 = hookTexture2D(uTex0, vTexCoord0, texSize0);
    vec4 texVal1 = hookTexture2D(uTex1, vTexCoord1, texSize1);
    // else
    // if s && t
    vec4 texVal0 = hookTexture2D(uTex0, clamp(vTexCoord0, 0.5 / texSize0, vec2(vTexClampS0, vTexClampT0)), texSize0);
    vec4 texVal1 = hookTexture2D(uTex1, clamp(vTexCoord1, 0.5 / texSize1, vec2(vTexClampS1, vTexClampT1)), texSize1);
    // else if (s)
    vec4 texVal0 = hookTexture2D(uTex0, vec2(clamp(vTexCoord0.s, 0.5 / texSize0.s, vTexClampS0), vTexCoord0.t), texSize0);
    vec4 texVal1 = hookTexture2D(uTex1, vec2(clamp(vTexCoord1.s, 0.5 / texSize1.s, vTexClampS1), vTexCoord1.t), texSize1);
    // else
    vec4 texVal0 = hookTexture2D(uTex0, vec2(vTexCoord0.s, clamp(vTexCoord0.t, 0.5 / texSize0.t, vTexClampT0)), texSize0);
    vec4 texVal1 = hookTexture2D(uTex1, vec2(vTexCoord1.s, clamp(vTexCoord1.t, 0.5 / texSize1.t, vTexClampT1)), texSize1);

    vec4 texel; vec3 texel;

    // if (!cc_features.color_alpha_same[c] && cc_features.opt_alpha)
    // TODO: there's some complex string interpolation going on here [skipping for now]

    // if features fog
    // if features alpha
    texel = vec4(mix(texel.rgb, vFog.rgb, vFog.a), texel.a);
    // else
    texel = mix(texel, vFog.rgb, vFog.a);

    // if cc_features.opt_texture_edge && cc_features.opt_alpha
    if (texel.a > 0.19) texel.a = 1.0; else discard;

    // if (cc_features.opt_alpha && cc_features.opt_noise)
    texel.a *= floor(clamp(random(vec3(floor(gl_FragCoord.xy * noise_scale), float(frame_count))) + texel.a, 0.0, 1.0));

    // if grayscale feature
    float intensity = (texel.r + texel.g + texel.b) / 3.0;
    vec3 new_texel = vGrayscaleColor.rgb * intensity;
    texel.rgb = mix(texel.rgb, new_texel, vGrayscaleColor.a);

    // if alpha feature
    // if (cc_features.opt_alpha_threshold)
    if (texel.a < 8.0 / 256.0) discard;
    // if (cc_features.opt_invisible)
    texel.a = 0.0;
    gl_FragColor = texel;
    // else
    gl_FragColor = vec4(texel, 1.0);
}
