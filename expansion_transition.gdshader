shader_type canvas_item;
// The Prestige/Expansion "universe compresses toward a point of light"
// transition. Originally an inline string constant in root_ui.gd
// (_EXPANSION_SHADER_SRC); extracted to a shared resource 2026-09-23 so
// intro_screen.gd's vessel-selection sequence can reuse the exact same
// transition instead of duplicating the source. Reads the actual screen
// content, so it works as a full-screen overlay over ANY scene.

uniform float distortion_strength : hint_range(0.0, 3.0) = 0.0;
uniform float white_amount        : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
    vec2  center = vec2(0.5, 0.5);
    vec2  offset = SCREEN_UV - center;
    float r      = length(offset);

    // Barrel distortion: sample UV is pulled toward center.
    // Output pixels at the edges show content from near-center,
    // so the center content appears to rush outward — toward the player.
    float warp_scale = 1.0 / (1.0 + distortion_strength * r * r * 3.0);
    vec2  sample_uv  = center + offset * warp_scale;

    // Radial vignette: white blooms inward from the screen boundary
    // as distortion grows, completing the enveloping sensation.
    // At distortion_strength = 0 the threshold sits beyond the screen
    // corners (~0.707) so no white is visible at rest.
    float inner     = 0.75 - distortion_strength * 0.65;
    float outer     = inner + 0.14;
    float edge_white = smoothstep(inner, outer, r);

    vec4 screen_col = texture(SCREEN_TEXTURE, sample_uv);

    // edge_white closes in from outside; white_amount takes everything
    // to full white at the peak regardless of remaining distortion.
    COLOR = mix(screen_col, vec4(1.0), max(white_amount, edge_white));
}
