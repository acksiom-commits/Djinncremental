extends Control
# ================= CONSTELLATION PANEL v1.2.0 =================
# v1.2.0: StudyButton hidden by default (see RootUI.tscn); reveal_study_button()
#         added, called by root_ui.gd after the study_panel_reveal dialogue.
# v1.1.0: Lazy starfield search, background color rect removed,
#         starfield snap triggered on constellation selection.
# Selector machinery removed. Pure display node.
# Selection callbacks arrive via signal from ConstellationPopout,
# wired in root_ui.gd _ready().

var _cd: Node = null
var _gc: Node = null

@onready var _constellation_art_rect: TextureRect = $ConstellationDisplay/ConstellationArtTextureRect
@onready var _study_btn: Button = $StudyButton

var _active_id:  int  = 8
var _starfield:  Node = null


func _ready() -> void:
    _cd = get_node_or_null("/root/ConstellationData")
    _gc = get_node_or_null("/root/GameContext")
    var display := get_node_or_null("ConstellationDisplay")
    if display is Control:
        display.draw.connect(_draw_border.bind(display))
        display.queue_redraw()
    _set_active_constellation(8)
    _study_btn.pressed.connect(_on_study_pressed)


func _get_starfield() -> Node:
    if _starfield:
        return _starfield
    _starfield = _find_starfield(get_tree().root)
    return _starfield


func _find_starfield(node: Node) -> Node:
    if node.has_method("snap_to_constellation"):
        return node
    for child in node.get_children():
        var result := _find_starfield(child)
        if result:
            return result
    return null


# ── SIZING AID — set _border_alpha to 0.0 when sizing complete ──
const _border_alpha := 1.0
func _draw_border(display: Control) -> void:
    var r := Rect2(Vector2.ZERO, display.size)
    display.draw_rect(r, Color(1.0, 0.85, 0.2, _border_alpha), false, 2.0)
# ────────────────────────────────────────────────────────────────


func _set_active_constellation(constellation_id: int) -> void:
    _active_id = constellation_id
    _refresh_display()


func _refresh_display() -> void:
    if _constellation_art_rect and _cd:
        _constellation_art_rect.visible = (_cd.get_visual_state(_active_id) == "art")


func on_constellation_selected(constellation_id: int) -> void:
    _set_active_constellation(constellation_id)
    if _cd:
        _cd.set_display_constellation(constellation_id)
    var sf := _get_starfield()
    if not sf:
        return
    if constellation_id < 0:
        sf.clear_constellation_target()
    else:
        var display := get_node_or_null("ConstellationDisplay")
        var center_px: Vector2
        if display:
            center_px = display.get_global_rect().get_center() - Vector2(0.0, 35.0)
        else:
            center_px = get_global_rect().get_center()
        print("SNAP center_px: ", center_px, "  display_rect: ", display.get_global_rect() if display else "NO DISPLAY")
        sf.snap_to_constellation(constellation_id, center_px)


func _on_study_pressed() -> void:
    var overlay := get_tree().root.find_child("ConstellationStudyOverlay", true, false)
    if overlay and overlay.has_method("show_for_constellation"):
        overlay.show_for_constellation(_active_id)


## Reveals the Study Constellation button, hidden by default until the
## player's first constellation-star click (see root_ui.gd's
## study_panel_reveal dialogue trigger).
func reveal_study_button() -> void:
    _study_btn.visible = true
