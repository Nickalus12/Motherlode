#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

// Grid dimensions
uniform vec2 uSize;
// Time step
uniform float uDt;
// Feed rate
uniform float uF;
// Kill rate
uniform float uK;
// U diffusion rate
uniform float uDu;
// V diffusion rate
uniform float uDv;
// Previous state texture (R=U, G=V)
uniform sampler2D uState;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 texel = 1.0 / uSize;

  vec4 c = texture(uState, uv);
  float U = c.r;
  float V = c.g;

  // Laplacian via 3x3 kernel:
  // orthogonal = 0.2, diagonal = 0.05, center = -1.0
  float lapU = 0.0;
  float lapV = 0.0;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec4 n = texture(uState, uv + vec2(float(dx), float(dy)) * texel);
      float w;
      if (dx == 0 && dy == 0) {
        w = -1.0;
      } else if (dx == 0 || dy == 0) {
        w = 0.2;
      } else {
        w = 0.05;
      }
      lapU += n.r * w;
      lapV += n.g * w;
    }
  }

  float uvv = U * V * V;
  float newU = U + (uDu * lapU - uvv + uF * (1.0 - U)) * uDt;
  float newV = V + (uDv * lapV + uvv - (uF + uK) * V) * uDt;

  fragColor = vec4(clamp(newU, 0.0, 1.0), clamp(newV, 0.0, 1.0), 0.0, 1.0);
}
