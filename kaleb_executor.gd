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
    # The stack waits for The Djinn's Tier 1 (author, 2026-11-10), still
    # running, so it starts by itself once The Djinn gets there.
    if not gc.kaleb_djinn_ready():
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
                # The crew does the pressing (author, 2026-11-06): with none,
                # a press would make nothing, so pause and say so.
                # Create Uonite is crewless: it needs no crew, and waits out
                # the Oscillation it starts (the button ignores a press then).
                var crewless: bool = bool(def.get("crewless", false))
                if crewless and ui._expansion_anim_active:
                    return
                if not crewless and gc.kaleb_bar_workers(bar) < 1:
                    _pause(bar, "Kaleb has no crew (set one in the Commands header)")
                    return
                var full_before: bool = _storage_full()
                var stored_before: BigNum = gc.get_storage_total()
                ui.kaleb_press(def["handler"], 1 if crewless else gc.kaleb_bar_workers(bar))
                if full_before and not crewless and String(bar.get("cmd", "")) != "summon_spark" \
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
            "supply":
                # Supply Sparks into one Constellation (author,
                # 2026-11-06): once a second; click multiplier × the crew's
                # Foci on the bar; only with a Volition on it, like its
                # automatic feeding. A press that moves nothing (capped, or
                # no Sparks) still counts, as for the other presses.
                var id: int = _constellation_target(bar)
                var why: String = _supply_blocker(id, bar)
                if why != "":
                    _pause(bar, why)
                    return
                if now() < float(_timer_ready.get("supply", 0.0)):
                    return
                gc.supply_constellation_sparks(id, gc.get_click_multiplier() * gc.kaleb_bar_workers(bar))
                _timer_ready["supply"] = now() + KalebCommands.SUPPLY_INTERVAL
                gc.kaleb_repeat_done += 1
                if gc.kaleb_repeat_done >= int(bar.get("repeat", 1)):
                    _advance()
                return
            "assign":
                var why: String = _assign(bar)
                if why != "":
                    _pause(bar, why)
                    return
                _advance()
            "feed":
                # Switch a Constellation's automatic feeding (Endow / Ignore),
                # as its slideout buttons do. Instant.
                var id: int = _constellation_target(bar)
                if id < 0:
                    _pause(bar, "it has no Constellation chosen")
                    return
                gc.assignments["constellation_%d_feed_mode" % id] = int(def.get("mode", 0))
                _advance()
            "cfoci":
                var why: String = _constellation_foci(bar)
                if why != "":
                    _pause(bar, why)
                    return
                _advance()
            "volition":
                var why: String = _move_volition(bar)
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


## The Constellation id a Constellation bar names, or -1 if none / not
## unlocked.
func _constellation_target(bar: Dictionary) -> int:
    var t: String = String(bar.get("target", ""))
    if not t.is_valid_int():
        return -1
    var cdata: Node = get_node_or_null("/root/ConstellationData")
    var id: int = t.to_int()
    if cdata and not cdata.unlocked.has(id):
        return -1
    return id


## Why Kaleb can't Supply Sparks for this bar, or "".
func _supply_blocker(id: int, bar: Dictionary) -> String:
    if id < 0:
        return "it has no unlocked Constellation chosen"
    if not gc.has_volition_for_constellation(id):
        return "no Volition is on %s" % KalebCommands.constellation_name(id, gc, get_node_or_null("/root/ConstellationData"))
    if gc.kaleb_bar_workers(bar) < 1:
        return "only Foci work in Constellations, and the crew has none"
    return ""


