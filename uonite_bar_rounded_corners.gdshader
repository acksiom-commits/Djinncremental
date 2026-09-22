shader_type canvas_item;

// Rounds UoniteCooldownBar's corners to match every other CooldownBar's
// StyleBoxFlat corner_radius (2px, see cooldown_bar.gd's
// _make_fill_style()/_make_bg_style()). TextureProgressBar has no
// StyleBoxFlat of its own -- it draws a texture, not a flat-colored box --
// so corner rounding has to happen here instead.
//
// Uses VERTEX (the fragment's true position in the control's own local
// space, valid regardless of which sub-rect Godot is currently drawing)
// rather than UV, because TextureProgressBar's fill_mode draws the
// "progress" layer as a SMALLER quad clipped to the current fill
// fraction -- UV within that quad would be 0..1 across just the visible
// sliver, not the full bar, which would incorrectly round the MOVING fill
// edge instead of the bar's actual fixed left/right edges. VERTEX stays
// anchored to the control's real origin no matter which layer or how much
// of it is currently drawn, so only the true corners ever round.

uniform vec2 bar_size = vec2(140.0, 6.0);
uniform float corner_radius : hint_range(0.0, 10.0) = 2.0;

varying vec2 local_pos;

void vertex() {
    local_pos = VERTEX;
}

float rounded_rect_sdf(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) - radius;
}

void fragment() {
    vec2 centered = local_pos - bar_size * 0.5;
    float d = rounded_rect_sdf(centered, bar_size * 0.5, corner_radius);
    if (d > 0.0) {
        discard;
    }
}
