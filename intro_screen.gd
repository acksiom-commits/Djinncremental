extends Control
# The game's opening sequence — "memory wipe" vessel selection.
# This is the game's boot scene (project.godot run/main_scene): the
# player sees this FIRST, picks one of three vessel outlines, watches the
# Prestige/Expansion transition play once, and lands on RootUI.tscn (what
# was, until this screen existed, itself the boot scene — see git history
# before 2026-09-23 if that framing is confusing later).
#
# The pick becomes The Djinn's (constellation id 6) eventual constellation
# art/lore variant — constellation_data.gd's "CONSTELLATION 7-7: THE DJINN"
# comment already anticipated exactly this: "Themed around the vessel
# (Ring, Jar, Lamp, etc.) the player favored during the pre-game intro's
# training-period selection." This screen IS that intro; its whole job is
# to capture and persist the CHOICE, stored on GameContext as chosen_vessel
# ("lamp"/"ring"/"jar"), which constellation_data.gd's
# _resolve_vessel_layout() already reads for BOTH hard-mode geometry and
# (since 2026-10-01) each vessel's own nested "easy_layout" Beginner-mode
# geometry — this screen needs no separate wiring for that, only to set
# chosen_vessel correctly, which it already did before today.
#
# Selector shapes (2026-10-01): all three vessels draw the SAME Beginner-mode
# star/line data the puzzle itself uses, read straight from
# constellation_data.gd's vessel_layouts[key]["easy_layout"] (see
# _vessel_easy_shape() below) rather than a hand-copied second copy, so this
# screen can't silently drift from the real puzzle geometry.

const BG_HUE_CYCLE_SECONDS: float = 24.0
const BG_SATURATION: float = 0.10
const BG_VALUE: float = 1.0

const TEXT_TOP_FRACTION: float = 1.0 / 6.0
const TEXT_LINE: String = "SELECTED MEMORIES CLEARED...CONFIRM VESSEL"
const TEXT_COLOR: Color = Color(0.28, 0.22, 0.32)

const OUTLINE_COLOR: Color        = Color(0.30, 0.26, 0.36, 0.9)
const OUTLINE_HOVER_COLOR: Color  = Color(0.55, 0.30, 0.70, 1.0)
const OUTLINE_WIDTH: float        = 3.0
const SHAPE_SCALE: float          = 130.0   # unit-box half-extent, in pixels
const STAR_DOT_RADIUS: float      = 4.0

## The half-extent every easy_layout's fixed_star_positions is scaled to on
## its larger axis (constellation_data.gd's own convention — e.g. its Ring
## vessel comment: "scale so the larger axis spans +/-0.13"). Dividing by
## this turns those positions back into this screen's own [-1,1]-ish
## unit-box convention.
const VESSEL_EASY_LAYOUT_HALF_EXTENT: float = 0.13

## Reads a vessel's Beginner-mode star/line data straight from
## constellation_data.gd's own BUILT_IN table (single source of truth,
## rather than hand-copying a second star list here that could drift from
## the real puzzle geometry) and converts it into this screen's 2D unit-box
## convention. Returns {} for a vessel with no easy_layout.
## fixed_star_positions' Z is dropped — this is a flat 2D silhouette, not a
## puzzle board.
static func _vessel_easy_shape(vessel_key: String) -> Dictionary:
    var cd = load("res://constellation_data.gd").new()
    for c in cd.BUILT_IN:
        var layouts: Dictionary = c.get("vessel_layouts", {})
        if not layouts.has(vessel_key):
            continue
        var vessel: Dictionary = layouts[vessel_key]
        var easy = vessel.get("easy_layout")
        if not (easy is Dictionary):
            return {}
        var raw_positions: Array = easy.get("fixed_star_positions", [])
        var stars: Array[Vector2] = []
        for p in raw_positions:
            stars.append(Vector2(float(p[0]), float(p[1])) / VESSEL_EASY_LAYOUT_HALF_EXTENT)
        var raw_pairs: Array = easy.get("line_pairs", [])
        var edges: Array[Vector2i] = []
        for i in range(0, raw_pairs.size(), 2):
            edges.append(Vector2i(int(raw_pairs[i]), int(raw_pairs[i + 1])))
        return {"stars": stars, "edges": edges}
    return {}


