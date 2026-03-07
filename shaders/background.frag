#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// ============================================================================
// Motherlode Background Fragment Shader
// Fullscreen procedural background with depth-zone transitions, parallax
// cave walls, floating particles, volumetric pod light scattering.
// All procedural — no texture dependencies.
// ============================================================================

// --- Uniforms ----------------------------------------------------------------
uniform float uSizeX;          // index 0 - viewport width in world units
uniform float uSizeY;          // index 1 - viewport height in world units
uniform float uCameraPosX;     // index 2 - camera world X in tiles
uniform float uCameraPosY;     // index 3 - camera world Y in tiles
uniform float uDepthFeet;      // index 4 - camera depth in feet
uniform float uTime;           // index 5 - animation time
uniform float uPodPosX;        // index 6 - pod world X
uniform float uPodPosY;        // index 7 - pod world Y
uniform float uPodLightRadius; // index 8 - pod light radius in tiles

#define uSize      vec2(uSizeX, uSizeY)
#define uCameraPos vec2(uCameraPosX, uCameraPosY)
#define uPodPos    vec2(uPodPosX, uPodPosY)

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

// Depth zone boundaries (feet)
const float SAND_END      = 200.0;
const float TOPSOIL_END   = 1000.0;
const float ROCK_END      = 3000.0;
const float VOLCANIC_END  = 5000.0;
const float HELL_START    = 5000.0;
const float MAX_DEPTH     = 7500.0;
const float SKY_FADE_DEPTH = 30.0;


// ============================================================================
//  SIMPLEX NOISE  (Ashima Arts / webgl-noise)
// ============================================================================

vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute3(vec3 x) { return mod289_3(((x * 34.0) + 10.0) * x); }
vec4 permute4(vec4 x) { return mod289_4(((x * 34.0) + 10.0) * x); }

float snoise2(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec2 x1 = x0 - i1 + C.xx;
    vec2 x2 = x0 + C.zz;
    i = mod289_2(i);
    vec3 p = permute3(permute3(i.y + vec3(0.0, i1.y, 1.0))
                                + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x  = 2.0 * fract(p * C.www) - 1.0;
    vec3 h  = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x1.x + h.y * x1.y;
    g.z = a0.z * x2.x + h.z * x2.y;
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
    vec3 ns  = n_ * D.wyz - D.xzx;
    vec4 j  = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x  = x_ * ns.x + ns.yyyy;
    vec4 y  = y_ * ns.x + ns.yyyy;
    vec4 h  = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0_v = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1_v = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0_v.xy, h.x);
    vec3 p1 = vec3(a0_v.zw, h.y);
    vec3 p2 = vec3(a1_v.xy, h.z);
    vec3 p3 = vec3(a1_v.zw, h.w);
    vec4 norm = 1.79284291400159 - 0.85373472095314 *
        vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1),
                             dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1),
                                   dot(p2, x2), dot(p3, x3)));
}


// ============================================================================
//  FRACTAL BROWNIAN MOTION
// ============================================================================

float fbm2(vec2 p, int octaves) {
    float value = 0.0, amplitude = 0.5, total = 0.0;
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        value += amplitude * snoise2(p);
        total += amplitude;
        amplitude *= 0.5;
        p *= 2.0;
    }
    return value / total;
}

float fbm3(vec3 p, int octaves) {
    float value = 0.0, amplitude = 0.5, total = 0.0;
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        value += amplitude * snoise3(p);
        total += amplitude;
        amplitude *= 0.5;
        p *= 2.0;
    }
    return value / total;
}


// ============================================================================
//  UTILITY
// ============================================================================

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float zoneWeight(float depth, float zStart, float zEnd) {
    float margin = min(100.0, (zEnd - zStart) * 0.15);
    return smoothstep(zStart - margin, zStart + margin, depth)
         * (1.0 - smoothstep(zEnd - margin, zEnd + margin, depth));
}


// ============================================================================
//  COLOR PALETTES
// ============================================================================

vec3 skyColorTop()       { return vec3(0.30, 0.52, 0.78); }
vec3 skyColorBottom()    { return vec3(0.58, 0.82, 0.95); }

vec3 shallowCaveDark()   { return vec3(0.18, 0.14, 0.10); }
vec3 shallowCaveLight()  { return vec3(0.28, 0.22, 0.16); }

vec3 rockCaveDark()      { return vec3(0.14, 0.15, 0.20); }
vec3 rockCaveLight()     { return vec3(0.24, 0.25, 0.30); }

vec3 volcanicDark()      { return vec3(0.16, 0.06, 0.03); }
vec3 volcanicLight()     { return vec3(0.30, 0.12, 0.06); }

vec3 hellDark()          { return vec3(0.08, 0.02, 0.02); }
vec3 hellLight()         { return vec3(0.18, 0.05, 0.04); }

vec3 getBiomeColor(float depth, float screenY01) {
    float vt = screenY01;
    float wShallow  = zoneWeight(depth, 0.0,        TOPSOIL_END);
    float wRock     = zoneWeight(depth, TOPSOIL_END, ROCK_END);
    float wVolcanic = zoneWeight(depth, ROCK_END,    VOLCANIC_END);
    float wHell     = zoneWeight(depth, HELL_START,  MAX_DEPTH + 500.0);

    vec3 col = vec3(0.0);
    float totalW = 0.0;

    if (wShallow > 0.0) {
        col += wShallow * mix(shallowCaveLight(), shallowCaveDark(), vt);
        totalW += wShallow;
    }
    if (wRock > 0.0) {
        col += wRock * mix(rockCaveLight(), rockCaveDark(), vt);
        totalW += wRock;
    }
    if (wVolcanic > 0.0) {
        col += wVolcanic * mix(volcanicLight(), volcanicDark(), vt);
        totalW += wVolcanic;
    }
    if (wHell > 0.0) {
        col += wHell * mix(hellLight(), hellDark(), vt);
        totalW += wHell;
    }

    return totalW > 0.0 ? col / totalW : shallowCaveLight();
}


