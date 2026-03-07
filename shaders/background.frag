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
const float SKY_FADE_DEPTH = 350.0;


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

float zoneWeight(float depth, float zStart, float zEnd) {
    float margin = min(100.0, (zEnd - zStart) * 0.15);
    return smoothstep(zStart - margin, zStart + margin, depth)
         * (1.0 - smoothstep(zEnd - margin, zEnd + margin, depth));
}


// ============================================================================
//  COLOR PALETTES — brighter, more atmospheric cave colors
// ============================================================================

vec3 skyColorTop()       { return vec3(0.30, 0.52, 0.78); }
vec3 skyColorBottom()    { return vec3(0.58, 0.82, 0.95); }

// Shallow caves: warm earth tones, visible
vec3 shallowCaveDark()   { return vec3(0.18, 0.14, 0.10); }
vec3 shallowCaveLight()  { return vec3(0.28, 0.22, 0.16); }

// Rock caves: cool blue-gray, like real limestone caves
vec3 rockCaveDark()      { return vec3(0.14, 0.15, 0.20); }
vec3 rockCaveLight()     { return vec3(0.24, 0.25, 0.30); }

// Volcanic: warm orange-red glow
vec3 volcanicDark()      { return vec3(0.16, 0.06, 0.03); }
vec3 volcanicLight()     { return vec3(0.30, 0.12, 0.06); }

// Hell: deep crimson atmosphere
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
//  SKY SYSTEM
// ============================================================================

vec3 renderSky(vec2 uv, vec2 worldPos) {
    // Sky gradient — richer blue
    vec3 sky = mix(skyColorBottom(), skyColorTop(), uv.y);

    // Warm horizon band
    float horizonBand = exp(-pow((uv.y - 0.85) * 4.0, 2.0));
    sky = mix(sky, vec3(0.95, 0.75, 0.50), horizonBand * 0.35);

    // Sun glow — soft, warm
    vec2 sunPos = vec2(0.65, 0.22) + uCameraPos * 0.00005;
    float sunDist = length(uv - sunPos);

    float outerGlow = exp(-sunDist * 3.5) * 0.25;
    sky += vec3(1.0, 0.94, 0.65) * outerGlow;

    float coreGlow = exp(-sunDist * 14.0) * 0.5;
    sky += vec3(1.0, 0.97, 0.85) * coreGlow;

    // Cloud layer 1: high wispy
    vec2 cloudOffset = uCameraPos * 0.0001;
    vec2 cp1 = worldPos * 0.0003 + vec2(uTime * 0.008, 0.0) - cloudOffset * 0.5;
    float warp1 = snoise2(cp1 * 2.0 + uTime * 0.005) * 0.15;
    float cloud1 = fbm2(cp1 + vec2(warp1, warp1 * 0.7), 4);
    cloud1 = smoothstep(0.05, 0.45, cloud1);
    float cloudMask1 = smoothstep(0.7, 0.3, uv.y);
    cloud1 *= cloudMask1;

    float cloudShadeY = fbm2(cp1 * 1.5 + vec2(0.0, 0.3), 3);
    vec3 cloudColor1 = mix(vec3(0.80, 0.82, 0.88), vec3(1.0, 1.0, 1.0),
                           smoothstep(-0.2, 0.3, cloudShadeY));
    sky = mix(sky, cloudColor1, cloud1 * 0.7);

    // Cloud layer 2: lower cumulus
    vec2 cp2 = worldPos * 0.0005 + vec2(uTime * 0.012, 0.0) - cloudOffset;
    float warp2 = snoise2(cp2 * 3.0 + uTime * 0.007) * 0.2;
    float cloud2 = fbm2(cp2 + vec2(warp2, warp2 * 0.5), 4);
    cloud2 = smoothstep(0.1, 0.55, cloud2);
    float cloudMask2 = smoothstep(0.85, 0.5, uv.y) * smoothstep(0.2, 0.4, uv.y);
    cloud2 *= cloudMask2;

    float cloudShade2 = fbm2(cp2 * 1.2 + vec2(0.0, 0.5), 3);
    vec3 cloudColor2 = mix(vec3(0.74, 0.76, 0.84), vec3(0.98, 0.98, 1.0),
                           smoothstep(-0.3, 0.2, cloudShade2));
    float bottomShade = smoothstep(0.55, 0.75, uv.y) * 0.12;
    cloudColor2 -= vec3(bottomShade);
    sky = mix(sky, cloudColor2, cloud2 * 0.65);

    return sky;
}


