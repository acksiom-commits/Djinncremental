extends Control
# ================= CONSTELLATION PANEL v1.7.0 =================
# v1.7.0: Root cause #2/#4, fixed at the source instead of patched around.
#         This panel (ConstellationPanel) draws nothing of its own — it's a
#         VBoxContainer purely for layout, stacking ConstellationDisplay and
#         StudyButton. Its `modulate` was only ever being used as a shortcut
#         to hide/show both children at once via cascade, but
#         CanvasItem.modulate cascades MULTIPLICATIVELY, so StudyButton's
#         effective on-screen alpha was always parent.modulate.a x its own —
#         never purely dependent on its own reveal (the placeholder study-
#         panel dialogue), no matter how correct that reveal logic was.
#         root_ui.gd's _reveal_panel/_hide_all_panels/_apply_unlock_
#         visibility now use `self_modulate` for this panel's own reveal
#         instead — self_modulate tints only a node's own drawing and does
#         NOT cascade to children, so StudyButton's visibility is now purely
#         its own, full stop. ConstellationDisplay (the other child, which
#         has no modulate of its own and relied entirely on inheriting this
#         panel's hidden-by-default state) now gets that applied to it
#         directly by root_ui.gd wherever this panel's own visibility
#         changes. Both also skip the tween now (direct assignment) — no
#         reason to reintroduce the live-tween-doesn't-paint pattern (root
#         causes #3/#4) on the two nodes it was just found on.
#         The self-heal below now watches self_modulate (not modulate) and
#         ConstellationDisplay's modulate, matching the new mechanism —
#         genuine defense-in-depth now, not compensating for a known-broken
#         path, since both are direct-assigned rather than tweened.
# v1.5.0: Added a per-frame self-heal in _process() — reveal_study_button()
#         re-runs automatically whenever study_panel_reveal_done is true but
#         the button's disabled/modulate state doesn't match, independent of
#         whichever signal/trigger was supposed to have called it. Three
#         separate root causes (v1.3.0, v1.4.0, and the modulate-cascade fix
#         in root_ui.gd) have now made this specific button end up stuck
#         despite the underlying flag being correct — this makes any future
#         divergence self-correct within a frame instead of requiring a
#         fourth investigation.
# v1.4.0: reveal_study_button() no longer tweens modulate.a — root cause #3.
#         Confirmed (user: reload fixes it, live never does, regardless of
#         window resize/minimize/alt-tab) that tween-driven modulate changes
#         don't reliably repaint live on this hardware, the same underlying
#         class of issue as v1.3.0 one level removed: root_ui.gd's reload
#         path (_apply_unlock_visibility) sets modulate.a directly with no
#         tween and always works, because a full scene boot redraws
#         everything unconditionally as nodes enter the tree — a live,
#         already-booted scene gets no such blanket redraw to fall back on.
#         Set modulate.a directly instead; dropped STUDY_BUTTON_REVEAL_DURATION.
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

var _cd:  Node = null
var _adm: Node = null
var _gc:  Node = null

@onready var _constellation_art_rect: TextureRect = $ConstellationDisplay/ConstellationArtTextureRect
@onready var _display: Control = $ConstellationDisplay
@onready var _study_btn: Button = $StudyButton

var _active_id:  int  = 8
var _starfield:  Node = null

## Set ONLY by the study_panel_reveal_sequence_complete signal, which only
## fires once the placeholder dialogue has actually been read to
## completion (dialogue_ended). Deliberately NOT archon_dialogue_manager's
## own study_panel_reveal_done — that flag goes true the instant the
## dialogue is enqueued (the moment the star is clicked), not when it's
## actually finished, which made the v1.5.0 self-heal below reveal the
## button immediately on click instead of waiting for the dialogue like
## the signal-driven path (_on_study_panel_reveal_complete in root_ui.gd)
## always correctly did. This flag tracks the SAME "truly complete" event
## that signal represents, so the self-heal can no longer race ahead of it.
## Stays false for a save where the dialogue already completed in a PRIOR
## session (the signal won't refire) — that's fine, root_ui.gd's own
## load-time resync (_sync_trigger_flags_from_loaded_state) already reveals
## the button directly for that case, independent of this self-heal.
var _study_reveal_complete: bool = false


func _ready() -> void:
    _cd  = get_node_or_null("/root/ConstellationData")
    _adm = get_node_or_null("/root/ArchonDialogueManager")
    _gc  = get_node_or_null("/root/GameContext")
    if _adm:
        _adm.study_panel_reveal_sequence_complete.connect(func(): _study_reveal_complete = true)
    var display := get_node_or_null("ConstellationDisplay")
    if display is Control:
        display.draw.connect(_draw_border.bind(display))
        display.queue_redraw()
    _set_active_constellation(8)
    _study_btn.pressed.connect(_on_study_pressed)


## Self-heals StudyButton's visual/interactive state, and (v1.7.0) this
## panel's own self_modulate + ConstellationDisplay's modulate, against
## their authoritative flags every frame — instead of relying solely on
## whichever one-shot signal/trigger call happened to set them. Genuine
## defense-in-depth now that all three are direct-assigned rather than
## tweened (see v1.7.0 header note for why the button and the panel both
## used to be tween-driven and unreliable live).
func _process(_delta: float) -> void:
    if _gc and _gc.ui_unlocks.get("constellation", false):
        if self_modulate.a < 1.0:
            self_modulate.a = 1.0
        if _display and _display.modulate.a < 1.0:
            _display.modulate.a = 1.0
    if not _study_reveal_complete:
        return
    if _study_btn.disabled or _study_btn.modulate.a < 1.0:
        reveal_study_button()


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
    # v1.4.0: dropped the tween — root cause #3. User confirmed the button
    # DOES appear correctly after a save reload, but never live, no matter
    # what (this is run through the Godot editor's embedded game window, so
    # window resize/minimize/alt-tab aren't meaningful reproduction tools
    # here). The reload path (root_ui.gd's _apply_unlock_visibility) sets
    # modulate.a on already-unlocked panels DIRECTLY, with no tween — this
    # function was the one remaining place still animating modulate via
    # create_tween().tween_property() instead. That matches root cause #1's
    # underlying class of issue (this hardware/renderer doesn't reliably
    # repaint some categories of property change) one level removed:
    # tweened Button.modulate mid-animation isn't repainting live, even
    # though a full scene boot (which redraws everything unconditionally
    # as nodes enter the tree) always picks up the reload path's direct
    # assignment correctly. Set modulate.a directly instead, trading the
    # 1.5s fade-in for a reveal that's actually guaranteed to render.
    _study_btn.disabled = false
    _study_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    _study_btn.modulate.a = 1.0