// ============================================================================
//  AURORA / NORTHERN LIGHTS (sky near horizon)
// ============================================================================

vec3 renderAurora(vec2 uv, vec2 worldPos) {
    // Only visible in upper sky, strongest near horizon (uv.y ~0.6-0.9)
    float horizonMask = smoothstep(0.35, 0.65, uv.y) * smoothstep(0.95, 0.75, uv.y);
    if (horizonMask < 0.01) return vec3(0.0);

    // Waving curtain effect - multiple vertical bands
    float curtainX = worldPos.x * 0.02 + uTime * 0.015;
    float curtain1 = snoise2(vec2(curtainX, uv.y * 3.0 + uTime * 0.08));
    float curtain2 = snoise2(vec2(curtainX * 1.7 + 5.0, uv.y * 2.5 - uTime * 0.06));
    float curtain3 = snoise2(vec2(curtainX * 0.6, uv.y * 4.0 + uTime * 0.04));

    // Vertical streaks for curtain folds
    float streaks = sin(worldPos.x * 0.12 + curtain1 * 2.0) * 0.5 + 0.5;
    streaks = pow(streaks, 3.0);

    float intensity = (curtain1 * 0.4 + curtain2 * 0.3 + curtain3 * 0.3);
    intensity = max(intensity, 0.0);
    intensity = pow(intensity, 2.0) * streaks;

    // Color: green base, purple at edges, with shimmer
    vec3 auroraGreen = vec3(0.1, 0.85, 0.35);
    vec3 auroraPurple = vec3(0.6, 0.15, 0.9);
    vec3 auroraBlue = vec3(0.15, 0.5, 0.95);

    float colorShift = snoise2(vec2(worldPos.x * 0.025 + uTime * 0.02, 0.0)) * 0.5 + 0.5;
    vec3 auroraColor = mix(auroraGreen, auroraPurple, smoothstep(0.3, 0.7, colorShift));
    auroraColor = mix(auroraColor, auroraBlue, smoothstep(0.6, 0.9, uv.y) * 0.4);

    return auroraColor * intensity * horizonMask * 0.18;
}


// ============================================================================
//  SKY SYSTEM — with god rays and improved atmosphere
// ============================================================================

vec3 renderSky(vec2 uv, vec2 worldPos) {
    // Sky gradient
    vec3 sky = mix(skyColorBottom(), skyColorTop(), uv.y);

    // Warm horizon band
    float horizonBand = exp(-pow((uv.y - 0.85) * 4.0, 2.0));
    sky = mix(sky, vec3(0.95, 0.75, 0.50), horizonBand * 0.35);

    // Sun position
    vec2 sunPos = vec2(0.65, 0.22) + uCameraPos * 0.001;
    float sunDist = length(uv - sunPos);

    float outerGlow = exp(-sunDist * 3.5) * 0.25;
    sky += vec3(1.0, 0.94, 0.65) * outerGlow;

    float coreGlow = exp(-sunDist * 14.0) * 0.5;
    sky += vec3(1.0, 0.97, 0.85) * coreGlow;

    // --- God rays (crepuscular rays) ---
    vec2 toSun = uv - sunPos;
    float angle = atan(toSun.y, toSun.x);
    float radialDist = length(toSun);

    float rays = 0.0;
    float rayNoise1 = snoise2(vec2(angle * 8.0, uTime * 0.1 + radialDist * 2.0));
    float rayNoise2 = snoise2(vec2(angle * 16.0, uTime * 0.05 + radialDist * 3.0));
    rays += smoothstep(0.0, 0.5, rayNoise1) * 0.6;
    rays += smoothstep(0.1, 0.6, rayNoise2) * 0.3;

    float rayFade = exp(-radialDist * 2.5) * smoothstep(0.15, 0.5, uv.y);
    float rayOcclusion = snoise2(vec2(angle * 3.0 + uTime * 0.02, radialDist));
    rayOcclusion = smoothstep(0.1, 0.5, rayOcclusion);

    rays *= rayFade * rayOcclusion;
    sky += vec3(1.0, 0.92, 0.65) * rays * 0.12;

    // Atmospheric scattering
    float scatterMask = exp(-pow((uv.y - 0.8) * 3.0, 2.0));
    float scatterAngle = exp(-abs(angle - PI * 0.25) * 2.0);
    sky += vec3(1.0, 0.7, 0.35) * scatterMask * scatterAngle * 0.08;

    // Cloud layer 1: high wispy (reduced to 2 octaves for perf)
    vec2 cloudOffset = uCameraPos * 0.003;
    vec2 cp1 = worldPos * 0.008 + vec2(uTime * 0.008, 0.0) - cloudOffset * 0.5;
    float warp1 = snoise2(cp1 * 2.0 + uTime * 0.005) * 0.15;
    float cloud1 = fbm2(cp1 + vec2(warp1, warp1 * 0.7), 2);
    cloud1 = smoothstep(0.05, 0.45, cloud1);
    float cloudMask1 = smoothstep(0.7, 0.3, uv.y);
    cloud1 *= cloudMask1;

    float cloudShadeY = snoise2(cp1 * 1.5 + vec2(0.0, 0.3));
    vec3 cloudColor1 = mix(vec3(0.80, 0.82, 0.88), vec3(1.0, 1.0, 1.0),
                           smoothstep(-0.2, 0.3, cloudShadeY));
    float cloudSunlit = exp(-length(cp1 - sunPos * 40.0) * 0.003);
    cloudColor1 = mix(cloudColor1, vec3(1.0, 0.95, 0.8), cloudSunlit * 0.2);
    sky = mix(sky, cloudColor1, cloud1 * 0.7);

    // Cloud layer 2: lower cumulus (reduced octaves)
    vec2 cp2 = worldPos * 0.012 + vec2(uTime * 0.012, 0.0) - cloudOffset;
    float warp2 = snoise2(cp2 * 3.0 + uTime * 0.007) * 0.2;
    float cloud2 = fbm2(cp2 + vec2(warp2, warp2 * 0.5), 2);
    cloud2 = smoothstep(0.1, 0.55, cloud2);
    float cloudMask2 = smoothstep(0.85, 0.5, uv.y) * smoothstep(0.2, 0.4, uv.y);
    cloud2 *= cloudMask2;

    float cloudShade2 = snoise2(cp2 * 1.2 + vec2(0.0, 0.5));
    vec3 cloudColor2 = mix(vec3(0.74, 0.76, 0.84), vec3(0.98, 0.98, 1.0),
                           smoothstep(-0.3, 0.2, cloudShade2));
    float bottomShade = smoothstep(0.55, 0.75, uv.y) * 0.12;
    cloudColor2 -= vec3(bottomShade);
    sky = mix(sky, cloudColor2, cloud2 * 0.65);

    // Aurora / northern lights
    sky += renderAurora(uv, worldPos);

    return sky;
}