// ============================================================================
//  PARALLAX CAVE WALL SILHOUETTES
// ============================================================================

float caveWallLayer(vec2 worldPos, float parallaxRate, float layerSeed, float ceiling) {
    vec2 p = worldPos * parallaxRate;
    p += uCameraPos * (1.0 - parallaxRate) * 0.02;

    vec2 noiseCoord = p * vec2(0.003, 0.008) + vec2(layerSeed * 17.3, layerSeed * 7.1);
    float wall = fbm2(noiseCoord, 3);

    float spikes = fbm2(noiseCoord * vec2(3.0, 1.0) + 100.0, 3);
    float bumps = fbm2(noiseCoord * vec2(2.5, 1.5) + 200.0, 3);
    wall += mix(max(0.0, bumps) * 0.3, max(0.0, spikes) * 0.4, ceiling);

    return wall;
}

vec3 renderCaveWalls(vec2 uv, vec2 worldPos, float depth, vec3 baseColor) {
    vec3 col = baseColor;

    for (int i = 0; i < 4; i++) {
        float rate = (i == 0) ? 0.1 : (i == 1) ? 0.2 : (i == 2) ? 0.4 : 0.6;
        // Subtler darkening — don't crush blacks
        float darkness = (i == 0) ? 0.06 : (i == 1) ? 0.10 : (i == 2) ? 0.14 : 0.20;
        float seed = float(i);

        // Ceiling silhouette
        float ceiling = caveWallLayer(worldPos, rate, seed, 1.0);
        float ceilMask = smoothstep(0.2, 0.5, ceiling) * smoothstep(0.35, 0.0, uv.y);
        vec3 ceilColor = baseColor * (1.0 - darkness * 1.5);
        col = mix(col, ceilColor, ceilMask * 0.5);

        // Floor silhouette
        float floorN = caveWallLayer(worldPos, rate, seed + 10.0, 0.0);
        float floorMask = smoothstep(0.2, 0.5, floorN) * smoothstep(0.65, 1.0, uv.y);
        vec3 floorColor = baseColor * (1.0 - darkness * 1.3);
        col = mix(col, floorColor, floorMask * 0.4);

        // Side walls
        float sideL = caveWallLayer(worldPos + vec2(0.0, 50.0), rate, seed + 20.0, 0.0);
        float sideLMask = smoothstep(0.15, 0.45, sideL) * smoothstep(0.2, 0.0, uv.x);
        col = mix(col, baseColor * (1.0 - darkness * 1.2), sideLMask * 0.35);

        float sideR = caveWallLayer(worldPos + vec2(0.0, -50.0), rate, seed + 30.0, 0.0);
        float sideRMask = smoothstep(0.15, 0.45, sideR) * smoothstep(0.8, 1.0, uv.x);
        col = mix(col, baseColor * (1.0 - darkness * 1.2), sideRMask * 0.35);
    }

    return col;
}


// ============================================================================
//  FLOATING PARTICLES
// ============================================================================