## Order fixes left-to-right layout AND is the only source of truth for
## which vessel_key a click resolves to.
const VESSEL_ORDER: Array[String] = ["lamp", "ring", "jar"]

var _shape_stars: Dictionary = {}    # vessel_key -> Array[Vector2] (unit box)
var _shape_edges: Dictionary = {}    # vessel_key -> Array[Vector2i] (star index pairs)
var _shape_centers: Dictionary = {}  # vessel_key -> Vector2 (screen space, updated on resize)
var _hovered_vessel: String = ""
var _confirmed_vessel: String = ""
var _input_locked: bool = false

# Background is painted by THIS node's own _draw(), not a child ColorRect —
# a child always draws ON TOP of its parent's _draw() output regardless of
# child order, so an opaque full-rect ColorRect child would silently cover
# the outline shapes drawn below. Repainting a plain Color each frame via
# _draw() instead keeps the background strictly BEHIND everything drawn
# after it in the same call.
var _bg_color: Color = Color.WHITE
var _label: Label = null
var _bg_elapsed: float = 0.0


func _ready() -> void:
    # Once per PLAYTHROUGH, not once per LAUNCH: a returning player with an
    # existing save has already picked a vessel (or never will, for saves
    # that predate this screen), and re-running "memories cleared" on every
    # single boot would be a re-triggered ritual, not a one-time one. Skip
    # straight to the Main UI, no transition ceremony -- that belongs to
    # the fresh-start moment specifically, not to ordinary continued play.
    var save_manager = get_node_or_null("/root/SaveManager")
    if save_manager and save_manager.has_existing_save():
        get_tree().change_scene_to_file("res://RootUI.tscn")
        return

    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    _populate_shapes()

    _label = Label.new()
    _label.text = TEXT_LINE
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _label.add_theme_color_override("font_color", TEXT_COLOR)
    _label.add_theme_font_size_override("font_size", 32)
    _label.anchor_left = 0.0
    _label.anchor_right = 1.0
    _label.anchor_top = 0.0
    _label.anchor_bottom = TEXT_TOP_FRACTION
    _label.offset_left = 0.0
    _label.offset_right = 0.0
    _label.offset_top = 0.0
    _label.offset_bottom = 0.0
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_label)

    _update_shape_layout()
    resized.connect(_update_shape_layout)
    gui_input.connect(_on_gui_input)
    set_process(true)


## Split out of _ready() so it can be exercised directly — _ready() itself
## returns early for a returning player's save (see above), which would
## otherwise make this logic unreachable from a headless test run on any
## machine that already has a save file on disk.
func _populate_shapes() -> void:
    _shape_stars = {}
    _shape_edges = {}
    for key in VESSEL_ORDER:
        var easy: Dictionary = _vessel_easy_shape(key)
        if easy.is_empty():
            push_warning("intro_screen: vessel '%s' has no easy_layout — selector will be blank" % key)
            continue
        _shape_stars[key] = easy["stars"]
        _shape_edges[key] = easy["edges"]


func _update_shape_layout() -> void:
    var vp_size: Vector2 = get_rect().size
    if vp_size.x <= 0.0 or vp_size.y <= 0.0:
        return
    var band_top: float    = vp_size.y * TEXT_TOP_FRACTION
    var band_height: float = vp_size.y - band_top
    var slot_width: float  = vp_size.x / float(VESSEL_ORDER.size())
    for i in VESSEL_ORDER.size():
        var key: String = VESSEL_ORDER[i]
        _shape_centers[key] = Vector2(
            slot_width * (float(i) + 0.5),
            band_top + band_height * 0.5)
    queue_redraw()


