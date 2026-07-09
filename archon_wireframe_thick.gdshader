shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float line_thickness : hint_range(1.0, 12.0) = 4.0;

void vertex() {
    // Very minimal expansion - only enough to make lines thicker
    // This version is much gentler and respects your orthogonal camera + tracking better
    vec4 world_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    
    // Expand slightly in camera-right direction (screen X)
    vec3 right = normalize(cross(vec3(0.0, 0.0, -1.0), world_pos.xyz)); // approximate camera right
    VERTEX += right * (line_thickness * 0.001);
}

void fragment() {
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a;
}