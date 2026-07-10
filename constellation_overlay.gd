extends Control
# ================ CONSTELLATION OVERLAY v1.0.0 ================
# Fullscreen transparent Control (Mouse Filter: Pass) that sits
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

# ===================== AUTOLOAD REFS =============
var _cd: Node = null
var _gc: Node = null

# ===================== NODE REFS =================
var _starfield: Node = null

# ===================== TUNING ===================
const HIT_RADIUS:            float = 22.0
const SUCCESS_NOTE_DURATION: float = 0.16
const WRONG_FLASH_DURATION:  float = 0.6
const LINE_COLOR_DIM:        Color = Color(0.7,  0.65, 0.5,  0.25)
const LINE_COLOR_BRIGHT:     Color = Color(0.9,  0.85, 0.65, 0.65)
const WRONG_FLASH_COLOR:     Color = Color(1.0,  0.2,  0.2,  0.5)

const STAR_COLOR_BLUE:          Color = Color(0.45, 0.65, 1.00, 1.0)
const STAR_COLOR_WHITE:         Color = Color(1.00, 1.00, 1.00, 1.0)
const STAR_COLOR_YELLOW_ORANGE: Color = Color(1.00, 0.80, 0.30, 1.0)
const STAR_COLOR_RED:           Color = Color(1.00, 0.35, 0.25, 1.0)
const STAR_COLORS_BY_IDX: Array = [
    Color(0.45, 0.65, 1.00, 1.0),  # 0 BLUE
    Color(1.00, 1.00, 1.00, 1.0),  # 1 WHITE
    Color(1.00, 0.80, 0.30, 1.0),  # 2 YELLOW_ORANGE
    Color(1.00, 0.35, 0.25, 1.0),  # 3 RED
]

# ===================== PUZZLE STATE ==============
enum PuzzleState { IDLE, ACTIVE, SUCCESS }

var _puzzle_target_id:   int         = 0
var _puzzle_state:       PuzzleState = PuzzleState.IDLE
var _puzzle_step:        int         = 0
var _puzzle_progress:    float       = 0.0
var _note_assignment:    Array       = []
var _tone_players:       Array       = []
var _wrong_flash_timer:  float       = 0.0
var _wrong_star_index:   int         = -1
var _correct_star_sequence: Array    = []
var _fanfare_lit_star:   int = -1

@onready var _synth: Node = get_node_or_null("../RootUI/PuzzleSynths")
@onready var _study_overlay: Node = get_node_or_null("../ConstellationStudyOverlay")

# ===================== PUZZLE TESTING ==============
var _debug_seq_active:  bool  = false
var _debug_seq_step:    int   = 0
var _debug_seq_timer:   float = 0.0
var _debug_lit_star:    int   = -1
var _debug_current_gap:  float = 0.65

# ===================== REPLAY ON WRONG NOTE ======
var _replay_active:      bool  = false
var _replay_step:        int   = 0
var _replay_limit:       int   = 0
var _replay_timer:       float = 0.0
var _replay_current_gap: float = 0.0
var _replay_lit_star:    int   = -1
var _puzzle_high_water:  int   = 0

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
    _check_puzzle_availability()
    if _synth and _synth.has_signal("sequence_note_played"):
        _synth.sequence_note_played.connect(_on_fanfare_note)


