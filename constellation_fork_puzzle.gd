class_name ConstellationForkPuzzle
extends RefCounted
# ================ CONSTELLATION FORK PUZZLE v1.0.0 ================
# Extracted from constellation_study_overlay.gd (Stage 1 of the file split
# described in docs/early_game_architecture_overview.md, §4). This is the
# "Tuning-Fork Sequence Mode" minigame: click stars in the order their notes
# played, Simon-says style. Owned and driven by ConstellationStudyOverlay —
# constructed once in _ready(), reconfigured per-constellation via
# set_constellation(), and ticked from the owner's _process().
#
# Known duplication (not resolved by this extraction): this is a near-total
# copy of constellation_overlay.gd's live click-sequence puzzle, including a
# second independent WAV-synth fallback. Flagged in the architecture
# overview as a future de-duplication candidate, not attempted here.
#
# Internal var/function names keep their original "_fork_" prefixing from
# the monolithic file on purpose — this was a mechanical move, not a
# rewrite, to minimize the chance of a rename slipping past review.

enum ForkState { IDLE, ACTIVE, SUCCESS }

const FORK_WRONG_FLASH_DURATION: float = 0.6
const FORK_COLOR_WRONG:   Color = Color(1.0, 0.2, 1.0, 1.0)
const FORK_COLOR_REPLAY:  Color = Color(0.3, 0.8, 1.0, 1.0)
const FORK_COLOR_FANFARE: Color = Color(1.0, 0.95, 0.5, 1.0)

# ── DEPENDENCIES (injected via setup()/set_constellation()) ───────────
var _synth:             Node    = null
var _star_map_control:  Control = null
var _fork_btn:          Button  = null
var _audio_parent:      Node    = null
var _cd:                Node    = null
var _gc:                Node    = null
var _constellation_id:  int     = -1

# ── STATE ────────────────────────────────────────────────────────────
var _fork_mode:             bool      = false
var _fork_state:            ForkState = ForkState.IDLE
var _fork_step:             int       = 0
var _fork_note_assignment:  Array     = []
var _fork_correct_sequence: Array     = []
var _fork_tone_players:     Array     = []
var _fork_wrong_star:       int       = -1
var _fork_wrong_flash_timer: float    = 0.0
var _fork_replay_active:    bool      = false
var _fork_replay_step:      int       = 0
var _fork_replay_limit:     int       = 0
var _fork_replay_timer:     float     = 0.0
var _fork_replay_gap:       float     = 0.0
var _fork_replay_lit_star:  int       = -1
var _fork_high_water:       int       = 0
var _fork_fanfare_lit_star: int       = -1


# ==================================================
# PUBLIC API (called from ConstellationStudyOverlay)
# ==================================================
func setup(synth: Node, star_map_control: Control, fork_btn: Button, audio_parent: Node) -> void:
    _synth            = synth
    _star_map_control = star_map_control
    _fork_btn         = fork_btn
    _audio_parent     = audio_parent
    if _synth and _synth.has_signal("sequence_note_played"):
        _synth.sequence_note_played.connect(_on_fork_fanfare_note)


func set_constellation(constellation_id: int, cd: Node, gc: Node) -> void:
    _constellation_id = constellation_id
    _cd = cd
    _gc = gc
    _reset()


func toggle_mode() -> void:
    _fork_mode = not _fork_mode
    _fork_btn.modulate = Color(0.3, 1.0, 0.4, 1.0) if _fork_mode else Color(1, 1, 1, 1)
    if _fork_mode:
        _check_fork_availability()
    if is_instance_valid(_star_map_control):
        _star_map_control.queue_redraw()


func force_off() -> void:
    _fork_mode = false
    _fork_btn.modulate = Color(1, 1, 1, 1)


func tick(delta: float) -> void:
    if _fork_wrong_flash_timer > 0.0:
        _fork_wrong_flash_timer -= delta
        _star_map_control.queue_redraw()

    if _fork_replay_active:
        _fork_replay_timer += delta
        if _fork_replay_timer >= _fork_replay_gap:
            _fork_replay_timer = 0.0
            var def:       Dictionary = _cd.get_constellation_def(_constellation_id)
            var sequence:  Array      = def.get("puzzle_sequence", [])
            var durations: Array      = def.get("note_durations", [])
            if _fork_replay_step >= _fork_replay_limit:
                _fork_replay_active   = false
                _fork_replay_lit_star = -1
            else:
                var pitch_idx: int = sequence[_fork_replay_step]
                _play_fork_note_by_pitch_index(pitch_idx)
                _fork_replay_lit_star = _fork_correct_sequence[_fork_replay_step]
                if _fork_replay_step < durations.size():
                    _fork_replay_gap = durations[_fork_replay_step]
                else:
                    _fork_replay_gap = 0.65
                _fork_replay_step += 1
            _star_map_control.queue_redraw()


# ==================================================
# FORK PUZZLE — TUNING-FORK SEQUENCE MODE
# ==================================================
func _reset() -> void:
    _fork_mode = false
    if is_instance_valid(_fork_btn):
        _fork_btn.modulate = Color(1, 1, 1, 1)
    _fork_step = 0
    _fork_note_assignment.clear()
    _fork_correct_sequence.clear()
    _fork_wrong_star = -1
    _fork_wrong_flash_timer = 0.0
    _fork_replay_active = false
    _fork_replay_lit_star = -1
    _fork_fanfare_lit_star = -1
    _fork_state = ForkState.IDLE
    if is_instance_valid(_star_map_control):
        _star_map_control.queue_redraw()