// ============================================================================
//  PARALLAX CAVE WALL SILHOUETTES — more dramatic
// ============================================================================

float caveWallLayer(vec2 worldPos, float parallaxRate, float layerSeed, float ceiling) {
    vec2 p = worldPos * parallaxRate;
    p += uCameraPos * (1.0 - parallaxRate) * 0.5;

    // worldPos is in tiles (~0-500 range), scale to get good noise variation
    vec2 noiseCoord = p * vec2(0.08, 0.2) + vec2(layerSeed * 17.3, layerSeed * 7.1);
    float wall = fbm2(noiseCoord, 2);

    float detail = fbm2(noiseCoord * vec2(2.8, 1.2) + 100.0, 2);
    wall += max(0.0, detail) * mix(0.3, 0.4, ceiling);

    return wall;
}

vec3 renderCaveWalls(vec2 uv, vec2 worldPos, float depth, vec3 baseColor) {
    vec3 col = baseColor;

    // Depth-scaled wall thickness — deeper = more enclosed feeling
    float depthScale = mix(0.7, 1.3, clamp(depth / 5000.0, 0.0, 1.0));

    // 2 parallax layers instead of 4 for performance (saves ~96 noise evals/pixel)
    for (int i = 0; i < 2; i++) {
        float rate = (i == 0) ? 0.15 : 0.45;
        float darkness = (i == 0) ? 0.10 : 0.24;
        darkness *= depthScale;
        float seed = float(i);

        // Ceiling silhouette
        float ceiling = caveWallLayer(worldPos, rate, seed, 1.0);
        float ceilThreshold = 0.15 + float(i) * 0.05;
        float ceilMask = smoothstep(ceilThreshold, 0.5, ceiling)
                       * smoothstep(0.35 + float(i) * 0.08, 0.0, uv.y);
        vec3 ceilColor = baseColor * (1.0 - darkness * 1.5);
        col = mix(col, ceilColor, ceilMask * 0.6);

        // Floor silhouette
        float floorN = caveWallLayer(worldPos, rate, seed + 10.0, 0.0);
        float floorMask = smoothstep(ceilThreshold, 0.5, floorN)
                        * smoothstep(0.65 - float(i) * 0.05, 1.0, uv.y);
        vec3 floorColor = baseColor * (1.0 - darkness * 1.3);
        col = mix(col, floorColor, floorMask * 0.5);

        // Side walls
        float sideReach = 0.22 + float(i) * 0.06;
        float sideL = caveWallLayer(worldPos + vec2(0.0, 50.0), rate, seed + 20.0, 0.0);
        float sideLMask = smoothstep(0.15, 0.45, sideL) * smoothstep(sideReach, 0.0, uv.x);
        col = mix(col, baseColor * (1.0 - darkness * 1.2), sideLMask * 0.45);

        float sideR = caveWallLayer(worldPos + vec2(0.0, -50.0), rate, seed + 30.0, 0.0);
        float sideRMask = smoothstep(0.15, 0.45, sideR) * smoothstep(1.0 - sideReach, 1.0, uv.x);
        col = mix(col, baseColor * (1.0 - darkness * 1.2), sideRMask * 0.45);
    }

    // Stalactite/stalagmite detail on closest layer
    float stalDetail = snoise2(worldPos * 0.4 + vec2(0.0, 77.0));
    float stalMask = smoothstep(0.3, 0.6, stalDetail) * smoothstep(0.15, 0.0, uv.y);
    col = mix(col, baseColor * 0.5, stalMask * 0.3);

    float stagDetail = snoise2(worldPos * 0.4 + vec2(77.0, 0.0));
    float stagMask = smoothstep(0.3, 0.6, stagDetail) * smoothstep(0.85, 1.0, uv.y);
    col = mix(col, baseColor * 0.55, stagMask * 0.25);

    return col;
}


// ============================================================================
//  STALACTITE DRIPPING WATER ANIMATION
// ============================================================================

