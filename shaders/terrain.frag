#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// ============================================================================
// Motherlode Terrain Fragment Shader
// SDF terrain rendering with smooth material blending, natural fog of war,
// dynamic lighting, ambient occlusion, procedural texturing, subsurface
// scattering, wetness, parallax depth, and enhanced ore/grass effects.
// ============================================================================

// --- Uniforms ----------------------------------------------------------------
uniform float uSizeX;          // index 0
uniform float uSizeY;          // index 1
uniform float uChunkWorldX;    // index 2
uniform float uChunkWorldY;    // index 3
uniform float uTime;           // index 4
uniform float uPodPosX;        // index 5
uniform float uPodPosY;        // index 6
uniform float uPodLightRadius; // index 7
uniform float uDepthFeet;      // index 8
uniform float uChunkSize;      // index 9
uniform float uScreenScale;    // index 10 - screen pixels per tile (camera zoom)
uniform sampler2D uSdfTexture; // sampler index 0

#define uSize        vec2(uSizeX, uSizeY)
#define uChunkWorld  vec2(uChunkWorldX, uChunkWorldY)
#define uPodPos      vec2(uPodPosX, uPodPosY)

const float PI            = 3.14159265359;
const float FEET_PER_TILE = 15.0;

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

// Water table depth in feet (sandstone/limestone transition area)
const float WATER_TABLE_DEPTH = 800.0;


// ============================================================================
//  SIMPLEX NOISE
// ============================================================================

vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute3(vec3 x) { return mod289_3(((x * 34.0) + 10.0) * x); }
vec4 permute4(vec4 x) { return mod289_4(((x * 34.0) + 10.0) * x); }

