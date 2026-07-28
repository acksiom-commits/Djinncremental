extends Control
# ================= STORAGE DISPLAY v0.8.0 =================
# v0.8.0: +/- volition assignment buttons at upper-left (+) and
#         upper-right (-) corners of the node rect.
# v0.6.0: Renamed chain to match canonical GameData order:
#         particle -> monad compress output (face 1)
#         iota     -> tetrad compress output (face 2) ... etc.
#         Restored angle_offset -90deg rotation (lost in v0.5.0 rename).
#         Restored exit pull speed (DRIFT_SPEED*5, delta*8).
# v0.5.0: Exit face moved to top. Faces assigned clockwise
#         in production chain order. Icon size scales with
#         resource tier — Monad=6px through Uonite=18px.
# v0.4.0: Octagon container, zero-g drift, face-per-resource.
# v0.3.0: Collision separation every 3rd frame.
# v0.2.0: Bottom stacking with drop tween.
# v0.1.0: Initial implementation.
#
# Octagon face assignments (clockwise from top):
#   0: EXIT      (top — consumed resources leave here)
#   1: Monad     (~1:30)
#   2: Tetrad    (~3:00)
#   3: Particle  (~4:30)
#   4: Iota      (~6:00)
#   5: Mote      (~7:30)
#   6: Grain     (~9:00)
#   7: Uonite    (~10:30)

# ===================== AUTOLOAD REFS =============
var _gc: Node = null
var _settings_popout: Node = null

# ===================== TUNING ====================
const MAX_ICONS:      int   = 150
const DRIFT_SPEED:    float = 12.0
const RANDOM_VEL:     float = 8.0
const DAMPING:        float = 0.98
const FADE_DURATION:  float = 0.3
const SPAWN_DURATION: float = 0.5
const BTN_SIZE:        float = 20.0   # +/- button side length in pixels
const BTN_INSET:       float = 5.0    # gap from node edge to button — pull in to avoid overlap
const LABEL_FONT_SIZE: int   = 16     # volition counter and percentage text
const BTN_FONT_SIZE:   int   = 18     # + / - label inside buttons

const RESOURCE_KEYS = [
    "monad", "tetrad", "particle", "iota", "mote", "grain", "uonite"
]

# Face index per resource (face 0 = exit)
const RESOURCE_FACE = {
    "monad":    1,
    "tetrad":   2,
    "particle": 3,
    "iota":     4,
    "mote":     5,
    "grain":    6,
    "uonite":   7,
}

# Icon size scales with production tier
const ICON_SIZES = {
    "monad":    6.0,
    "tetrad":   8.0,
    "particle": 10.0,
    "iota":     12.0,
    "mote":     14.0,
    "grain":    16.0,
    "uonite":   18.0,
}

const RESOURCE_COLORS = {
    "monad":    Color("#ee4444"),
    "tetrad":   Color("#ffbb44"),
    "particle": Color("#eecc00"),
    "iota":     Color("#55ff88"),
    "mote":     Color("#55aaff"),
    "grain":    Color("#9944ee"),
    "uonite":   Color("#ffdd55"),
}

const EXIT_FACE_COLOR: Color = Color("#ffffff", 0.25)
const FACE_HIGHLIGHT_ALPHA: float = 0.4

# Face-index-keyed alpha'd view of RESOURCE_COLORS — built once in _ready()
# instead of hardcoding the same 7 hex values a second time (they'd
# previously drifted apart from RESOURCE_COLORS with no shared source).
var _face_colors: Dictionary = {}

# ===================== ICON TEXTURES =============
var _textures: Dictionary = {}

# ===================== OCTAGON GEOMETRY ==========
var _oct_verts:      PackedVector2Array = PackedVector2Array()
var _oct_center:     Vector2 = Vector2.ZERO
var _oct_radius:     float   = 0.0
var _face_midpoints: Array   = []
var _face_normals:   Array   = []
var _face1_len: float = 0.0