## An Assign bar (author, 2026-11-07): sets the Uonites or Foci on one wheel
## resource to the bar's value, the way the wheel's + and − do (it writes the
## same assignment key and tells the production manager), but never taking
## more than are free: asking for more than there is takes what is free, so a
## large value means "all free". Returns "" when done, else why not (the
## caller pauses Kaleb on it).
func _assign(bar: Dictionary) -> String:
    var rkey: String = String(bar.get("target", ""))
    var pool: String = String(bar.get("res", ""))
    if not KalebCommands.ASSIGN_OPS.has(rkey):
        return "it has no wheel resource chosen"
    if not KalebCommands.ASSIGN_POOLS.has(pool):
        return "it has no Uonites or Foci chosen"
    if gc.is_wheel_resource_locked(rkey):
        return "the Allocation Wheel can't take %s yet" % KalebCommands.ASSIGN_NAMES[rkey]
    var akey: String = "%s_%s" % [KalebCommands.ASSIGN_OPS[rkey], pool]
    var want: int = maxi(0, int(bar.get("value", 0)))
    var new_value
    if pool == "uonites":
        var raw = gc.assignments.get(akey, BigNum.zero())
        var current: int = raw.to_int() if raw is BigNum else 0
        var assigned: BigNum = gc.get_total_uonites_assigned()
        var free: int = gc.uonite.sub(assigned).to_int() if gc.uonite.is_greater_or_equal(assigned) else 0
        new_value = BigNum.from_int(mini(want, current + free))
    else:
        var current: int = gc._assignment_int(akey, 0)
        var free: int = maxi(0, gc.archon_foci - gc.get_total_foci_assigned())
        new_value = mini(want, current + free)
    gc.assignments[akey] = new_value
    var pm: Node = ui.get("production_manager") if ui else null
    if pm and pm.has_method("update_assignment"):
        pm.update_assignment(akey, new_value)
    return ""


## A Move Volition bar (author, 2026-11-10): the Djinn's first effect. The
## Djinn's Tier 1 gate is on the whole stack (step()). Returns "" when done,
## else why.
func _move_volition(bar: Dictionary) -> String:
    var cdata: Node = get_node_or_null("/root/ConstellationData")
    var from: String = String(bar.get("res", ""))
    var to: String = String(bar.get("target", ""))
    for e in [from, to]:
        if e == "free":
            continue
        if not String(e).is_valid_int() or not cdata.unlocked.has(String(e).to_int()):
            return "it has no unlocked Constellation chosen"
    return gc.kaleb_move_volition(from, to, int(bar.get("value", 1)))


## A Constellation Foci bar (author, 2026-11-10, the Djinn's): SETS the Foci
## on one Constellation to the bar's value, writing the key the popout's
## Foci + and − write, never taking more than are free (so 99999 is "all
## free"); a lower value gives Foci back. Returns "" when done, else why.
## (The Djinn's Tier 1 gate is on the whole stack, in step().)
func _constellation_foci(bar: Dictionary) -> String:
    var id: int = _constellation_target(bar)
    if id < 0:
        return "it has no unlocked Constellation chosen"
    var key: String = "constellation_%d_foci" % id
    var current: int = gc._assignment_int(key, 0)
    var free: int = maxi(0, gc.archon_foci - gc.get_total_foci_assigned())
    gc.assignments[key] = mini(maxi(0, int(bar.get("value", 0))), current + free)
    return ""


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
    elif String(def.get("kind", "")) == "volition":
        var cdn: Node = get_node_or_null("/root/ConstellationData")
        var ends: Array[String] = []
        for e in [String(bar.get("res", "")), String(bar.get("target", ""))]:
            ends.append("Free" if e == "free" else (KalebCommands.constellation_name(e.to_int(), gc, cdn) if e.is_valid_int() else "?"))
        what += ", %s → %s" % ends
    elif String(def.get("kind", "")) in ["supply", "feed", "cfoci"] and String(bar.get("target", "")).is_valid_int():
        what += ", " + KalebCommands.constellation_name(String(bar["target"]).to_int(), gc, get_node_or_null("/root/ConstellationData"))
    var adm: Node = ui.get("archon_dialogue_manager") if ui else null
    if adm:
        adm.enqueue_notification("Kaleb paused at bar %d (%s): %s." % [gc.kaleb_index + 1, what, why])
        adm.try_show_next_notification()
