extends Control
# =================== MANIFOLD DIAL v0.1 ===================
# Dodecagon allocation dial for the Manifold system.
# 12 faces = 12 Firmament outputs, arranged as a purity altimeter:
#   Phlogiston at 12-o'clock apex.
#   Right arc (1–5): Solid stocks, high→low purity descending.
#   6-o'clock nadir: Oil (lowest liquid tier).
#   Left arc (7–11): Liquid and Gas, ascending back toward apex.
#
# Visual style: thin cream lines on transparent background,
# same vocabulary as AllocationWheelControl (Stoctagon).
# Channel: narrow rectangle extending from the selected face outward.
# Grain particles burst from center toward channel on each manifold tick.
# Skills (2026-11-04): each skill in GameData.SKILLS has a clickable name
# inside the ring at its dial_hour, tinted like its skill card; clicking it
# turns the channel (the spout) to point there. Choosing a skill and choosing
# an output icon are one selection: picking either clears the other.

# === LAYOUT ===
const DIAL_RADIUS:    float = 115.0
## Space between the ring and the nearest edge of each output's icon or name
## (clear of the station arcs, drawn at DIAL_RADIUS + 7).
const OUTPUT_GAP:     float = 12.0
const CHANNEL_LENGTH: float = 36.0
const CHANNEL_HALF_W: float = 6.0
const ICON_SIZE:      float = 28.0
## Radius of the ring of skill names, inside the dodecagon.
const SKILL_ORBIT:    float = 76.0
const SKILL_FONT_SIZE: int  = 13
## Output names, shown where an output has no icon file.
const OUTPUT_FONT_SIZE: int = 12

# === COLORS ===
const COLOR_RING         := Color(UIAccentColors.CREAM, 0.10)
const COLOR_RING_SEL     := Color(UIAccentColors.CREAM, 0.90)
const COLOR_CHANNEL      := Color(UIAccentColors.CREAM, 0.72)
const COLOR_PURITY_ARC   := Color(1.00, 0.90, 0.55, 0.32)

# Icon tint by station membership — OUTPUT_COLOR previously hardcoded this
# same literal 5x for calcination outputs and 3x each for dissolution/
# sublimation (12 entries, only 4 distinct colors) with no shared source.
# Now derived once in _ready() via OUTPUT_STATION, which already carries
# the same grouping for arc-coloring purposes below.
const STATION_TINT: Dictionary = {
    "":             Color(1.00, 0.52, 0.25, 1.00),  # phlogiston (no station)
    "calcination":  Color(1.00, 0.82, 0.52, 1.00),
    "dissolution":  Color(0.50, 0.75, 1.00, 1.00),
    "sublimation":  Color(0.72, 0.50, 1.00, 1.00),
}
var _output_color: Dictionary = {}

# === OUTPUT LAYOUT ===
# Face i outward normal = (-90 + i*30) degrees.
const OUTPUT_KEYS: Array[String] = [
    "phlogiston",  # 0 — 12:00
    "ore_silver",  # 1 —  1:00
    "ore_copper",  # 2 —  2:00
    "ore_iron",    # 3 —  3:00
    "stone",       # 4 —  4:00
    "clay",        # 5 —  5:00
    "oil",         # 6 —  6:00  nadir
    "infusion",    # 7 —  7:00
    "elixir",      # 8 —  8:00
    "steam",       # 9 —  9:00
    "smoke",       # 10 — 10:00
    "spirit",      # 11 — 11:00
]

# Station membership for arc coloring
const OUTPUT_STATION: Dictionary = {
    "phlogiston": "",
    "ore_silver":  "calcination", "ore_copper": "calcination",
    "ore_iron":    "calcination", "stone":      "calcination", "clay": "calcination",
    "oil":        "dissolution",  "infusion":   "dissolution", "elixir": "dissolution",
    "steam":      "sublimation",  "smoke":      "sublimation", "spirit": "sublimation",
}