vec3 renderStalactiteDrips(vec2 uv, vec2 worldPos, float depth) {
    if (depth < SAND_END || depth > ROCK_END) return vec3(0.0);

    vec3 drips = vec3(0.0);
    float dripWeight = zoneWeight(depth, SAND_END, ROCK_END);

    // Place drip sources at stalactite tips along the ceiling
    for (int i = 0; i < 3; i++) {
        float id = float(i);
        float tipX = hash11(id * 13.7 + 47.0);
        float tipY = hash11(id * 9.3 + 63.0) * 0.08; // near top of screen

        // Drip timing - each stalactite drips at different rate
        float dripSpeed = 0.3 + hash11(id * 6.1 + 99.0) * 0.4;
        float cycle = fract(uTime * dripSpeed * 0.08 + hash11(id * 2.7));

        // Growing droplet at tip before falling
        float growPhase = smoothstep(0.0, 0.3, cycle);
        float fallPhase = smoothstep(0.3, 1.0, cycle);

        // Droplet at tip (growing)
        float dropSize = mix(0.001, 0.003, growPhase) * (1.0 - fallPhase);
        float tipDist = length(uv - vec2(tipX, tipY));
        float tipGlow = smoothstep(dropSize, dropSize * 0.2, tipDist) * (1.0 - fallPhase);

        // Falling droplet
        float fallY = tipY + fallPhase * fallPhase * 0.5; // accelerating fall
        float fallDist = length(uv - vec2(tipX, fallY));
        float fallGlow = smoothstep(0.003, 0.0008, fallDist) * fallPhase;

        // Thin water streak connecting tip to drop
        float streakMask = step(tipY, uv.y) * step(uv.y, fallY);
        float streakDist = abs(uv.x - tipX);
        float streak = smoothstep(0.002, 0.0, streakDist) * streakMask * fallPhase * 0.4;

        // Water color with slight refraction highlight
        vec3 waterColor = vec3(0.5, 0.7, 1.0);
        drips += waterColor * (tipGlow + fallGlow + streak) * dripWeight * 0.4;
    }

    return drips;
}


// ============================================================================
//  CRYSTAL SPARKLE (rock zone)
// ============================================================================

vec3 renderCrystalSparkle(vec2 uv, vec2 worldPos, float depth) {
    if (depth < TOPSOIL_END || depth > VOLCANIC_END) return vec3(0.0);

    vec3 sparkles = vec3(0.0);
    float rockWeight = zoneWeight(depth, TOPSOIL_END, ROCK_END);

    for (int i = 0; i < 8; i++) {
        float id = float(i);
        float h1 = hash11(id * 7.13 + 111.0);
        float h2 = hash11(id * 4.27 + 222.0);
        float h3 = hash11(id * 9.51 + 333.0);

        vec2 crystalPos = vec2(h1, h2);
        float dist = length(uv - crystalPos);

        // Twinkle animation — each crystal has unique phase
        float twinkle = sin(uTime * (2.0 + h3 * 4.0) + id * 11.0) * 0.5 + 0.5;
        twinkle = pow(twinkle, 4.0); // Sharp on/off

        float radius = 0.001 + h3 * 0.002;
        float brightness = smoothstep(radius, radius * 0.2, dist) * twinkle;

        // Crystal colors: blue, white, pale purple
        vec3 crystalColor;
        float colorSel = h1 * 3.0;
        if (colorSel < 1.0) crystalColor = vec3(0.6, 0.75, 1.0);
        else if (colorSel < 2.0) crystalColor = vec3(0.95, 0.95, 1.0);
        else crystalColor = vec3(0.75, 0.6, 0.95);

        sparkles += crystalColor * brightness * rockWeight * 0.6;
    }

    return sparkles;
}


// ============================================================================
//  BIOLUMINESCENT FUNGI (rock zone caves)
// ============================================================================

vec3 renderBioFungi(vec2 uv, vec2 worldPos, float depth) {
    if (depth < TOPSOIL_END || depth > VOLCANIC_END) return vec3(0.0);

    vec3 fungi = vec3(0.0);
    float rockWeight = zoneWeight(depth, TOPSOIL_END, ROCK_END);
    if (rockWeight < 0.01) return vec3(0.0);

    // Place fungi clusters on cave walls (near ceiling and floor edges)
    float wallProximity = smoothstep(0.2, 0.0, uv.y) + smoothstep(0.8, 1.0, uv.y);
    wallProximity += smoothstep(0.15, 0.0, uv.x) + smoothstep(0.85, 1.0, uv.x);
    wallProximity = clamp(wallProximity, 0.0, 1.0);

    // Grid-based fungi placement in world space (tile coords)
    vec2 cellSize = vec2(8.0, 6.0);
    vec2 cellId = floor(worldPos / cellSize);

    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            vec2 neighbor = cellId + vec2(float(ox), float(oy));
            float cellHash = hash21(neighbor * 0.73 + 17.0);

            // Only 15% of cells have fungi
            if (cellHash > 0.15) continue;

            // Fungi position within cell
            vec2 fungiWorldPos = (neighbor + hash22(neighbor + 3.7)) * cellSize;
            vec2 fungiScreenPos = (fungiWorldPos - uCameraPos) / uSize + 0.5;

            float dist = length(uv - fungiScreenPos);

            // Gentle pulsing glow
            float pulse = 0.5 + 0.5 * sin(uTime * 1.5 + cellHash * TAU);
            float glow = smoothstep(0.012, 0.0, dist) * pulse;
            float softHalo = smoothstep(0.03, 0.005, dist) * pulse * 0.3;

            // Color varies: cyan, green-blue, pale green
            float colorVar = hash11(cellHash * 77.0);
            vec3 fungiColor;
            if (colorVar < 0.4) fungiColor = vec3(0.1, 0.85, 0.9);
            else if (colorVar < 0.7) fungiColor = vec3(0.15, 0.9, 0.5);
            else fungiColor = vec3(0.3, 0.95, 0.7);

            fungi += fungiColor * (glow + softHalo) * rockWeight * wallProximity * 0.5;
        }
    }

    return fungi;
}


// ============================================================================
//  CAUSTIC PATTERNS (shallow caves)
// ============================================================================

vec3 renderCaustics(vec2 uv, vec2 worldPos, float depth) {
    if (depth < SAND_END || depth > TOPSOIL_END) return vec3(0.0);

    float shallowWeight = zoneWeight(depth, SAND_END, TOPSOIL_END);

    // Animated caustic pattern — overlapping sine waves
    vec2 causticUV = worldPos * 0.08;
    float c1 = sin(causticUV.x * 8.0 + uTime * 0.4) * sin(causticUV.y * 6.0 + uTime * 0.3);
    float c2 = sin(causticUV.x * 5.0 - uTime * 0.35 + 1.0) *
               sin(causticUV.y * 9.0 + uTime * 0.25 + 2.0);
    float c3 = sin((causticUV.x + causticUV.y) * 7.0 + uTime * 0.5);

    float caustic = (c1 + c2 + c3) / 3.0;
    caustic = pow(max(caustic, 0.0), 2.0);

    // Caustics fade toward edges (light from above)
    float topFade = smoothstep(0.5, 0.1, uv.y);

    vec3 causticColor = vec3(0.85, 0.78, 0.55) * caustic * shallowWeight * topFade * 0.06;
    return causticColor;
}


