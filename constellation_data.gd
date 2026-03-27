extends Node
# ================= CONSTELLATION DATA v0.1.0 =================
# Autoload: add as "ConstellationData" ABOVE GameContext.
#
# Manages all 64 constellation definitions across 8 octants.
# Handles unlock evaluation, active selection per octant,
# bonus application via string keys, and shader data export.
#
# SLOT ALLOCATION:
#   IDs 0-15:  Built-in (narrative/lore, designed by dev)
#   IDs 16-31: Player-designed (personal customization)
#   IDs 32-47: Patron monthly (approved submissions)
#   IDs 48-63: Reserved (events, achievements, future use)
#
# OCTANTS (8 divisions of the unit sphere):
#   Each octant is defined by the sign of (x, y, z):
#   0: (+,+,+)  1: (-,+,+)  2: (+,-,+)  3: (-,-,+)
#   4: (+,+,-)  5: (-,+,-)  6: (+,-,-)  7: (-,-,-)
#
# UNLOCK CONDITIONS (string keys):
#   "always"                  — always unlocked
#   "achievement:KEY"         — unlocks when achievement KEY fires
#   "stat:FIELD >= N"         — polls GameContext.FIELD >= N
#   "stat:FIELD == N"         — polls GameContext.FIELD == N
#   "constellation:ID"        — requires constellation ID unlocked first
#
# BONUS KEYS (string keys read by ProductionManager):
#   ""                        — no passive bonus (mechanic-only unlock)
#   "sparks_summon_bonus"     — extra sparks per summon tick
#   "monad_compress_bonus"    — extra monads per compress tick
#   "archon_foci_bonus"       — extra archon foci (flat)
#   "purity_lock_slots"       — extra purity lock slots
#   (extend this list as new mechanics are added)
#
# MECHANIC UNLOCK KEYS (string keys read by ProductionManager):
#   ""                        — no mechanic unlock
#   "unlock_purity_sorting"   — enables purity-sorted compression
#   "unlock_tetrad_memory"    — Archon remembers last tetrad composition
#   "unlock_iota_targeting"   — allows targeting specific iota types
#   "unlock_spark_burst"      — new button: spend grain for spark burst
#   "unlock_archon_recall"    — Archon can replay any past dialogue
#   "unlock_uonite_training"  — Uonites gain experience from operations
#   "unlock_constellation_view" — enables ConstellationViewPanel UI
#   (extend as mid/late game mechanics are designed)


# ==================================================
# SIGNALS
# ==================================================
signal constellation_unlocked(constellation_id: int)
signal active_constellation_changed(octant: int, constellation_id: int)
signal mechanic_unlocked(mechanic_key: String)


# ==================================================
# OCTANT DEFINITIONS
# ==================================================
# Each octant has a center direction (unit vector) and
# a display name. The center is used for constellation
# pull targeting in the starfield.
const OCTANTS = [
    {"name": "Zenith-Forward-Right",  "dir": Vector3( 0.577,  0.577,  0.577)},
    {"name": "Zenith-Forward-Left",   "dir": Vector3(-0.577,  0.577,  0.577)},
    {"name": "Nadir-Forward-Right",   "dir": Vector3( 0.577, -0.577,  0.577)},
    {"name": "Nadir-Forward-Left",    "dir": Vector3(-0.577, -0.577,  0.577)},
    {"name": "Zenith-Back-Right",     "dir": Vector3( 0.577,  0.577, -0.577)},
    {"name": "Zenith-Back-Left",      "dir": Vector3(-0.577,  0.577, -0.577)},
    {"name": "Nadir-Back-Right",      "dir": Vector3( 0.577, -0.577, -0.577)},
    {"name": "Nadir-Back-Left",       "dir": Vector3(-0.577, -0.577, -0.577)},
]