func _process(delta: float) -> void:
    if not _cd or not _starfield:
        return

    _update_projected_positions()
    queue_redraw()
    
    if _puzzle_state == PuzzleState.IDLE:
        _check_puzzle_availability()

    if _wrong_flash_timer > 0.0:
        _wrong_flash_timer -= delta
                
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
                var pitch_idx: int = sequence[_debug_seq_step]
                _play_note_by_pitch_index(pitch_idx)
                _debug_lit_star = -1
                for si in _note_assignment.size():
                    if _note_assignment[si] == pitch_idx:
                        _debug_lit_star = si
                        break
                if _debug_seq_step < durations.size():
                    _debug_current_gap = durations[_debug_seq_step]
                else:
                    _debug_current_gap = 0.65
                _debug_seq_step += 1

    if _replay_active:
        _replay_timer += delta
        if _replay_timer >= _replay_current_gap:
            _replay_timer = 0.0
            var def:       Dictionary = _cd.get_constellation_def(_puzzle_target_id)
            var sequence:  Array      = def.get("puzzle_sequence", [])
            var durations: Array      = def.get("note_durations", [])
            if _replay_step >= _replay_limit:
                _replay_active   = false
                _replay_lit_star = -1
            else:
                var pitch_idx: int = sequence[_replay_step]
                _play_note_by_pitch_index(pitch_idx)
                _replay_lit_star = _correct_star_sequence[_replay_step]
                if _replay_step < durations.size():
                    _replay_current_gap = durations[_replay_step]
                else:
                    _replay_current_gap = 0.65
                _replay_step += 1

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
        var fraction:     float  = _cd.get_spark_fraction(id)
        var draw_lines: bool = (
            visual_state == "lines" or visual_state == "art"
        )

        if draw_lines:
            var def_lt: float = _cd.get_constellation_def(id).get("line_threshold", 0.3)
            var line_frac: float = clampf((fraction - def_lt) / (0.85 - def_lt), 0.0, 1.0)
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
                    var ai: int = pairs[k]
                    var bi: int = pairs[k + 1]
                    if ai >= positions.size() or bi >= positions.size():
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
            _puzzle_state in [PuzzleState.ACTIVE, PuzzleState.SUCCESS]
        )

        if show_stars or puzzle_active:
            for i in positions.size():
                var p: Vector2 = positions[i]
                if p.x < -500.0:
                    continue

                # Base star color: puzzle color if available, else white.
                var base_color: Color
                if has_star_colors:
                    var ci: int = int(puzzle_star_colors[i])
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
                if i == _replay_lit_star:
                    draw_circle(p, HIT_RADIUS * 1.4, Color(0.3, 0.8, 1.0, 0.45))
                    draw_circle(p, 6.0,               Color(0.3, 0.8, 1.0, 1.00))
                if i == _wrong_star_index and _wrong_flash_timer > 0.0:
                    var t: float = _wrong_flash_timer / WRONG_FLASH_DURATION
                    draw_circle(p, HIT_RADIUS * 1.6, Color(1.0, 0.2, 1.0, 0.4 * t))
                    draw_circle(p, 5.0,               Color(1.0, 0.2, 1.0, 0.9 * t))
                if i == _fanfare_lit_star and _puzzle_state == PuzzleState.SUCCESS:
                    draw_circle(p, HIT_RADIUS * 1.6, Color(1.0, 0.9, 0.3, 0.50))
                    draw_circle(p, 7.0,               Color(1.0, 0.95, 0.5, 1.00))


# ==================================================
# INPUT
# ==================================================
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_Q:
            _debug_play_sequence()
            return
        if event.keycode == KEY_P:
            _debug_solve_puzzle()
            return
    if _study_overlay and is_instance_valid(_study_overlay) and _study_overlay.visible:
        return
    if _puzzle_state != PuzzleState.ACTIVE or not _constellations_visible or _replay_active:
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
        _on_star_clicked(best_idx)
        get_viewport().set_input_as_handled()

# ==================================================
# PUZZLE — AVAILABILITY
# ==================================================
func _on_active_constellation_changed(_octant: int, constellation_id: int) -> void:
    if constellation_id != -1:
        _puzzle_target_id = constellation_id
        _reset_puzzle()


func _reset_puzzle() -> void:
    _puzzle_step     = 0
    _puzzle_progress = 0.0
    _note_assignment.clear()
    _correct_star_sequence.clear()
    _puzzle_state = PuzzleState.IDLE
    _check_puzzle_availability()


func _check_puzzle_availability() -> void:
    if not _cd or not _gc:
        return
    var def: Dictionary = _cd.get_constellation_def(_puzzle_target_id)
    if not def.has("puzzle_sequence"):
        _puzzle_state = PuzzleState.IDLE
        return
    var solve_key: String = "constellation_%d_solve_count" % _puzzle_target_id
    var solves:    int    = _gc.assignments.get(solve_key, 0)
    if solves > 0:
        _puzzle_state = PuzzleState.IDLE
        return
    var visual: String = _cd.get_visual_state(_puzzle_target_id)
    if visual == "dark":
        _puzzle_state = PuzzleState.IDLE
        return
    _puzzle_state = PuzzleState.ACTIVE
    _puzzle_step  = 0
    if _gc:
        var hw_key := "constellation_%d_high_water" % _puzzle_target_id
        _puzzle_high_water = _gc.assignments.get(hw_key, 0)
    if _note_assignment.is_empty():
        _note_assignment = _cd.get_note_assignment(_puzzle_target_id)
    if _correct_star_sequence.is_empty():
        _build_correct_star_sequence()
    if _tone_players.is_empty():
        _build_tone_players()


