extends RefCounted
## Kaleb's command palette (SysDoc §7.3): every bar the player can put in his
## stack. The stack itself lives in GameContext.kaleb_stack; kaleb_executor.gd
## runs it.
##
## Kinds:
##   press   Kaleb presses that production button on Primordial: the same
##           root_ui.gd handler a click calls, gated by the same cooldown bar
##           (so the Hourglass speeds him up). A bar's ×N repeat counts its
##           presses; a press that can't happen (not enough material) still
##           counts, so If-then bars guard what matters.
##   lock / unlock   switch the Purity Lock on `target` (a lock key, e.g.
##           "monad_liquid", "adaemant", "cat_medial"). Instant.
##   if      "if res cmp value, go to bar goto": a count check. Instant.
## Every bar holds a Focus (its On/Off); every bar but If-then also holds its
## workers, Uonites or, when none is free, Foci (GameContext.kaleb_bar_workers).

const COMMANDS := {
    # The Summon Spark button has no cooldown bar (a player may click it as
    # fast as they like), so Kaleb's presses wait the wheel's Spark timer
    # instead ("timer", production_manager.get_timer_intervals(); author,
    # 2026-11-05): a Summon worker then makes what a wheel worker makes.
    "summon_spark":        {"name": "Summon Spark",      "kind": "press",
        "handler": "_on_summon_spark_pressed",    "cooldown": "", "timer": "sparks_summon"},
    "monad_compress":      {"name": "Compress Monad",    "kind": "press",
        "handler": "_on_monad_compress_pressed",  "cooldown": "MonadCooldownBar"},
    "tetrad_assemble":     {"name": "Assemble Tetrad",   "kind": "press",
        "handler": "_on_tetrad_assemble_pressed", "cooldown": "TetradCooldownBar"},
    "persistent_particle": {"name": "Assemble Persistent Particle", "kind": "press",
        "handler": "_on_persistent_particle_pressed", "cooldown": "ParticleCooldownBar"},
    "persistent_iota":     {"name": "Assemble Persistent Iota",     "kind": "press",
        "handler": "_on_persistent_iota_pressed",     "cooldown": "IotaCooldownBar"},
    "persistent_mote":     {"name": "Assemble Persistent Mote",     "kind": "press",
        "handler": "_on_persistent_mote_pressed",     "cooldown": "MoteCooldownBar"},
    "persistent_grain":    {"name": "Assemble Persistent Grain",    "kind": "press",
        "handler": "_on_persistent_grain_pressed",    "cooldown": ""},
    "lock":                {"name": "Lock",   "kind": "lock"},
    "unlock":              {"name": "Unlock", "kind": "unlock"},
    "if":                  {"name": "If",     "kind": "if"},
}

const COMPARISONS: Array[String] = ["<", ">="]


## A new bar of `cmd` with its defaults.
static func make_bar(cmd: String, repeat: int = 1) -> Dictionary:
    return {"cmd": cmd, "repeat": maxi(1, repeat), "on": true,
        "target": "", "res": "", "cmp": "<", "value": 0, "goto": 0,
        "uonites": 1, "foci_workers": 0}


## The count an If-then bar reads for `key`: Sparks, a Monad type
## ("monad_solid"), a Tetrad variety ("adaemant"), or a chain stock
## ("particle", "persistent_particle", ...). Unknown keys read 0.
static func read_count(gc: Node, key: String) -> int:
    # All unlocked Monads or Tetrads together: what a Grain's 64 Monads and
    # a Mote's 48 cavity Tetrads draw from (added 2026-11-05 for the full
    # Persistent Grain stack).
    if key == "monad":
        return gc.get_monad_unlocked_total().to_int()
    if key == "tetrad":
        return gc.get_tetrad_unlocked_total().to_int()
    if key.begins_with("monad_"):
        var t: String = key.trim_prefix("monad_")
        return gc.monad[t].to_int() if gc.monad.has(t) else 0
    if gc.tetrad.has(key):
        return gc.tetrad[key].to_int()
    match key:
        "sparks", "particle", "iota_grains", "mote_grains", "grain", "uonite", \
                "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain":
            return gc.get_resource(key).to_int()
    return 0


static func test(gc: Node, bar: Dictionary) -> bool:
    var n: int = read_count(gc, String(bar.get("res", "")))
    var v: int = int(bar.get("value", 0))
    match String(bar.get("cmp", "<")):
        ">=": return n >= v
        _:    return n < v