# Station arc colors
const COLOR_SOLID  := Color(1.00, 0.80, 0.50, 0.55)
const COLOR_LIQUID := Color(0.50, 0.75, 1.00, 0.55)
const COLOR_GAS    := Color(0.72, 0.50, 1.00, 0.55)

# === PARTICLES ===
const PARTICLES_FULL:    int   = 6
const PARTICLES_STARVED: int   = 2
const PARTICLE_LIFETIME: float = 0.65

# === REFERENCES ===
var gc:        Node = null
var game_data: Node = null

# === STATE ===
var _selected_index:    int   = 0
## Index into GameData.SKILLS of the chosen skill, or -1 when an output is chosen.
var _selected_skill:    int   = -1
## Where the channel is turning to, in degrees (-90 is 12 o'clock).
var _spout_target_deg:  float = -90.0
var _channel_angle_deg: float = -90.0
var _purity:            float = 0.0
var _is_starved:        bool  = false

var _icon_buttons:  Array              = []
var _skill_buttons: Array              = []
var _icon_textures: Dictionary         = {}
var _particles:     Array[Dictionary]  = []


# ==================================================
# READY
# ==================================================
func _ready() -> void:
    gc        = get_node_or_null("/root/GameContext")
    game_data = get_node_or_null("/root/GameData")
    _build_output_colors()
    _preload_textures()
    _build_icon_buttons()
    _build_skill_buttons()
    var pm: Node = get_node_or_null("/root/ProductionManager")
    if pm and pm.has_signal("manifold_ticked"):
        pm.manifold_ticked.connect(_on_manifold_ticked)
    resized.connect(func(): _reposition_icons(); queue_redraw())
    call_deferred("_reposition_icons")


# ==================================================
# GEOMETRY
# ==================================================
func _center() -> Vector2:
    return size * 0.5

func _apothem() -> float:
    # Inradius of regular 12-gon: R * cos(π/12)
    return DIAL_RADIUS * cos(deg_to_rad(15.0))

func _vertex_pos(v: int) -> Vector2:
    # Vertex 0 at -105° so face 0 normal points exactly at -90° (12:00)
    var r := deg_to_rad(-105.0 + v * 30.0)
    return _center() + Vector2(cos(r), sin(r)) * DIAL_RADIUS


# ==================================================
# ICONS
# ==================================================
func _build_output_colors() -> void:
    for key in OUTPUT_KEYS:
        var station: String = OUTPUT_STATION.get(key, "")
        _output_color[key] = STATION_TINT.get(station, Color.WHITE)


func _preload_textures() -> void:
    if not game_data: return
    for key in OUTPUT_KEYS:
        var path: String = game_data.RESOURCES.get(key, {}).get("icon", "")
        if path != "" and ResourceLoader.exists(path):
            _icon_textures[key] = load(path)


## One button per output. It shows the output's icon when that file exists,
## and otherwise its name (2026-11-04: none of the twelve Firmament icons
## exist yet, which left the outputs invisible and unclickable).
func _build_icon_buttons() -> void:
    for i in 12:
        var key: String = OUTPUT_KEYS[i]
        var btn: BaseButton
        if _icon_textures.has(key):
            var tb := TextureButton.new()
            tb.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
            tb.stretch_mode   = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
            tb.ignore_texture_size = true
            tb.texture_normal = _icon_textures[key]
            btn = tb
        else:
            var b := Button.new()
            b.text = game_data.get_resource_name(key) if game_data else key
            b.flat = true
            b.add_theme_font_size_override("font_size", OUTPUT_FONT_SIZE)
            # White text, so the station tint in modulate is the colour shown.
            for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
                b.add_theme_color_override(state, Color.WHITE)
            btn = b
        btn.name = "DialIcon_" + key
        btn.focus_mode = Control.FOCUS_NONE
        btn.tooltip_text = game_data.get_resource_name(key) if game_data else key
        btn.modulate = _output_color.get(key, Color.WHITE).darkened(0.40)
        _icon_buttons.append(btn)
        var captured := i
        btn.pressed.connect(func(): _select_face(captured))
        add_child(btn)