# ==================================================
# BUILT-IN CONSTELLATION DEFINITIONS (IDs 0-15)
# ==================================================
# Each entry:
#   id:             int (0-63)
#   name:           String
#   lore:           String (shown in ConstellationViewPanel)
#   octant:         int (0-7)
#   star_count:     int (3-12, seed fills positions at runtime)
#   unlock:         String (condition key, see header)
#   bonus_key:      String (passive bonus, see header)
#   bonus_value:    float (magnitude of passive bonus)
#   mechanic_key:   String (mechanic unlock key, see header)
#   line_threshold: float (0..1, spark fraction needed for lines to appear)
const BUILT_IN = [
    {
        "id": 0,
        "name": "The First Spark",
        "lore": "The moment of ignition. All things begin here.",
        "octant": 0,
        "star_count": 3,
        "unlock": "always",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "unlock_constellation_view",
        "line_threshold": 0.1,
    },
    {
        "id": 1,
        "name": "The Archon's Hand",
        "lore": "Five points of will, extended in guidance.",
        "octant": 1,
        "star_count": 5,
        "unlock": "achievement:first_archon_focus",
        "bonus_key": "archon_foci_bonus",
        "bonus_value": 1.0,
        "mechanic_key": "unlock_archon_recall",
        "line_threshold": 0.25,
    },
    {
        "id": 2,
        "name": "The Compression",
        "lore": "Four into one. The fundamental act of creation.",
        "octant": 2,
        "star_count": 4,
        "unlock": "achievement:first_monad",
        "bonus_key": "monad_compress_bonus",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "line_threshold": 0.2,
    },
    {
        "id": 3,
        "name": "The Tetrad Crown",
        "lore": "Fifteen varieties of four. The geometry of matter.",
        "octant": 3,
        "star_count": 7,
        "unlock": "achievement:first_tetrad",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "unlock_tetrad_memory",
        "line_threshold": 0.3,
    },
    {
        "id": 4,
        "name": "The Purity Gate",
        "lore": "Not all things are equal. Some must be held apart.",
        "octant": 4,
        "star_count": 6,
        "unlock": "achievement:first_purity_lock",
        "bonus_key": "purity_lock_slots",
        "bonus_value": 2.0,
        "mechanic_key": "unlock_purity_sorting",
        "line_threshold": 0.35,
    },
    {
        "id": 5,
        "name": "The Iota Chain",
        "lore": "Five become one, over and over, until the sky is full.",
        "octant": 5,
        "star_count": 5,
        "unlock": "achievement:first_iota",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "unlock_iota_targeting",
        "line_threshold": 0.3,
    },
    {
        "id": 6,
        "name": "The Mote",
        "lore": "A speck of potential, assembled from many.",
        "octant": 6,
        "star_count": 4,
        "unlock": "achievement:first_mote",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "",
        "line_threshold": 0.4,
    },
    {
        "id": 7,
        "name": "The Grain",
        "lore": "The last step before creation. The threshold approaches.",
        "octant": 7,
        "star_count": 8,
        "unlock": "achievement:first_grain",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "unlock_spark_burst",
        "line_threshold": 0.5,
    },
    {
        "id": 8,
        "name": "The Uonite",
        "lore": "Your first creation. The cosmos remembers.",
        "octant": 0,
        "star_count": 9,
        "unlock": "achievement:first_uonite",
        "bonus_key": "",
        "bonus_value": 0.0,
        "mechanic_key": "unlock_uonite_training",
        "line_threshold": 0.5,
    },
    # IDs 9-15: reserved for future built-in constellations
    # Add entries here as mid/late game content is designed
]


# ==================================================
# PATRON CONSTELLATION TEMPLATE (IDs 32-47)
# ==================================================
# Patron constellations are loaded from res://data/patron_constellations.json
# at startup if the file exists. Each entry follows the same
# structure as BUILT_IN above, plus:
#   "patron_name": String  — credited patron name
#   "submitted_date": String
#   "approved": bool       — must be true to display
#
# The JSON file is maintained by the dev team and updated
# with each patron content drop. Never auto-generated from
# player input — all entries are manually reviewed.
const PATRON_DATA_PATH = "res://data/patron_constellations.json"


# ==================================================
# RUNTIME STATE
# ==================================================
var player_seed: int = 0

# Which constellation is active in each octant (-1 = none)
var active_per_octant: Array = [-1, -1, -1, -1, -1, -1, -1, -1]

# Set of unlocked constellation IDs
var unlocked: Array = []

# Player-designed constellations (IDs 16-31)
# Populated from save data
var player_constellations: Array = []

# Patron constellations loaded from JSON (IDs 32-47)
var patron_constellations: Array = []

# Currently active mechanic unlock keys
# ProductionManager reads this each tick
var active_mechanic_unlocks: Array = []

# Cached star positions per constellation ID
# key: constellation_id, value: Array of Vector3 (unit sphere positions)
var _star_positions_cache: Dictionary = {}

