extends Control
# ================ CONSTELLATION OVERLAY v2.1.0 ================
# Fullscreen transparent Control (Mouse Filter: Ignore) that sits
# between the starfield and the UI in the CanvasLayer.
#
# Responsibilities:
#   - Projects 3D constellation star positions to screen space
#     using the starfield's live effective view matrix.
#   - Draws connecting lines between stars via _draw().
#   - Handles puzzle click interaction for all active constellations.
#
# The starfield shader renders the star dots/glows.
# This overlay renders lines and owns all puzzle state.
#
# v2.1.0: star-click reading moved from _input() to _unhandled_input()
# so UI drawn on top of this fullscreen overlay always wins clicks. See
# _unhandled_input()'s comment — reading in _input() ran before Control
# GUI picking and made this overlay swallow clicks meant for the
# constellation slideout's buttons / the study panel, a recurring bug.
# Requires the starfield ColorRect behind us to be MOUSE_FILTER_IGNORE
# (RootUI.tscn) so open-space star clicks still reach here.
#
# v2.0.0: the click-sequence state machine + audio now delegate to
# ClickSequencePuzzleEngine, shared with constellation_fork_puzzle.gd's
# Fork mode — see docs/early_game_architecture_overview.md §4,
# refactor-order item #9. Projection/drawing/input and the Q/P debug
# hotkeys (no Fork equivalent) stay here.

signal puzzle_star_clicked(star_index: int)

# ===================== AUTOLOAD REFS =============
var _cd: Node = null
var _gc: Node = null

# ===================== NODE REFS =================
var _starfield: Node = null

# ===================== TUNING ===================
const HIT_RADIUS:            float = 22.0
const SUCCESS_NOTE_DURATION: float = 0.16
const LINE_COLOR_DIM:        Color = Color(0.7,  0.65, 0.5,  0.25)
const LINE_COLOR_BRIGHT:     Color = Color(0.9,  0.85, 0.65, 0.65)
const WRONG_FLASH_COLOR:     Color = Color(1.0,  0.2,  0.2,  0.5)

# Shared with constellation_study_overlay.gd — see star_color_palette.gd.
# (STAR_COLOR_BLUE/WHITE/YELLOW_ORANGE/RED individually-named consts
# removed 2026-07-27 — confirmed dead, unused anywhere in the project,
# redundant with the array below even where they were declared.)
const STAR_COLORS_BY_IDX: Array = preload("res://star_color_palette.tres").by_idx

# ===================== PUZZLE STATE ==============
var _puzzle_target_id: int = 0
var _engine: ClickSequencePuzzleEngine = ClickSequencePuzzleEngine.new()

@onready var _synth: Node = get_node_or_null("../RootUI/PuzzleSynths")
@onready var _study_overlay: Node = get_node_or_null("../ConstellationStudyOverlay")

# ===================== PUZZLE TESTING ==============
var _debug_seq_active:  bool  = false
var _debug_seq_step:    int   = 0
var _debug_seq_timer:   float = 0.0
var _debug_lit_star:    int   = -1
var _debug_current_gap:  float = 0.65

# ===================== PROJECTION CACHE ==========
# constellation_id -> Array[Vector2] of screen positions
var _projected_positions: Dictionary = {}
var _constellations_visible: bool = true

const HFOV_DEG: float = 75.0

# ==================================================
# LIFECYCLE
# ==================================================
func _ready() -> void:
    _cd        = get_node_or_null("/root/ConstellationData")
    _gc        = get_node_or_null("/root/GameContext")
    _starfield = get_node_or_null("../ColorRect")
    if _cd:
        _cd.active_constellation_changed.connect(_on_active_constellation_changed)
    _engine.configure_io(_synth, Callable(self, "queue_redraw"))
    _engine.set_constellation(_puzzle_target_id, _cd, _gc)
    _engine.check_availability()


