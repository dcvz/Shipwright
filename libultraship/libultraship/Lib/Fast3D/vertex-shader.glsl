#version 110
attribute vec4 aVtxPos;

// loop: over used textures and add one per used texture - for (int i = 0; i < 2; i++) - if (cc_features.used_textures[i])
attribute vec2 aTexCoord0; // 0 - 1
varying vec2 vTexCoord0; // 0 - 1

// if we use two textures then this is also created
attribute vec2 aTexCoord1; // 0 - 1
varying vec2 vTexCoord1; // 0 - 1

// loop: over 0, 2 and check if we should clamp - for (int j = 0; j < 2; j++) - if (cc_features.clamp[i][j])
attribute float aTexClampS0; // S0, T0, S1, T1
attribute float aTexClampT0; // S0, T0, S1, T1
varying float vTexClampS0; // S0, T0, S1, T1
varying float vTexClampT0; // S0, T0, S1, T1

attribute float aTexClampS1; // S0, T0, S1, T1
attribute float aTexClampT1; // S0, T0, S1, T1
varying float vTexClampS1; // S0, T0, S1, T1
varying float vTexClampT1; // S0, T0, S1, T1
// end of loop
// end of loop

// if fog feature
attribute vec4 aFog;
varying vec4 vFog;

// if greyscale feature
attribute vec4 aGrayscaleColor;
varying vec4 vGrayscaleColor;

// loop: over num_inputs (setting alpha) - for (int i = 0; i < cc_features.num_inputs; i++)
attribute vec4 aInput1; // attribute vec3 aInput1; if alpha disabled - index is i + 1 (does not start at 0)
varying vec4 vInput1; // varying vec3 vInput1; if alpha disabled - index is i + 1 (does not start at 0)

void main() {
    // loop: over used textures and add one per texture - for (int i = 0; i < 2; i++) - if (cc_features.used_textures[i])
    vTexCoord0 = aTexCoord0; // 0 - 1
    vTexCoord1 = aTexCoord1; // 0 - 1
    // loop: over 0, 2 and check if we should clamp - for (int j = 0; j < 2; j++) - if (cc_features.clamp[i][j])
    vTexClampS0 = aTexClampS0; // S0, T0, S1, T1
    vTexClampT0 = aTexClampT0; // S0, T0, S1, T1
    vTexClampS1 = aTexClampS1; // S0, T0, S1, T1
    vTexClampT1 = aTexClampT1; // S0, T0, S1, T1
    // end of loop
    // end of loop

    // if fog feature
    vFog = aFog;

    // if greyscale feature
    vGrayscaleColor = aGrayscaleColor;

    // loop: over num_inputs (setting alpha) - for (int i = 0; i < cc_features.num_inputs; i++)
    vInput1 = aInput1; // index is i + 1 (does not start at 0)

    gl_Position = aVtxPos;
}
