extends Control
# ================= CONSTELLATION PANEL v1.3.0 =================
# v1.3.0: reveal_study_button() root-caused: StudyButton was the only
#         reveal-gated element in the whole game hidden via `visible`
#         instead of `modulate.a` + `mouse_filter` (the pattern every
#         other gated panel already uses via root_ui.gd's _reveal_panel/
#         _hide_all_panels). `visible = false` fully excludes a CanvasItem
#         from the renderer's draw list; re-including it later apparently
#         doesn't reliably repaint on this hardware/driver combination
#         (Intel integrated graphics, OpenGL Compatibility renderer) —
#         three different "force a re-registration" attempts on the
#         visible-based version (toggle, detach+reattach, destroy+
#         recreate) all either failed or worked at best inconsistently.
#         modulate.a=0 never removes the CanvasItem from the draw list at
#         all (it's just always drawing at zero alpha), so there's no
#         re-inclusion step to fail. StudyButton's .tscn default changed
#         from `visible = false` to `modulate = Color(1,1,1,0)` +
#         `mouse_filter = 2` (IGNORE) + `disabled = true` to match — see
#         reveal_study_button()'s own comment for why `disabled`, not
#         `mouse_filter`, ended up as the actual interaction gate.
# v1.2.0: StudyButton hidden by default (see RootUI.tscn); reveal_study_button()
#         added, called by root_ui.gd after the study_panel_reveal dialogue.
# v1.1.0: Lazy starfield search, background color rect removed,
#         starfield snap triggered on constellation selection.
# Selector machinery removed. Pure display node.
# Selection callbacks arrive via signal from ConstellationPopout,
# wired in root_ui.gd _ready().

var _cd: Node = null

const STUDY_BUTTON_REVEAL_DURATION: float = 1.5   # matches root_ui.gd's REVEAL_DURATION

@onready var _constellation_art_rect: TextureRect = $ConstellationDisplay/ConstellationArtTextureRect
@onready var _study_btn: Button = $StudyButton

var _active_id:  int  = 8
var _starfield:  Node = null


func _ready() -> void:
    _cd = get_node_or_null("/root/ConstellationData")
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
        sf.snap_to_constellation(constellation_id, center_px)


func _on_study_pressed() -> void:
    var overlay := get_tree().root.find_child("ConstellationStudyOverlay", true, false)
    if overlay and overlay.has_method("show_for_constellation"):
        overlay.show_for_constellation(_active_id)


## Reveals the Study Constellation button, hidden by default until the
## player's first constellation-star click (see root_ui.gd's
## study_panel_reveal dialogue trigger).
func reveal_study_button() -> void:
    # See the v1.3.0 header note — root cause was `visible` itself, not
    # anything about how the transition to visible was triggered. Reveals
    # the same way every other gated panel in the game does (root_ui.gd's
    # _reveal_panel): fade modulate.a up and flip mouse_filter to STOP.
    # The button has been actively drawing at zero alpha the whole time,
    # so there's no "just got re-included in the draw list" step for the
    # renderer to ever get wrong.
    #
    # `disabled` is the actual interaction gate, not mouse_filter — this
    # button lives inside ConstellationPanel, which root_ui.gd's own
    # _restore_subtree_input() unconditionally flips every Button's
    # mouse_filter to STOP for the moment the "constellation" panel
    # itself gets revealed (much earlier than this). With the old
    # `visible = false` that premature flip was harmless, since an
    # invisible Control never receives input regardless of mouse_filter —
    # but this button is visible (at alpha 0) the whole time now, so
    # mouse_filter alone would let it be clicked well before its own
    # reveal. _restore_subtree_input() never touches `disabled`, so it
    # stays the reliable gate independent of that.
    _study_btn.disabled = false
    _study_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    var tween := create_tween()
    tween.tween_property(_study_btn, "modulate:a", 1.0, STUDY_BUTTON_REVEAL_DURATION) \
        .set_trans(Tween.TRANS_SINE) \
        .set_ease(Tween.EASE_OUT)