func _process(delta: float) -> void:
    if not _cd or not _starfield:
        return

    _update_projected_positions()
    queue_redraw()

    if _engine.state == ClickSequencePuzzleEngine.State.IDLE:
        _engine.check_availability()

    if _debug_seq_active:
        _debug_seq_timer += delta
        if _debug_seq_timer >= _debug_current_gap:
            _debug_seq_timer = 0.0
            var def:       Dictionary = _cd.get_constellation_def(_puzzle_target_id)
            var sequence:  Array      = def.get("puzzle_sequence", [])
            var durations: Array      = def.get("note_durations", [])
            if _debug_seq_step >= sequence.size():
                _debug_seq_active   = false
                _debug_lit_star     = -1
                _debug_current_gap  = 0.65
            else:
                # Same dormant-but-real exposure as line_pairs above: this
                # def could be a player/patron constellation with a
                # corrupted "puzzle_sequence" element.
                var raw_pitch = sequence[_debug_seq_step]
                var pitch_idx: int = int(raw_pitch) if typeof(raw_pitch) in [TYPE_INT, TYPE_FLOAT] else 0
                _engine.play_note_by_pitch_index(pitch_idx)
                _debug_lit_star = -1
                for si in _engine.note_assignment.size():
                    if _engine.note_assignment[si] == pitch_idx:
                        _debug_lit_star = si
                        break
                if _debug_seq_step < durations.size():
                    # Same corrupted-save exposure as raw_pitch above — a
                    # typed float assignment from a wrong-typed "note_
                    # durations" element hangs rather than raising a
                    # catchable error (confirmed elsewhere this session).
                    var raw_duration = durations[_debug_seq_step]
                    _debug_current_gap = float(raw_duration) if typeof(raw_duration) in [TYPE_INT, TYPE_FLOAT] else 0.65
                else:
                    _debug_current_gap = 0.65
                _debug_seq_step += 1

    _engine.tick(delta)

# ==================================================
# PROJECTION
# ==================================================
func _update_projected_positions() -> void:
    _projected_positions.clear()
    var eff_mat: Basis      = _starfield.get_effective_view_matrix()
    var vp_size: Vector2    = get_viewport_rect().size
    var aspect:  float      = vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.0

    for octant in 8:
        var id: int = _cd.active_per_octant[octant]
        if id == -1:
            continue
        var positions: Array = _cd.get_star_positions(id)
        var screen_positions: Array = []
        for world_dir in positions:
            var sp: Vector2 = _world_to_screen(world_dir, eff_mat, vp_size, aspect)
            screen_positions.append(sp)
        # Apply visual offset so the snapped constellation appears
        # at the panel position rather than screen center.
        var snap_offset: Vector2 = _starfield.get_snap_draw_offset()
        if snap_offset != Vector2.ZERO and id == _puzzle_target_id:
            for i in screen_positions.size():
                screen_positions[i] = screen_positions[i] + snap_offset
        _projected_positions[id] = screen_positions


func set_constellations_visible(vis: bool) -> void:
    _constellations_visible = vis
    visible = vis
    queue_redraw()



func _world_to_screen(world_dir: Vector3, eff_mat: Basis,
                      vp_size: Vector2, aspect: float) -> Vector2:
    var local_ray: Vector3 = eff_mat.inverse() * world_dir
    if local_ray.z <= 0.001:
        return Vector2(-9999.0, -9999.0)
    var inv_2tan: float = 1.0 / (2.0 * tan(deg_to_rad(HFOV_DEG * 0.5)))
    var sx: float = local_ray.x / local_ray.z * inv_2tan + 0.5
    var sy: float = local_ray.y / local_ray.z * aspect * inv_2tan + 0.5
    return Vector2(sx, sy) * vp_size