// ============================================================================
//  DUST / HAZE PARALLAX LAYERS
// ============================================================================

vec3 renderDustHaze(vec2 uv, vec2 worldPos, float depth) {
    if (depth < 300.0) return vec3(0.0);

    // Far haze layer — slow parallax
    vec2 farCoord = worldPos * 0.1 - uCameraPos * 0.02 + vec2(uTime * 0.01, uTime * 0.005);
    float farHaze = fbm2(farCoord, 2);
    farHaze = smoothstep(0.1, 0.7, farHaze);

    // Near haze layer — faster parallax
    vec2 nearCoord = worldPos * 0.3 - uCameraPos * 0.06 + vec2(uTime * 0.02, -uTime * 0.008);
    float nearHaze = snoise2(nearCoord) * 0.5 + 0.5;
    nearHaze = smoothstep(0.2, 0.8, nearHaze);

    float combined = farHaze * 0.55 + nearHaze * 0.45;

    // Intensity increases with depth
    float depthFactor = smoothstep(300.0, 3000.0, depth) * 0.08;
    depthFactor += smoothstep(3000.0, 6000.0, depth) * 0.04;

    // Haze color matches biome
    vec3 hazeColor;
    if (depth < TOPSOIL_END) hazeColor = vec3(0.15, 0.12, 0.10);
    else if (depth < ROCK_END) hazeColor = vec3(0.12, 0.13, 0.18);
    else if (depth < VOLCANIC_END) hazeColor = vec3(0.18, 0.08, 0.04);
    else hazeColor = vec3(0.12, 0.03, 0.03);

    return hazeColor * combined * depthFactor;
}


// ============================================================================
//  FLOATING PARTICLES — zone-varied density
// ============================================================================

vec3 renderParticles(vec2 uv, vec2 worldPos, float depth) {
    vec3 particles = vec3(0.0);

    for (int i = 0; i < 12; i++) {
        float id = float(i);
        float h1 = hash11(id * 1.731);
        float h2 = hash11(id * 2.459 + 7.0);
        float h3 = hash11(id * 3.187 + 13.0);
        float h4 = hash11(id * 4.923 + 19.0);

        float speed = 0.5 + h3 * 1.5;
        vec2 pPos;

        if (depth < TOPSOIL_END) {
            // Dust motes — slow drift
            pPos.x = fract(h1 + uTime * 0.01 * (h3 - 0.5));
            pPos.y = fract(h2 + uTime * 0.005 * speed);
        } else if (depth < VOLCANIC_END) {
            // Mineral dust — gentle float
            pPos.x = fract(h1 + sin(uTime * 0.3 + id) * 0.05);
            pPos.y = fract(h2 - uTime * 0.02 * speed);
        } else {
            // Embers/ash — rising with turbulence
            pPos.x = fract(h1 + sin(uTime * 0.8 + id * 2.0) * 0.08);
            pPos.y = fract(h2 - uTime * 0.03 * speed + sin(uTime + id) * 0.02);
        }

        float dist = length(uv - pPos);
        float radius = 0.002 + h4 * 0.004;
        float brightness = smoothstep(radius, radius * 0.3, dist);

        float flicker = 0.5 + 0.5 * sin(uTime * (3.0 + h3 * 5.0) + id * 7.0);

        vec3 pColor;
        if (depth < TOPSOIL_END) {
            pColor = vec3(0.85, 0.80, 0.65) * (0.3 + 0.7 * flicker);
            brightness *= 0.5;
        } else if (depth < ROCK_END) {
            pColor = vec3(0.65, 0.75, 0.95) * (0.4 + 0.6 * flicker);
            brightness *= 0.45;
        } else if (depth < VOLCANIC_END) {
            pColor = vec3(0.7, 0.3 + flicker * 0.2, 0.03) * (0.4 + 0.4 * flicker);
            brightness *= 0.35;
            // Ember trail
            float trail = smoothstep(radius * 4.0, radius, dist + (uv.y - pPos.y) * 3.0);
            brightness += trail * 0.12;
        } else {
            pColor = mix(vec3(0.6, 0.1, 0.0), vec3(0.4, 0.03, 0.5), h1);
            pColor *= (0.3 + 0.5 * flicker);
            brightness *= 0.35;
        }

        particles += pColor * brightness;
    }

    return particles;
}


// ============================================================================
//  WATER DRIPS (limestone/rock zone)
// ============================================================================

vec3 renderWaterDrips(vec2 uv, vec2 worldPos, float depth) {
    if (depth < SAND_END || depth > ROCK_END) return vec3(0.0);

    vec3 drips = vec3(0.0);
    float dripIntensity = zoneWeight(depth, SAND_END, ROCK_END);

    for (int i = 0; i < 4; i++) {
        float id = float(i);
        float h1 = hash11(id * 5.731 + 42.0);
        float h2 = hash11(id * 3.917 + 88.0);
        float speed = 0.8 + hash11(id * 2.1 + 55.0) * 1.5;

        float dripX = h1;
        float cycle = fract(uTime * speed * 0.1 + h2);
        float dripY = cycle;

        float dx = abs(uv.x - dripX);
        float dy = uv.y - dripY;
        float streakLen = 0.03 + h2 * 0.04;
        float streak = smoothstep(0.002, 0.0, dx)
                      * smoothstep(0.0, streakLen, -dy)
                      * smoothstep(streakLen * 2.0, streakLen, -dy);

        float headDist = length(uv - vec2(dripX, dripY));
        float head = smoothstep(0.004, 0.001, headDist);

        float alpha = (streak + head) * (1.0 - cycle) * dripIntensity;
        drips += vec3(0.55, 0.70, 0.95) * alpha * 0.35;

        if (cycle > 0.85) {
            float splashT = (cycle - 0.85) / 0.15;
            float splashR = 0.005 + splashT * 0.02;
            float splashDist = length(uv - vec2(dripX, h2 * 0.3 + 0.7));
            float splash = smoothstep(splashR, splashR * 0.5, splashDist) * (1.0 - splashT);
            drips += vec3(0.55, 0.70, 0.95) * splash * 0.25;
        }
    }

    return drips;
}


