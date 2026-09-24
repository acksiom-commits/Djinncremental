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
# training-period selection." This screen IS that intro. The actual
# Djinn fixed_star_positions/line_pairs per vessel choice are a separate,
# not-yet-designed follow-up (that TODO predates this screen and is
# unaffected by it) — this screen's whole job is to capture and persist
# the CHOICE, stored on GameContext as chosen_vessel ("lamp"/"ring"/"jar").
#
# Shapes below are hand-authored placeholder silhouettes (unit-box point
# loops, scaled/positioned at draw time), same "authored art data, not
# derived" spirit as every BUILT_IN constellation's fixed_star_positions —
# not a final art pass.

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

const RING_POINT_COUNT: int = 28

## Unit-box point loops (roughly [-1,1] x [-1,1], y-down), one per vessel.
## "ring" is generated at runtime (_ring_points()) rather than hand-listed.
static func _lamp_points() -> PackedVector2Array:
    return PackedVector2Array([
        Vector2(-0.70,  0.70), Vector2( 0.30,  0.70), Vector2( 0.55,  0.55),
        Vector2( 0.65,  0.25), Vector2( 0.50,  0.00), Vector2( 0.65, -0.05),
        Vector2( 1.00, -0.15), Vector2( 0.95, -0.25), Vector2( 0.55, -0.15),
        Vector2( 0.25, -0.35), Vector2( 0.05, -0.40), Vector2(-0.25, -0.25),
        Vector2(-0.60, -0.15), Vector2(-0.60,  0.15), Vector2(-0.65,  0.35),
    ])


static func _jar_points() -> PackedVector2Array:
    return PackedVector2Array([
        Vector2(-0.25, -0.90), Vector2( 0.25, -0.90), Vector2( 0.25, -0.65),
        Vector2( 0.55, -0.40), Vector2( 0.60,  0.20), Vector2( 0.45,  0.85),
        Vector2(-0.45,  0.85), Vector2(-0.60,  0.20), Vector2(-0.55, -0.40),
        Vector2(-0.25, -0.65),
    ])


static func _ring_points() -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in RING_POINT_COUNT:
        var a: float = TAU * float(i) / float(RING_POINT_COUNT)
        pts.append(Vector2(cos(a), sin(a)))
    return pts


## Order fixes left-to-right layout AND is the only source of truth for
## which vessel_key a click resolves to.
const VESSEL_ORDER: Array[String] = ["lamp", "ring", "jar"]

var _shape_points: Dictionary = {}   # vessel_key -> PackedVector2Array (unit box)
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

    _shape_points = {
        "lamp": _lamp_points(),
        "ring": _ring_points(),
        "jar":  _jar_points(),
    }

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
        var poly: PackedVector2Array = _scaled_points(key)
        if Geometry2D.is_point_in_polygon(point, poly):
            return key
        # The outline is a thin loop, not a filled shape the player is
        # likely to click dead-center of — also accept a click within
        # OUTLINE_WIDTH*4 of any edge, so "clicking on the outline" (the
        # literal ask) works as reliably as clicking inside it.
        var n: int = poly.size()
        for i in n:
            var a: Vector2 = poly[i]
            var b: Vector2 = poly[(i + 1) % n]
            if _distance_to_segment(point, a, b) <= OUTLINE_WIDTH * 4.0:
                return key
    return ""


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var ab: Vector2 = b - a
    var len_sq: float = ab.length_squared()
    if len_sq <= 0.00001:
        return p.distance_to(a)
    var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
    return p.distance_to(a + ab * t)


func _scaled_points(key: String) -> PackedVector2Array:
    var center: Vector2 = _shape_centers.get(key, Vector2.ZERO)
    var base: PackedVector2Array = _shape_points.get(key, PackedVector2Array())
    var out := PackedVector2Array()
    out.resize(base.size())
    for i in base.size():
        out[i] = center + base[i] * SHAPE_SCALE
    return out


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, get_rect().size), _bg_color)
    for key in VESSEL_ORDER:
        var poly: PackedVector2Array = _scaled_points(key)
        if poly.size() < 2:
            continue
        var col: Color = OUTLINE_HOVER_COLOR if key == _hovered_vessel else OUTLINE_COLOR
        var closed := PackedVector2Array(poly)
        closed.append(poly[0])
        draw_polyline(closed, col, OUTLINE_WIDTH, true)


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