# ===================== STATE =====================
var _icons:       Array = []
var _rng:         RandomNumberGenerator = RandomNumberGenerator.new()
var _frame_count: int   = 0
var _overflow_tri:      PackedVector2Array = PackedVector2Array()
var _vol_center:        Vector2 = Vector2.ZERO
var _pct_center:        Vector2 = Vector2.ZERO
var _plus_rect:         Rect2   = Rect2()
var _minus_rect:        Rect2   = Rect2()
var _plus_hovered:      bool    = false
var _minus_hovered:     bool    = false


func _ready() -> void:
    _gc = get_node_or_null("/root/GameContext")
    _settings_popout = get_node_or_null("/root/Node2D/CanvasLayer/RootUI/TopBandHBox/RightEdgePopoutsVBox/settingsPopout")
    _rng.randomize()
    _load_textures()
    _build_face_colors()


func _build_face_colors() -> void:
    _face_colors[0] = EXIT_FACE_COLOR
    for key in RESOURCE_FACE:
        var col: Color = RESOURCE_COLORS[key]
        col.a = FACE_HIGHLIGHT_ALPHA
        _face_colors[RESOURCE_FACE[key]] = col


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _rebuild_octagon()
        queue_redraw()


func _rebuild_octagon() -> void:
    _oct_center = size * 0.5
    _oct_radius = min(size.x, size.y) * 0.5 - 4.0

    # Button rects anchored to node corners — computed before vertex loops
    _plus_rect  = Rect2(BTN_INSET,                      BTN_INSET, BTN_SIZE, BTN_SIZE)
    _minus_rect = Rect2(size.x - BTN_SIZE - BTN_INSET,  BTN_INSET, BTN_SIZE, BTN_SIZE)

    _oct_verts.clear()
    _face_midpoints.clear()
    _face_normals.clear()

    var angle_offset = -PI / 8.0 + deg_to_rad(-90.0)
    for i in 8:
        var angle = angle_offset + i * TAU / 8.0
        _oct_verts.append(_oct_center + Vector2(cos(angle), sin(angle)) * _oct_radius)

    for i in 8:
        var a   = _oct_verts[i]
        var b   = _oct_verts[(i + 1) % 8]
        var mid = (a + b) * 0.5
        _face_midpoints.append(mid)
        _face_normals.append((_oct_center - mid).normalized())

    # Volition toggle anchor — lower-right corner (face 3, ~4:30)
    if _face_normals.size() < 6:
        return
    var GAP:       float   = 3.0
    var f3a:       Vector2 = _oct_verts[3]
    var f3b:       Vector2 = _oct_verts[4]
    var outward3:  Vector2 = -_face_normals[3]
    _face1_len = (f3b - f3a).length()   # all octagon faces equal length
    var face3_mid: Vector2 = (f3a + f3b) * 0.5
    _vol_center = face3_mid + outward3 * (GAP + _face1_len * 0.38)

    # Percentage counter anchor — lower-left corner (face 5, ~7:30)
    var f5a:       Vector2 = _oct_verts[5]
    var f5b:       Vector2 = _oct_verts[6]
    var outward5:  Vector2 = -_face_normals[5]
    var face5_mid: Vector2 = (f5a + f5b) * 0.5
    _pct_center = face5_mid + outward5 * (GAP + _face1_len * 0.38)

    # Keep _overflow_tri empty — hit-test uses radius instead
    _overflow_tri = PackedVector2Array()


func _load_textures() -> void:
    var icon_paths = {
        "monad":    "res://icons/monad.svg",
        "tetrad":   "res://icons/tetrad.svg",
        "particle": "res://icons/particle.svg",
        "iota":     "res://icons/iota.svg",
        "mote":     "res://icons/mote.svg",
        "grain":    "res://icons/grain.svg",
        "uonite":   "res://icons/uonite.svg",
    }
    for key in icon_paths:
        if ResourceLoader.exists(icon_paths[key]):
            _textures[key] = load(icon_paths[key])