func _build_correct_star_sequence() -> void:
    _correct_star_sequence.clear()
    if not _cd or _note_assignment.is_empty():
        return
    var def: Dictionary = _cd.get_constellation_def(_puzzle_target_id)
    var sequence: Array = def.get("puzzle_sequence", [])
    var used: Array = []
    for step in sequence.size():
        var pitch: int = sequence[step]
        var best_star: int = -1
        for si in _note_assignment.size():
            if _note_assignment[si] == pitch and si not in used:
                best_star = si
                break
        if best_star == -1:
            for si in _note_assignment.size():
                if _note_assignment[si] == pitch:
                    best_star = si
                    break
        if best_star >= 0:
            used.append(best_star)
        _correct_star_sequence.append(best_star)


func get_correct_star_sequence(for_constellation_id: int) -> Array:
    if _puzzle_target_id != for_constellation_id or _correct_star_sequence.is_empty():
        var prev_target: int = _puzzle_target_id
        _puzzle_target_id = for_constellation_id
        if _note_assignment.is_empty() or prev_target != for_constellation_id:
            _note_assignment = _cd.get_note_assignment(for_constellation_id)
        _build_correct_star_sequence()
    return _correct_star_sequence


# ==================================================
# PUZZLE — STAR CLICK
# ==================================================
func _on_star_clicked(star_index: int) -> void:
    if _replay_active:
        return
    if _correct_star_sequence.is_empty() or not _cd:
        return
    var def: Dictionary = _cd.get_constellation_def(_puzzle_target_id)
    if not def.has("puzzle_sequence"):
        return
    var sequence: Array = def["puzzle_sequence"]
    var clicked:  int   = _note_assignment[star_index]
    var correct_star: int = _correct_star_sequence[_puzzle_step]
    print("[PUZZLE] step=%d correct_star=%d clicked_star=%d match=%s" % [_puzzle_step, correct_star, star_index, star_index == correct_star])

    _play_note_by_pitch_index(clicked)

    if star_index == correct_star:
        _puzzle_step     += 1
        _puzzle_progress  = float(_puzzle_step) / float(sequence.size())
        _wrong_star_index  = -1
        _wrong_flash_timer = 0.0
        if _puzzle_step > _puzzle_high_water:
            _puzzle_high_water = _puzzle_step
            if _gc:
                var hw_key := "constellation_%d_high_water" % _puzzle_target_id
                _gc.assignments[hw_key] = _puzzle_high_water
        if _puzzle_step >= sequence.size():
            _on_puzzle_complete()
    else:
        _wrong_star_index  = star_index
        _wrong_flash_timer = WRONG_FLASH_DURATION
        _puzzle_step       = 0
        _puzzle_progress   = 0.0
        if _puzzle_high_water > 0:
            _replay_active      = true
            _replay_step        = 0
            _replay_limit       = _puzzle_high_water
            _replay_timer       = 0.0
            _replay_current_gap = WRONG_FLASH_DURATION + 0.3
            _replay_lit_star    = -1


func _on_puzzle_complete() -> void:
    _puzzle_state    = PuzzleState.SUCCESS
    _puzzle_progress = 1.0
    if _gc:
        var solve_key: String = "constellation_%d_solve_count" % _puzzle_target_id
        _gc.assignments[solve_key] = 1

    # Play solve fanfare, then completion reward, then reset
    var solve_path: String = "res://sequences/constellation_%d_solve.tres" % _puzzle_target_id
    var solve_seq = load(solve_path) as PuzzleSequenceResource
    if solve_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(solve_seq, _play_completion_reward)
    else:
        # No sequence file — fall back to immediate reset
        _finish_puzzle_sequences()
        
        
func _on_fanfare_note(freq: float) -> void:
    if _puzzle_state != PuzzleState.SUCCESS:
        return
    _fanfare_lit_star = _freq_to_star(freq)
    queue_redraw()


