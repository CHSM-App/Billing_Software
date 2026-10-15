#version 460 core

// Liquid-glass lens for the bottom nav highlight (see bottom_nav_bar.dart).
// Runs as a BackdropFilter on Impeller, clipped to the lens's stadium shape,
// over the LIVE backdrop (no screen capture). On Impeller (Flutter 3.38) the
// fragment coordinates are full-frame physical pixels, the same space as
// u_lens.
//
// Optical model, a glass slab with a flat middle and a rounded rim:
//  - middle: plain magnification, lightly frosted;
//  - rim band: the surface curves away on a circular profile, so refraction
//    grows smoothly toward the edge and samples from beyond the rim;
//  - dispersion: blue bends most, red least, so content edges at the rim
//    pick up thin blue/purple and yellow fringes;
//  - light: a Fresnel rim plus a thin specular from the upper left (and a
//    faint opposite arc), brighter over bright backgrounds.

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;    // set by the engine: input texture size (px)
uniform vec4 u_lens;    // lens rect in input-texture px: x, y, w, h
uniform float u_swell;  // 0..1: how formed the lens is
uniform float u_mag;    // magnification in the middle

uniform sampler2D u_input;

out vec4 frag_color;

vec3 sampleAt(vec2 p) {
  vec2 uv = p / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
#ifndef IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED
  // Older Android phones without Vulkan run Impeller on OpenGL ES, whose
  // framebuffer is Y-flipped up to engine 3.44; newer engines unflip it and
  // define this macro, so the flip must not apply twice.
  uv.y = 1.0 - uv.y;
#endif
#endif
  // Impeller's backdrop alpha is not a transparency signal (it can read 0
  // over dark content), so the glass treats the backdrop as opaque.
  return texture(u_input, uv).rgb;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 hs = u_lens.zw * 0.5;
  vec2 c = u_lens.xy + hs;
  vec2 q = p - c;
  float r = min(hs.x, hs.y);

  // Stadium: v points from the nearest spot on its spine to p, so its length
  // is r at the rim; e is the depth inside the rim, n the outward normal.
  vec2 v = vec2(sign(q.x) * max(abs(q.x) - (hs.x - r), 0.0), q.y);
  float len = length(v);
  float e = max(r - len, 0.0);
  vec2 n = len > 0.001 ? v / len : vec2(0.0, 1.0);

  // Rim band: t = 0 in the flat middle, 1 at the rim. The circular profile
  // stays flat inside and turns steep right at the edge.
  float band = r * 0.6;
  float t = clamp(1.0 - e / band, 0.0, 1.0);
  float bend = 1.0 - sqrt(max(1.0 - t * t, 0.0));

  vec2 base = c + q / u_mag;
  vec2 o = n * bend * band * 1.1 * u_swell;

  // Dispersion, concentrated where the rim bends light hardest.
  float disp = 0.14 * u_swell;
  vec3 col = vec3(sampleAt(base + o * (1.0 - disp)).r,
                  sampleAt(base + o).g,
                  sampleAt(base + o * (1.0 + disp)).b);

  // Light frost in the middle: a faint milky lift, no blur, so what is
  // under the lens stays readable.
  col = mix(col, vec3(1.0), 0.07 * u_swell * (1.0 - t));

  // Edge light. Fresnel: grazing angles near the rim reflect more.
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  float fresnel = pow(t, 4.0) * 0.18;
  // A thin specular line along the rim (about 1.5% of the lens height),
  // strongest facing the light at the upper left, with a faint far arc.
  float line = 1.0 - smoothstep(0.0, r * 0.09, e);
  vec2 light = normalize(vec2(-0.55, -0.85));
  float facing = pow(max(dot(n, light), 0.0), 3.0)
               + 0.35 * pow(max(dot(n, -light), 0.0), 4.0);
  float spec = line * (0.25 + 0.75 * facing) * 0.65;
  col += (fresnel + spec) * mix(0.55, 1.0, luma) * u_swell;

  frag_color = vec4(min(col, vec3(1.0)), 1.0);
}