func _process(delta: float) -> void:
    if _oct_verts.is_empty():
        _rebuild_octagon()
    if not _gc:
        queue_redraw()
        return
    _frame_count += 1
    _sync_icons()
    _update_icons(delta)
    queue_redraw()
    if _settings_popout and not _settings_popout.tooltips_enabled:
        tooltip_text = ""
    else:
        tooltip_text = "%s / %s" % [
            _gc.get_storage_total().to_display_string(),
            _gc.get_effective_storage_cap().to_display_string()
        ]
    
    
func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var changed: bool = false
        var hov: bool
        hov = _plus_rect.has_point(event.position)
        if hov != _plus_hovered:    _plus_hovered  = hov; changed = true
        hov = _minus_rect.has_point(event.position)
        if hov != _minus_hovered:   _minus_hovered = hov; changed = true
        if changed:
            queue_redraw()
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
            and event.pressed:
        if _plus_rect.has_point(event.position):
            _on_vol_plus_pressed()
            accept_event()
        elif _minus_rect.has_point(event.position):
            _on_vol_minus_pressed()
            accept_event()


func _point_in_triangle(pt: Vector2, tri: PackedVector2Array) -> bool:
    # Sign method — works for any triangle winding
    var d1 = _tri_sign(pt, tri[0], tri[1])
    var d2 = _tri_sign(pt, tri[1], tri[2])
    var d3 = _tri_sign(pt, tri[2], tri[0])
    var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


func _tri_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
    return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _on_overflow_toggle_pressed() -> void:
    if not _gc:
        return
    var current = _gc.assignments.get("storage_overflow_volitions", 0)
    if current == 0:
        var idx = _gc.get_first_free_parent_index()
        if idx < 0:
            return
        _gc.assign_parent_volition(idx, "stoctagon", "")
    else:
        var idx = _gc.get_first_parent_index_with_target("stoctagon", "")
        if idx >= 0:
            _gc.unassign_parent_volition(idx)
    queue_redraw()
    
    

func _on_vol_plus_pressed() -> void:
    if not _gc: return
    var idx = _gc.get_first_free_parent_index()
    if idx < 0: return
    _gc.assign_parent_volition(idx, "stoctagon", "")
    queue_redraw()


func _on_vol_minus_pressed() -> void:
    if not _gc: return
    var idx = _gc.get_first_parent_index_with_target("stoctagon", "")
    if idx < 0: return
    _gc.unassign_parent_volition(idx)
    queue_redraw()


func _sync_icons() -> void:
    var fill         = _gc.get_storage_fill_fraction()
    var target_total = int(fill * MAX_ICONS)

    var current_counts: Dictionary = {}
    for key in RESOURCE_KEYS:
        current_counts[key] = 0
    for icon in _icons:
        if not icon["fading"]:
            current_counts[icon["resource"]] += 1

    var targets: Dictionary = {}
    for key in RESOURCE_KEYS:
        var frac      = _gc.get_resource_storage_fraction(key)
        var has_stock = false
        match key:
            "monad":    has_stock = not _gc.get_monad_total().is_zero()
            "tetrad":   has_stock = not _gc.get_tetrad_total().is_zero()
            "particle": has_stock = not _gc.particle.is_zero()
            "iota":     has_stock = not _gc.iota.is_zero()
            "mote":     has_stock = not _gc.mote.is_zero()
            "grain":    has_stock = not _gc.grain.is_zero()
            "uonite":   has_stock = not _gc.uonite.is_zero()
        var base = 1 if (has_stock and key != "uonite") else 0
        targets[key] = max(base, int(frac * target_total))

    for key in RESOURCE_KEYS:
        var needed = targets[key] - current_counts[key]
        for i in max(0, needed):
            _spawn_icon(key)

    for key in RESOURCE_KEYS:
        var excess  = current_counts[key] - targets[key]
        var removed = 0
        var i       = _icons.size() - 1
        while i >= 0 and removed < excess:
            if _icons[i]["resource"] == key and not _icons[i]["fading"]:
                _icons[i]["fading"] = true
                removed += 1
            i -= 1