// ============================================================================
//  VOLUMETRIC HEADLIGHT — world-space, matching terrain fog
// ============================================================================

vec3 renderHeadlight(vec2 worldPos, float depth) {
    if (depth < 50.0) return vec3(0.0);

    vec2 toLight = worldPos - uPodPos;
    float dist = length(toLight);

    float innerR = uPodLightRadius * 0.8;
    float outerR = uPodLightRadius * 2.5;

    float glow = 1.0 - smoothstep(0.0, outerR, dist);
    glow = glow * glow;

    float core = 1.0 - smoothstep(0.0, innerR, dist);
    core = core * core * core;

    // Directional rays with noise distortion
    float angle = atan(toLight.y, toLight.x);
    float rayNoise = snoise2(vec2(angle * 4.0, dist * 0.3 - uTime * 0.3));
    float rays = smoothstep(-0.1, 0.3, rayNoise) * 0.15 * glow;

    // Dust motes caught in the light beam
    float dustNoise = snoise2(worldPos * 0.5 + uTime * 0.2);
    float dustMotes = pow(max(dustNoise, 0.0), 3.0) * glow * 0.08;

    float intensity = (glow * 0.20 + core * 0.28 + rays + dustMotes);

    // Reduce headlight intensity in deep zones to avoid over-brightness
    // when combined with volcanic/hell ambient glow
    float depthDim = 1.0 - smoothstep(ROCK_END, VOLCANIC_END, depth) * 0.4;
    intensity *= depthDim;

    vec3 lightColor = vec3(1.0, 0.95, 0.82);
    if (depth > ROCK_END) {
        float hellBlend = smoothstep(ROCK_END, VOLCANIC_END, depth);
        lightColor = mix(lightColor, vec3(0.8, 0.55, 0.3), hellBlend * 0.5);
    }

    return lightColor * intensity;
}


// ============================================================================
//  VOLCANIC / HELL SPECIAL EFFECTS — with face pareidolia
// ============================================================================

// Subtle screaming face shapes in fire columns
float hellFacePattern(vec2 pos, float time) {
    // Distorted face-like shapes using noise
    vec2 faceUV = pos * 0.08;

    // Eye sockets — two dark voids
    float eyeL = length(faceUV - vec2(-0.15, 0.12));
    float eyeR = length(faceUV - vec2(0.15, 0.12));
    float eyes = smoothstep(0.08, 0.03, eyeL) + smoothstep(0.08, 0.03, eyeR);

    // Screaming mouth — elongated oval
    vec2 mouthUV = faceUV - vec2(0.0, -0.12);
    mouthUV.x *= 1.5; // wider than tall
    float mouth = smoothstep(0.12, 0.04, length(mouthUV));

    // Distort the whole face with fire noise so it's subtle
    float distort = snoise2(pos * 0.04 + time * 0.6) * 0.5;
    float fadeNoise = snoise2(pos * 0.02 - time * 0.3);
    float fadeMask = smoothstep(0.2, 0.6, fadeNoise);

    return (eyes * 0.7 + mouth * 0.5) * fadeMask * (0.5 + distort * 0.5);
}

