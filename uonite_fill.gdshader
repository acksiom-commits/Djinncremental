shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

uniform vec4 outer_color : source_color = vec4(0.6, 0.27, 0.93, 1.0); // purple - outer
uniform vec4 mid_color   : source_color = vec4(0.2, 0.85, 0.35, 1.0); // green
uniform vec4 inner_color : source_color = vec4(0.95, 0.25, 0.25, 1.0); // red
uniform vec4 center_spark : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float purple_size : hint_range(0.10, 0.40) = 0.29;     // ← increased a bit
uniform float green_size  : hint_range(0.20, 0.45) = 0.27;     // ← decreased a bit
uniform float transition_width : hint_range(0.01, 0.08) = 0.02; // narrow clean transition
uniform float sharpness       : hint_range(2.0, 5.0) = 3.0;

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    float dist = length(local_pos);
    float t = clamp(dist / 1.0, 0.0, 1.0); // 1.0 = outer, 0.0 = center

    float purple_end = 1.0 - purple_size;      // purple zone: t >= purple_end
    float green_end  = purple_end - green_size;

    vec4 col;

    if (t >= purple_end) {
        col = outer_color;                     // pure purple
    }
    else if (t >= green_end) {
        float dist_to_purple = purple_end - t;
        if (dist_to_purple < transition_width) {
            float mix_t = smoothstep(0.0, transition_width, dist_to_purple);
            col = mix(mid_color, outer_color, pow(mix_t, sharpness));
        } else {
            col = mid_color;                   // pure green
        }
    }
    else {
        float dist_to_green = green_end - t;
        if (dist_to_green < transition_width) {
            float mix_t = smoothstep(0.0, transition_width, dist_to_green);
            col = mix(inner_color, mid_color, pow(mix_t, sharpness));
        } else {
            col = inner_color;                 // pure red
        }
    }

    if (dist < 0.12) {
        col = center_spark;
    }

    ALBEDO = col.rgb;
    ALPHA = 1.0;  // always fully opaque
}