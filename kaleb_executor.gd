extends Node
## Runs Kaleb's command stack (GameContext.kaleb_stack; SysDoc §7.3) on the
## Primordial page: one bar at a time, top to bottom, recycling to the top.
## Press bars wait for their button's cooldown, then press it through
## root_ui.gd (kaleb_press()), once per frame at most; Lock/Unlock and If-then
## bars are instant. Off bars are skipped. Created by root_ui.gd, so Kaleb
## works while the Primordial page is up.

const KalebCommands = preload("res://kaleb_commands.gd")

## Instant bars (locks, If-then, Off bars) Kaleb may pass in one frame. Keeps
## a stack of nothing but instant bars, or an If-then that jumps to itself,
## from spinning forever inside a frame.
const MAX_INSTANT_STEPS: int = 64

var ui: Node = null
var gc: Node = null

## When each command timer (KalebCommands "timer") is next ready, in now()'s
## seconds. Kaleb's own: the player's clicks don't touch it.
var _timer_ready: Dictionary = {}
## Tests and the timing simulation set this to run Kaleb on their own clock;
## negative means the real clock.
var clock_override: float = -1.0


func now() -> float:
    return clock_override if clock_override >= 0.0 else Time.get_ticks_msec() / 1000.0


## The timer's length: the same production timer the wheel's automation
## uses for that operation, Hourglass included.
func _timer_interval(timer: String) -> float:
    var pm: Node = get_node_or_null("/root/ProductionManager")
    if pm == null:
        return 1.0
    return float(pm.get_timer_intervals().get(timer, 1.0))


func setup(root_ui: Node, game_context: Node) -> void:
    ui = root_ui
    gc = game_context


func _process(_delta: float) -> void:
    step()


## One frame of work. Public so tests can drive Kaleb without waiting.
func step() -> void:
    if gc == null or ui == null or not gc.kaleb_running or gc.kaleb_stack.is_empty():
        return
    for _i in MAX_INSTANT_STEPS:
        if gc.kaleb_index < 0 or gc.kaleb_index >= gc.kaleb_stack.size():
            gc.kaleb_index = 0
            gc.kaleb_repeat_done = 0
        var bar: Dictionary = gc.kaleb_stack[gc.kaleb_index]
        var def: Dictionary = KalebCommands.COMMANDS.get(String(bar.get("cmd", "")), {})
        if def.is_empty() or not bool(bar.get("on", true)):
            _advance()
            continue
        match String(def["kind"]):
            "press":
                var cd: Node = ui._get_cooldown_bar(def["cooldown"]) if def["cooldown"] != "" else null
                if cd and not cd.is_ready():
                    return   # wait for the button
                # A command with a timer of its own (no cooldown bar) waits it.
                var timer: String = String(def.get("timer", ""))
                if timer != "" and now() < float(_timer_ready.get(timer, 0.0)):
                    return
                # A press at full storage that changes nothing (Compress,
                # say) would loop forever: pause and say so instead (author,
                # 2026-11-05). Summon is exempt: Sparks take no storage, so
                # it works at full storage. Room freed by a press shows as a
                # changed total, so a Particle or Tetrad press still goes on.
                var full_before: bool = _storage_full()
                var stored_before: BigNum = gc.get_storage_total()
                ui.kaleb_press(def["handler"], gc.kaleb_bar_workers(bar))
                if full_before and String(bar.get("cmd", "")) != "summon_spark" \
                        and gc.get_storage_total().equals(stored_before):
                    _pause(bar, "storage is full")
                    return
                if timer != "":
                    _timer_ready[timer] = now() + _timer_interval(timer)
                gc.kaleb_repeat_done += 1
                if gc.kaleb_repeat_done >= int(bar.get("repeat", 1)):
                    _advance()
                return
            "lock", "unlock":
                var want: bool = def["kind"] == "lock"
                var why: String = _set_lock(String(bar.get("target", "")), want)
                if why != "":
                    _pause(bar, why)
                    return
                _advance()
            "if":
                if KalebCommands.test(gc, bar):
                    gc.kaleb_index = clampi(int(bar.get("goto", 0)), 0, gc.kaleb_stack.size() - 1)
                    gc.kaleb_repeat_done = 0
                else:
                    _advance()
            _:
                _advance()


func _advance() -> void:
    gc.kaleb_repeat_done = 0
    gc.kaleb_index = (gc.kaleb_index + 1) % gc.kaleb_stack.size()


## Puts the Purity Lock on `key` into the wanted state, through the same
## calls a click makes (they assign and free the lock's Volition). Returns ""
## when the lock ends up as wanted, else why it couldn't (no Volition free,
## locks not unlocked, no target): the caller pauses Kaleb on it (author,
## 2026-11-05: a lock that silently failed let his stack fill storage with
## the wrong Monads and Tetrads).
func _set_lock(key: String, want: bool) -> String:
    if key == "" or not gc.locks.has(key):
        return "it has no target"
    if bool(gc.locks.get(key, false)) == want:
        return ""
    if not gc.purity_locks_unlocked:
        return "Purity Locks aren't unlocked yet"
    if key.begins_with("cat_"):
        gc.toggle_category_lock(key)
    else:
        gc.toggle_lock(key)
    if bool(gc.locks.get(key, false)) == want:
        return ""
    return "no Volition is free for the %s lock" % KalebCommands.display_name(key, _gd())


func _storage_full() -> bool:
    return gc.get_storage_total().is_greater_or_equal(gc.get_effective_storage_cap())


func _gd() -> Node:
    return get_node_or_null("/root/GameData")


## Stops the stack where it is (the same bar runs again on Run) and tells the
## player which bar and why, in the notice line like other milestones.
func _pause(bar: Dictionary, why: String) -> void:
    gc.kaleb_running = false
    var def: Dictionary = KalebCommands.COMMANDS.get(String(bar.get("cmd", "")), {})
    var what: String = String(def.get("name", bar.get("cmd", "")))
    if String(def.get("kind", "")) in ["lock", "unlock"] and String(bar.get("target", "")) != "":
        what += " " + KalebCommands.display_name(String(bar["target"]), _gd())
    var adm: Node = ui.get("archon_dialogue_manager") if ui else null
    if adm:
        adm.enqueue_notification("Kaleb paused at bar %d (%s): %s." % [gc.kaleb_index + 1, what, why])
        adm.try_show_next_notification()
