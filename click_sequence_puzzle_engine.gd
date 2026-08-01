class_name ClickSequencePuzzleEngine
extends RefCounted
# ============= CLICK SEQUENCE PUZZLE ENGINE v1.0.0 =============
# Shared "click stars in the order their notes played" (Simon-says style)
# state machine + audio, extracted from constellation_overlay.gd (the live
# main puzzle) and constellation_fork_puzzle.gd (the Fork-mode duplicate of
# it) — see docs/early_game_architecture_overview.md §4, refactor-order
# item #9. Both owners inject their own cd/gc/synth and drive this engine
# per-constellation; drawing, projection, and input stay with each owner.
#
# reset() deliberately does NOT call check_availability() — the two owners
# want different eagerness (the main puzzle should be live the instant a
# constellation is switched to; Fork mode is opt-in and only checks
# availability when the player toggles it on). That decision stays with
# the caller.
#
# tick() calls the injected redraw_cb unconditionally at every state
# change point. This mirrors Fork's original explicit queue_redraw() calls;
# it's a harmless no-op for owners (like the main overlay) whose own
# _process() already redraws every frame regardless.

enum State { IDLE, ACTIVE, SUCCESS }

const WRONG_FLASH_DURATION: float = 0.6

# ── DEPENDENCIES (injected via configure_io()/set_constellation()) ─────
var synth:           Node = null
var _redraw_cb:       Callable = Callable()
var cd:              Node = null
var gc:              Node = null
var constellation_id: int  = -1

# ── STATE ────────────────────────────────────────────────────────────
var state:             State  = State.IDLE
var step:               int    = 0
var note_assignment:    Array  = []
var correct_sequence:   Array  = []
var wrong_star:         int    = -1
var wrong_flash_timer:  float  = 0.0
var replay_active:      bool   = false
var replay_step:        int    = 0
var replay_limit:       int    = 0
var replay_timer:       float  = 0.0
var replay_gap:         float  = 0.0
var replay_lit_star:    int    = -1
var high_water:         int    = 0
var fanfare_lit_star:   int    = -1


# ==================================================
# COERCION HELPERS — cd.get_constellation_def() serves player_constellations/
# patron_constellations, both loaded from save data, so "puzzle_sequence"/
# "note_durations" fields (and their elements) can be wrong-typed. A typed
# Array assignment or per-element typed int/float assignment from a
# wrong-typed value hangs the engine rather than raising a catchable error
# (confirmed directly this session) — every def-field read below is routed
# through one of these first.
# ==================================================
func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


func _coerce_float(val, default: float) -> float:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return float(val)
    return default


func _coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


# ==================================================
# PUBLIC API
# ==================================================
func configure_io(p_synth: Node, redraw_cb: Callable) -> void:
    synth      = p_synth
    _redraw_cb = redraw_cb
    # Both current call sites (constellation_overlay.gd, constellation_fork_
    # puzzle.gd via .setup()) only call this once, from _ready() — so this
    # guard isn't reachable today. Added defensively so configure_io() stays
    # safe to call more than once on the same synth (e.g. a future audio
    # rework that re-configures IO after a synth swap) without _on_fanfare_note
    # firing once per stacked connection.
    if synth and synth.has_signal("sequence_note_played") \
            and not synth.sequence_note_played.is_connected(_on_fanfare_note):
        synth.sequence_note_played.connect(_on_fanfare_note)


func set_constellation(p_constellation_id: int, p_cd: Node, p_gc: Node) -> void:
    constellation_id = p_constellation_id
    cd = p_cd
    gc = p_gc
    reset()


func reset() -> void:
    step = 0
    note_assignment.clear()
    correct_sequence.clear()
    wrong_star = -1
    wrong_flash_timer = 0.0
    replay_active = false
    replay_lit_star = -1
    fanfare_lit_star = -1
    state = State.IDLE


func check_availability() -> void:
    if not cd or not gc or constellation_id < 0:
        return
    var def: Dictionary = cd.get_constellation_def(constellation_id)
    if not def.has("puzzle_sequence"):
        state = State.IDLE
        return
    var solve_key: String = "constellation_%d_solve_count" % constellation_id
    var solves: int = gc._assignment_int(solve_key, 0)
    if solves > 0:
        state = State.IDLE
        return
    var visual: String = cd.get_visual_state(constellation_id)
    if visual == "dark":
        state = State.IDLE
        return
    state = State.ACTIVE
    step  = 0
    var hw_key := "constellation_%d_high_water" % constellation_id
    high_water = gc._assignment_int(hw_key, 0)
    if note_assignment.is_empty():
        note_assignment = cd.get_note_assignment(constellation_id)
    if correct_sequence.is_empty():
        _build_correct_star_sequence()