func _freq_to_star(freq: float) -> int:
    var freqs: Array = _cd.get_note_freqs(_puzzle_target_id)
    var best_pitch: int = -1
    var best_diff: float = 2.0
    for pitch_idx in freqs.size():
        var f: float = freqs[pitch_idx]
        if f <= 0.0:
            continue
        if absf(f - freq) < best_diff:
            best_diff = absf(f - freq)
            best_pitch = pitch_idx
    if best_pitch == -1:
        return -1
    for si in _note_assignment.size():
        if _note_assignment[si] == best_pitch:
            return si
    return -1


func _play_completion_reward() -> void:
    var reward_path: String = "res://sequences/constellation_%d_reward.tres" % _puzzle_target_id
    var reward_seq = load(reward_path) as PuzzleSequenceResource
    if reward_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(reward_seq, _finish_puzzle_sequences)
    else:
        _finish_puzzle_sequences()


func _finish_puzzle_sequences() -> void:
    _fanfare_lit_star = -1
    _puzzle_state     = PuzzleState.IDLE
    _puzzle_progress  = 0.0
    _check_puzzle_availability()
    
    
func _debug_play_sequence() -> void:
    if _note_assignment.is_empty():
        _note_assignment = _cd.get_note_assignment(_puzzle_target_id)
    if _tone_players.is_empty():
        _build_tone_players()
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
    if _gc.assignments.get(solve_key, 0) > 0:
        print("[DEBUG] Constellation %d already solved — resetting for retest." % _puzzle_target_id)
        _gc.assignments[solve_key] = 0
        _reset_puzzle()
        return
    if _puzzle_state != PuzzleState.ACTIVE:
        print("[DEBUG] Puzzle not ACTIVE (visual state: %s). Invest more sparks first." % _cd.get_visual_state(_puzzle_target_id))
        return
    print("[DEBUG] Force-solving constellation %d." % _puzzle_target_id)
    _puzzle_step     = def["puzzle_sequence"].size()
    _puzzle_progress = 1.0
    _on_puzzle_complete()


# ==================================================
# AUDIO
# ==================================================
func _make_tone_wav(freq: float, duration: float) -> AudioStreamWAV:
    const SAMPLE_RATE: int = 22050
    var n:   int           = int(duration * SAMPLE_RATE)
    var buf: PackedByteArray = PackedByteArray()
    buf.resize(n * 2)
    for i in n:
        var t:   float = float(i) / SAMPLE_RATE
        var env: float = 1.0
        if t < 0.01:
            env = t / 0.01
        elif t > duration - 0.05:
            env = clamp((duration - t) / 0.05, 0.0, 1.0)
        var s: int = int(sin(TAU * freq * t) * 32767.0 * env * 0.38)
        s = clamp(s, -32768, 32767)
        buf[i * 2]     = s & 0xFF
        buf[i * 2 + 1] = (s >> 8) & 0xFF
    var wav: AudioStreamWAV = AudioStreamWAV.new()
    wav.data     = buf
    wav.format   = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = SAMPLE_RATE
    wav.stereo   = false
    return wav
    
    
func _play_note_by_pitch_index(pitch_index: int) -> void:
    if not _synth:
        # Fallback to old WAV system
        if pitch_index < 0 or pitch_index >= _tone_players.size():
            return
        _tone_players[pitch_index].stop()
        _tone_players[pitch_index].play()
        return
    var freqs: Array = _cd.get_note_freqs(_puzzle_target_id)
    if pitch_index < 0 or pitch_index >= freqs.size():
        return
    var freq: float = freqs[pitch_index]
    if freq == 0.0:
        if _synth.has_method("play_thud"):
            _synth.play_thud()
        return
    if _synth.has_method("play_bell_note"):
        _synth.play_bell_note(freq)


func _build_tone_players() -> void:
    for p in _tone_players:
        p.queue_free()
    _tone_players.clear()
    var freqs: Array = _cd.get_note_freqs(_puzzle_target_id)
    for freq in freqs:
        var p: AudioStreamPlayer = AudioStreamPlayer.new()
        p.stream    = _make_tone_wav(freq, 0.35)
        p.volume_db = -6.0
        add_child(p)
        _tone_players.append(p)