func _spawn_icon(resource_key: String) -> void:
    if _face_midpoints.is_empty():
        return
    var face_idx  = RESOURCE_FACE.get(resource_key, 1)
    var spawn_pos = _face_midpoints[face_idx]
    var to_center = (_oct_center - spawn_pos).normalized()
    var perp      = Vector2(-to_center.y, to_center.x)
    var vel       = to_center * DRIFT_SPEED + perp * _rng.randf_range(-RANDOM_VEL, RANDOM_VEL)

    _icons.append({
        "resource": resource_key,
        "pos":      spawn_pos,
        "vel":      vel,
        "alpha":    0.0,
        "fading":   false,
        "spawning": true,
        "spawn_t":  0.0,
    })


func _update_icons(delta: float) -> void:
    var to_remove: Array = []

    for i in _icons.size():
        var icon = _icons[i]

        if icon["spawning"]:
            icon["spawn_t"] += delta / SPAWN_DURATION
            icon["alpha"]    = clamp(icon["spawn_t"], 0.0, 1.0)
            if icon["spawn_t"] >= 1.0:
                icon["spawning"] = false

        if not icon["fading"]:
            icon["vel"] = icon["vel"] * DAMPING
            if _frame_count % 10 == i % 10:
                icon["vel"] += Vector2(
                    _rng.randf_range(-1.0, 1.0),
                    _rng.randf_range(-1.0, 1.0))
            icon["pos"] += icon["vel"] * delta
            _bounce_off_octagon(icon)

        else:
            icon["alpha"] -= delta / FADE_DURATION
            if not _face_midpoints.is_empty():
                var exit_dir = (_face_midpoints[0] - icon["pos"]).normalized()
                icon["vel"]  = icon["vel"].lerp(exit_dir * DRIFT_SPEED * 5.0, delta * 8.0)
                icon["pos"] += icon["vel"] * delta
            if icon["alpha"] <= 0.0:
                to_remove.append(i)

    for i in range(to_remove.size() - 1, -1, -1):
        _icons.remove_at(to_remove[i])


func _bounce_off_octagon(icon: Dictionary) -> void:
    var icon_size = ICON_SIZES.get(icon["resource"], 7.0)
    var half      = icon_size * 0.5
    for i in 8:
        var outward = Vector2(-_face_normals[i].x, -_face_normals[i].y)
        var to_icon = icon["pos"] - _face_midpoints[i]
        var dist    = to_icon.dot(outward)
        if dist > -half:
            icon["pos"] -= outward * (dist + half + 0.5)
            var vel_out = icon["vel"].dot(outward)
            if vel_out > 0:
                icon["vel"] -= outward * vel_out * 1.6


