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
    # This panel (a shrink-sized VBoxContainer, custom_minimum_size floor
    # 175) sits nested inside three more shrink-sized containers —
    # ConstellationLeftMargin (MarginContainer) -> AllocationConstellationVBox
    # (VBoxContainer) -> TopBandHBox (HBoxContainer) — each of which also
    # needs to re-sort once this panel grows to fit the newly-visible
    # button below ConstellationDisplay. The single awaited process_frame
    # this had before (the previous fix here) reliably settles the button
    # becoming visible/clickable, but leading theory for the still-open bug
    # report (button fully functional — clicks work, panel opens — but not
    # visually rendered, persisting until a full reload forces a fresh
    # layout pass) is that this doesn't reliably settle the full multi-
    # level resize cascade up through all three ancestor containers in a
    # busy live scene, and nothing else ever re-dirties them afterward once
    # left in a bad state. NOT independently confirmed — a synthetic mock
    # of this exact container chain settled fine even with the OLD single-
    # frame version, so this fix is a defensible hardening of a documented
    # fragile spot, not a proven root-cause fix. Explicitly queue_sort() on
    # every Container ancestor and give the cascade more than one frame to
    # propagate, rather than relying on automatic dirty-tracking alone.
    var ancestor: Node = self
    while ancestor:
        if ancestor is Container:
            ancestor.queue_sort()
        ancestor = ancestor.get_parent()
    for _i in 3:
        await get_tree().process_frame

    # TEMPORARY DIAGNOSTIC — the previous layout-settle fix here did not
    # resolve the reported bug (button clickable/functional but invisible,
    # persisting until reload). Dumping the actual render-relevant state of
    # the button and every Control ancestor to find out which one is
    # actually wrong, instead of guessing again. Safe to remove once
    # confirmed/fixed — prints nothing that affects gameplay.
    print("[STUDY_BTN_DIAG] --- reveal_study_button diagnostic dump ---")
    print("[STUDY_BTN_DIAG] StudyButton: visible=%s modulate=%s self_modulate=%s global_rect=%s size=%s z_index=%s theme=%s" % [
        _study_btn.visible, _study_btn.modulate, _study_btn.self_modulate,
        _study_btn.get_global_rect(), _study_btn.size, _study_btn.z_index, _study_btn.theme])
    var diag_node: Node = self
    while diag_node:
        if diag_node is Control:
            print("[STUDY_BTN_DIAG] %s (%s): visible=%s modulate=%s self_modulate=%s size=%s z_index=%s z_as_relative=%s clip_contents=%s" % [
                diag_node.name, diag_node.get_class(), diag_node.visible, diag_node.modulate,
                diag_node.self_modulate, diag_node.size, diag_node.z_index, diag_node.z_as_relative,
                diag_node.clip_contents])
        elif diag_node is CanvasLayer:
            print("[STUDY_BTN_DIAG] %s (CanvasLayer): layer=%s visible=%s" % [diag_node.name, diag_node.layer, diag_node.visible])
        diag_node = diag_node.get_parent()
    print("[STUDY_BTN_DIAG] --- end dump ---")
