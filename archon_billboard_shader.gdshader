shader_type spatial;
render_mode unshaded, cull_disabled;

void vertex() {
    // Y-axis constrained billboard (keeps the object upright, no roll)
    // It still allows your script to control yaw (left/right) and limited pitch
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],           // X axis from camera
        vec4(0.0, 1.0, 0.0, 0.0),     // Force Y axis to stay world-up
        INV_VIEW_MATRIX[2],           // Z axis from camera
        MODEL_MATRIX[3]               // Keep original position + scale
    );
}

void fragment() {
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a;
}