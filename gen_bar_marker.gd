extends Control
# ================= GEN BAR MARKER v1.0.0 =================
# Draws a thin vertical line at the 50% position on the
# parent GenBar to give the player a visual warning threshold.
# Add as a sibling of the GenBar ProgressBar inside a
# GenBarContainer Control node. Set to Full Rect anchors.

const MARKER_COLOR: Color = Color(0.92, 0.90, 0.85, 0.45)
const MARKER_WIDTH: float = 1.5


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
    var mid_x = size.x * 0.5
    draw_line(
        Vector2(mid_x, 0.0),
        Vector2(mid_x, size.y),
        MARKER_COLOR,
        MARKER_WIDTH,
        true)