vec3 renderVolcanicEffects(vec2 uv, vec2 worldPos, float depth) {
    vec3 fx = vec3(0.0);

    float volcanicWeight = zoneWeight(depth, ROCK_END, VOLCANIC_END);
    float hellWeight     = zoneWeight(depth, HELL_START, MAX_DEPTH + 500.0);

    if (volcanicWeight <= 0.0 && hellWeight <= 0.0) return fx;

    // Distant lava rivers — subtle glow
    if (volcanicWeight > 0.0 || hellWeight > 0.0) {
        float lavaY = worldPos.y * 0.12;
        for (int i = 0; i < 3; i++) {
            float id = float(i);
            float bandY = fract(lavaY + id * 0.33 + hash11(id + 99.0) * 0.1);
            float bandDist = abs(uv.y - bandY);
            float bandWidth = 0.012 + hash11(id * 3.0 + 50.0) * 0.018;

            float band = smoothstep(bandWidth, 0.0, bandDist);
            float flow = snoise2(vec2(worldPos.x * 0.05 + uTime * 0.1, id * 7.7));
            band *= smoothstep(-0.2, 0.3, flow);

            float pulse = 0.6 + 0.4 * sin(uTime * (0.5 + hash11(id) * 0.5) + id * 2.0);
            vec3 lavaColor = mix(vec3(0.55, 0.15, 0.0), vec3(0.8, 0.4, 0.08), pulse);

            // Glow halo around lava rivers
            float halo = smoothstep(bandWidth * 3.0, 0.0, bandDist) * 0.08;
            vec3 haloColor = vec3(0.3, 0.08, 0.02);

            float zoneStrength = max(volcanicWeight, hellWeight);
            fx += lavaColor * band * 0.25 * zoneStrength;
            fx += haloColor * halo * zoneStrength;
        }
    }

    // Heat haze distortion effect (visual shimmer)
    if (volcanicWeight > 0.0) {
        float shimmer = sin(uv.y * 80.0 + uTime * 3.0 + worldPos.x * 2.5) * 0.002;
        float shimmer2 = sin(uv.x * 60.0 + uTime * 2.5 + worldPos.y * 2.0) * 0.001;
        fx += vec3(shimmer + shimmer2) * volcanicWeight * 0.3;

        // Heat distortion waves rising
        float heatWave = sin(uv.y * 40.0 - uTime * 2.0 + snoise2(worldPos * 0.25) * 5.0);
        heatWave = smoothstep(0.7, 1.0, heatWave);
        fx += vec3(0.10, 0.03, 0.01) * heatWave * volcanicWeight * 0.05;
    }

    // Hellfire columns — with screaming face pareidolia
    if (hellWeight > 0.0) {
        for (int i = 0; i < 4; i++) {
            float id = float(i);
            float colX = hash11(id * 11.0 + 333.0);
            float colDist = abs(uv.x - colX);
            float colWidth = 0.04 + hash11(id * 5.0 + 77.0) * 0.06;

            if (colDist < colWidth * 2.0) {
                vec2 flameCoord = vec2(
                    (uv.x - colX) * 12.0,
                    uv.y * 6.0 - uTime * 1.8
                );
                float warp = snoise2(flameCoord * 0.5 + uTime * 0.3) * 0.6;
                float flame = fbm2(flameCoord + vec2(warp, 0.0), 2);
                flame = smoothstep(-0.1, 0.6, flame);

                float colFade = 1.0 - smoothstep(0.0, colWidth, colDist);
                flame *= colFade;

                // Fire color gradient: dark red core -> orange -> dim red edges
                vec3 flameColor = mix(vec3(0.6, 0.15, 0.03), vec3(0.8, 0.4, 0.1), flame);
                float coreHeat = pow(flame, 3.0);
                flameColor = mix(flameColor, vec3(0.9, 0.6, 0.25), coreHeat * 0.2);
                flameColor = mix(flameColor, vec3(0.4, 0.08, 0.3), 0.08);

                // Screaming face silhouettes within fire columns
                vec2 facePos = vec2((uv.x - colX) * 15.0, uv.y * 8.0 - uTime * 0.8 + id * 3.0);
                float face = hellFacePattern(facePos, uTime);
                // Faces darken the flame slightly — subtle pareidolia
                float faceDarken = face * 0.15 * flame;
                flameColor = mix(flameColor, vec3(0.2, 0.03, 0.05), faceDarken);

                fx += flameColor * flame * hellWeight * 0.18;
            }
        }

        // Deep red ambient pulse — subtle
        float hellPulse = 0.5 + 0.5 * sin(uTime * 0.8 + worldPos.y * 0.025);
        float hellPulse2 = 0.5 + 0.5 * sin(uTime * 1.3 + worldPos.x * 0.05 + 2.0);
        fx += vec3(0.08, 0.02, 0.02) * hellPulse * hellWeight;
        fx += vec3(0.04, 0.005, 0.03) * hellPulse2 * hellWeight;

        // Glow from below — subtle infernal light
        float supernaturalGlow = smoothstep(0.3, 1.0, uv.y) * hellWeight;
        float glowPulse = 0.5 + 0.5 * sin(uTime * 0.4 + 1.7);
        float glowPulse2 = 0.3 + 0.7 * sin(uTime * 0.7 + 3.1);
        fx += vec3(0.06, 0.015, 0.02) * supernaturalGlow * glowPulse;
        // Purple demonic tint
        fx += vec3(0.03, 0.005, 0.04) * supernaturalGlow * glowPulse2 * 0.4;
    }

    // Clamp volcanic/hell effects to prevent additive blowout
    return min(fx, vec3(0.5));
}


// ============================================================================
//  DEPTH FOG — gentler, more atmospheric
// ============================================================================

vec3 applyDepthFog(vec3 color, float depth) {
    float fogDensity = smoothstep(800.0, 4500.0, depth) * 0.20
                     + smoothstep(4500.0, 7000.0, depth) * 0.15;
    fogDensity = clamp(fogDensity, 0.0, 0.35);

    vec3 fogColor;
    if (depth < TOPSOIL_END) fogColor = vec3(0.10, 0.08, 0.06);
    else if (depth < ROCK_END) fogColor = vec3(0.08, 0.08, 0.10);
    else if (depth < VOLCANIC_END) fogColor = vec3(0.10, 0.04, 0.02);
    else fogColor = vec3(0.06, 0.01, 0.01);

    return mix(color, fogColor, fogDensity);
}


// ============================================================================
//  DIRT / ROOT CEILING TRANSITION
// ============================================================================

vec3 renderDirtRootCeiling(vec2 uv, vec2 worldPos, float depth, vec3 baseColor) {
    // Active in the transition from sky to underground
    float transWeight = smoothstep(50.0, SAND_END, depth)
                      * (1.0 - smoothstep(SAND_END, TOPSOIL_END * 0.5, depth));
    if (transWeight < 0.01) return baseColor;

    // Irregular dirt ceiling edge
    float dirtNoise = fbm2(worldPos * 0.08 + vec2(0.0, depth * 0.003), 2);
    float dirtEdge = 0.12 + dirtNoise * 0.15;
    float dirtMask = smoothstep(dirtEdge + 0.05, dirtEdge - 0.02, uv.y);

    // Dirt color with subtle variation
    vec3 dirtColor = vec3(0.16, 0.12, 0.08);
    float dirtVar = snoise2(worldPos * 0.25 + 55.0) * 0.03;
    dirtColor += vec3(dirtVar, dirtVar * 0.8, dirtVar * 0.5);

    // Dangling roots — thin vertical tendrils below the dirt edge
    float rootAccum = 0.0;
    for (int i = 0; i < 3; i++) {
        float id = float(i);
        float rootX = hash11(id * 7.3 + 29.0);
        float rootLen = 0.06 + hash11(id * 3.1 + 41.0) * 0.12;

        // Wiggle the root with noise
        float wiggle = snoise2(vec2(worldPos.x * 0.25 + id * 5.0, uv.y * 8.0 + uTime * 0.1)) * 0.015;
        float rootDist = abs(uv.x - rootX - wiggle);

        // Root thins toward the tip
        float rootThickness = 0.003 * (1.0 - smoothstep(0.0, rootLen, uv.y - dirtEdge + 0.05));
        float rootMask = smoothstep(rootThickness, rootThickness * 0.3, rootDist);
        rootMask *= smoothstep(dirtEdge - 0.02, dirtEdge + 0.02, uv.y);
        rootMask *= smoothstep(dirtEdge + rootLen, dirtEdge, uv.y);

        rootAccum += rootMask;
    }
    rootAccum = clamp(rootAccum, 0.0, 1.0);

    vec3 rootColor = vec3(0.10, 0.07, 0.04);
    vec3 result = mix(baseColor, dirtColor, dirtMask * transWeight * 0.7);
    result = mix(result, rootColor, rootAccum * transWeight * 0.6);

    return result;
}