# GameContext reference
var _game_context: Node = null


# ==================================================
# READY
# ==================================================
func _ready() -> void:
    _game_context = get_node_or_null("/root/GameContext")
    _load_patron_constellations()
    # Always unlock constellation 0 (The First Spark)
    _unlock_constellation(0)


# ==================================================
# SEED AND STAR POSITION GENERATION
# ==================================================
func set_player_seed(genesis: int) -> void:
    player_seed = genesis
    _star_positions_cache.clear()


func get_star_positions(constellation_id: int) -> Array:
    if _star_positions_cache.has(constellation_id):
        return _star_positions_cache[constellation_id]

    var def = get_constellation_def(constellation_id)
    if def.is_empty():
        return []

    var star_count: int = def.get("star_count", 5)
    var octant: int = def.get("octant", 0)
    var octant_dir: Vector3 = OCTANTS[octant]["dir"]

    var rng = RandomNumberGenerator.new()
    rng.seed = player_seed ^ (constellation_id * 2654435761)

    var positions: Array = []
    var attempts = 0
    while positions.size() < star_count and attempts < star_count * 20:
        attempts += 1
        # Generate random point on sphere
        var theta = rng.randf() * TAU
        var phi   = acos(rng.randf_range(-1.0, 1.0))
        var pos   = Vector3(
            sin(phi) * cos(theta),
            cos(phi),
            sin(phi) * sin(theta)
        )
        # Keep only points in the correct octant
        # (within ~60 degrees of octant center)
        if pos.dot(octant_dir) > 0.3:
            positions.append(pos.normalized())

    _star_positions_cache[constellation_id] = positions
    return positions


# ==================================================
# CONSTELLATION LOOKUP
# ==================================================
func get_constellation_def(id: int) -> Dictionary:
    # Built-in
    for c in BUILT_IN:
        if c["id"] == id:
            return c
    # Player
    for c in player_constellations:
        if c["id"] == id:
            return c
    # Patron
    for c in patron_constellations:
        if c.get("approved", false) and c["id"] == id:
            return c
    return {}


func get_constellations_in_octant(octant: int) -> Array:
    var result = []
    for c in BUILT_IN:
        if c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    for c in player_constellations:
        if c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    for c in patron_constellations:
        if c.get("approved", false) and c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    return result


# ==================================================
# UNLOCK SYSTEM
# ==================================================
func _unlock_constellation(id: int) -> void:
    if unlocked.has(id):
        return
    unlocked.append(id)
    emit_signal("constellation_unlocked", id)
    # Apply mechanic unlock if any
    var def = get_constellation_def(id)
    var mechanic = def.get("mechanic_key", "")
    if mechanic != "" and not active_mechanic_unlocks.has(mechanic):
        active_mechanic_unlocks.append(mechanic)
        emit_signal("mechanic_unlocked", mechanic)


# Called by achievement system when an achievement fires
func on_achievement(achievement_key: String) -> void:
    for c in BUILT_IN:
        var condition: String = c.get("unlock", "")
        if condition == "achievement:" + achievement_key:
            _unlock_constellation(c["id"])
    # Check constellation chain unlocks
    _check_chain_unlocks()


func _check_chain_unlocks() -> void:
    for c in BUILT_IN:
        var condition: String = c.get("unlock", "")
        if condition.begins_with("constellation:"):
            var required_id = condition.split(":")[1].to_int()
            if unlocked.has(required_id):
                _unlock_constellation(c["id"])


# Poll stat-based unlock conditions each frame
# Called from _process — only checks unmet conditions
func _check_stat_unlocks() -> void:
    if not _game_context:
        return
    for c in BUILT_IN:
        if unlocked.has(c["id"]):
            continue
        var condition: String = c.get("unlock", "")
        if not condition.begins_with("stat:"):
            continue
        # Parse "stat:FIELD >= N" or "stat:FIELD == N"
        var parts = condition.substr(5).split(" ")
        if parts.size() < 3:
            continue
        var field = parts[0]
        var op    = parts[1]
        var val   = parts[2].to_float()
        if not _game_context.get(field) != null:
            continue
        var current = float(_game_context.get(field))
        var passes = false
        if op == ">=" and current >= val:
            passes = true
        elif op == "==" and current == val:
            passes = true
        if passes:
            _unlock_constellation(c["id"])