func _reposition_icons() -> void:
    var c := _center()
    for i in _icon_buttons.size():
        var r := deg_to_rad(-90.0 + i * 30.0)
        var dir := Vector2(cos(r), sin(r))
        var btn: Control = _icon_buttons[i]
        btn.size = btn.get_combined_minimum_size()
        # The edge of the button nearest the ring sits OUTPUT_GAP outside it,
        # so wide names sit closer in at 3 and 9 o'clock and stay in the panel.
        var reach: float = absf(dir.x) * btn.size.x * 0.5 + absf(dir.y) * btn.size.y * 0.5
        btn.position = c + dir * (DIAL_RADIUS + OUTPUT_GAP + reach) - btn.size * 0.5
    for k in _skill_buttons.size():
        var btn: Button = _skill_buttons[k]
        var r := deg_to_rad(_skill_angle_deg(k))
        btn.size = btn.get_combined_minimum_size()
        btn.position = c + Vector2(cos(r), sin(r)) * SKILL_ORBIT - btn.size * 0.5


# ==================================================
# SKILLS
# ==================================================
func _build_skill_buttons() -> void:
    if not game_data: return
    for k in game_data.SKILLS.size():
        var skill: Dictionary = game_data.SKILLS[k]
        var btn := Button.new()
        btn.name = "DialSkill_" + String(skill["key"])
        btn.text = String(skill["name"])
        btn.flat = true
        btn.focus_mode = Control.FOCUS_NONE
        btn.tooltip_text = "Turn the spout to %s" % skill["name"]
        btn.add_theme_font_size_override("font_size", SKILL_FONT_SIZE)
        var col: Color = game_data.card_color(int(skill["card"])).lightened(0.35)
        btn.add_theme_color_override("font_color", col)
        btn.add_theme_color_override("font_hover_color", col.lightened(0.3))
        btn.add_theme_color_override("font_pressed_color", col)
        btn.add_theme_color_override("font_focus_color", col)
        _skill_buttons.append(btn)
        btn.pressed.connect(select_skill.bind(k))
        add_child(btn)
    _refresh_icon_tints()


## Clock position of skill k as an angle, the same way faces are numbered.
func _skill_angle_deg(k: int) -> float:
    return -90.0 + float(game_data.SKILLS[k]["dial_hour"]) * 30.0


## Chooses skill k (an index into GameData.SKILLS) and turns the spout to it.
func select_skill(k: int) -> void:
    _selected_skill = k
    _selected_index = -1
    _spout_target_deg = _skill_angle_deg(k)
    _refresh_icon_tints()
    queue_redraw()


func _select_face(index: int) -> void:
    _selected_index = index
    _selected_skill = -1
    _spout_target_deg = -90.0 + index * 30.0
    _refresh_icon_tints()
    queue_redraw()


func _refresh_icon_tints() -> void:
    for i in _icon_buttons.size():
        var base: Color = _output_color.get(OUTPUT_KEYS[i], Color.WHITE)
        (_icon_buttons[i] as Control).modulate = \
            base if i == _selected_index else base.darkened(0.45)
    for k in _skill_buttons.size():
        (_skill_buttons[k] as Button).modulate = \
            Color.WHITE if k == _selected_skill else Color(1, 1, 1, 0.55)


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    if gc:
        _purity = gc.grain_purity_profile.get("fundament", 0.0)
        var mf = gc.get("manifold_total_flows")
        _is_starved = (mf != null and (mf as int) > 0 and gc.grain.is_zero())

    # Smooth channel rotation
    var diff := fposmod(_spout_target_deg - _channel_angle_deg + 180.0, 360.0) - 180.0
    _channel_angle_deg += diff * minf(delta * 5.0, 1.0)

    # Age particles
    var alive: Array[Dictionary] = []
    for p in _particles:
        p["life"] -= delta
        if p["life"] > 0.0:
            p["pos"] += (p["dir"] as Vector2) * (delta * 160.0)
            alive.append(p)
    _particles = alive

    if not _particles.is_empty() or abs(diff) > 0.05:
        queue_redraw()


