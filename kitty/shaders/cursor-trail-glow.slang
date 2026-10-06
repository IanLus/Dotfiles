#language slang 2026
// Sharp cursor trail with a thin same-color halo.
// The quad stays a hard shape. Glow only tints pixels outside it,
// matching the juejin demo: a concrete cursor, with the color glowing.

import kitty_custom_shader_types;

// How far the tint stays visible, in pixels. Kept small so the silhouette stays crisp.
static const float GLOW_SIGMA = 2.4;
// Peak strength of the halo just outside the edge. The shape itself is fully opaque.
static const float GLOW_STRENGTH = 0.45;

float
dist_to_segment(float2 p, float2 a, float2 b) {
    float2 e = b - a;
    float len2 = dot(e, e);
    float t = 0.0;
    if (len2 > 1e-4) t = clamp(dot(p - a, e) / len2, 0.0, 1.0);
    return length(p - (a + e * t));
}

// Corner order: 0=top-right, 1=bottom-right, 2=bottom-left, 3=top-left.
bool
inside_quad(float2 p, float2 c0, float2 c1, float2 c2, float2 c3) {
    float2 e0 = c1 - c0;
    float2 e1 = c2 - c1;
    float2 e2 = c3 - c2;
    float2 e3 = c0 - c3;
    float s0 = e0.x * (p.y - c0.y) - e0.y * (p.x - c0.x);
    float s1 = e1.x * (p.y - c1.y) - e1.y * (p.x - c1.x);
    float s2 = e2.x * (p.y - c2.y) - e2.y * (p.x - c2.x);
    float s3 = e3.x * (p.y - c3.y) - e3.y * (p.x - c3.x);
    return s0 <= 0.0 && s1 <= 0.0 && s2 <= 0.0 && s3 <= 0.0;
}

float
sd_quad(float2 p, float2 c0, float2 c1, float2 c2, float2 c3) {
    float d = dist_to_segment(p, c0, c1);
    d = min(d, dist_to_segment(p, c1, c2));
    d = min(d, dist_to_segment(p, c2, c3));
    d = min(d, dist_to_segment(p, c3, c0));
    if (inside_quad(p, c0, c1, c2, c3)) d = -d;
    return d;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_color.a <= 0.0) return color;

    float2 pixel_dims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixel_dims;

    float2 c0 = float2(d.cursor_trail_corners_x.x, d.cursor_trail_corners_y.x) * pixel_dims;
    float2 c1 = float2(d.cursor_trail_corners_x.y, d.cursor_trail_corners_y.y) * pixel_dims;
    float2 c2 = float2(d.cursor_trail_corners_x.z, d.cursor_trail_corners_y.z) * pixel_dims;
    float2 c3 = float2(d.cursor_trail_corners_x.w, d.cursor_trail_corners_y.w) * pixel_dims;

    float sdf = sd_quad(px, c0, c1, c2, c3);
    // Hard silhouette, about one pixel of antialiasing.
    float fill = 1.0 - smoothstep(0.0, 1.0, sdf);
    float outside = max(sdf, 0.0);
    float glow = exp(-(outside * outside) / (2.0 * GLOW_SIGMA * GLOW_SIGMA)) * GLOW_STRENGTH;
    glow *= 1.0 - fill;

    float2 uv = t.pos;
    float inside_cursor =
        step(d.cursor_trail_edge.x, uv.x) * step(uv.x, d.cursor_trail_edge.y) *
        step(d.cursor_trail_edge.w, uv.y) * step(uv.y, d.cursor_trail_edge.z);
    fill *= 1.0 - inside_cursor;

    float amount = max(fill, glow);
    if (amount <= 0.01) return color;

    return float4(lerp(color.rgb, d.cursor_trail_color.rgb, amount), color.a);
}