func get_correct_star_sequence(for_constellation_id: int) -> Array:
    if constellation_id == for_constellation_id and not correct_sequence.is_empty():
        return correct_sequence
    # This same engine instance also drives LIVE click-based gameplay
    # (constellation_overlay.gd's _engine). root_ui.gd's background puzzle-
    # generation trigger (_start_puzzle_generation(), fired on prestige
    # completion — a normal core-gameplay event, not an edge case) calls
    # through to this function for whichever constellation id it's
    # pre-generating, independent of whatever the player may currently be
    # actively clicking through. Silently overwriting constellation_id/
    # note_assignment/correct_sequence here — as the old code did
    # unconditionally — would corrupt that live session: `step` isn't
    # reset to match, so the next click evaluates against the wrong
    # constellation's data, and crashes outright (Array OOB) if the new
    # correct_sequence is shorter than `step`. Compute into a standalone
    # result instead of touching self's fields whenever there's a live
    # session for a DIFFERENT constellation to protect.
    if state == State.ACTIVE and constellation_id >= 0 and constellation_id != for_constellation_id:
        var other_note_assignment: Array = cd.get_note_assignment(for_constellation_id) if cd else []
        return _compute_correct_star_sequence(for_constellation_id, other_note_assignment)

    var prev_target: int = constellation_id
    constellation_id = for_constellation_id
    if note_assignment.is_empty() or prev_target != for_constellation_id:
        note_assignment = cd.get_note_assignment(for_constellation_id)
    _build_correct_star_sequence()
    return correct_sequence


func on_star_clicked(star_index: int) -> void:
    if replay_active:
        return
    # Only accept clicks while the puzzle is actively being solved. This
    # rejects both "not started" (IDLE) and — the actual bug — "already
    # solved" (SUCCESS): _on_puzzle_complete() leaves step at sequence.size(),
    # so a stray post-solve click read correct_sequence[step] out of bounds.
    # The main overlay gated this itself, but the study/Fork path
    # (constellation_fork_puzzle.gd) calls through unconditionally, so the
    # guard belongs here in the shared engine.
    if state != State.ACTIVE:
        return
    if correct_sequence.is_empty() or not cd:
        return
    # A bad hit-test index must not read past note_assignment — same
    # out-of-bounds class as the step overflow the state guard above fixes.
    if star_index < 0 or star_index >= note_assignment.size():
        return
    var def: Dictionary = cd.get_constellation_def(constellation_id)
    var sequence: Array = _coerce_array(def.get("puzzle_sequence"), [])
    if sequence.is_empty():
        return
    var clicked: int = _coerce_int(note_assignment[star_index], -1)
    var correct_star: int = correct_sequence[step]

    play_note_by_pitch_index(clicked)

    if star_index == correct_star:
        step += 1
        wrong_star = -1
        wrong_flash_timer = 0.0
        if step > high_water:
            high_water = step
            if gc:
                var hw_key := "constellation_%d_high_water" % constellation_id
                gc.assignments[hw_key] = high_water
        if step >= sequence.size():
            _on_puzzle_complete()
    else:
        wrong_star = star_index
        wrong_flash_timer = WRONG_FLASH_DURATION
        step = 0
        if high_water > 0:
            replay_active = true
            replay_step = 0
            replay_limit = high_water
            replay_timer = 0.0
            replay_gap = WRONG_FLASH_DURATION + 0.3
            replay_lit_star = -1
    _redraw_cb.call()


## Force the puzzle to its completion state — used by constellation_overlay.gd's
## debug P-key force-solve hotkey, which has no Fork equivalent.
func force_complete() -> void:
    _on_puzzle_complete()


func tick(delta: float) -> void:
    if wrong_flash_timer > 0.0:
        wrong_flash_timer -= delta
        _redraw_cb.call()

    if replay_active:
        replay_timer += delta
        if replay_timer >= replay_gap:
            replay_timer = 0.0
            var def:       Dictionary = cd.get_constellation_def(constellation_id)
            var sequence:  Array      = _coerce_array(def.get("puzzle_sequence"), [])
            var durations: Array      = _coerce_array(def.get("note_durations"), [])
            if replay_step >= replay_limit or replay_step >= sequence.size():
                replay_active   = false
                replay_lit_star = -1
            else:
                var pitch_idx: int = _coerce_int(sequence[replay_step], -1)
                play_note_by_pitch_index(pitch_idx)
                replay_lit_star = correct_sequence[replay_step]
                if replay_step < durations.size():
                    replay_gap = _coerce_float(durations[replay_step], 0.65)
                else:
                    replay_gap = 0.65
                replay_step += 1
            _redraw_cb.call()