# ==================================================
# PARTICLE BURST  (called by ProductionManager signal)
# ==================================================
func _on_manifold_ticked() -> void:
    var c := _center()
    var ch_rad := deg_to_rad(_channel_angle_deg)
    var ch_dir := Vector2(cos(ch_rad), sin(ch_rad))
    var count:     int   = PARTICLES_STARVED if _is_starved else PARTICLES_FULL
    var base_alpha: float = 0.40              if _is_starved else 1.0
    for _i in count:
        var spread := randf_range(-0.22, 0.22)
        _particles.append({
            "pos":      c + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)),
            "dir":      ch_dir.rotated(spread),
            "life":     randf_range(0.38, PARTICLE_LIFETIME),
            "max_life": PARTICLE_LIFETIME,
            "alpha":    base_alpha,
        })
    queue_redraw()


# ==================================================
# DRAW
# ==================================================
func _draw() -> void:
    var c     := _center()
    var apoth := _apothem()

    # 1 — Dodecagon edges
    for i in 12:
        var is_sel: bool = (i == _selected_index)
        draw_line(
            _vertex_pos(i), _vertex_pos((i + 1) % 12),
            COLOR_RING_SEL if is_sel else COLOR_RING,
            2.5 if is_sel else 1.5
        )

    # 2 — Purity arc (clockwise from 12-o'clock, inside ring)
    if _purity > 0.01:
        var pcol := COLOR_PURITY_ARC
        if _is_starved: pcol.a = 0.10
        draw_arc(c, DIAL_RADIUS - 10.0, -PI * 0.5, -PI * 0.5 + _purity * TAU, 48, pcol, 1.5)

    # 3 — Station arc bands (outside ring, color-coded)
    # Arcs inset ±13° from the first/last face boundary of each station.
    _draw_station_arc(c, 1, 5,  COLOR_SOLID)
    _draw_station_arc(c, 6, 8,  COLOR_LIQUID)
    _draw_station_arc(c, 9, 11, COLOR_GAS)

    # 4 — Channel tube
    var ch_rad := deg_to_rad(_channel_angle_deg)
    var ch_dir := Vector2(cos(ch_rad), sin(ch_rad))
    var ch_perp := ch_dir.rotated(PI * 0.5) * CHANNEL_HALF_W
    var ch_start := c + ch_dir * apoth
    var ch_end   := ch_start + ch_dir * CHANNEL_LENGTH
    var ch_col   := COLOR_CHANNEL
    if _is_starved: ch_col.a = 0.22
    draw_line(ch_start + ch_perp, ch_end + ch_perp, ch_col, 1.5)
    draw_line(ch_start - ch_perp, ch_end - ch_perp, ch_col, 1.5)
    draw_line(ch_end   + ch_perp, ch_end   - ch_perp, ch_col, 1.5)

    # 5 — Particles (grain motes, purple tint matching grain resource color)
    for p in _particles:
        var t:     float = p["life"] / p["max_life"]
        var alpha: float = t * t * (p["alpha"] as float)
        draw_circle(p["pos"], 2.5 * t + 0.8, Color(0.78, 0.55, 0.95, alpha))


func _draw_station_arc(c: Vector2, face_start: int, face_end: int, col: Color) -> void:
    var a_start := deg_to_rad(-90.0 + face_start * 30.0 - 13.0)
    var a_end   := deg_to_rad(-90.0 + face_end   * 30.0 + 13.0)
    draw_arc(c, DIAL_RADIUS + 7.0, a_start, a_end, 24, col, 2.5)