func _draw() -> void:
    if _oct_verts.is_empty():
        return

    draw_colored_polygon(_oct_verts, Color(0.04, 0.03, 0.08, 0.92))

    # Face highlights
    for i in 8:
        var a   = _oct_verts[i]
        var b   = _oct_verts[(i + 1) % 8]
        var col = _face_colors.get(i, Color(0.3, 0.3, 0.3, 0.2))
        draw_line(a, b, col, 2.5)

    # Octagon border
    for i in 8:
        draw_line(_oct_verts[i], _oct_verts[(i + 1) % 8],
            Color(0.3, 0.25, 0.5, 0.7), 1.0)
            
    # Icons
    for icon in _icons:
        var pos       = icon["pos"]
        var key       = icon["resource"]
        var icon_size = ICON_SIZES.get(key, 7.0)
        var half      = icon_size * 0.5
        var col       = RESOURCE_COLORS.get(key, Color.WHITE)
        col.a         = icon["alpha"]
        var rect      = Rect2(pos.x - half, pos.y - half, icon_size, icon_size)
        if _textures.has(key):
            draw_texture_rect(_textures[key], rect, false, col)
        else:
            draw_circle(pos, half, col)

    # Volition assignment counter — lower-right corner (face 3)
    if _vol_center != Vector2.ZERO and _gc:
        var assigned = _gc.assignments.get("storage_overflow_volitions", 0) \
                     + _gc.assignments.get("storage_overflow_bonus_volitions", 0)
        var vol_str  = "V:%d" % assigned
        var txt_col  = Color(1.0, 0.85, 0.2, 0.90) if assigned > 0 \
                       else Color(0.5, 0.45, 0.65, 0.55)
        var font     = ThemeDB.fallback_font
        var font_sz  = LABEL_FONT_SIZE
        var txt_w    = font.get_string_size(vol_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
        var txt_pos  = _vol_center + Vector2(-txt_w * 0.5, font_sz * 0.35)
        draw_string(font, txt_pos, vol_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, txt_col)

    # Fill percentage — lower-left corner (face 5)
    if _pct_center != Vector2.ZERO and _gc:
        var fill     = _gc.get_storage_fill_fraction()
        var pct_str  = "%d%%" % round(fill * 100.0)
        var txt_col  = Color(0.7, 0.65, 0.9, 0.70).lerp(Color(1.0, 0.92, 0.45, 0.97), fill)
        var font     = ThemeDB.fallback_font
        var font_sz  = LABEL_FONT_SIZE
        var txt_w    = font.get_string_size(pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
        var txt_pos  = _pct_center + Vector2(-txt_w * 0.5, font_sz * 0.35)
        draw_string(font, txt_pos, pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, txt_col)

    # + button — upper-left corner
    if _plus_rect.has_area() and _gc:
        var available = _gc.volitions - _gc.get_total_volitions_assigned()
        var can_add   = available > 0
        var bg_col    = Color(1.0, 1.0, 1.0, 0.18) if (_plus_hovered and can_add) \
                        else Color(0.12, 0.10, 0.20, 0.55)
        var brd_col   = Color(1.0, 0.85, 0.2, 0.80) if can_add \
                        else Color(0.4, 0.4, 0.4, 0.25)
        var lbl_col   = Color(1.0, 0.85, 0.2, 0.90) if can_add \
                        else Color(0.35, 0.35, 0.40, 0.40)
        draw_rect(_plus_rect, bg_col)
        draw_rect(_plus_rect, brd_col, false, 1.0)
        var font_p    = ThemeDB.fallback_font
        var lbl_w     = font_p.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, BTN_FONT_SIZE).x
        draw_string(font_p, _plus_rect.get_center() + Vector2(-lbl_w * 0.5, BTN_FONT_SIZE * 0.35),
                "+", HORIZONTAL_ALIGNMENT_LEFT, -1, BTN_FONT_SIZE, lbl_col)

    # - button — upper-right corner
    if _minus_rect.has_area() and _gc:
        var current  = _gc.assignments.get("storage_overflow_volitions", 0)
        var can_sub  = current > 0
        var bg_col   = Color(1.0, 1.0, 1.0, 0.18) if (_minus_hovered and can_sub) \
                       else Color(0.12, 0.10, 0.20, 0.55)
        var brd_col  = Color(1.0, 0.85, 0.2, 0.80) if can_sub \
                       else Color(0.4, 0.4, 0.4, 0.25)
        var lbl_col  = Color(1.0, 0.85, 0.2, 0.90) if can_sub \
                       else Color(0.35, 0.35, 0.40, 0.40)
        draw_rect(_minus_rect, bg_col)
        draw_rect(_minus_rect, brd_col, false, 1.0)
        var font_m   = ThemeDB.fallback_font
        var lbl_w    = font_m.get_string_size("-", HORIZONTAL_ALIGNMENT_LEFT, -1, BTN_FONT_SIZE).x
        draw_string(font_m, _minus_rect.get_center() + Vector2(-lbl_w * 0.5, BTN_FONT_SIZE * 0.35),
                "-", HORIZONTAL_ALIGNMENT_LEFT, -1, BTN_FONT_SIZE, lbl_col)