# ==================================================
# ACTIVE CONSTELLATION MANAGEMENT
# ==================================================
func set_active_constellation(octant: int, constellation_id: int) -> void:
    if octant < 0 or octant > 7:
        return
    if not unlocked.has(constellation_id) and constellation_id != -1:
        return
    active_per_octant[octant] = constellation_id
    emit_signal("active_constellation_changed", octant, constellation_id)
    _rebuild_active_mechanics()


func _rebuild_active_mechanics() -> void:
    active_mechanic_unlocks.clear()
    for octant in range(8):
        var id = active_per_octant[octant]
        if id == -1:
            continue
        var def = get_constellation_def(id)
        var mechanic = def.get("mechanic_key", "")
        if mechanic != "" and not active_mechanic_unlocks.has(mechanic):
            active_mechanic_unlocks.append(mechanic)
            emit_signal("mechanic_unlocked", mechanic)


# ==================================================
# BONUS QUERY (called by ProductionManager)
# ==================================================
func get_active_bonus(bonus_key: String) -> float:
    var total = 0.0
    for octant in range(8):
        var id = active_per_octant[octant]
        if id == -1:
            continue
        var def = get_constellation_def(id)
        if def.get("bonus_key", "") == bonus_key:
            total += def.get("bonus_value", 0.0)
    return total


func has_mechanic_unlock(mechanic_key: String) -> bool:
    return active_mechanic_unlocks.has(mechanic_key)


# ==================================================
# SHADER DATA EXPORT
# ==================================================
# Returns data needed by the starfield shader to render
# all active constellations: star positions, line pairs,
# brightness scale, and line fade threshold.
func get_shader_constellation_data() -> Dictionary:
    var star_dirs: Array = []    # Vector3 array, all active stars
    var line_pairs: Array = []   # pairs of indices into star_dirs
    var brightnesses: Array = [] # float per star

    var spark_fraction = 0.0
    if _game_context:
        var cap = 2000.0  # matches shader max_stars
        spark_fraction = clamp(float(_game_context.sparks) / cap, 0.0, 1.0)

    for octant in range(8):
        var id = active_per_octant[octant]
        if id == -1:
            continue
        var def = get_constellation_def(id)
        if def.is_empty():
            continue

        var positions = get_star_positions(id)
        var base_index = star_dirs.size()
        var line_threshold = def.get("line_threshold", 0.3)
        var lines_visible = spark_fraction >= line_threshold

        for i in positions.size():
            star_dirs.append(positions[i])
            brightnesses.append(spark_fraction)

        # Lines: connect stars in order (simple chain)
        # TODO: replace with hand-authored line pairs per constellation
        if lines_visible and positions.size() >= 2:
            for i in positions.size() - 1:
                line_pairs.append(base_index + i)
                line_pairs.append(base_index + i + 1)

    return {
        "star_dirs":    star_dirs,
        "line_pairs":   line_pairs,
        "brightnesses": brightnesses,
        "spark_fraction": spark_fraction,
    }


# ==================================================
# PATRON CONSTELLATION LOADING
# ==================================================
func _load_patron_constellations() -> void:
    if not FileAccess.file_exists(PATRON_DATA_PATH):
        return
    var file = FileAccess.open(PATRON_DATA_PATH, FileAccess.READ)
    if not file:
        return
    var json = JSON.new()
    var err = json.parse(file.get_as_text())
    file.close()
    if err != OK:
        push_warning("ConstellationData: failed to parse patron_constellations.json")
        return
    var data = json.get_data()
    if data is Array:
        patron_constellations = data
        print("ConstellationData: loaded ", patron_constellations.size(), " patron constellations")


# ==================================================
# SAVE / LOAD
# ==================================================
func get_save_data() -> Dictionary:
    return {
        "player_seed":           player_seed,
        "active_per_octant":     active_per_octant,
        "unlocked":              unlocked,
        "player_constellations": player_constellations,
    }


func load_save_data(data: Dictionary) -> void:
    player_seed         = data.get("player_seed", randi())
    active_per_octant   = data.get("active_per_octant", [-1,-1,-1,-1,-1,-1,-1,-1])
    unlocked            = data.get("unlocked", [0])
    player_constellations = data.get("player_constellations", [])
    _star_positions_cache.clear()
    _rebuild_active_mechanics()


# ==================================================
# PROCESS — stat-based unlock polling
# ==================================================
func _process(_delta: float) -> void:
    _check_stat_unlocks()
