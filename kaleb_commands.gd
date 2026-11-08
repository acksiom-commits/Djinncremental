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
##   supply  Supply Sparks into the Constellation `target` (its id, as
##           a String): the slideout's button, click multiplier × the crew's
##           FOCI on the bar (only Foci work in Constellations), up to its
##           cap; once a second; needs a Volition on that Constellation, like
##           its automatic feeding (author, 2026-11-06).
##   feed    switch the Constellation `target`'s automatic feeding to Endow
##           (feed_endow) or Ignore (feed_ignore). Instant.
## Every bar holds a Focus (its On/Off); press and supply bars say how many
## of the stack's shared crew they use (GameContext.kaleb_bar_workers).

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
    # Create Uonite (author, 2026-11-07): the same button, so it also
    # Oscillates (a made Uonite, or the cap's bare Oscillation). It makes a
    # whole batch by itself, so the crew does not work it ("crewless"), and it
    # waits out the Oscillation's animation. This is what lets a stack run
    # the Expansions unattended.
    "create_uonite":       {"name": "Create Uonite",     "kind": "press",
        "handler": "_on_create_uonite_pressed",   "cooldown": "", "crewless": true},
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
    # Constellations (author, 2026-11-06).
    "supply_sparks":        {"name": "Supply Sparks", "kind": "supply", "timer": "supply"},
    # Allocation Wheel (author, 2026-11-07): sets how many Uonites or Foci
    # sit on one wheel resource. Instant.
    "assign":              {"name": "Assign", "kind": "assign"},
    "feed_endow":          {"name": "Endow",  "kind": "feed", "mode": 1},
    "feed_ignore":         {"name": "Ignore", "kind": "feed", "mode": 0},
}

## The wheel resources an Assign bar can fill, in the wheel's order, with the
## wheel's operation each one is (the keys of allocation_wheel_control.gd's
## RESOURCE_OPERATIONS, less the inert Uonite slot) and what the menu calls them.
const ASSIGN_OPS := {
    "sparks": "sparks_summon", "monad": "monad_compress", "tetrad": "tetrad_assemble",
    "particle": "particle_assemble", "iota_uonite": "iota_assemble_uonite",
    "mote_uonite": "mote_assemble_uonite", "grain": "grain_assemble",
}
const ASSIGN_NAMES := {
    "sparks": "Sparks", "monad": "Monads", "tetrad": "Tetrads", "particle": "Particles",
    "iota_uonite": "Iota", "mote_uonite": "Mote", "grain": "Grains",
}
## Pools an Assign bar moves (never Volitions: author, 2026-10-26).
const ASSIGN_POOLS: Array[String] = ["uonites", "foci"]

## Kaleb's Supply Sparks presses, one a second (author, 2026-11-06).
const SUPPLY_INTERVAL: float = 1.0


## A Constellation as the stack shows it: its title, "The Archon", or UNKNOWN
## while its identity is still hidden (the same rule as the slideout).
static func constellation_name(id: int, gc: Node, cd: Node) -> String:
    if cd == null:
        return "Constellation %d" % id
    var hidden: bool = true
    if gc:
        hidden = not gc.ui_unlocks.get("kaleb_identity_revealed", false) if id == cd.ARCHON_ID \
            else not bool(gc.constellation_identity_revealed.get(id, false))
    if hidden:
        return "UNKNOWN (%d)" % (id + 1)
    # The title only, "The Hourglass", not the designation ("DRASIN"):
    # author, 2026-11-06.
    return String(cd.get_constellation_def(id).get("name", "Constellation %d" % id))

const COMPARISONS: Array[String] = ["<", ">="]


## A lock key or count key as the player reads it (the stack view's menus and
## Kaleb's pause notices). `gd` is GameData, for resource and Tetrad names.
static func display_name(key: String, gd: Node = null) -> String:
    match key:
        "<", ">=": return key
        "sparks": return "Sparks"
        "monad": return "Monads (unlocked)"
        "tetrad": return "Tetrads (unlocked)"
        "monad_solid": return "Solid Monads"
        "monad_liquid": return "Liquid Monads"
        "monad_gas": return "Gas Monads"
        "cat_fundament": return "Fundaments"
        "cat_element": return "Elements"
        "cat_symmetric": return "Symmetrics"
        "cat_medial": return "Medials"
        "iota_uonite", "iota_grains": return "Iota"
        "mote_uonite", "mote_grains": return "Mote"
    if gd and gd.RESOURCES.has(key):
        return String(gd.RESOURCES[key]["name"])
    if gd and gd.TETRADS.has(key):
        var shown: String = String(gd.TETRADS[key].get("display", ""))
        return shown if shown != "" else key.capitalize()
    return key.capitalize()


## A new bar of `cmd` with its defaults.
static func make_bar(cmd: String, repeat: int = 1) -> Dictionary:
    return {"cmd": cmd, "repeat": maxi(1, repeat), "on": true,
        "target": "", "res": "", "cmp": "<", "value": 0, "goto": 0,
        "workers": 1}


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
        "sparks", "particle", "iota_grains", "mote_grains", "mote_uonite", "grain", "uonite", \
                "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain":
            return gc.get_resource(key).to_int()
    return 0


static func test(gc: Node, bar: Dictionary) -> bool:
    var n: int = read_count(gc, String(bar.get("res", "")))
    var v: int = int(bar.get("value", 0))
    match String(bar.get("cmp", "<")):
        ">=": return n >= v
        _:    return n < v
