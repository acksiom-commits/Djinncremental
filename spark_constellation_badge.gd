extends Control
# ========== SPARK CONSTELLATION BADGE v1.2 ==========
# Displays the Kaleb (archon_face) mini-icon on the Sparks
# genbar row when The Spark constellation (id 1) is active
# in its octant AND has at least one Volition assigned.
# v1.2: _process() polling disabled until game_loaded fires,
#       preventing the default active_per_octant=[-1...] from
#       overriding correct state on the frame after load.

const BADGE_SIZE  := Vector2(20.0, 20.0)
const BADGE_COLOR := Color(1.0, 1.0, 1.0, 0.88)

var gc: Node = null
var cd: Node = null
var _badge_tex: Texture2D = null
var _game_loaded: bool = false


func _ready() -> void:
    gc = get_node_or_null("/root/GameContext")
    cd = get_node_or_null("/root/ConstellationData")
    var sm: Node = get_node_or_null("/root/SaveManager")
    var badge_path := "res://icons/archon_face.svg"
    if ResourceLoader.exists(badge_path):
        _badge_tex = load(badge_path)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    tooltip_text = "The Spark is active"
    if sm and sm.has_signal("game_loaded"):
        sm.game_loaded.connect(_on_game_loaded)


func _on_game_loaded(_elapsed: float) -> void:
    _game_loaded = true
    print("[BADGE] game_loaded fired. cd=", cd, " gc=", gc)
    if cd:
        print("[BADGE] active_per_octant=", cd.get("active_per_octant"))
    if gc:
        print("[BADGE] has_volition_1=", gc.has_volition_for_constellation(1))
    _refresh_visibility()
    print("[BADGE] visible after refresh=", visible)


func _is_active() -> bool:
    if not gc or not cd:
        return false
    var active_arr = cd.get("active_per_octant")
    if not active_arr is Array:
        return false
    # active_per_octant values are floats after JSON round-trip.
    # Cast each element to int before comparison.
    var found := false
    for v in (active_arr as Array):
        if int(v) == 1:
            found = true
            break
    if not found:
        return false
    return gc.has_method("has_volition_for_constellation") \
        and gc.has_volition_for_constellation(1)


func _refresh_visibility() -> void:
    var active := _is_active()
    visible = active
    if active:
        queue_redraw()


func _process(_delta: float) -> void:
    if not _game_loaded:
        return
    _refresh_visibility()


func _draw() -> void:
    if not _badge_tex or not _is_active():
        return
    var pos := (size - BADGE_SIZE) * 0.5
    draw_texture_rect(
        _badge_tex,
        Rect2(pos, BADGE_SIZE),
        false,
        BADGE_COLOR
    )
