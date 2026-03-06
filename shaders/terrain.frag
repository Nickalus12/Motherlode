#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// ============================================================================
// Motherlode Terrain Fragment Shader
// SDF terrain rendering with procedural texturing, dynamic lighting,
// ambient occlusion, animated effects, and procedural grass.
// ============================================================================

// --- Uniforms (Flutter: sequential float indices, samplers separate) --------
uniform float uSizeX;          // index 0 - output rect width pixels
uniform float uSizeY;          // index 1 - output rect height pixels
uniform float uChunkWorldX;    // index 2 - chunk world X in tiles
uniform float uChunkWorldY;    // index 3 - chunk world Y in tiles
uniform float uTime;           // index 4 - animation time
uniform float uPodPosX;        // index 5 - pod world X
uniform float uPodPosY;        // index 6 - pod world Y
uniform float uPodLightRadius; // index 7 - light radius in tiles
uniform float uDepthFeet;      // index 8 - camera depth
uniform float uChunkSize;      // index 9 - chunk size (32)
uniform sampler2D uSdfTexture; // sampler index 0

// --- Derived convenience ---
#define uSize        vec2(uSizeX, uSizeY)
#define uChunkWorld  vec2(uChunkWorldX, uChunkWorldY)
#define uPodPos      vec2(uPodPosX, uPodPosY)

// --- Constants --------------------------------------------------------------
const float PI            = 3.14159265359;
const float TAU           = 6.28318530718;
const float FEET_PER_TILE = 15.0;

// Material IDs (from G channel * 255)
const int MAT_TOPSOIL    = 0;
const int MAT_SANDSTONE  = 1;
const int MAT_LIMESTONE  = 2;
const int MAT_SHALE      = 3;
const int MAT_GRANITE    = 4;
const int MAT_BASALT     = 5;
const int MAT_OBSIDIAN   = 6;
const int MAT_MANTLE     = 7;
const int MAT_HELLSTONE  = 8;
const int MAT_ORE        = 9;
const int MAT_LAVA       = 10;

// Flag bits (from A channel * 255)
const int FLAG_ORE     = 1;
const int FLAG_LAVA    = 2;
const int FLAG_BEDROCK = 4;


// ============================================================================
//  SIMPLEX NOISE  (Ashima Arts / webgl-noise)
// ============================================================================

vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute3(vec3 x) { return mod289_3(((x * 34.0) + 10.0) * x); }
vec4 permute4(vec4 x) { return mod289_4(((x * 34.0) + 10.0) * x); }