float snoise2(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
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
    float n_ = 0.142857142857;
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

// LOD-aware FBM: fewer octaves when zoomed out
float fbm2_lod(vec2 p, int maxOct) {
    float f = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        if (i >= maxOct) break;
        f += a * snoise2(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

float fbm2(vec2 p) {
    float f = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        f += a * snoise2(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

float fbm2_4oct(vec2 p) {
    float f = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        f += a * snoise2(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

float fbm3(vec3 p) {
    float f = 0.0;
    float a = 0.5;
    for (int i = 0; i < 2; i++) {
        f += a * snoise3(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

// Simple hash for flower placement
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}


// ============================================================================
//  SDF TEXTURE SAMPLING
// ============================================================================

float sampleSdf(vec2 uv) {
    return (texture(uSdfTexture, uv).r - 0.5) * 4.0;
}

vec4 texelAtCell(float cx, float cy) {
    vec2 uv = (vec2(cx, cy) + 0.5) / uChunkSize;
    uv = clamp(uv, 0.5 / uChunkSize, 1.0 - 0.5 / uChunkSize);
    return texture(uSdfTexture, uv);
}

vec3 decodeCell(vec4 texel) {
    return vec3(
        floor(texel.g * 255.0 + 0.5),
        floor(texel.b * 255.0 + 0.5),
        floor(texel.a * 255.0 + 0.5)
    );
}


// ============================================================================
//  COMBINED SURFACE PROPERTIES (Normal + AO in one pass)
//  Returns: .xy = normal, .z = AO value
// ============================================================================

vec3 computeSurfaceProps(vec2 uv, float sdfCenter) {
    vec2 ts = vec2(1.0 / uChunkSize);

    // 4 neighbor samples for normal
    float sdfL = sampleSdf(uv - vec2(ts.x, 0.0));
    float sdfR = sampleSdf(uv + vec2(ts.x, 0.0));
    float sdfU = sampleSdf(uv - vec2(0.0, ts.y));
    float sdfD = sampleSdf(uv + vec2(0.0, ts.y));

    // Normal from gradient
    vec2 grad = vec2(sdfR - sdfL, sdfD - sdfU);
    float len = length(grad);
    vec2 normal = (len > 0.001) ? grad / len : vec2(0.0, -1.0);

    // AO from wider-tap neighbors (reuse existing samples at 1x distance,
    // approximate 2x with extrapolation to save 4 texture fetches)
    float avgNeighbor = (sdfL + sdfR + sdfU + sdfD) * 0.25;
    float baseAO = smoothstep(-1.5, 0.0, sdfCenter) * 0.6 + 0.4;
    float cavity = smoothstep(0.0, -0.5, sdfCenter - avgNeighbor) * 0.15;
    float ao = max(baseAO - cavity, 0.15);

    return vec3(normal, ao);
}


// ============================================================================
//  MATERIAL COLOR PALETTE
// ============================================================================

vec3 getMatColor(float matIdF, vec2 wp, float subType) {
    int matId = int(matIdF);
    vec3 col;
    if      (matId == MAT_TOPSOIL)   col = vec3(0.45, 0.35, 0.22);
    else if (matId == MAT_SANDSTONE) col = vec3(0.55, 0.42, 0.28);
    else if (matId == MAT_LIMESTONE) col = vec3(0.50, 0.47, 0.38);
    else if (matId == MAT_SHALE)     col = vec3(0.40, 0.34, 0.28);
    else if (matId == MAT_GRANITE)   col = vec3(0.45, 0.44, 0.43);
    else if (matId == MAT_BASALT)    col = vec3(0.35, 0.34, 0.38);
    else if (matId == MAT_OBSIDIAN)  col = vec3(0.22, 0.14, 0.28);
    else if (matId == MAT_MANTLE)    col = vec3(0.30, 0.12, 0.10);
    else if (matId == MAT_HELLSTONE) col = vec3(0.18, 0.06, 0.05);
    else if (matId == MAT_ORE)       col = vec3(0.90, 0.78, 0.30);
    else if (matId == MAT_LAVA)      col = vec3(1.0, 0.35, 0.05);
    else                             col = vec3(0.5, 0.5, 0.5);

    if (matId == MAT_ORE) {
        float oreHue = subType / 255.0;
        col = mix(vec3(0.90, 0.78, 0.30), vec3(0.65, 0.88, 0.50), oreHue * 0.3);
        col = mix(col, vec3(0.82, 0.82, 0.88), step(128.0, subType) * 0.5);
    }
    return col;
}


// ============================================================================
//  SMOOTH MATERIAL COLOR BLENDING
// ============================================================================

vec3 getBlendedColor(vec2 uv, vec2 worldPos) {
    vec2 cellPos = uv * uChunkSize - 0.5;
    vec2 cell0 = floor(cellPos);
    vec2 f = cellPos - cell0;
    vec2 t = f * f * (3.0 - 2.0 * f);

    vec4 r00 = texelAtCell(cell0.x,       cell0.y);
    vec4 r10 = texelAtCell(cell0.x + 1.0, cell0.y);
    vec4 r01 = texelAtCell(cell0.x,       cell0.y + 1.0);
    vec4 r11 = texelAtCell(cell0.x + 1.0, cell0.y + 1.0);

    vec3 d00 = decodeCell(r00);
    vec3 d10 = decodeCell(r10);
    vec3 d01 = decodeCell(r01);
    vec3 d11 = decodeCell(r11);

    vec3 c00 = getMatColor(d00.x, worldPos, d00.y);
    vec3 c10 = getMatColor(d10.x, worldPos, d10.y);
    vec3 c01 = getMatColor(d01.x, worldPos, d01.y);
    vec3 c11 = getMatColor(d11.x, worldPos, d11.y);

    vec3 top = mix(c00, c10, t.x);
    vec3 bot = mix(c01, c11, t.x);
    return mix(top, bot, t.y);
}


// ============================================================================
//  PARALLAX DEPTH EFFECT — fake 3D for deep interior cells
// ============================================================================

vec2 applyParallax(vec2 worldPos, vec2 uv, float sdf) {
    // Only apply deep inside solid ground
    float parallaxMask = smoothstep(-0.2, -0.8, sdf);
    if (parallaxMask < 0.01) return worldPos;

    // View direction from cell center to fragment
    vec2 viewDir = fract(uv * uChunkSize) - 0.5;

    // Fake heightmap from noise
    float height = snoise2(worldPos * 5.0) * 0.5 + 0.5;

    // Small offset for subtle depth illusion
    float parallaxStrength = 0.15;
    vec2 offset = viewDir * height * parallaxStrength * parallaxMask;

    return worldPos - offset;
}


// ============================================================================
//  PROCEDURAL TEXTURING PER MATERIAL — with parallax and SSS prep
// ============================================================================

vec3 applyProceduralTexture(vec3 baseColor, int matId, vec2 worldPos, float sdf,
                            vec2 normal, vec2 uv, int lodOctaves) {
    vec3 col = baseColor;

    // Apply parallax offset for deep interior texturing
    vec2 texPos = applyParallax(worldPos, uv, sdf);

    // Noise-based bump for all rock types (simulates normal-mapped micro-detail)
    float microBump = snoise2(texPos * 25.0) * 0.03;

    if (matId == MAT_TOPSOIL) {
        col += fbm2_lod(texPos * 3.0, lodOctaves) * 0.12;
        float pebble = smoothstep(0.68, 0.72, snoise2(texPos * 18.0));
        col = mix(col, col * 0.7, pebble);
        // Root-like veins near surface
        float roots = smoothstep(0.85, 0.92, abs(snoise2(texPos * vec2(8.0, 2.0) + 33.0)));
        col = mix(col, col * 0.6, roots * 0.3);
    }
    else if (matId == MAT_SANDSTONE) {
        col += fbm2_lod(texPos * 2.5, lodOctaves) * 0.10;
        // Layered sediment bands
        float band1 = sin(texPos.y * 8.0 + snoise2(texPos * 1.5) * 2.0) * 0.04;
        float band2 = sin(texPos.y * 22.0 + snoise2(texPos * 0.8) * 3.0) * 0.02;
        col += band1 + band2;
        // Cross-bedding pattern
        float crossBed = sin(texPos.x * 4.0 + texPos.y * 12.0 +
                            snoise2(texPos * 0.5) * 4.0) * 0.025;
        col += crossBed;
    }
    else if (matId == MAT_LIMESTONE) {
        float bandNoise = snoise2(texPos * vec2(0.5, 0.1)) * 1.5;
        col += sin(texPos.y * 12.0 + bandNoise) * 0.06;
        // Fossil-like circular patterns
        float fossil = snoise2(texPos * 8.0);
        float fossilRing = smoothstep(0.02, 0.0, abs(fossil - 0.3)) * 0.12;
        col += fossilRing;
        // Moss/lichen patches on limestone
        float moss = smoothstep(0.4, 0.7, snoise2(texPos * 5.0 + 99.0));
        float mossDetail = smoothstep(0.3, 0.6, snoise2(texPos * 15.0 + 77.0));
        vec3 mossColor = vec3(0.22, 0.35, 0.18);
        col = mix(col, mossColor, moss * mossDetail * 0.25 * smoothstep(-0.5, 0.0, sdf));
    }
    else if (matId == MAT_SHALE) {
        float laminate = sin(texPos.y * 40.0 + snoise2(texPos * vec2(2.0, 0.5)) * 3.0);
        col += smoothstep(-0.2, 0.2, laminate) * 0.06 - 0.03;
        // Flaky fracture pattern
        float flake = snoise2(texPos * vec2(15.0, 5.0) + 42.0);
        col += smoothstep(0.7, 0.85, abs(flake)) * 0.04;
    }
    else if (matId == MAT_GRANITE) {
        float quartz = smoothstep(0.5, 0.7, snoise2(texPos * 12.0));
        float feldspar = smoothstep(0.4, 0.6, snoise2(texPos * 12.0 + 77.7));
        float mica = smoothstep(0.7, 0.8, snoise2(texPos * 20.0 + 155.5));
        col = mix(col, vec3(0.60, 0.58, 0.55), quartz * 0.2);
        col = mix(col, vec3(0.52, 0.42, 0.38), feldspar * 0.15);
        col = mix(col, vec3(0.22, 0.22, 0.20), mica * 0.25);
        // Sparkle on mica flakes — use chained multiply instead of pow
        float sRaw = max(snoise2(texPos * 40.0 + uTime * 0.5), 0.0);
        float s2 = sRaw * sRaw;
        float s4 = s2 * s2;
        float s8 = s4 * s4;
        float sparkle = s8 * s4; // pow 12
        col += sparkle * vec3(0.5, 0.5, 0.4) * 0.15;
    }
    else if (matId == MAT_BASALT) {
        vec2 bp = texPos * 6.0;
        float hex = snoise2(bp) + 0.5 * snoise2(bp * 2.0);
        float edge = 1.0 - smoothstep(0.0, 0.15, abs(fract(hex * 2.5) - 0.5));
        col -= edge * 0.05;
        // Vesicle (gas bubble) holes
        float vesicle = smoothstep(0.75, 0.82, snoise2(texPos * 14.0 + 200.0));
        col = mix(col, col * 0.65, vesicle * 0.3);
    }
    else if (matId == MAT_OBSIDIAN) {
        col += snoise2(texPos * 1.5) * 0.03;
        float fracLines = smoothstep(0.90, 0.95, abs(snoise2(texPos * vec2(8.0, 3.0) + 42.0)));
        col = mix(col, vec3(0.30, 0.18, 0.38), fracLines * 0.4);
        // Conchoidal fracture sheen
        float sheen = pow(max(dot(normal, vec2(0.0, -1.0)), 0.0), 3.0) * 0.15;
        col += vec3(0.15, 0.08, 0.22) * sheen;
        // Iridescent edge highlight
        float edgeDist = smoothstep(-0.3, 0.0, sdf);
        float iridescence = sin(sdf * 30.0 + texPos.x * 5.0) * 0.5 + 0.5;
        col += mix(vec3(0.1, 0.05, 0.2), vec3(0.05, 0.15, 0.1), iridescence)
             * edgeDist * 0.12;
    }
    else if (matId == MAT_MANTLE) {
        col += fbm3(vec3(texPos * 2.0, uTime * 0.3)) * 0.10;
        float vein = smoothstep(0.55, 0.65, snoise3(vec3(texPos * 4.0, uTime * 0.15)));
        col = mix(col, vec3(0.6, 0.18, 0.04), vein * 0.3);
        // Glowing cracks
        float crack = smoothstep(0.88, 0.95, abs(snoise2(texPos * vec2(6.0, 3.0))));
        float crackGlow = crack * (0.6 + 0.4 * sin(uTime * 1.2 + texPos.y * 2.0));
        col += vec3(0.8, 0.25, 0.02) * crackGlow * 0.35;
    }
    else if (matId == MAT_HELLSTONE) {
        col += fbm3(vec3(texPos * 1.5, uTime * 0.4)) * 0.08;
        // Lava fissures that glow
        float crack = smoothstep(0.5, 0.6, snoise3(vec3(texPos * 5.0, uTime * 0.2)));
        col = mix(col, vec3(0.8, 0.12, 0.0), crack * 0.4);
        col += vec3(smoothstep(-0.3, 0.0, sdf) * 0.10, 0.0, 0.0);
        // Deep cracks with bright lava glow
        float deepCrack = smoothstep(0.82, 0.92, abs(snoise2(texPos * vec2(4.0, 8.0) + 55.0)));
        float lavaGlow = deepCrack * (0.7 + 0.3 * sin(uTime * 2.0 + texPos.x * 3.0));
        col += vec3(1.0, 0.4, 0.05) * lavaGlow * 0.4;
    }

    // Apply micro-bump to all solid materials
    col += microBump;

    return col;
}


// ============================================================================
//  DYNAMIC LIGHTING — with specular, SSS, and wetness
// ============================================================================

vec3 computeLighting(vec3 baseColor, vec2 worldPos, vec2 normal, float sdf,
                     float ao, float pixelDepthFeet, int matId, float wetness) {

    // --- Depth-based ambient ---
    float depthNorm = clamp(pixelDepthFeet / 7000.0, 0.0, 1.0);
    float ambient = mix(0.35, 0.12, depthNorm);

    // Extra sky ambient near surface
    float skyAmbient = smoothstep(500.0, -50.0, pixelDepthFeet) * 0.55;
    ambient += skyAmbient;

    // --- Pod headlight ---
    vec2 toLight = uPodPos - worldPos;
    float dist = length(toLight);
    vec2 lightDir = (dist > 0.001) ? toLight / dist : vec2(0.0, -1.0);

    float effectiveRadius = uPodLightRadius * 1.5;
    float atten = effectiveRadius * effectiveRadius /
                  (dist * dist + effectiveRadius * effectiveRadius);

    // Wrap lighting for softer shadows
    float NdotL = max(dot(normal, lightDir), 0.0);
    float wrap = 0.35;
    float diffuse = max((NdotL + wrap) / (1.0 + wrap), 0.0);

    // --- Subsurface Scattering for translucent materials ---
    float sss = 0.0;
    if (matId == MAT_SANDSTONE || matId == MAT_LIMESTONE) {
        // Light wrapping from behind, modulated by thickness (SDF proximity)
        float thickness = smoothstep(-0.8, 0.0, sdf);
        float litFromBehind = max(dot(normal, -lightDir), 0.0);
        litFromBehind = litFromBehind * litFromBehind; // pow 2
        sss = litFromBehind * thickness * 0.4;
    }

    // --- Specular highlights ---
    vec2 viewDir = vec2(0.0, -1.0);
    vec2 halfVec = normalize(lightDir + viewDir);
    float NdotH = max(dot(normal, halfVec), 0.0);

    float specPower = 16.0;
    float specIntensity = 0.0;
    if (matId == MAT_GRANITE || matId == MAT_BASALT) {
        specIntensity = 0.15;
        specPower = 24.0;
    } else if (matId == MAT_OBSIDIAN) {
        specIntensity = 0.35;
        specPower = 48.0;
    } else if (matId == MAT_LIMESTONE || matId == MAT_SHALE) {
        specIntensity = 0.1;
        specPower = 16.0;
    } else if (matId == MAT_ORE) {
        specIntensity = 0.25;
        specPower = 32.0;
    }

    // Wetness boosts specular: shinier, tighter highlights
    specIntensity = mix(specIntensity, 0.55, wetness);
    specPower = mix(specPower, 96.0, wetness);

    float spec = pow(NdotH, specPower) * specIntensity * atten;

    // Subtle rim light
    float rim = pow(1.0 - max(dot(normal, lightDir), 0.0), 3.0) * 0.06 * atten;

    float totalLight = ambient + diffuse * atten * 1.4 + rim;
    totalLight *= ao;
    totalLight = max(totalLight, 0.08);

    // Wetness darkens the base color (water absorption)
    vec3 wetColor = baseColor * mix(1.0, 0.6, wetness);

    vec3 litColor = wetColor * totalLight;

    // Subsurface scattering contribution (warm light bleeding through)
    litColor += baseColor * sss * atten * vec3(1.0, 0.85, 0.7);

    // Specular is additive (white highlight)
    vec3 specColor = vec3(1.0, 0.97, 0.90);
    litColor += specColor * spec;

    // Warm headlight tint
    litColor += wetColor * atten * vec3(0.08, 0.06, 0.02) * NdotL;

    return litColor;
}


// ============================================================================
//  ORE SHIMMER — sub-type-varied patterns with pulsing aura
// ============================================================================

vec3 applyOreShimmer(vec3 col, vec2 worldPos, int matId, float subTypeF, float sdf) {
    if (matId != MAT_ORE) return col;

    // Normalize ore sub-type to 0-1
    float oreType = subTypeF / 255.0;

    // Vary parameters by ore sub-type for distinct shimmer per ore
    float timeScale = mix(1.5, 4.0, fract(oreType * 3.14));
    float freq1 = mix(8.0, 15.0, fract(oreType * 1.618));
    float freq2 = mix(6.0, 12.0, fract(oreType * 2.718));
    float shimmerPow = mix(2.0, 4.0, fract(oreType * 5.432));

    // Three distinct shimmer patterns based on ore type range
    float shimmer = 0.0;
    float oreRange1 = step(oreType, 0.33);              // oreType < 0.33
    float oreRange2 = step(0.33, oreType) * step(oreType, 0.66); // 0.33-0.66
    float oreRange3 = step(0.66, oreType);              // > 0.66

    // Pattern 1: Smooth sine wave pulse
    float p1 = sin(uTime * timeScale + worldPos.x * freq1 + worldPos.y * freq2) * 0.5 + 0.5;
    p1 *= sin(uTime * timeScale * 1.3 + worldPos.x * freq1 * 0.5 - worldPos.y * freq2) * 0.5 + 0.5;

    // Pattern 2: Sharp sparkly noise
    float p2raw = snoise2(worldPos * freq1 + uTime * timeScale * 0.5);
    float p2 = smoothstep(0.6, 0.65, p2raw);

    // Pattern 3: Diagonal rolling bands
    float p3 = sin((worldPos.x + worldPos.y) * freq1 + uTime * timeScale) * 0.5 + 0.5;

    shimmer = p1 * oreRange1 + p2 * oreRange2 + p3 * oreRange3;
    shimmer = pow(shimmer, shimmerPow) * 0.35;

    // Brighter sparkle points
    float sRaw = max(snoise2(worldPos * 30.0 + uTime * 1.5), 0.0);
    float s3 = sRaw * sRaw * sRaw;
    float sparkle = s3 * s3 * 0.7; // pow 6

    // Pulsing glow near ore edges (aura effect)
    float edgeGlow = smoothstep(-0.5, 0.0, sdf) * smoothstep(0.3, -0.1, sdf);
    float pulse = 0.5 + 0.5 * sin(uTime * 1.8 + worldPos.x * 4.0 + worldPos.y * 3.0);
    edgeGlow *= pulse * 0.3;

    // Ore-type-varied glow color
    vec3 glowColor = mix(vec3(1.0, 0.9, 0.5), vec3(0.6, 1.0, 0.8), fract(oreType * 7.0));
    glowColor = mix(glowColor, vec3(0.9, 0.5, 1.0), fract(oreType * 13.0) * 0.3);

    col += (shimmer + sparkle + edgeGlow) * glowColor;
    return col;
}


// ============================================================================
//  LAVA ANIMATION
// ============================================================================

vec3 applyLavaEffect(vec3 col, vec2 worldPos, float sdf, int matId) {
    if (matId != MAT_LAVA) return col;

    vec2 flowUV = worldPos * 2.0 + vec2(uTime * 0.1, uTime * 0.05);
    float flow = fbm3(vec3(flowUV, uTime * 0.2));
    float pulse = sin(uTime * 1.5 + worldPos.x * 3.0) * 0.15 + 0.85;

    float heat = smoothstep(-1.0, -0.1, sdf);
    col = mix(vec3(0.7, 0.12, 0.0), vec3(1.0, 0.65, 0.1) * 1.3, heat * pulse);

    float vein = smoothstep(0.3, 0.5, flow) * heat;
    col = mix(col, vec3(1.0, 0.9, 0.4), vein * 0.4);

    // Bright hot spots — chained multiply for pow 4
    float hsRaw = max(snoise2(worldPos * 6.0 + uTime * 0.3), 0.0);
    float hs2 = hsRaw * hsRaw;
    float hotspot = hs2 * hs2;
    col += vec3(0.3, 0.2, 0.05) * hotspot * heat;

    return col;
}


// ============================================================================
//  PROCEDURAL GRASS — wind-animated with color variation and flower patches
// ============================================================================

vec3 applyGrass(vec3 currentColor, vec2 uv, vec2 worldPos, float sdf, int matId) {
    if (matId != MAT_TOPSOIL && matId != MAT_SANDSTONE) return currentColor;

    vec2 texelSize = vec2(1.0 / uChunkSize);
    float sdfAbove = sampleSdf(uv - vec2(0.0, texelSize.y));

    float isSurface = step(0.001, sdfAbove) * step(0.001, -sdf);
    if (isSurface < 0.5) return currentColor;

    // Wind sway animation
    float windPhase = uTime * 1.8 + worldPos.x * 0.7;
    float windSway = sin(windPhase) * 0.3 + sin(windPhase * 2.3 + 1.0) * 0.15;
    float windGusts = smoothstep(0.5, 1.0, sin(uTime * 0.4 + worldPos.x * 0.1)) * 0.2;
    windSway += windGusts;

    // Color variation — multiple grass tones
    float grassNoise = snoise2(vec2(worldPos.x * 2.0, 0.0)) * 0.5 + 0.5;
    float grassNoise2 = snoise2(vec2(worldPos.x * 5.0, 10.0)) * 0.5 + 0.5;
    vec3 grassBase = mix(vec3(0.15, 0.38, 0.08), vec3(0.30, 0.50, 0.14), grassNoise);
    // Mix in yellow-green patches
    grassBase = mix(grassBase, vec3(0.40, 0.48, 0.12), grassNoise2 * 0.3);
    // Seasonal tint from wind
    grassBase += windSway * vec3(0.02, 0.03, 0.0);

    // Multiple blade layers for depth
    float surfaceBlend = smoothstep(-0.5, -0.05, sdf) * 0.7;

    // Darker undergrowth layer
    float undergrowth = smoothstep(-0.4, -0.15, sdf) * 0.3;
    vec3 darkGrass = grassBase * 0.6;

    vec3 result = mix(currentColor, darkGrass, undergrowth * isSurface);
    result = mix(result, grassBase, surfaceBlend * isSurface);

    // Grass blade tips — thin bright highlights
    float tipMask = smoothstep(-0.12, -0.03, sdf);
    float tipPattern = smoothstep(0.3, 0.5, snoise2(worldPos * vec2(20.0, 5.0) + windSway));
    result = mix(result, grassBase * 1.3, tipMask * tipPattern * isSurface * 0.4);

    // --- Flower patches ---
    // Large-scale noise to define flower patch regions
    float patchMask = smoothstep(0.4, 0.6, snoise2(worldPos * 0.3));
    if (patchMask > 0.1) {
        vec2 gridId = floor(worldPos * 15.0);
        float flowerChance = hash12(gridId);

        // ~4% of grid cells in a patch have a flower
        if (flowerChance > 0.96) {
            vec2 gridUv = fract(worldPos * 15.0) - 0.5;
            float distToCenter = length(gridUv);

            // Small dot shape
            float flowerShape = smoothstep(0.15, 0.08, distToCenter);

            // Consistent random color per flower
            float colorHash = hash12(gridId + 42.0);
            // Red/pink flowers
            vec3 flowerColor = vec3(0.9, 0.2, 0.15);
            // Blue/purple flowers
            flowerColor = mix(flowerColor, vec3(0.35, 0.2, 0.85), step(0.4, colorHash));
            // Yellow/white flowers
            flowerColor = mix(flowerColor, vec3(1.0, 0.92, 0.3), step(0.7, colorHash));
            // White daisies
            flowerColor = mix(flowerColor, vec3(0.95, 0.95, 0.9), step(0.9, colorHash));

            // Only on the very top surface
            float surfaceMask = smoothstep(-0.1, -0.02, sdf);
            result = mix(result, flowerColor, flowerShape * patchMask * surfaceMask * isSurface);
        }
    }

    return result;
}


// ============================================================================
//  MAIN
// ============================================================================

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;

    vec2 localTile = uv * uChunkSize;
    vec2 worldPos  = uChunkWorld + localTile;

    // --- SDF ---
    float sdf = sampleSdf(uv);

    // --- Material at this cell center ---
    vec2 cellCoord = floor(uv * uChunkSize);
    vec4 cellTexel = texelAtCell(cellCoord.x, cellCoord.y);
    vec3 cellInfo  = decodeCell(cellTexel);
    int matId      = int(cellInfo.x);
    float subType  = cellInfo.y;
    int flags      = int(cellInfo.z);

    // --- Anti-aliasing ---
    float tilesPerPixel = 1.0 / max(uScreenScale, 1.0);
    float sdfPerPixel = tilesPerPixel * (4.0 / uChunkSize);
    float aaWidth = clamp(sdfPerPixel * 1.5, 0.003, 0.2);

    float alpha = smoothstep(aaWidth, -aaWidth, sdf);
    if (alpha < 0.005) {
        fragColor = vec4(0.0);
        return;
    }

    // --- Combined surface properties (normal + AO, saves 4 texture fetches) ---
    vec3 surfProps = computeSurfaceProps(uv, sdf);
    vec2 normal = surfProps.xy;
    float ao = surfProps.z;

    // --- LOD octave count based on zoom level ---
    int lodOctaves = 3;
    if (uScreenScale < 15.0) lodOctaves = 2;
    if (uScreenScale < 8.0) lodOctaves = 1;

    // --- Blended material color ---
    vec3 baseColor = getBlendedColor(uv, worldPos);

    // Procedural texturing with parallax and LOD
    baseColor = applyProceduralTexture(baseColor, matId, worldPos, sdf, normal, uv, lodOctaves);

    // Per-pixel depth
    float pixelDepthFeet = worldPos.y * FEET_PER_TILE;

    // --- Wetness near water table ---
    float wetness = smoothstep(WATER_TABLE_DEPTH - 100.0, WATER_TABLE_DEPTH + 200.0, pixelDepthFeet)
                  * (1.0 - smoothstep(WATER_TABLE_DEPTH + 200.0, WATER_TABLE_DEPTH + 600.0, pixelDepthFeet));

    // Lighting with SSS and wetness
    vec3 litColor = computeLighting(baseColor, worldPos, normal, sdf, ao,
                                    pixelDepthFeet, matId, wetness);

    // Lava bypasses lighting (self-illuminated)
    if (matId == MAT_LAVA) litColor = baseColor;

    // Ore shimmer — sub-type-varied patterns
    litColor = applyOreShimmer(litColor, worldPos, matId, subType, sdf);

    // Lava animation
    litColor = applyLavaEffect(litColor, worldPos, sdf, matId);

    // Grass — wind-animated with flower patches
    litColor = applyGrass(litColor, uv, worldPos, sdf, matId);

    // ======================================================================
    //  FOG OF WAR — noise-distorted, zone-colored, with material self-glow
    // ======================================================================
    float distToPod = length(worldPos - uPodPos);

    // Noise-distorted fog boundary — organic, non-circular edge
    vec2 fogNoiseCoord = worldPos * 0.15 + uTime * 0.05;
    float fogDistortion = fbm2(fogNoiseCoord) * 1.8;
    // Second octave of distortion at different scale for complexity
    float fogDistortion2 = snoise2(worldPos * 0.3 + uTime * 0.02) * 0.8;
    float distortedDist = distToPod + fogDistortion + fogDistortion2;

    // Three-zone fog with noise-distorted boundaries
    float innerRadius = uPodLightRadius * 0.8;
    float midRadius   = uPodLightRadius * 2.0;
    float outerRadius = uPodLightRadius * 4.0;

    float innerFog = 1.0 - smoothstep(0.0, innerRadius, distortedDist);
    float midFog   = (1.0 - smoothstep(innerRadius, midRadius, distortedDist)) * 0.6;
    float outerFog = (1.0 - smoothstep(midRadius, outerRadius, distortedDist)) * 0.15;

    float fogOfWar = innerFog + midFog + outerFog;

    // Fog wisps at the visibility boundary
    float wispDist = abs(distortedDist - midRadius);
    float wispMask = smoothstep(3.0, 0.0, wispDist);
    float wisps = snoise2(worldPos * 0.8 + vec2(uTime * 0.15, uTime * -0.1));
    wisps = smoothstep(0.1, 0.6, wisps) * wispMask * 0.08;
    fogOfWar += wisps;

    // Minimum ambient so distant terrain isn't pure black
    float depthAmbient = mix(0.06, 0.02, clamp(pixelDepthFeet / 7000.0, 0.0, 1.0));
    fogOfWar = max(fogOfWar, depthAmbient);

    // Surface gets full natural daylight (no fog above ground)
    float surfaceLight = smoothstep(400.0, -50.0, pixelDepthFeet);
    fogOfWar = max(fogOfWar, surfaceLight);

    // Material self-glow — lava and hellstone cast ambient light through fog
    float selfGlow = 0.0;
    if (matId == MAT_LAVA) selfGlow = 0.6;
    else if (matId == MAT_HELLSTONE) selfGlow = 0.12;
    else if (matId == MAT_MANTLE) selfGlow = 0.08;
    else if (matId == MAT_ORE) selfGlow = 0.04;
    fogOfWar = max(fogOfWar, selfGlow);

    // Zone-colored fog tint (fog color matches depth zone)
    vec3 fogTint = vec3(1.0); // neutral by default
    float fogTintStrength = (1.0 - fogOfWar) * 0.3;
    if (pixelDepthFeet < 1000.0) {
        // Shallow: warm brown fog
        fogTint = mix(vec3(1.0), vec3(0.7, 0.55, 0.35), fogTintStrength);
    } else if (pixelDepthFeet < 3000.0) {
        // Rock zone: cool blue-gray fog
        fogTint = mix(vec3(1.0), vec3(0.5, 0.55, 0.7), fogTintStrength);
    } else if (pixelDepthFeet < 5000.0) {
        // Volcanic: deep red-orange fog
        fogTint = mix(vec3(1.0), vec3(0.8, 0.4, 0.2), fogTintStrength);
    } else {
        // Hell: crimson fog
        fogTint = mix(vec3(1.0), vec3(0.7, 0.15, 0.1), fogTintStrength);
    }

    litColor *= fogOfWar * fogTint;

    // Depth atmosphere tint — subtle color shift at extreme depths
    float depthTint = smoothstep(1500.0, 6000.0, pixelDepthFeet);
    litColor = mix(litColor, litColor * vec3(0.88, 0.82, 0.98), depthTint * 0.2);

    // Volcanic warm tint
    float volcanicTint = smoothstep(3000.0, 5000.0, pixelDepthFeet)
                       * (1.0 - smoothstep(5000.0, 6000.0, pixelDepthFeet));
    litColor = mix(litColor, litColor * vec3(1.1, 0.9, 0.8), volcanicTint * 0.15);

    fragColor = vec4(litColor, alpha);
}