func _check_fork_availability() -> void:
    if not _cd or not _gc or _constellation_id < 0:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    if not def.has("puzzle_sequence"):
        _fork_state = ForkState.IDLE
        return
    var solve_key: String = "constellation_%d_solve_count" % _constellation_id
    var solves: int = _gc.assignments.get(solve_key, 0)
    if solves > 0:
        _fork_state = ForkState.IDLE
        return
    var visual: String = _cd.get_visual_state(_constellation_id)
    if visual == "dark":
        _fork_state = ForkState.IDLE
        return
    _fork_state = ForkState.ACTIVE
    _fork_step  = 0
    var hw_key := "constellation_%d_high_water" % _constellation_id
    _fork_high_water = _gc.assignments.get(hw_key, 0)
    if _fork_note_assignment.is_empty():
        _fork_note_assignment = _cd.get_note_assignment(_constellation_id)
    if _fork_correct_sequence.is_empty():
        _build_fork_correct_sequence()
    if _fork_tone_players.is_empty():
        _build_fork_tone_players()


func _build_fork_correct_sequence() -> void:
    _fork_correct_sequence.clear()
    if not _cd or _fork_note_assignment.is_empty():
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    var sequence: Array = def.get("puzzle_sequence", [])
    var used: Array = []
    for step in sequence.size():
        var pitch: int = sequence[step]
        var best_star: int = -1
        for si in _fork_note_assignment.size():
            if _fork_note_assignment[si] == pitch and si not in used:
                best_star = si
                break
        if best_star == -1:
            for si in _fork_note_assignment.size():
                if _fork_note_assignment[si] == pitch:
                    best_star = si
                    break
        if best_star >= 0:
            used.append(best_star)
        _fork_correct_sequence.append(best_star)


func _on_fork_star_clicked(star_index: int) -> void:
    if _fork_replay_active:
        return
    if _fork_correct_sequence.is_empty() or not _cd:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    if not def.has("puzzle_sequence"):
        return
    var sequence: Array = def["puzzle_sequence"]
    var clicked: int = _fork_note_assignment[star_index]
    var correct_star: int = _fork_correct_sequence[_fork_step]

    _play_fork_note_by_pitch_index(clicked)

    if star_index == correct_star:
        _fork_step += 1
        _fork_wrong_star        = -1
        _fork_wrong_flash_timer = 0.0
        if _fork_step > _fork_high_water:
            _fork_high_water = _fork_step
            if _gc:
                var hw_key := "constellation_%d_high_water" % _constellation_id
                _gc.assignments[hw_key] = _fork_high_water
        if _fork_step >= sequence.size():
            _on_fork_puzzle_complete()
    else:
        _fork_wrong_star        = star_index
        _fork_wrong_flash_timer = FORK_WRONG_FLASH_DURATION
        _fork_step               = 0
        if _fork_high_water > 0:
            _fork_replay_active   = true
            _fork_replay_step     = 0
            _fork_replay_limit    = _fork_high_water
            _fork_replay_timer    = 0.0
            _fork_replay_gap      = FORK_WRONG_FLASH_DURATION + 0.3
            _fork_replay_lit_star = -1
    _star_map_control.queue_redraw()


func _on_fork_puzzle_complete() -> void:
    _fork_state = ForkState.SUCCESS
    if _gc:
        var solve_key: String = "constellation_%d_solve_count" % _constellation_id
        _gc.assignments[solve_key] = 1

    var solve_path: String = "res://sequences/constellation_%d_solve.tres" % _constellation_id
    var solve_seq = load(solve_path) as PuzzleSequenceResource
    if solve_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(solve_seq, _play_fork_completion_reward)
    else:
        _finish_fork_sequences()


func _on_fork_fanfare_note(freq: float) -> void:
    if _fork_state != ForkState.SUCCESS:
        return
    _fork_fanfare_lit_star = _freq_to_fork_star(freq)
    _star_map_control.queue_redraw()


func _freq_to_fork_star(freq: float) -> int:
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
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
    for si in _fork_note_assignment.size():
        if _fork_note_assignment[si] == best_pitch:
            return si
    return -1


func _play_fork_completion_reward() -> void:
    var reward_path: String = "res://sequences/constellation_%d_reward.tres" % _constellation_id
    var reward_seq = load(reward_path) as PuzzleSequenceResource
    if reward_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(reward_seq, _finish_fork_sequences)
    else:
        _finish_fork_sequences()


func _finish_fork_sequences() -> void:
    _fork_fanfare_lit_star = -1
    _fork_state             = ForkState.IDLE
    _check_fork_availability()
    _star_map_control.queue_redraw()


func _play_fork_note_by_pitch_index(pitch_index: int) -> void:
    if not _synth:
        if pitch_index < 0 or pitch_index >= _fork_tone_players.size():
            return
        _fork_tone_players[pitch_index].stop()
        _fork_tone_players[pitch_index].play()
        return
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
    if pitch_index < 0 or pitch_index >= freqs.size():
        return
    var freq: float = freqs[pitch_index]
    if freq == 0.0:
        if _synth.has_method("play_thud"):
            _synth.play_thud()
        return
    if _synth.has_method("play_bell_note"):
        _synth.play_bell_note(freq)


func _build_fork_tone_players() -> void:
    for p in _fork_tone_players:
        p.queue_free()
    _fork_tone_players.clear()
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
    for freq in freqs:
        var p: AudioStreamPlayer = AudioStreamPlayer.new()
        p.stream    = _make_fork_tone_wav(freq, 0.35)
        p.volume_db = -6.0
        _audio_parent.add_child(p)
        _fork_tone_players.append(p)


func _make_fork_tone_wav(freq: float, duration: float) -> AudioStreamWAV:
    const SAMPLE_RATE: int = 22050
    var n: int = int(duration * SAMPLE_RATE)
    var buf: PackedByteArray = PackedByteArray()
    buf.resize(n * 2)
    for i in n:
        var t: float = float(i) / SAMPLE_RATE
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