// 2D Simplex Noise
float snoise2(vec2 v) {
    const vec4 C = vec4(
        0.211324865405187,   // (3 - sqrt(3)) / 6
        0.366025403784439,   // 0.5 * (sqrt(3) - 1)
       -0.577350269189626,   // -1 + 2 * C.x
        0.024390243902439    // 1 / 41
    );
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289_2(i);
    vec3 p = permute3(permute3(i.y + vec3(0.0, i1.y, 1.0))
                             + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x  = 2.0 * fract(p * C.www) - 1.0;
    vec3 h  = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// 3D Simplex Noise
float snoise3(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g  = step(x0.yzx, x0.xyz);
    vec3 l  = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289_3(i);
    vec4 p = permute4(permute4(permute4(
             i.z + vec4(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857; // 1/7
    vec3  ns = n_ * D.wyz - D.xzx;
    vec4 j  = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = 1.79284291400159 - 0.85373472095314 *
                vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// FBM 2D (4 octaves)
float fbm2(vec2 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        f += a * snoise2(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

// FBM 3D (3 octaves, for animation)
float fbm3(vec3 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) {
        f += a * snoise3(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}


// ============================================================================
//  UTILITY
// ============================================================================

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}


// ============================================================================
//  SDF TEXTURE SAMPLING
// ============================================================================

// Raw SDF value: [0,1] -> [-2, +2]
float sampleSdf(vec2 uv) {
    return (texture(uSdfTexture, uv).r - 0.5) * 4.0;
}

// Full decode: vec4(sdf, materialId, subType, flags)
vec4 sampleFull(vec2 uv) {
    vec4 texel = texture(uSdfTexture, uv);
    return vec4(
        (texel.r - 0.5) * 4.0,
        floor(texel.g * 255.0 + 0.5),
        floor(texel.b * 255.0 + 0.5),
        floor(texel.a * 255.0 + 0.5)
    );
}


// ============================================================================
//  SDF SURFACE NORMALS
// ============================================================================

vec2 computeNormal(vec2 uv) {
    vec2 ts = vec2(1.0 / uChunkSize);
    float sdfL = sampleSdf(uv - vec2(ts.x, 0.0));
    float sdfR = sampleSdf(uv + vec2(ts.x, 0.0));
    float sdfU = sampleSdf(uv - vec2(0.0, ts.y));
    float sdfD = sampleSdf(uv + vec2(0.0, ts.y));
    vec2 grad = vec2(sdfR - sdfL, sdfD - sdfU);
    float len = length(grad);
    return (len > 0.001) ? grad / len : vec2(0.0, -1.0);
}


// ============================================================================
//  MATERIAL COLOR PALETTE
// ============================================================================

vec3 getMaterialBaseColor(int matId, vec2 worldPos, float subType) {
    vec3 col;
    if      (matId == MAT_TOPSOIL)   col = vec3(0.35, 0.27, 0.16);
    else if (matId == MAT_SANDSTONE) col = vec3(0.40, 0.31, 0.19);
    else if (matId == MAT_LIMESTONE) col = vec3(0.35, 0.32, 0.23);
    else if (matId == MAT_SHALE)     col = vec3(0.361, 0.290, 0.220);
    else if (matId == MAT_GRANITE)   col = vec3(0.30, 0.30, 0.30);
    else if (matId == MAT_BASALT)    col = vec3(0.282, 0.282, 0.282);
    else if (matId == MAT_OBSIDIAN)  col = vec3(0.176, 0.106, 0.239);
    else if (matId == MAT_MANTLE)    col = vec3(0.227, 0.082, 0.082);
    else if (matId == MAT_HELLSTONE) col = vec3(0.102, 0.020, 0.020);
    else if (matId == MAT_ORE)       col = vec3(0.85, 0.72, 0.20);
    else if (matId == MAT_LAVA)      col = vec3(1.0, 0.270, 0.0);
    else                             col = vec3(0.5, 0.5, 0.5);

    // Ore sub-type color variation
    if (matId == MAT_ORE) {
        float oreHue = subType / 255.0;
        col = mix(vec3(0.85, 0.72, 0.20), vec3(0.60, 0.85, 0.45), oreHue * 0.3);
        col = mix(col, vec3(0.78, 0.78, 0.82), step(128.0, subType) * 0.5);
    }
    return col;
}


// ============================================================================
//  PROCEDURAL TEXTURING PER MATERIAL
// ============================================================================

vec3 applyProceduralTexture(vec3 baseColor, int matId, vec2 worldPos, float sdf) {
    vec3 col = baseColor;
    float n;

    // Topsoil: organic blobby noise + scattered pebbles
    if (matId == MAT_TOPSOIL) {
        n = fbm2(worldPos * 3.0) * 0.15;
        col += n;
        float pebble = smoothstep(0.68, 0.72, snoise2(worldPos * 18.0));
        col = mix(col, col * 0.65, pebble);
    }

    // Sandstone: cross-bedding layers + sand grain scatter
    else if (matId == MAT_SANDSTONE) {
        n = fbm2(worldPos * 2.5) * 0.12;
        col += n;
        float band = sin(worldPos.y * 8.0 + snoise2(worldPos * 1.5) * 2.0) * 0.06;
        col += band;
        float grain = smoothstep(0.6, 0.65, snoise2(worldPos * 25.0));
        col = mix(col, col * 0.7, grain * 0.4);
    }

    // Limestone: horizontal bands + fossil speckles
    else if (matId == MAT_LIMESTONE) {
        float bandNoise = snoise2(worldPos * vec2(0.5, 0.1)) * 1.5;
        float bands = sin(worldPos.y * 12.0 + bandNoise) * 0.08;
        col += bands;
        float fossil = smoothstep(0.72, 0.76, snoise2(worldPos * 14.0));
        col = mix(col, col * 1.15, fossil * 0.3);
    }

    // Shale: thin laminated layers
    else if (matId == MAT_SHALE) {
        float laminate = sin(worldPos.y * 40.0 + snoise2(worldPos * vec2(2.0, 0.5)) * 3.0);
        laminate = smoothstep(-0.2, 0.2, laminate) * 0.12;
        col += laminate - 0.06;
        float fracture = abs(snoise2(worldPos * vec2(1.0, 30.0)));
        col -= smoothstep(0.92, 0.96, fracture) * 0.15;
    }

    // Granite: speckled crystalline (quartz, feldspar, mica)
    else if (matId == MAT_GRANITE) {
        float quartz   = smoothstep(0.5, 0.7, snoise2(worldPos * 12.0));
        float feldspar = smoothstep(0.4, 0.6, snoise2(worldPos * 12.0 + 77.7));
        float mica     = smoothstep(0.7, 0.8, snoise2(worldPos * 20.0 + 155.5));
        col = mix(col, vec3(0.62, 0.60, 0.58), quartz * 0.3);
        col = mix(col, vec3(0.55, 0.42, 0.38), feldspar * 0.25);
        col = mix(col, vec3(0.18, 0.18, 0.16), mica * 0.35);
    }

    // Basalt: columnar joints + vesicle bubbles
    else if (matId == MAT_BASALT) {
        vec2 bp = worldPos * 6.0;
        float hex = snoise2(bp) + 0.5 * snoise2(bp * 2.0);
        float edge = 1.0 - smoothstep(0.0, 0.15, abs(fract(hex * 2.5) - 0.5));
        col -= edge * 0.08;
        float vesicle = smoothstep(0.78, 0.82, snoise2(worldPos * 22.0));
        col = mix(col, col * 0.7, vesicle * 0.5);
    }

    // Obsidian: glassy smooth + conchoidal fractures + iridescence
    else if (matId == MAT_OBSIDIAN) {
        float sheen = snoise2(worldPos * 1.5) * 0.04;
        col += sheen;
        float fracture1 = abs(snoise2(worldPos * vec2(8.0, 3.0) + 42.0));
        float fracture2 = abs(snoise2(worldPos * vec2(3.0, 9.0) + 91.0));
        float fracLines = smoothstep(0.90, 0.95, max(fracture1, fracture2));
        col = mix(col, vec3(0.25, 0.15, 0.35), fracLines * 0.6);
        float irid = sin(worldPos.x * 20.0 + worldPos.y * 15.0 + uTime * 0.3) * 0.03;
        col.b += irid;
        col.r += irid * 0.5;
    }

    // Mantle Rock: pulsing heat shimmer + magma veins
    else if (matId == MAT_MANTLE) {
        float heat = fbm3(vec3(worldPos * 2.0, uTime * 0.4)) * 0.15;
        col += heat;
        float vein = smoothstep(0.55, 0.65, snoise3(vec3(worldPos * 4.0, uTime * 0.2)));
        col = mix(col, vec3(0.6, 0.15, 0.02), vein * 0.4);
    }

    // Hellstone: intense animated heat + cracked ember veins
    else if (matId == MAT_HELLSTONE) {
        float pulse = fbm3(vec3(worldPos * 1.5, uTime * 0.6)) * 0.12;
        col += pulse;
        float crack = smoothstep(0.5, 0.6, snoise3(vec3(worldPos * 5.0, uTime * 0.3)));
        col = mix(col, vec3(0.8, 0.1, 0.0), crack * 0.5);
        float glow = smoothstep(-0.3, 0.0, sdf) * 0.15;
        col += vec3(glow * 0.6, glow * 0.05, 0.0);
    }

    return col;
}


// ============================================================================
//  AMBIENT OCCLUSION
// ============================================================================

float computeAO(float sdf) {
    return smoothstep(-1.5, 0.0, sdf) * 0.7 + 0.3;
}


// ============================================================================
//  DYNAMIC LIGHTING
// ============================================================================

vec3 computeLighting(vec3 baseColor, vec2 worldPos, vec2 normal, float sdf,
                     float ao, int matId, int flags, float pixelDepthFeet) {
    // Depth-based ambient darkening (per-pixel)
    float depthDark = clamp(1.0 - pixelDepthFeet / 8000.0, 0.15, 1.0);
    float ambient = 0.08 * depthDark;

    // Sky ambient near surface (per-pixel)
    float skyAmbient = smoothstep(300.0, 0.0, pixelDepthFeet) * 0.35;
    ambient += skyAmbient;

    // Pod headlight
    vec2 toLight = uPodPos - worldPos;
    float dist = length(toLight);
    vec2 lightDir = (dist > 0.001) ? toLight / dist : vec2(0.0, -1.0);

    // Inverse-square attenuation (physically plausible falloff)
    float atten = 1.0 / (1.0 + dist * dist / (uPodLightRadius * uPodLightRadius));

    // Diffuse with wrap lighting
    float NdotL = max(dot(normal, lightDir), 0.0);
    float wrap = 0.25;
    float diffuse = max((NdotL + wrap) / (1.0 + wrap), 0.0);

    // Rim light at glancing angles
    float rim = pow(1.0 - max(dot(normal, lightDir), 0.0), 3.0) * 0.1 * atten;

    // Combined
    float totalLight = ambient + diffuse * atten * 1.2 + rim;
    totalLight *= ao;

    vec3 litColor = baseColor * totalLight;

    // Warm headlight tint
    litColor += baseColor * atten * vec3(0.08, 0.06, 0.02) * NdotL;

    // Lava / emissive bypass lighting
    // flags bit 1 = FLAG_LAVA (value 2): extract via mod(floor(flags/2), 2)
    float isLavaF = step(0.5, float(matId == MAT_LAVA ? 1 : 0) + mod(floor(float(flags) / 2.0), 2.0));
    if (isLavaF > 0.5) return baseColor;

    return litColor;
}


// ============================================================================
//  ORE SHIMMER
// ============================================================================

vec3 applyOreShimmer(vec3 col, vec2 worldPos, int matId, int flags) {
    // flags bit 0 = FLAG_ORE (value 1): extract via mod(flags, 2)
    float isOreF = step(0.5, float(matId == MAT_ORE ? 1 : 0) + mod(float(flags), 2.0));
    if (isOreF < 0.5) return col;

    // Multi-frequency shimmer
    float shimmer = sin(uTime * 2.0 + worldPos.x * 10.0 + worldPos.y * 7.0) * 0.5 + 0.5;
    shimmer *= sin(uTime * 3.1 + worldPos.x * 5.5 - worldPos.y * 8.3) * 0.5 + 0.5;
    shimmer = pow(shimmer, 2.0) * 0.35;

    // Sparkle highlights
    float sparkle = snoise2(worldPos * 30.0 + uTime * 1.5);
    sparkle = pow(max(sparkle, 0.0), 8.0) * 0.6;

    col += (shimmer + sparkle) * vec3(1.0, 0.9, 0.5);
    return col;
}


// ============================================================================
//  LAVA ANIMATION
// ============================================================================

vec3 applyLavaEffect(vec3 col, vec2 worldPos, float sdf, int matId, int flags) {
    float isLavaF = step(0.5, float(matId == MAT_LAVA ? 1 : 0) + mod(floor(float(flags) / 2.0), 2.0));
    if (isLavaF < 0.5) return col;

    vec2 flowUV = worldPos * 2.0 + vec2(uTime * 0.1, uTime * 0.05);
    float flow = fbm3(vec3(flowUV, uTime * 0.3));
    float pulse = sin(uTime * 1.5 + worldPos.x * 3.0) * 0.15 + 0.85;

    float heat = smoothstep(-1.0, -0.1, sdf);
    vec3 hotColor  = vec3(1.0, 0.65, 0.1) * 1.3;
    vec3 coolColor = vec3(0.7, 0.12, 0.0);
    col = mix(coolColor, hotColor, heat * pulse);

    float vein = smoothstep(0.3, 0.5, flow) * heat;
    col = mix(col, vec3(1.0, 0.9, 0.4), vein * 0.5);
    col *= 1.0 + pulse * 0.2;

    return col;
}


// ============================================================================
//  PROCEDURAL GRASS
// ============================================================================

vec3 applyGrass(vec3 currentColor, float currentAlpha, vec2 uv, vec2 worldPos,
                float sdf, int matId, out float grassAlpha) {
    grassAlpha = 0.0;
    if (matId != MAT_TOPSOIL && matId != MAT_SANDSTONE) return currentColor;

    vec2 texelSize = vec2(1.0 / uChunkSize);
    float sdfAbove = sampleSdf(uv - vec2(0.0, texelSize.y));

    // Surface cell: solid here, air above
    float isSurface = step(0.001, sdfAbove) * step(0.001, -sdf);
    if (isSurface < 0.5) return currentColor;

    // Simple grass color blend based on world position noise
    float grassNoise = snoise2(vec2(worldPos.x * 2.0, 0.0)) * 0.5 + 0.5;
    vec3 grassDark = vec3(0.12, 0.30, 0.06);
    vec3 grassLight = vec3(0.25, 0.40, 0.10);
    vec3 grassColor = mix(grassDark, grassLight, grassNoise);

    // Gentle wind sway on color only (no geometry)
    float wind = sin(uTime * 1.2 + worldPos.x * 0.5) * 0.08;
    grassColor += wind;

    // Blend grass onto top portion of surface cells
    float surfaceBlend = smoothstep(-0.5, -0.05, sdf) * 0.7;
    grassAlpha = 0.0; // No alpha extension needed
    return mix(currentColor, grassColor, surfaceBlend * isSurface);
}


// ============================================================================
//  MAIN
// ============================================================================

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;

    // World position of this fragment (in tiles)
    vec2 localTile = uv * uChunkSize;
    vec2 worldPos  = uChunkWorld + localTile;

    // Sample SDF texture
    vec4 data  = sampleFull(uv);
    float sdf  = data.x;
    int matId  = int(data.y);
    float subType = data.z;
    int flags  = int(data.w);

    // Anti-aliasing: pixel width in SDF space
    float sdfPerPixel = 4.0 / uSizeX;
    float aaWidth = sdfPerPixel * 1.5;

    // Air: fully transparent (discard not reliable on all Flutter backends)
    float alpha = smoothstep(aaWidth, -aaWidth, sdf);
    if (alpha < 0.005) {
        fragColor = vec4(0.0);
        return;
    }

    // Surface normal from SDF gradient
    vec2 normal = computeNormal(uv);

    // Base material color
    vec3 baseColor = getMaterialBaseColor(matId, worldPos, subType);

    // Procedural texturing
    baseColor = applyProceduralTexture(baseColor, matId, worldPos, sdf);

    // Ambient occlusion
    float ao = computeAO(sdf);

    // Per-pixel depth in feet
    float pixelDepthFeet = worldPos.y * FEET_PER_TILE;

    // Dynamic lighting (per-pixel depth)
    vec3 litColor = computeLighting(baseColor, worldPos, normal, sdf, ao, matId, flags, pixelDepthFeet);

    // Ore shimmer
    litColor = applyOreShimmer(litColor, worldPos, matId, flags);

    // Lava animation
    litColor = applyLavaEffect(litColor, worldPos, sdf, matId, flags);

    // Procedural grass
    float grassAlpha;
    litColor = applyGrass(litColor, alpha, uv, worldPos, sdf, matId, grassAlpha);
    alpha = max(alpha, grassAlpha);

    // Fog of war: terrain far from pod fades to black
    float distToPod = length(worldPos - uPodPos);
    float fogOfWar = smoothstep(uPodLightRadius * 2.0, uPodLightRadius * 0.3, distToPod);
    // Surface terrain (shallow) gets natural light
    float surfaceLight = smoothstep(200.0, 0.0, pixelDepthFeet);
    fogOfWar = max(fogOfWar, surfaceLight);
    litColor *= fogOfWar;

    // Depth atmosphere tint (deep = cool blue-purple cast, per-pixel)
    float depthTint = smoothstep(1000.0, 6000.0, pixelDepthFeet);
    litColor = mix(litColor, litColor * vec3(0.85, 0.80, 0.95), depthTint * 0.25);

    fragColor = vec4(litColor, alpha);
}
