shader_type canvas_item;

// ================= UONITE FILL SHADER v0.1.0 =================
// Applied to the Uonite icon TextureRect on the Create Uonite button.
// fill_amount: 0.0 (no grains) -> 1.0 (20 grains, ready to create)
// time_offset: passed each frame for pulse animation when ready
//
// Effect:
//   - Brightness fills from outer edge INWARD toward center
//   - At fill_amount = 1.0, whole icon is bright and pulses

uniform float fill_amount : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset : hint_range(0.0, 1000.0) = 0.0;
uniform vec4  icon_color  : source_color = vec4(1.0, 0.87, 0.33, 1.0); // gold

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Distance from center — 0.0 at center, ~0.707 at corner
	vec2 centered = UV - 0.5;
	float dist_from_center = length(centered);
	// Normalize so edge = 1.0, center = 0.0
	// Max possible distance from center to corner is ~0.707
	float normalized_dist = dist_from_center / 0.5;
	// Invert: edge_dist = 0 at edge, 1 at center
	float dist_from_edge = 1.0 - clamp(normalized_dist, 0.0, 1.0);

	// Fill threshold moves inward as fill_amount increases
	// At fill_amount=0: only pixels right at the edge are lit (threshold=0)
	// At fill_amount=1: all pixels lit (threshold=1)
	float threshold = fill_amount;
	float filled = smoothstep(threshold - 0.15, threshold + 0.05, dist_from_edge);

	// Pulse when full
	float pulse = 1.0;
	if (fill_amount >= 1.0) {
		pulse = 0.75 + 0.25 * sin(time_offset * 3.0);
	}

	// Apply color tint and fill mask to texture alpha
	vec3 tinted = tex.rgb * icon_color.rgb;
	float alpha = tex.a * filled * pulse;

	// Dim unfilled portions very slightly so icon shape is still visible
	float dim = 0.08;
	vec3 final_rgb = mix(tex.rgb * dim, tinted, filled * pulse);
	float final_alpha = max(tex.a * dim, alpha);

	COLOR = vec4(final_rgb, final_alpha);
}