func _process(_delta: float) -> void:
    _bg_elapsed += _delta
    var hue: float = fmod(_bg_elapsed / BG_HUE_CYCLE_SECONDS, 1.0)
    _bg_color = Color.from_hsv(hue, BG_SATURATION, BG_VALUE)
    queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
    if _input_locked:
        return
    if event is InputEventMouseMotion:
        var hit: String = _vessel_at_point(event.position)
        if hit != _hovered_vessel:
            _hovered_vessel = hit
            queue_redraw()
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var chosen: String = _vessel_at_point(event.position)
        if chosen != "":
            _confirm_vessel(chosen)


func _vessel_at_point(point: Vector2) -> String:
    for key in VESSEL_ORDER:
        if _hit_test_star_graph(key, point):
            return key
    return ""


## These constellations aren't simple closed loops (the lamp branches), so
## there's no "fill" to test: a click counts if it lands near any edge or
## near any star dot.
func _hit_test_star_graph(key: String, point: Vector2) -> bool:
    var screen_stars: Array[Vector2] = _screen_stars(key)
    for p in screen_stars:
        if point.distance_to(p) <= STAR_DOT_RADIUS * 3.0:
            return true
    for e in (_shape_edges.get(key, []) as Array):
        var pair: Vector2i = e
        if pair.x < 0 or pair.x >= screen_stars.size() or pair.y < 0 or pair.y >= screen_stars.size():
            continue
        if _distance_to_segment(point, screen_stars[pair.x], screen_stars[pair.y]) <= OUTLINE_WIDTH * 4.0:
            return true
    return false


func _screen_stars(key: String) -> Array[Vector2]:
    var center: Vector2 = _shape_centers.get(key, Vector2.ZERO)
    var out: Array[Vector2] = []
    for p in (_shape_stars.get(key, []) as Array):
        out.append(center + (p as Vector2) * SHAPE_SCALE)
    return out


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var ab: Vector2 = b - a
    var len_sq: float = ab.length_squared()
    if len_sq <= 0.00001:
        return p.distance_to(a)
    var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
    return p.distance_to(a + ab * t)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, get_rect().size), _bg_color)
    for key in VESSEL_ORDER:
        var col: Color = OUTLINE_HOVER_COLOR if key == _hovered_vessel else OUTLINE_COLOR
        _draw_star_graph(key, col)


func _draw_star_graph(key: String, col: Color) -> void:
    var screen_stars: Array[Vector2] = _screen_stars(key)
    for e in (_shape_edges.get(key, []) as Array):
        var pair: Vector2i = e
        if pair.x < 0 or pair.x >= screen_stars.size() or pair.y < 0 or pair.y >= screen_stars.size():
            continue
        draw_line(screen_stars[pair.x], screen_stars[pair.y], col, OUTLINE_WIDTH)
    for p in screen_stars:
        draw_circle(p, STAR_DOT_RADIUS, col)


func _confirm_vessel(vessel_key: String) -> void:
    _confirmed_vessel = vessel_key
    _input_locked = true
    _hovered_vessel = vessel_key
    queue_redraw()

    var gc = get_node_or_null("/root/GameContext")
    if gc and ("chosen_vessel" in gc):
        gc.chosen_vessel = vessel_key

    _play_transition_and_continue()


## Phase 1 (warp to white) plays here; Phase 2 (recede, revealing the Main
## UI) has to play AFTER change_scene_to_file() swaps in RootUI.tscn, at
## which point THIS node and this whole scene are already freed — so the
## overlay itself can't be a child of this node (see expansion_overlay.gd's
## own header for why get_tree().root, not `self`, is what survives a
## scene change). root_ui.gd's _ready() finds this same overlay via
## ExpansionOverlay.PENDING_REVEAL_GROUP and plays Phase 2 on it once the
## new scene has had a frame to settle.
func _play_transition_and_continue() -> void:
    # preload(), not a class_name reference -- this project's own
    # headless-run gotcha: bare class_name lookups are flaky outside the
    # editor (godot_global_class_name_cache_flaky_use_preload).
    var overlay = preload("res://expansion_overlay.gd").new()
    get_tree().root.add_child(overlay)
    overlay.setup()
    await overlay.warp_to_white(1.8)
    get_tree().change_scene_to_file("res://RootUI.tscn")