// ============================================================================
//  MAIN
// ============================================================================

void main() {
    vec2 fragPos = FlutterFragCoord().xy;
    vec2 uv = fragPos / uSize;

    // Compute world position from UV: camera center + offset from center of viewport
    // uCameraPos is center of view, uSize is viewport dimensions in world tiles
    vec2 worldPos = uCameraPos + (uv - 0.5) * uSize;

    // Per-pixel depth in feet from the pixel's world Y position (not the pod's depth)
    // Positive Y = underground, so depth = worldY * feetPerTile, clamped to >= 0
    float depth = max(worldPos.y * 15.0, 0.0);

    // Sky vs underground blend — computed per-pixel based on this pixel's depth
    float skyBlend = 1.0 - smoothstep(0.0, SKY_FADE_DEPTH, depth);

    vec3 finalColor = vec3(0.0);

    // Sky (visible near surface)
    if (skyBlend > 0.001) {
        vec3 sky = renderSky(uv, worldPos);
        finalColor += sky * skyBlend;
    }

    // Underground
    float undergroundBlend = 1.0 - skyBlend;

    if (undergroundBlend > 0.001) {
        vec3 caveColor = getBiomeColor(depth, uv.y);

        // Procedural texture on cave background
        float caveTex = fbm2(worldPos * 0.06 + vec2(depth * 0.002, 0.0), 2) * 0.08;
        caveColor += caveTex;

        caveColor = renderCaveWalls(uv, worldPos, depth, caveColor);
        caveColor += renderCaustics(uv, worldPos, depth);
        caveColor += renderCrystalSparkle(uv, worldPos, depth);
        caveColor += renderBioFungi(uv, worldPos, depth);
        caveColor += renderStalactiteDrips(uv, worldPos, depth);
        caveColor += renderWaterDrips(uv, worldPos, depth);
        caveColor += renderParticles(uv, worldPos, depth);
        caveColor += renderDustHaze(uv, worldPos, depth);
        caveColor += renderVolcanicEffects(uv, worldPos, depth);
        caveColor = applyDepthFog(caveColor, depth);

        // Clamp cave color before lighting to prevent additive blowout
        caveColor = min(caveColor, vec3(1.0));

        // --- Pod light visibility using WORLD-SPACE distance ---
        float distToPodWorld = length(worldPos - uPodPos);

        // Noise distortion matching terrain fog (simplified for performance)
        float fogDistortion = snoise2(worldPos * 0.15 + uTime * 0.05) * 1.8;
        float fogDistortion2 = snoise2(worldPos * 0.3 + uTime * 0.02) * 0.8;
        float distortedDist = distToPodWorld + fogDistortion + fogDistortion2;

        // Three-zone fog matching terrain shader
        float innerRadius = uPodLightRadius * 0.8;
        float midRadius   = uPodLightRadius * 2.0;
        float outerRadius = uPodLightRadius * 4.0;

        float innerFog = 1.0 - smoothstep(0.0, innerRadius, distortedDist);
        float midFog   = (1.0 - smoothstep(innerRadius, midRadius, distortedDist)) * 0.6;
        float outerFog = (1.0 - smoothstep(midRadius, outerRadius, distortedDist)) * 0.15;

        float podVisibility = innerFog + midFog + outerFog;

        // Fog wisps at boundary
        float wispDist = abs(distortedDist - midRadius);
        float wispMask = smoothstep(3.0, 0.0, wispDist);
        float wisps = snoise2(worldPos * 0.8 + vec2(uTime * 0.15, uTime * -0.1));
        wisps = smoothstep(0.1, 0.6, wisps) * wispMask * 0.08;
        podVisibility += wisps;

        // Minimum ambient — enough to see cave walls and atmosphere even outside headlight
        float depthAmbient = mix(0.15, 0.06, clamp(depth / 7000.0, 0.0, 1.0));
        podVisibility = max(podVisibility, depthAmbient);

        // Surface transition: full daylight above ground
        float surfaceAmbient = smoothstep(500.0, -50.0, depth) * 0.85;
        podVisibility = max(podVisibility, surfaceAmbient);

        // Volcanic/hell zones have ambient glow from lava and magma
        float volcanicGlow = smoothstep(3000.0, 5000.0, depth) * 0.12;
        float hellGlow = smoothstep(5000.0, 7000.0, depth) * 0.10;
        podVisibility = max(podVisibility, volcanicGlow + hellGlow);

        caveColor *= podVisibility;

        // Headlight volumetric glow (world-space)
        caveColor += renderHeadlight(worldPos, depth);

        finalColor = mix(finalColor, caveColor, undergroundBlend);
    }

    // Dirt/root ceiling transition effect
    finalColor = renderDirtRootCeiling(uv, worldPos, depth, finalColor);

    // Subtle vignette
    float vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.5;
    vignette = clamp(vignette, 0.0, 1.0);
    float vignetteStrength = mix(0.06, 0.22, 1.0 - skyBlend);
    finalColor *= mix(1.0, vignette, vignetteStrength);

    fragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