vec3 renderParticles(vec2 uv, vec2 worldPos, float depth) {
    vec3 particles = vec3(0.0);

    for (int i = 0; i < 20; i++) {
        float id = float(i);
        float h1 = hash11(id * 1.731);
        float h2 = hash11(id * 2.459 + 7.0);
        float h3 = hash11(id * 3.187 + 13.0);
        float h4 = hash11(id * 4.923 + 19.0);

        float speed = 0.5 + h3 * 1.5;
        vec2 pPos;

        if (depth < TOPSOIL_END) {
            pPos.x = fract(h1 + uTime * 0.01 * (h3 - 0.5));
            pPos.y = fract(h2 + uTime * 0.005 * speed);
        } else if (depth < VOLCANIC_END) {
            pPos.x = fract(h1 + sin(uTime * 0.3 + id) * 0.05);
            pPos.y = fract(h2 - uTime * 0.02 * speed);
        } else {
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
            pColor = vec3(1.0, 0.45 + flicker * 0.3, 0.05) * (0.5 + 0.5 * flicker);
            brightness *= 0.7;
        } else {
            pColor = mix(vec3(1.0, 0.15, 0.0), vec3(0.65, 0.05, 0.8), h1);
            pColor *= (0.4 + 0.6 * flicker);
            brightness *= 0.8;
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

    for (int i = 0; i < 8; i++) {
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
//  VOLUMETRIC HEADLIGHT — world-space for consistency with terrain fog
// ============================================================================

vec3 renderHeadlight(vec2 worldPos, float depth) {
    if (depth < 50.0) return vec3(0.0);

    // Distance from this pixel to the pod in world space
    vec2 toLight = worldPos - uPodPos;
    float dist = length(toLight);

    // Use the same radii as terrain fog for visual coherence
    float innerR = uPodLightRadius * 0.8;
    float outerR = uPodLightRadius * 2.5;

    // Soft radial glow
    float glow = 1.0 - smoothstep(0.0, outerR, dist);
    glow = glow * glow; // quadratic falloff

    // Bright core
    float core = 1.0 - smoothstep(0.0, innerR, dist);
    core = core * core * core;

    // Directional rays (subtle)
    float angle = atan(toLight.y, toLight.x);
    float rayNoise = fbm2(vec2(angle * 4.0, dist * 0.3 - uTime * 0.3), 3);
    float rays = smoothstep(-0.1, 0.3, rayNoise) * 0.15 * glow;

    float intensity = (glow * 0.25 + core * 0.35 + rays);

    // Light color: warm white, shifts amber in volcanic zones
    vec3 lightColor = vec3(1.0, 0.95, 0.82);
    if (depth > ROCK_END) {
        float hellBlend = smoothstep(ROCK_END, VOLCANIC_END, depth);
        lightColor = mix(lightColor, vec3(1.0, 0.75, 0.45), hellBlend * 0.4);
    }

    return lightColor * intensity;
}


// ============================================================================
//  VOLCANIC / HELL SPECIAL EFFECTS
// ============================================================================

vec3 renderVolcanicEffects(vec2 uv, vec2 worldPos, float depth) {
    vec3 fx = vec3(0.0);

    float volcanicWeight = zoneWeight(depth, ROCK_END, VOLCANIC_END);
    float hellWeight     = zoneWeight(depth, HELL_START, MAX_DEPTH + 500.0);

    if (volcanicWeight <= 0.0 && hellWeight <= 0.0) return fx;

    // Distant lava rivers
    if (volcanicWeight > 0.0 || hellWeight > 0.0) {
        float lavaY = worldPos.y * 0.005;
        for (int i = 0; i < 4; i++) {
            float id = float(i);
            float bandY = fract(lavaY + id * 0.25 + hash11(id + 99.0) * 0.1);
            float bandDist = abs(uv.y - bandY);
            float bandWidth = 0.01 + hash11(id * 3.0 + 50.0) * 0.02;

            float band = smoothstep(bandWidth, 0.0, bandDist);
            float flow = snoise2(vec2(worldPos.x * 0.002 + uTime * 0.1, id * 7.7));
            band *= smoothstep(-0.2, 0.3, flow);

            float pulse = 0.6 + 0.4 * sin(uTime * (0.5 + hash11(id) * 0.5) + id * 2.0);
            vec3 lavaColor = mix(vec3(0.85, 0.25, 0.0), vec3(1.0, 0.65, 0.15), pulse);
            fx += lavaColor * band * 0.4 * max(volcanicWeight, hellWeight);
        }
    }

    // Heat shimmer
    if (volcanicWeight > 0.0) {
        float shimmer = sin(uv.y * 80.0 + uTime * 3.0 + worldPos.x * 0.1) * 0.003;
        float shimmer2 = sin(uv.x * 60.0 + uTime * 2.5 + worldPos.y * 0.08) * 0.002;
        fx += vec3(shimmer + shimmer2) * volcanicWeight * 0.5;
    }

    // Hellfire columns
    if (hellWeight > 0.0) {
        for (int i = 0; i < 5; i++) {
            float id = float(i);
            float colX = hash11(id * 11.0 + 333.0);
            float colDist = abs(uv.x - colX);
            float colWidth = 0.03 + hash11(id * 5.0 + 77.0) * 0.05;

            if (colDist < colWidth * 2.0) {
                vec2 flameCoord = vec2(
                    (uv.x - colX) * 15.0,
                    uv.y * 8.0 - uTime * 1.5
                );
                float warp = snoise2(flameCoord * 0.5 + uTime * 0.3) * 0.5;
                float flame = fbm2(flameCoord + vec2(warp, 0.0), 4);
                flame = smoothstep(0.0, 0.6, flame);

                float colFade = 1.0 - smoothstep(0.0, colWidth, colDist);
                flame *= colFade;

                vec3 flameColor = mix(vec3(1.0, 0.35, 0.08), vec3(1.0, 0.85, 0.35), flame);
                flameColor = mix(flameColor, vec3(0.65, 0.15, 0.5), 0.12);

                fx += flameColor * flame * hellWeight * 0.3;
            }
        }

        // Deep red ambient pulse
        float hellPulse = 0.5 + 0.5 * sin(uTime * 0.8 + worldPos.y * 0.001);
        fx += vec3(0.18, 0.02, 0.02) * hellPulse * hellWeight;

        // Glow from below
        float supernaturalGlow = smoothstep(0.3, 1.0, uv.y) * hellWeight;
        float glowPulse = 0.5 + 0.5 * sin(uTime * 0.4 + 1.7);
        fx += vec3(0.12, 0.02, 0.03) * supernaturalGlow * glowPulse;
    }

    return fx;
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
//  MAIN
// ============================================================================

void main() {
    vec2 fragPos = FlutterFragCoord().xy;
    vec2 uv = fragPos / uSize;

    // Approximate world position for noise sampling
    vec2 worldPos = fragPos + uCameraPos;

    float depth = uDepthFeet;

    // Sky vs underground blend — smoother transition
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

        // Add procedural texture to cave background
        float caveTex = fbm2(worldPos * 0.001 + vec2(depth * 0.0003, 0.0), 3) * 0.08;
        caveColor += caveTex;

        caveColor = renderCaveWalls(uv, worldPos, depth, caveColor);
        caveColor += renderWaterDrips(uv, worldPos, depth);
        caveColor += renderParticles(uv, worldPos, depth);
        caveColor += renderVolcanicEffects(uv, worldPos, depth);
        caveColor = applyDepthFog(caveColor, depth);

        // --- Pod light visibility using WORLD-SPACE distance ---
        // This must match the terrain shader's fog of war for visual coherence.
        // Convert fragment's approximate world tile position
        vec2 bgWorldTile = worldPos / uSize * vec2(uSizeX, uSizeY);
        // Use pod position in world tiles vs camera-relative fragment position
        vec2 fragWorldApprox = uCameraPos + (uv - 0.5) * uSize;
        float distToPodWorld = length(fragWorldApprox - uPodPos);

        // Three-zone fog matching terrain shader
        float innerRadius = uPodLightRadius * 0.8;
        float midRadius   = uPodLightRadius * 2.0;
        float outerRadius = uPodLightRadius * 4.0;

        float innerFog = 1.0 - smoothstep(0.0, innerRadius, distToPodWorld);
        float midFog   = (1.0 - smoothstep(innerRadius, midRadius, distToPodWorld)) * 0.6;
        float outerFog = (1.0 - smoothstep(midRadius, outerRadius, distToPodWorld)) * 0.15;

        float podVisibility = innerFog + midFog + outerFog;

        // Minimum ambient — caves are never pure black
        float depthAmbient = mix(0.08, 0.03, clamp(depth / 7000.0, 0.0, 1.0));
        podVisibility = max(podVisibility, depthAmbient);

        // Surface transition: full daylight above ground
        float surfaceAmbient = smoothstep(500.0, -50.0, depth) * 0.85;
        podVisibility = max(podVisibility, surfaceAmbient);

        // Volcanic/hell zones have ambient glow
        float volcanicGlow = smoothstep(3000.0, 5000.0, depth) * 0.12;
        float hellGlow = smoothstep(5000.0, 7000.0, depth) * 0.08;
        podVisibility = max(podVisibility, volcanicGlow + hellGlow);

        caveColor *= podVisibility;

        // Headlight volumetric glow (world-space)
        vec2 headlightWorldPos = uCameraPos + (uv - 0.5) * uSize;
        caveColor += renderHeadlight(headlightWorldPos, depth);

        finalColor = mix(finalColor, caveColor, undergroundBlend);
    }

    // Transition zone: dirt ceiling fading in (smoother)
    float transitionZone = smoothstep(80.0, SAND_END, depth)
                         * (1.0 - smoothstep(SAND_END, TOPSOIL_END * 0.4, depth));
    if (transitionZone > 0.0) {
        float ceilingNoise = fbm2(worldPos * 0.002 + vec2(0.0, depth * 0.001), 4);
        float ceilingMask = smoothstep(0.3, 0.0, uv.y + ceilingNoise * 0.15 - 0.1);
        vec3 dirtColor = vec3(0.16, 0.12, 0.08);
        finalColor = mix(finalColor, dirtColor, ceilingMask * transitionZone * 0.6);
    }

    // Subtle vignette
    float vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.5;
    vignette = clamp(vignette, 0.0, 1.0);
    float vignetteStrength = mix(0.06, 0.22, undergroundBlend);
    finalColor *= mix(1.0, vignette, vignetteStrength);

    fragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