# ==================================================
# DRAWING
# ==================================================
func _draw() -> void:
    if not _cd or not _constellations_visible:
        return
    var vp_size: Vector2 = get_viewport_rect().size

    for id in _projected_positions:
        var positions: Array = _projected_positions[id]
        if positions.size() < 2:
            continue

        var visual_state: String = _cd.get_visual_state(id)
        var invested:     float  = _cd.get_sparks_invested(id)
        var draw_lines: bool = (
            visual_state == "lines" or visual_state == "art"
        )

        if draw_lines:
            # Line brightness ramps from dim at the lines tier up to bright at
            # the art tier, using the hardcoded absolute spark tiers. The old
            # per-def fraction-based "line_threshold" / 0.85 math was removed
            # with the SPARKS_TIER_* rebalance (see constellation_data.gd).
            var line_frac: float = clampf(
                (invested - _cd.SPARKS_TIER_LINES) /
                (_cd.SPARKS_TIER_ART - _cd.SPARKS_TIER_LINES), 0.0, 1.0)
            var line_color: Color = LINE_COLOR_DIM.lerp(LINE_COLOR_BRIGHT, line_frac)
            var def:   Dictionary = _cd.get_constellation_def(id)
            var pairs: Array      = def.get("line_pairs", [])
            if pairs.is_empty():
                for i in positions.size() - 1:
                    var a: Vector2 = positions[i]
                    var b: Vector2 = positions[i + 1]
                    if a.x < -500.0 or b.x < -500.0:
                        continue
                    if a.x < 0 or a.x > vp_size.x or a.y < 0 or a.y > vp_size.y:
                        if b.x < 0 or b.x > vp_size.x or b.y < 0 or b.y > vp_size.y:
                            continue
                    draw_line(a, b, line_color, 1.5, true)
            else:
                for k in range(0, pairs.size(), 2):
                    # line_pairs is developer-authored constant data for
                    # BUILT_IN constellations, but get_constellation_def()
                    # also serves player_constellations/patron_constellations
                    # — both loaded from external/save data — so a wrong-
                    # typed element here isn't purely theoretical, just not
                    # reachable via any live gameplay path today.
                    var raw_ai = pairs[k]
                    var raw_bi = pairs[k + 1]
                    if not (typeof(raw_ai) in [TYPE_INT, TYPE_FLOAT] and typeof(raw_bi) in [TYPE_INT, TYPE_FLOAT]):
                        continue
                    var ai: int = int(raw_ai)
                    var bi: int = int(raw_bi)
                    if ai < 0 or bi < 0 or ai >= positions.size() or bi >= positions.size():
                        continue
                    var a: Vector2 = positions[ai]
                    var b: Vector2 = positions[bi]
                    if a.x < -500.0 or b.x < -500.0:
                        continue
                    if a.x < 0 or a.x > vp_size.x or a.y < 0 or a.y > vp_size.y:
                        if b.x < 0 or b.x > vp_size.x or b.y < 0 or b.y > vp_size.y:
                            continue
                    draw_line(a, b, line_color, 1.5, true)

        # Fetch per-star colors from puzzle cache if available.
        var puzzle_star_colors: Array = _cd.get_puzzle_star_colors(id)
        var has_star_colors: bool = puzzle_star_colors.size() == positions.size()

        var show_stars: bool = (
            visual_state in ["stars", "lines", "art"]
        )
        var puzzle_active: bool = (
            id == _puzzle_target_id and
            _engine.state in [ClickSequencePuzzleEngine.State.ACTIVE, ClickSequencePuzzleEngine.State.SUCCESS]
        )

        if show_stars or puzzle_active:
            for i in positions.size():
                var p: Vector2 = positions[i]
                if p.x < -500.0:
                    continue

                # Base star color: puzzle color if available, else white.
                var base_color: Color
                if has_star_colors:
                    # get_puzzle_star_colors() only validates that the
                    # returned value is an Array — not that each element is
                    # numeric. The puzzle cache round-trips through save
                    # data, so a corrupted save could put a non-numeric
                    # value at this index; int() on a Dictionary/Array
                    # hangs the engine rather than raising a catchable
                    # error (confirmed elsewhere this session).
                    var raw_color = puzzle_star_colors[i]
                    var ci: int = int(raw_color) if typeof(raw_color) in [TYPE_INT, TYPE_FLOAT] else 0
                    base_color = STAR_COLORS_BY_IDX[clamp(ci, 0, 3)]
                else:
                    base_color = Color(1.0, 1.0, 1.0, 1.0)

                # Modulate alpha by star brightness for the endowment fade-in.
                var brightness: float = _cd.get_star_brightness(id)
                base_color.a = lerp(0.3, 0.9, brightness) if show_stars else 0.70

                draw_circle(p, 3.5, base_color)

                if not puzzle_active:
                    continue

                if i == _debug_lit_star:
                    draw_circle(p, HIT_RADIUS * 1.4, Color(1.0, 1.0, 0.2, 0.45))
                    draw_circle(p, 6.0,               Color(1.0, 1.0, 0.2, 1.00))
                if i == _engine.replay_lit_star:
                    draw_circle(p, HIT_RADIUS * 1.4, Color(0.3, 0.8, 1.0, 0.45))
                    draw_circle(p, 6.0,               Color(0.3, 0.8, 1.0, 1.00))
                if i == _engine.wrong_star and _engine.wrong_flash_timer > 0.0:
                    var t: float = _engine.wrong_flash_timer / ClickSequencePuzzleEngine.WRONG_FLASH_DURATION
                    draw_circle(p, HIT_RADIUS * 1.6, Color(1.0, 0.2, 1.0, 0.4 * t))
                    draw_circle(p, 5.0,               Color(1.0, 0.2, 1.0, 0.9 * t))
                if i == _engine.fanfare_lit_star and _engine.state == ClickSequencePuzzleEngine.State.SUCCESS:
                    draw_circle(p, HIT_RADIUS * 1.6, Color(1.0, 0.9, 0.3, 0.50))
                    draw_circle(p, 7.0,               Color(1.0, 0.95, 0.5, 1.00))


