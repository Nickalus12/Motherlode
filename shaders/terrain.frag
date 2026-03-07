#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// ============================================================================
// Motherlode Terrain Fragment Shader
// SDF terrain rendering with smooth material blending, natural fog of war,
// dynamic lighting, ambient occlusion, and procedural texturing.
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

float fbm2(vec2 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) {
        f += a * snoise2(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

float fbm3(vec3 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 2; i++) {
        f += a * snoise3(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
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
//  MATERIAL COLOR PALETTE — brighter, more saturated colors
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
//  PROCEDURAL TEXTURING PER MATERIAL
// ============================================================================

vec3 applyProceduralTexture(vec3 baseColor, int matId, vec2 worldPos, float sdf) {
    vec3 col = baseColor;

    if (matId == MAT_TOPSOIL) {
        col += fbm2(worldPos * 3.0) * 0.12;
        float pebble = smoothstep(0.68, 0.72, snoise2(worldPos * 18.0));
        col = mix(col, col * 0.7, pebble);
    }
    else if (matId == MAT_SANDSTONE) {
        col += fbm2(worldPos * 2.5) * 0.10;
        col += sin(worldPos.y * 8.0 + snoise2(worldPos * 1.5) * 2.0) * 0.04;
    }
    else if (matId == MAT_LIMESTONE) {
        float bandNoise = snoise2(worldPos * vec2(0.5, 0.1)) * 1.5;
        col += sin(worldPos.y * 12.0 + bandNoise) * 0.06;
    }
    else if (matId == MAT_SHALE) {
        float laminate = sin(worldPos.y * 40.0 + snoise2(worldPos * vec2(2.0, 0.5)) * 3.0);
        col += smoothstep(-0.2, 0.2, laminate) * 0.06 - 0.03;
    }
    else if (matId == MAT_GRANITE) {
        float quartz = smoothstep(0.5, 0.7, snoise2(worldPos * 12.0));
        float feldspar = smoothstep(0.4, 0.6, snoise2(worldPos * 12.0 + 77.7));
        float mica = smoothstep(0.7, 0.8, snoise2(worldPos * 20.0 + 155.5));
        col = mix(col, vec3(0.60, 0.58, 0.55), quartz * 0.2);
        col = mix(col, vec3(0.52, 0.42, 0.38), feldspar * 0.15);
        col = mix(col, vec3(0.22, 0.22, 0.20), mica * 0.25);
    }
    else if (matId == MAT_BASALT) {
        vec2 bp = worldPos * 6.0;
        float hex = snoise2(bp) + 0.5 * snoise2(bp * 2.0);
        float edge = 1.0 - smoothstep(0.0, 0.15, abs(fract(hex * 2.5) - 0.5));
        col -= edge * 0.05;
    }
    else if (matId == MAT_OBSIDIAN) {
        col += snoise2(worldPos * 1.5) * 0.03;
        float fracLines = smoothstep(0.90, 0.95, abs(snoise2(worldPos * vec2(8.0, 3.0) + 42.0)));
        col = mix(col, vec3(0.30, 0.18, 0.38), fracLines * 0.4);
    }
    else if (matId == MAT_MANTLE) {
        col += fbm3(vec3(worldPos * 2.0, uTime * 0.3)) * 0.10;
        float vein = smoothstep(0.55, 0.65, snoise3(vec3(worldPos * 4.0, uTime * 0.15)));
        col = mix(col, vec3(0.6, 0.18, 0.04), vein * 0.3);
    }
    else if (matId == MAT_HELLSTONE) {
        col += fbm3(vec3(worldPos * 1.5, uTime * 0.4)) * 0.08;
        float crack = smoothstep(0.5, 0.6, snoise3(vec3(worldPos * 5.0, uTime * 0.2)));
        col = mix(col, vec3(0.8, 0.12, 0.0), crack * 0.4);
        col += vec3(smoothstep(-0.3, 0.0, sdf) * 0.10, 0.0, 0.0);
    }

    return col;
}


// ============================================================================
//  AMBIENT OCCLUSION
// ============================================================================

float computeAO(float sdf) {
    return smoothstep(-1.5, 0.0, sdf) * 0.6 + 0.4;
}


// ============================================================================
//  DYNAMIC LIGHTING — brighter, more natural
// ============================================================================

vec3 computeLighting(vec3 baseColor, vec2 worldPos, vec2 normal, float sdf,
                     float ao, float pixelDepthFeet) {

    // --- Depth-based ambient: keep terrain always somewhat visible ---
    // Near surface: generous daylight. Deep: dimmer but never pitch black.
    float depthNorm = clamp(pixelDepthFeet / 7000.0, 0.0, 1.0);
    float ambient = mix(0.35, 0.12, depthNorm);

    // Extra sky ambient near surface
    float skyAmbient = smoothstep(500.0, -50.0, pixelDepthFeet) * 0.55;
    ambient += skyAmbient;

    // --- Pod headlight ---
    vec2 toLight = uPodPos - worldPos;
    float dist = length(toLight);
    vec2 lightDir = (dist > 0.001) ? toLight / dist : vec2(0.0, -1.0);

    // Smooth inverse-square with generous radius
    float effectiveRadius = uPodLightRadius * 1.5;
    float atten = effectiveRadius * effectiveRadius /
                  (dist * dist + effectiveRadius * effectiveRadius);

    // Wrap lighting for softer shadows
    float NdotL = max(dot(normal, lightDir), 0.0);
    float wrap = 0.35;
    float diffuse = max((NdotL + wrap) / (1.0 + wrap), 0.0);

    // Subtle rim light
    float rim = pow(1.0 - max(dot(normal, lightDir), 0.0), 3.0) * 0.06 * atten;

    float totalLight = ambient + diffuse * atten * 1.4 + rim;
    totalLight *= ao;

    // Clamp to prevent over-darkening
    totalLight = max(totalLight, 0.08);

    vec3 litColor = baseColor * totalLight;

    // Warm headlight tint
    litColor += baseColor * atten * vec3(0.08, 0.06, 0.02) * NdotL;

    return litColor;
}


// ============================================================================
//  ORE SHIMMER
// ============================================================================

vec3 applyOreShimmer(vec3 col, vec2 worldPos, int matId) {
    if (matId != MAT_ORE) return col;

    float shimmer = sin(uTime * 2.0 + worldPos.x * 10.0 + worldPos.y * 7.0) * 0.5 + 0.5;
    shimmer *= sin(uTime * 3.1 + worldPos.x * 5.5 - worldPos.y * 8.3) * 0.5 + 0.5;
    shimmer = pow(shimmer, 2.0) * 0.3;

    float sparkle = snoise2(worldPos * 30.0 + uTime * 1.5);
    sparkle = pow(max(sparkle, 0.0), 8.0) * 0.5;

    col += (shimmer + sparkle) * vec3(1.0, 0.9, 0.5);
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

    return col;
}


// ============================================================================
//  PROCEDURAL GRASS
// ============================================================================

vec3 applyGrass(vec3 currentColor, vec2 uv, vec2 worldPos, float sdf, int matId) {
    if (matId != MAT_TOPSOIL && matId != MAT_SANDSTONE) return currentColor;

    vec2 texelSize = vec2(1.0 / uChunkSize);
    float sdfAbove = sampleSdf(uv - vec2(0.0, texelSize.y));

    float isSurface = step(0.001, sdfAbove) * step(0.001, -sdf);
    if (isSurface < 0.5) return currentColor;

    float grassNoise = snoise2(vec2(worldPos.x * 2.0, 0.0)) * 0.5 + 0.5;
    vec3 grassColor = mix(vec3(0.15, 0.38, 0.08), vec3(0.30, 0.50, 0.14), grassNoise);
    grassColor += sin(uTime * 1.2 + worldPos.x * 0.5) * 0.06;

    float surfaceBlend = smoothstep(-0.5, -0.05, sdf) * 0.7;
    return mix(currentColor, grassColor, surfaceBlend * isSurface);
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

    // Surface normal
    vec2 normal = computeNormal(uv);

    // --- Blended material color ---
    vec3 baseColor = getBlendedColor(uv, worldPos);

    // Procedural texturing
    baseColor = applyProceduralTexture(baseColor, matId, worldPos, sdf);

    // AO
    float ao = computeAO(sdf);

    // Per-pixel depth
    float pixelDepthFeet = worldPos.y * FEET_PER_TILE;

    // Lighting
    vec3 litColor = computeLighting(baseColor, worldPos, normal, sdf, ao, pixelDepthFeet);

    // Lava bypasses lighting (self-illuminated)
    if (matId == MAT_LAVA) litColor = baseColor;

    // Ore shimmer
    litColor = applyOreShimmer(litColor, worldPos, matId);

    // Lava animation
    litColor = applyLavaEffect(litColor, worldPos, sdf, matId);

    // Grass
    litColor = applyGrass(litColor, uv, worldPos, sdf, matId);

    // ---- FOG OF WAR ----
    // Natural exploration reveal: bright near pod, smooth gradient outward.
    // Uses world-space distance for consistency across zoom levels.
    float distToPod = length(worldPos - uPodPos);

    // Three-zone fog: bright core -> mid falloff -> dark outer
    float innerRadius = uPodLightRadius * 0.8;
    float midRadius   = uPodLightRadius * 2.0;
    float outerRadius = uPodLightRadius * 4.0;

    // Inner zone: fully lit (1.0)
    // Mid zone: gradual falloff with smooth curve
    // Outer zone: fades to a dim ambient
    float innerFog = 1.0 - smoothstep(0.0, innerRadius, distToPod);
    float midFog   = (1.0 - smoothstep(innerRadius, midRadius, distToPod)) * 0.6;
    float outerFog = (1.0 - smoothstep(midRadius, outerRadius, distToPod)) * 0.15;

    float fogOfWar = innerFog + midFog + outerFog;

    // Add a minimum ambient so distant terrain isn't pure black
    float depthAmbient = mix(0.06, 0.02, clamp(pixelDepthFeet / 7000.0, 0.0, 1.0));
    fogOfWar = max(fogOfWar, depthAmbient);

    // Surface gets full natural daylight (no fog above ground)
    float surfaceLight = smoothstep(400.0, -50.0, pixelDepthFeet);
    fogOfWar = max(fogOfWar, surfaceLight);

    // Lava and hellstone glow through fog slightly
    float selfGlow = 0.0;
    if (matId == MAT_LAVA) selfGlow = 0.5;
    else if (matId == MAT_HELLSTONE) selfGlow = 0.08;
    else if (matId == MAT_MANTLE) selfGlow = 0.05;
    fogOfWar = max(fogOfWar, selfGlow);

    litColor *= fogOfWar;

    // Depth atmosphere tint — subtle color shift at extreme depths
    float depthTint = smoothstep(1500.0, 6000.0, pixelDepthFeet);
    litColor = mix(litColor, litColor * vec3(0.88, 0.82, 0.98), depthTint * 0.2);

    // Volcanic warm tint
    float volcanicTint = smoothstep(3000.0, 5000.0, pixelDepthFeet)
                       * (1.0 - smoothstep(5000.0, 6000.0, pixelDepthFeet));
    litColor = mix(litColor, litColor * vec3(1.1, 0.9, 0.8), volcanicTint * 0.15);

    fragColor = vec4(litColor, alpha);
}
