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
    _study_btn.visible = true
    # Ruled out via a diagnostic dump comparing the live-broken state against
    # a reload-fixed state: EVERY geometry/render property (global_rect,
    # size, modulate, self_modulate, visible, z_index, clip_contents) up the
    # whole ancestor chain was byte-for-byte IDENTICAL in both states — the
    # earlier layout-cascade theory (and its queue_sort()-based fix) was
    # wrong. The button really is sitting in the correct, correctly-sized
    # place with correct visibility/modulate; it just isn't being repainted
    # there. This points at a canvas redraw-invalidation gap instead of a
    # layout gap — plausible given the player is on Intel integrated
    # graphics via the OpenGL Compatibility renderer, a combination with
    # known quirks around a newly-exposed screen region (this panel grew by
    # ~30px to fit this button) not getting flagged for repaint just because
    # a container resized, as opposed to an explicit redraw request. A full
    # reload forces everything to repaint from scratch, which is consistent
    # with "reload always fixes it" regardless of geometry.
    #
    # Toggling visibility off then back on forces Godot to fully re-register
    # this subtree with the rendering server — a much stronger guarantee of
    # a fresh repaint than queue_redraw() alone, which relies on the same
    # dirty-tracking that isn't reliably catching this case. CONFIRMED this
    # fixes the invisibility (player-tested), but the first version awaited
    # a frame between the false and true assignments, which actually
    # rendered a frame with the whole panel (border included) hidden — a
    # visible flicker the player also confirmed. Godot only composites a
    # frame at frame boundaries, so setting visible false then true with NO
    # await between them still drives the same off/on transition (and
    # whatever re-registration it triggers) without the renderer ever
    # getting a chance to draw the momentarily-hidden state.
    await get_tree().process_frame
    self.visible = false
    self.visible = true
    queue_redraw()
    _study_btn.queue_redraw()
    # Player reported this stopped reliably fixing the invisibility on a
    # later fresh playthrough — same symptom as before (button fully
    # functional, just never painted). Toggling `visible` above still
    # relies on Godot's own dirty-tracking deciding to re-submit this
    # subtree to the rendering server, which is exactly the mechanism
    # already suspected unreliable on this hardware/driver combination —
    # a heuristic can silently no-op. Fully detaching and reattaching from
    # the parent forces an unconditional teardown+rebuild of every
    # CanvasItem in this subtree's server-side representation instead, no
    # heuristic involved. move_child() restores the original sibling
    # index so layout order is unaffected; _ready() isn't re-run by
    # remove_child()/add_child() (the node isn't freed, just detached), so
    # the button's .pressed connection made there survives untouched.
    # Kept layered with the toggle above rather than replacing it, in case
    # either mechanism alone is what's actually working on any given setup.
    var parent := get_parent()
    if parent:
        var idx := get_index()
        parent.remove_child(self)
        parent.add_child(self)
        parent.move_child(self, idx)
        queue_redraw()
        _study_btn.queue_redraw()
