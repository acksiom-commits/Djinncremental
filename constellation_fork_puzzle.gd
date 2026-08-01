class_name ConstellationForkPuzzle
extends RefCounted
# ================ CONSTELLATION FORK PUZZLE v2.0.0 ================
# The "Tuning-Fork Sequence Mode" minigame: click stars in the order their
# notes played, Simon-says style. Owned and driven by ConstellationStudyOverlay
# — constructed once in _ready(), reconfigured per-constellation via
# set_constellation(), and ticked from the owner's _process().
#
# v2.0.0: thin adapter over ClickSequencePuzzleEngine, the state-machine +
# audio logic shared with constellation_overlay.gd's live main puzzle (see
# docs/early_game_architecture_overview.md §4, refactor-order item #9 — this
# resolves the "known duplication, not attempted" note the v1.0.0 extraction
# left behind). Every externally-read field/const/enum/method below keeps
# its original v1.0.0 name and shape on purpose, so constellation_study_overlay.gd
# needs zero changes: `_fork_wrong_star` etc. are computed getters backed by
# `_engine`, not stored fields.
#
# _fork_mode/_fork_btn (opt-in toggle UI) and toggle_mode()/force_off() stay
# genuinely local to this file — the main puzzle has no equivalent concept.

enum ForkState {
    IDLE    = ClickSequencePuzzleEngine.State.IDLE,
    ACTIVE  = ClickSequencePuzzleEngine.State.ACTIVE,
    SUCCESS = ClickSequencePuzzleEngine.State.SUCCESS,
}

const FORK_WRONG_FLASH_DURATION: float = 0.6
const FORK_COLOR_WRONG:   Color = Color(1.0, 0.2, 1.0, 1.0)
const FORK_COLOR_REPLAY:  Color = Color(0.3, 0.8, 1.0, 1.0)
const FORK_COLOR_FANFARE: Color = Color(1.0, 0.95, 0.5, 1.0)

# Shared puzzle-state color palette — see puzzle_state_colors.gd.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")

# ── DEPENDENCIES (injected via setup()/set_constellation()) ───────────
var _star_map_control:  Control = null
var _fork_btn:          Button  = null
var _engine:             ClickSequencePuzzleEngine = ClickSequencePuzzleEngine.new()

# ── FORK-ONLY UI STATE ──────────────────────────────────────────────
var _fork_mode: bool = false

# ── COMPUTED PASS-THROUGHS (preserve v1.0.0 external field names) ────
# Read only from constellation_study_overlay.gd (_fork.<name>), never from
# within this class, so Godot's static analyzer can't see the external use
# and flags each as unused — the same "written but never internally read"
# false-positive class root_ui.gd's dead _first_prestige_triggered field
# used to be an example of, before it was deleted 2026-07-26.
@warning_ignore("unused_private_class_variable")
var _fork_state: ForkState:
    get: return _engine.state as ForkState
@warning_ignore("unused_private_class_variable")
var _fork_wrong_star: int:
    get: return _engine.wrong_star
@warning_ignore("unused_private_class_variable")
var _fork_wrong_flash_timer: float:
    get: return _engine.wrong_flash_timer
@warning_ignore("unused_private_class_variable")
var _fork_replay_lit_star: int:
    get: return _engine.replay_lit_star
@warning_ignore("unused_private_class_variable")
var _fork_fanfare_lit_star: int:
    get: return _engine.fanfare_lit_star


# ==================================================
# PUBLIC API (called from ConstellationStudyOverlay)
# ==================================================
func setup(synth: Node, star_map_control: Control, fork_btn: Button) -> void:
    _star_map_control = star_map_control
    _fork_btn         = fork_btn
    _engine.configure_io(synth, Callable(star_map_control, "queue_redraw"))


func set_constellation(constellation_id: int, cd: Node, gc: Node) -> void:
    _fork_mode = false
    if is_instance_valid(_fork_btn):
        _fork_btn.modulate = Color(1, 1, 1, 1)
    _engine.set_constellation(constellation_id, cd, gc)
    if is_instance_valid(_star_map_control):
        _star_map_control.queue_redraw()


func toggle_mode() -> void:
    _fork_mode = not _fork_mode
    # Matches set_constellation()'s existing is_instance_valid(_fork_btn)
    # guard — touching .modulate on a freed/invalid Button crashes.
    if is_instance_valid(_fork_btn):
        _fork_btn.modulate = STATE_COLORS.confirmed if _fork_mode else Color(1, 1, 1, 1)
    if _fork_mode:
        _engine.check_availability()
    if is_instance_valid(_star_map_control):
        _star_map_control.queue_redraw()


func force_off() -> void:
    _fork_mode = false
    if is_instance_valid(_fork_btn):
        _fork_btn.modulate = Color(1, 1, 1, 1)


func tick(delta: float) -> void:
    _engine.tick(delta)


func _on_fork_star_clicked(star_index: int) -> void:
    _engine.on_star_clicked(star_index)