# ==================================================
# INPUT
# ==================================================
func _unhandled_input(event: InputEvent) -> void:
    # _unhandled_input, NOT _input, on purpose. _input runs BEFORE Control
    # GUI picking, so reading star clicks there made this fullscreen overlay
    # swallow clicks meant for UI drawn on top of it — the constellation
    # slideout's Foci/Volition/Endow buttons, the study panel — before those
    # Controls ever got their turn (the recurring "overlay steals clicks from
    # the UI" bug). _unhandled_input runs AFTER GUI picking, so any Control
    # that consumes a click (MOUSE_FILTER_STOP) now wins automatically, with
    # no per-panel guards. This relies on the fullscreen starfield ColorRect
    # behind us being MOUSE_FILTER_IGNORE (set in RootUI.tscn) — otherwise it
    # would consume open-space star clicks in the GUI phase and they'd never
    # reach here.
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_Q:
            _debug_play_sequence()
            return
        if event.keycode == KEY_P:
            _debug_solve_puzzle()
            return
    # Redundant belt-and-suspenders now: the study overlay's fullscreen
    # MOUSE_FILTER_STOP backdrop already consumes clicks in the GUI phase
    # before they could reach _unhandled_input. Kept as a cheap explicit guard.
    if _study_overlay and is_instance_valid(_study_overlay) and _study_overlay.visible:
        return
    if _engine.state != ClickSequencePuzzleEngine.State.ACTIVE or not _constellations_visible or _engine.replay_active:
        return
    if not event is InputEventMouseButton:
        return
    var mbe := event as InputEventMouseButton
    if not mbe.pressed or mbe.button_index != MOUSE_BUTTON_LEFT:
        return
    if not _projected_positions.has(_puzzle_target_id):
        return
    var positions:  Array = _projected_positions[_puzzle_target_id]
    var best_idx:   int   = -1
    var best_dist:  float = HIT_RADIUS
    for i in positions.size():
        var d: float = mbe.position.distance_to(positions[i])
        if d < best_dist:
            best_dist = d
            best_idx  = i
    if best_idx >= 0:
        _engine.on_star_clicked(best_idx)
        puzzle_star_clicked.emit(best_idx)
        get_viewport().set_input_as_handled()

# ==================================================
# PUZZLE — AVAILABILITY
# ==================================================
func _on_active_constellation_changed(_octant: int, constellation_id: int) -> void:
    if constellation_id != -1:
        _puzzle_target_id = constellation_id
        _reset_puzzle()


func _reset_puzzle() -> void:
    _engine.set_constellation(_puzzle_target_id, _cd, _gc)
    _engine.check_availability()


func get_correct_star_sequence(for_constellation_id: int) -> Array:
    return _engine.get_correct_star_sequence(for_constellation_id)


# ==================================================
# PUZZLE — DEBUG HOTKEYS (Q/P — no Fork equivalent)
# ==================================================
func _debug_play_sequence() -> void:
    if _engine.note_assignment.is_empty():
        _engine.note_assignment = _cd.get_note_assignment(_puzzle_target_id)
    _debug_seq_active = true
    _debug_seq_step   = 0
    _debug_seq_timer  = 0.0
    _debug_lit_star   = -1


func _debug_solve_puzzle() -> void:
    if not _cd or not _gc:
        return
    var def: Dictionary = _cd.get_constellation_def(_puzzle_target_id)
    if not def.has("puzzle_sequence"):
        print("[DEBUG] Constellation %d has no puzzle." % _puzzle_target_id)
        return
    var solve_key: String = "constellation_%d_solve_count" % _puzzle_target_id
    if _gc._assignment_int(solve_key, 0) > 0:
        print("[DEBUG] Constellation %d already solved — resetting for retest." % _puzzle_target_id)
        _gc.assignments[solve_key] = 0
        _reset_puzzle()
        return
    if _engine.state != ClickSequencePuzzleEngine.State.ACTIVE:
        print("[DEBUG] Puzzle not ACTIVE (visual state: %s). Invest more sparks first." % _cd.get_visual_state(_puzzle_target_id))
        return
    print("[DEBUG] Force-solving constellation %d." % _puzzle_target_id)
    # "puzzle_sequence" is present (checked above) but not guaranteed an
    # Array — calling .size() on a wrong-typed save-derived value crashes
    # the same way indexing one does (confirmed this session).
    var seq = def["puzzle_sequence"]
    _engine.step = seq.size() if seq is Array else 0
    _engine.force_complete()
