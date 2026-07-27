class_name ArchonPokeMinigame
extends RefCounted
# ================ ARCHON POKE MINIGAME v1.0.0 ================
# Extracted from root_ui.gd's _on_archon_panel_gui_input (refactor-order
# item #10 in docs/early_game_architecture_overview.md). Clicking the
# Archon avatar increments a poke count; archon_dialogue_manager maps that
# into escalating tiers (shiver → wiggle → one-time dialogue per tier →
# tantrum). A tantrum locks the whole UI for a duration that grows with
# archon_lockdown_level, followed by a "reentry grind" window where Kaleb
# stays silent until a fresh threshold is met. Achievements fire at
# specific lockdown milestones.
#
# All persistent state (archon_poke_count, archon_lockdown_*,
# archon_warning_window_end, archon_reentry_threshold) stays on
# game_context.gd exactly as before — this class is pure behavior, no
# state of its own.
#
# `host` is injected only so this RefCounted can reach host.get_tree()
# for the two one-shot timers (lockdown auto-release, delayed post-lockdown
# message) — the same pattern constellation_puzzle_widgets.gd/
# constellation_puzzle_deduction.gd use for their own host reference.

const LOCKDOWN_DURATIONS: Array[float] = [60.0, 120.0, 180.0, 300.0, 300.0, 300.0]
const POST_LOCKDOWN_MESSAGES: Array[String] = [
    "I hope you've learned your lesson.",
    "That was a nice rest. And the next one will be even longer.",
    "", "", "", "",
]

var _host:                    Node = null
var _gc:                      Node = null
var _archon_dialogue_manager: Node = null
var _archon_tetra:            Node = null
var _ui_lock_blocker:         Control = null


func setup(host: Node, gc: Node, archon_dialogue_manager: Node,
        archon_tetra: Node, ui_lock_blocker: Control) -> void:
    _host                    = host
    _gc                      = gc
    _archon_dialogue_manager = archon_dialogue_manager
    _archon_tetra            = archon_tetra
    _ui_lock_blocker         = ui_lock_blocker


## Restores an in-progress lockdown's UI block after a save reload.
func restore_on_load() -> void:
    var now: float = Time.get_unix_time_from_system()
    if _gc and _gc.archon_lockdown_end_time > now:
        var remaining: float = _gc.archon_lockdown_end_time - now
        _engage_ui_lock(remaining)
    elif _ui_lock_blocker:
        _ui_lock_blocker.visible = false


func on_gui_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton \
    and event.button_index == MOUSE_BUTTON_LEFT \
    and event.pressed):
        return

    _host.get_viewport().set_input_as_handled()

    if not _gc or not _archon_dialogue_manager:
        return

    # Block input during lockdown
    var now: float = Time.get_unix_time_from_system()
    if _gc.archon_lockdown_end_time > now:
        return

    # Post-lockdown window expired: enter reentry grind if threshold not yet set
    if _gc.archon_warning_window_end > 0.0 \
    and now > _gc.archon_warning_window_end \
    and _gc.archon_lockdown_level > 0 \
    and _gc.archon_lockdown_level < 6:
        if _gc.archon_reentry_threshold == 0:
            _gc.archon_reentry_threshold = _gc.archon_poke_count \
                + 166 + _gc.archon_lockdown_level
        _gc.archon_warning_window_end = 0.0

    _gc.archon_poke_count += 1
    var poke: int = _gc.archon_poke_count

    # Clear reentry threshold once met
    if _gc.archon_reentry_threshold > 0 \
    and poke >= _gc.archon_reentry_threshold:
        _gc.archon_reentry_threshold  = 0
        _gc.archon_warning_window_end = 0.0

    var response: Dictionary = _archon_dialogue_manager.get_poke_response(
        poke, _gc.archon_reentry_threshold)

    if _archon_tetra:
        if response["tantrum"]:
            _archon_tetra.play_tantrum()
        else:
            if response["shiver"]:
                _archon_tetra.play_shiver()
            if response["wiggle"]:
                _archon_tetra.play_wiggle_y()

    if response["dialogue"] != "":
        _archon_dialogue_manager.enqueue_dialogue([response["dialogue"]])

    # === LOCKDOWN HANDLING ===
    if response["tantrum"] and _gc.archon_lockdown_level < 6:
        var level: int = _gc.archon_lockdown_level
        var lock_dur:   float = LOCKDOWN_DURATIONS[level]
        _gc.archon_lockdown_end_time  = now + lock_dur
        _gc.archon_lockdown_level    += 1
        _gc.archon_warning_window_end = now + lock_dur + 900.0

        _engage_ui_lock(lock_dur)

        var post_msg: String = POST_LOCKDOWN_MESSAGES[level]
        if post_msg != "":
            _host.get_tree().create_timer(lock_dur).timeout.connect(
                func(): _archon_dialogue_manager.enqueue_dialogue([post_msg]), CONNECT_ONE_SHOT)

        if _gc.archon_lockdown_level == 4:
            _grant_poke_achievement("persistence_is_rewarded")
        elif _gc.archon_lockdown_level == 6:
            _grant_poke_achievement("pesteristence_is_rewarded")


func _grant_poke_achievement(achievement_key: String) -> void:
    var ar: Node = _host.get_node_or_null("/root/AchievementRegistry")
    if ar and ar.has_method("earn"):
        ar.earn(achievement_key)


func _engage_ui_lock(duration: float) -> void:
    if _ui_lock_blocker:
        _ui_lock_blocker.visible = true
    _host.get_tree().create_timer(duration).timeout.connect(_release_ui_lock, CONNECT_ONE_SHOT)


func _release_ui_lock() -> void:
    if _ui_lock_blocker:
        _ui_lock_blocker.visible = false