# ==================================================
# INTERNAL — SEQUENCE BUILD
# ==================================================
func _build_correct_star_sequence() -> void:
    correct_sequence = _compute_correct_star_sequence(constellation_id, note_assignment)


## Pure — reads/writes nothing on self except through its parameters, so
## get_correct_star_sequence() can call this for a constellation OTHER than
## the one this engine is currently live-tracking without disturbing that
## live session's own state (constellation_id/note_assignment/correct_
## sequence). _build_correct_star_sequence() above is the normal in-place
## wrapper other call sites (check_availability()) use.
func _compute_correct_star_sequence(target_constellation_id: int, target_note_assignment: Array) -> Array:
    var result: Array = []
    if not cd or target_note_assignment.is_empty():
        return result
    var def: Dictionary = cd.get_constellation_def(target_constellation_id)
    var sequence: Array = _coerce_array(def.get("puzzle_sequence"), [])
    var used: Array = []
    for step_i in sequence.size():
        var pitch: int = _coerce_int(sequence[step_i], -1)
        var best_star: int = -1
        for si in target_note_assignment.size():
            if target_note_assignment[si] == pitch and si not in used:
                best_star = si
                break
        if best_star == -1:
            for si in target_note_assignment.size():
                if target_note_assignment[si] == pitch:
                    best_star = si
                    break
        if best_star >= 0:
            used.append(best_star)
        result.append(best_star)
    return result


# ==================================================
# INTERNAL — COMPLETION / REWARD CHAIN
# ==================================================
func _on_puzzle_complete() -> void:
    state = State.SUCCESS
    if gc:
        var solve_key: String = "constellation_%d_solve_count" % constellation_id
        gc.assignments[solve_key] = 1

    # The per-constellation solve sequence is optional — only some
    # constellations ship a constellation_N_solve.tres. Guard the load with
    # ResourceLoader.exists() so a missing one is silent; load() logs
    # "Cannot open file" errors for a nonexistent path even though the null
    # result already falls through cleanly to _finish_sequences() below.
    var solve_path: String = "res://sequences/constellation_%d_solve.tres" % constellation_id
    var solve_seq: PuzzleSequenceResource = null
    if ResourceLoader.exists(solve_path):
        solve_seq = load(solve_path) as PuzzleSequenceResource
    if solve_seq and synth and synth.has_method("play_sequence"):
        synth.play_sequence(solve_seq, _play_completion_reward)
    else:
        _finish_sequences()


func _on_fanfare_note(freq: float) -> void:
    if state != State.SUCCESS:
        return
    fanfare_lit_star = _freq_to_star(freq)
    _redraw_cb.call()


func _freq_to_star(freq: float) -> int:
    var freqs: Array = cd.get_note_freqs(constellation_id)
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
    for si in note_assignment.size():
        if note_assignment[si] == best_pitch:
            return si
    return -1


func _play_completion_reward() -> void:
    # Same optional-resource shape as _on_puzzle_complete()'s solve_seq load —
    # currently only reachable for constellations that already have a
    # solve.tres (0, 1), which both also happen to have a matching
    # reward.tres, so this has never actually hit a missing file yet. Guarded
    # the same way regardless, so adding a solve.tres for another
    # constellation without its reward.tres counterpart doesn't reintroduce
    # the same "Cannot open file" log spam.
    var reward_path: String = "res://sequences/constellation_%d_reward.tres" % constellation_id
    var reward_seq: PuzzleSequenceResource = null
    if ResourceLoader.exists(reward_path):
        reward_seq = load(reward_path) as PuzzleSequenceResource
    if reward_seq and synth and synth.has_method("play_sequence"):
        synth.play_sequence(reward_seq, _finish_sequences)
    else:
        _finish_sequences()


func _finish_sequences() -> void:
    fanfare_lit_star = -1
    state = State.IDLE
    check_availability()
    _redraw_cb.call()


# ==================================================
# AUDIO — public: also called directly by constellation_overlay.gd's
# debug Q-key sequence-playback hotkey, which has no Fork equivalent.
# ==================================================
func play_note_by_pitch_index(pitch_index: int) -> void:
    if not synth:
        return
    var freqs: Array = cd.get_note_freqs(constellation_id)
    if pitch_index < 0 or pitch_index >= freqs.size():
        return
    var freq: float = freqs[pitch_index]
    if freq == 0.0:
        if synth.has_method("play_thud"):
            synth.play_thud()
        return
    if synth.has_method("play_bell_note"):
        synth.play_bell_note(freq)
