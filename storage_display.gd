extends Control
# ================= STORAGE DISPLAY v0.11.0 =================
# v0.11.0: Two fixes from live playtesting of v0.10.0:
#          (1) Wedge-crossing icons now land at a randomized point along
#              the shared wall (not always the exact midpoint) and glide
#              off at a randomized angle/distance, so a burst of several
#              icons crossing together fans out instead of marching along
#              one identical line. They also pick up a randomized velocity
#              on arrival (matching _spawn_icon()'s jitter pattern) instead
#              of stopping dead with vel=ZERO.
#          (2) The 5 "wedge"-terminal legs (Monad->Tetrad->Particle->Iota->
#              Mote->Grain) are no longer triggered by watching
#              totals_created every frame — that fired on every single
#              production tick, out of step with how storage icons
#              normally appear. They're now triggered from _sync_icons()'s
#              own needed-vs-current-count reconciliation (the same
#              fraction-of-storage batch schedule that has always governed
#              Monad's edge-spawns), and _spawn_icon() is no longer called
#              for those 5 keys at all — a wedge can now ONLY gain an icon
#              by a wall crossing from its upstream wedge, never by
#              spawning fresh at its own outer edge (this is what fixes
#              Tetrad icons still entering from the outer rim). The
#              Mote->Uonite "settle" leg is the one exception: it isn't
#              tied to any wedge's storage target (it settles in the
#              central cavity, not a wedge), so it stays on the original
#              totals_created-delta trigger, now scoped to just that leg.
# v0.10.0: Flow visualization reworked from independent spawned icons to
#          animating EXISTING storage icons in place. On a resource's own
#          production delta, an existing storage icon of the PRECEDING
#          resource (or a freshly spawned one if none is currently on
#          hand) drifts from wherever it is to the shared wall with the
#          new resource's wedge, transforms there, glides a short distance
#          past the wall into the new wedge, then simply rejoins the
#          normal storage population (_confine_to_wedge takes back over)
#          — never a separate icon appearing out of nowhere, never a full
#          wedge-spanning shot. Six legs now, one per real transformation
#          in the chain (Monad->Tetrad->Particle->Iota->Mote->{Grain,
#          Uonite}) — Iota->Mote used to be folded into the Particle->Iota
#          leg's "next" label with no trigger of its own; now it's its own
#          wall crossing, triggered by Mote's own delta. Only the
#          Mote->Uonite leg still ends specially: instead of rejoining a
#          wedge, it settles into the central octagon (_center_icons)
#          until Expansion clears it (clear_flow_icons(), called from
#          root_ui.gd's _do_prestige_reset). See _drive_flow_production().
# v0.9.0: Central octagon added inside the existing one, splitting each
#         wedge into a quadrilateral (outer face + two seams + inner face).
#         Storage icons now confine to their own wedge instead of bouncing
#         off all 8 outer faces (_confine_to_wedge replaces
#         _bounce_off_octagon) and no longer pull toward the top face when
#         fading — they just fade in place.
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

# ===================== FLOW STREAM TUNING =========
const INNER_OCT_RADIUS_FRAC: float = 0.30   # central octagon radius, as a fraction of the outer one
const FLOW_SPEED:          float = 70.0     # px/sec drifting to the shared wall
const FLOW_GLIDE_SPEED:    float = 40.0     # px/sec for the short glide past the wall — slower, "gentle"
const FLOW_GLIDE_DISTANCE: float = 16.0     # how far past the wall to glide into the new wedge
const FLOW_STAGGER:        float = 0.06     # seconds between staggered starts within one burst
const FLOW_BURST_MAX:      int   = 6        # cap on icons animated per settle-leg production-delta event (see _drive_flow_production)
const FLOW_WALL_SPREAD_MIN:       float = 0.2   # per-icon crossing point along the shared wall segment, as a 0..1 lerp
const FLOW_WALL_SPREAD_MAX:       float = 0.8   # (kept off the very corners so icons don't pop into a THIRD wedge)
const FLOW_GLIDE_ANGLE_JITTER_DEG: float = 25.0 # +/- degrees randomized off the base glide direction
const FLOW_GLIDE_DIST_JITTER_FRAC: float = 0.3  # +/- fraction of FLOW_GLIDE_DISTANCE randomized per icon

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
const FACE_HIGHLIGHT_ALPHA: float = 0.8

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

# Central octagon — same angular alignment as _oct_verts, smaller radius.
# The seams that used to run all the way to _oct_center now stop here,
# leaving its interior empty space for settled Uonite flow icons.
var _inner_verts:         PackedVector2Array = PackedVector2Array()
var _inner_face_midpoints: Array = []
var _inner_face_normals:   Array = []

# Per-wedge (quadrilateral, index = RESOURCE_FACE) bounce boundaries, each
# entry an Array of [point: Vector2, outward_normal: Vector2] pairs — outer
# face, both seams, and the inner face bordering the central octagon.
# Built once per _rebuild_octagon() call, not per-icon-per-frame.
var _wedge_bounds: Array = []

# Six wall crossings, one per real transformation in the chain
# (Monad->Tetrad->Particle->Iota->Mote->{Grain,Uonite}). A leg doesn't own
# an icon of its own — see _start_flow_for_leg() — it just describes the
# geometry: {"wall_a": Vector2, "wall_b": Vector2, "glide_dir": Vector2,
# "source": String, "next": String, "dest_wedge": int, "terminal": String}.
# "wall_a"/"wall_b" are the two ends of the shared seam segment — each icon
# picks its OWN random point along it (see _roll_flow_targets()) rather
# than every icon converging on one fixed point. "glide_dir" is the base
# direction from the wall toward the destination wedge/center, again
# randomized per icon (angle + distance) at roll time. "terminal" is
# "wedge" (glide completes, icon just resumes normal storage-icon behavior
# at "dest_wedge") or "settle" (glide completes, icon moves to
# _center_icons and bounces there until cleared). Built once per
# _rebuild_octagon() call — see _build_flow_legs().
var _flow_legs: Array = []

# ===================== STATE =====================
var _icons:         Array = []
# Icons that finished a "settle" terminal (Mote->Uonite) and now bounce
# freely inside the central octagon, awaiting Expansion. Everything else
# in the flow — the five "wedge" terminal legs — lives entirely inside
# _icons itself (existing entries temporarily marked flow_active; see
# _advance_flow_icon()), not a separate population.
var _center_icons:  Array = []
var _rng:         RandomNumberGenerator = RandomNumberGenerator.new()
var _frame_count: int   = 0
var _tooltip_accum: float = 0.0
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
    _inner_verts.clear()
    _face_midpoints.clear()
    _face_normals.clear()

    var angle_offset = -PI / 8.0 + deg_to_rad(-90.0)
    var inner_radius = _oct_radius * INNER_OCT_RADIUS_FRAC
    for i in 8:
        var angle = angle_offset + i * TAU / 8.0
        var dir   = Vector2(cos(angle), sin(angle))
        _oct_verts.append(_oct_center + dir * _oct_radius)
        _inner_verts.append(_oct_center + dir * inner_radius)

    for i in 8:
        var a   = _oct_verts[i]
        var b   = _oct_verts[(i + 1) % 8]
        var mid = (a + b) * 0.5
        _face_midpoints.append(mid)
        _face_normals.append((_oct_center - mid).normalized())

    _inner_face_midpoints.clear()
    _inner_face_normals.clear()
    for i in 8:
        var ia  = _inner_verts[i]
        var ib  = _inner_verts[(i + 1) % 8]
        var mid = (ia + ib) * 0.5
        _inner_face_midpoints.append(mid)
        _inner_face_normals.append((_oct_center - mid).normalized())

    _build_wedge_bounds()
    _build_flow_legs()

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


# Each wedge is bounded by 4 edges: the outer face, the two seams shared
# with its neighbors, and the inner face bordering the central octagon.
# "Outward" for each edge points out of THIS wedge's interior — reusing
# the same push-back-along-outward-normal bounce used by the original
# all-8-faces confinement, just scoped to one wedge's 4 edges instead.
func _build_wedge_bounds() -> void:
    _wedge_bounds.clear()
    if _oct_verts.size() < 8 or _inner_verts.size() < 8:
        return
    for w in 8:
        var a  = _oct_verts[w]
        var b  = _oct_verts[(w + 1) % 8]
        var ia = _inner_verts[w]
        var ib = _inner_verts[(w + 1) % 8]
        var bounds: Array = []

        # Outer face — same push-inward-off-the-outer-wall as before.
        bounds.append([_face_midpoints[w], Vector2(-_face_normals[w].x, -_face_normals[w].y)])

        # Seam at vertex w, shared with wedge (w-1). b belongs to this
        # wedge's interior, so outward is whichever perp direction b is
        # NOT on.
        var seam_a_dir:  Vector2 = (ia - a).normalized()
        var seam_a_perp: Vector2 = Vector2(-seam_a_dir.y, seam_a_dir.x)
        var outward_a: Vector2 = -seam_a_perp if (b - a).dot(seam_a_perp) > 0.0 else seam_a_perp
        bounds.append([(a + ia) * 0.5, outward_a])

        # Seam at vertex w+1, shared with wedge (w+1). a belongs to this
        # wedge's interior here.
        var seam_b_dir:  Vector2 = (ib - b).normalized()
        var seam_b_perp: Vector2 = Vector2(-seam_b_dir.y, seam_b_dir.x)
        var outward_b: Vector2 = -seam_b_perp if (a - b).dot(seam_b_perp) > 0.0 else seam_b_perp
        bounds.append([(b + ib) * 0.5, outward_b])

        # Inner face — the forbidden direction here is INTO the cavity,
        # i.e. TOWARD center, the opposite sign from the outer face. Every
        # entry in this array is "the direction beyond which _confine_to_
        # wedge() pushes back", so this one must NOT be negated like the
        # outer face is — that was the bug: storage icons were being
        # pushed toward center (into the cavity) instead of away from it.
        bounds.append([(ia + ib) * 0.5, _face_normals[w]])

        _wedge_bounds.append(bounds)


# Six wall crossings. Vertex indices 2..6 are exactly the seams bordering
# wedges 1(Monad)|2(Tetrad), 2(Tetrad)|3(Particle), 3(Particle)|4(Iota),
# 4(Iota)|5(Mote), and 5(Mote)|6(Grain) — one real transformation each.
# Mote's own inner edge additionally feeds the Uonite leg, into the
# central octagon instead of into wedge 6.
func _build_flow_legs() -> void:
    _flow_legs.clear()
    if _face_midpoints.size() < 8 or _oct_verts.size() < 8 or _inner_verts.size() < 8:
        return

    _flow_legs = [
        _make_wedge_leg(_oct_verts[2], _inner_verts[2], "monad",    "tetrad"),   # Monad|Tetrad
        _make_wedge_leg(_oct_verts[3], _inner_verts[3], "tetrad",   "particle"), # Tetrad|Particle
        _make_wedge_leg(_oct_verts[4], _inner_verts[4], "particle", "iota"),     # Particle|Iota
        _make_wedge_leg(_oct_verts[5], _inner_verts[5], "iota",     "mote"),     # Iota|Mote
        _make_wedge_leg(_oct_verts[6], _inner_verts[6], "mote",     "grain"),    # Mote|Grain
        _make_settle_leg(_inner_verts[5], _inner_verts[6], "mote", "uonite"),    # Mote's inner edge -> center
    ]


func _make_wedge_leg(wall_a: Vector2, wall_b: Vector2, source: String, next: String) -> Dictionary:
    var mid: Vector2       = (wall_a + wall_b) * 0.5
    var dest_wedge: int    = RESOURCE_FACE.get(next, 1)
    var glide_dir: Vector2 = (_face_midpoints[dest_wedge] - mid).normalized()
    return {
        "wall_a":     wall_a,
        "wall_b":     wall_b,
        "glide_dir":  glide_dir,
        "source":     source,
        "next":       next,
        "dest_wedge": dest_wedge,
        "terminal":   "wedge",
    }


func _make_settle_leg(wall_a: Vector2, wall_b: Vector2, source: String, next: String) -> Dictionary:
    var mid: Vector2 = (wall_a + wall_b) * 0.5
    return {
        "wall_a":     wall_a,
        "wall_b":     wall_b,
        "glide_dir":  (_oct_center - mid).normalized(),
        "source":     source,
        "next":       next,
        "dest_wedge": -1,
        "terminal":   "settle",
    }


# Rolls a randomized crossing point along the leg's shared wall segment and
# a randomized glide angle/distance off it, so several icons crossing the
# same leg at once fan out instead of marching along one identical line.
func _roll_flow_targets(leg: Dictionary) -> Dictionary:
    var t: float          = _rng.randf_range(FLOW_WALL_SPREAD_MIN, FLOW_WALL_SPREAD_MAX)
    var wall: Vector2     = leg["wall_a"].lerp(leg["wall_b"], t)
    var angle: float      = deg_to_rad(_rng.randf_range(-FLOW_GLIDE_ANGLE_JITTER_DEG, FLOW_GLIDE_ANGLE_JITTER_DEG))
    var dist: float       = FLOW_GLIDE_DISTANCE * (1.0 + _rng.randf_range(-FLOW_GLIDE_DIST_JITTER_FRAC, FLOW_GLIDE_DIST_JITTER_FRAC))
    var glide_to: Vector2 = wall + leg["glide_dir"].rotated(angle) * dist
    return {"wall": wall, "glide_to": glide_to}


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
    _drive_flow_production(delta)
    _update_icons(delta)
    _update_center_icons(delta)
    queue_redraw()
    if _settings_popout and not _settings_popout.tooltips_enabled:
        tooltip_text = ""
    else:
        # BigNum.to_display_string() formatting was previously redone every
        # single frame regardless of whether the tooltip is even visible —
        # throttled to 1x/sec, matching root_ui.gd's _update_button_tooltips()
        # precedent, since nothing here needs faster-than-eye-tracking updates.
        _tooltip_accum += delta
        if _tooltip_accum >= 1.0:
            _tooltip_accum = 0.0
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
    var current = _gc._assignment_int("storage_overflow_volitions", 0)
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
    # Icons already mid-flow toward a wedge are "spoken for" — counted
    # here so _sync_icons() doesn't re-trigger a fresh crossing for the
    # same shortfall every single frame while they're still in transit
    # (settle-terminal icons don't count toward any wedge, so they're
    # left out of this — see _drive_flow_production() for that leg).
    var in_flight_counts: Dictionary = {}
    for icon in _icons:
        # Mid-flow icons are in transition between two resources' counts —
        # excluded here (and from fade-selection below) so this fraction-
        # based accounting doesn't fight with the flow animation over them.
        if icon.get("flow_active", false):
            var leg: Dictionary = _flow_legs[icon["flow_leg"]]
            if leg["terminal"] == "wedge":
                var dest: String = leg["next"]
                in_flight_counts[dest] = in_flight_counts.get(dest, 0) + 1
            continue
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

    # A wedge that has an upstream flow leg (everything except Monad and
    # Uonite — see WEDGE_LEG_FOR_RESOURCE) can ONLY gain icons by a wall
    # crossing from that leg now, never by spawning fresh at its own outer
    # edge. Both paths pull from the exact same "needed" shortfall and the
    # exact same per-frame _sync_icons() cadence, so a wedge-crossing leg
    # is triggered on the identical batch schedule the old edge-spawn
    # always used — not on every raw production tick.
    for key in RESOURCE_KEYS:
        var needed = targets[key] - current_counts[key] - in_flight_counts.get(key, 0)
        if needed <= 0:
            continue
        if WEDGE_LEG_FOR_RESOURCE.has(key):
            _start_flow_for_leg(WEDGE_LEG_FOR_RESOURCE[key], needed)
        else:
            for i in needed:
                _spawn_icon(key)

    for key in RESOURCE_KEYS:
        var excess  = current_counts[key] - targets[key]
        var removed = 0
        var i       = _icons.size() - 1
        while i >= 0 and removed < excess:
            if not _icons[i].get("flow_active", false) \
            and _icons[i]["resource"] == key and not _icons[i]["fading"]:
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
        "wedge":    face_idx,
        "pos":      spawn_pos,
        "vel":      vel,
        "alpha":    0.0,
        "fading":   false,
        "spawning": true,
        "spawn_t":  0.0,
    })


func _update_icons(delta: float) -> void:
    var to_remove: Array = []      # indices removed from _icons this frame
    var to_center: Array = []      # subset of to_remove that transfers to _center_icons

    for i in _icons.size():
        var icon = _icons[i]

        if icon.get("flow_active", false):
            if _advance_flow_icon(icon, delta):
                to_remove.append(i)
                to_center.append(i)
            continue

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
            _confine_to_wedge(icon)

        else:
            # Confined to its own wedge now — no more top-exit ritual to
            # pull toward, so a despawning icon just fades in place.
            icon["alpha"] -= delta / FADE_DURATION
            if icon["alpha"] <= 0.0:
                to_remove.append(i)

    for i in range(to_remove.size() - 1, -1, -1):
        var idx: int = to_remove[i]
        if idx in to_center:
            var icon: Dictionary = _icons[idx]
            icon.erase("flow_active")
            icon.erase("flow_phase")
            icon.erase("flow_leg")
            icon.erase("flow_delay")
            icon.erase("flow_wall")
            icon.erase("flow_glide_to")
            icon["alpha"] = 1.0
            _center_icons.append(icon)
        _icons.remove_at(idx)


# Advances one icon through its wall-crossing animation. Returns true only
# when a "settle" terminal (Mote->Uonite) has fully completed, signaling
# the caller to move this icon out of _icons and into _center_icons — the
# far more common "wedge" terminal just clears its own flow_* bookkeeping
# and hands the icon back to normal drift+bounce behavior in place, no
# removal needed.
func _advance_flow_icon(icon: Dictionary, delta: float) -> bool:
    if icon.get("flow_delay", 0.0) > 0.0:
        icon["flow_delay"] -= delta
        return false

    var leg: Dictionary = _flow_legs[icon["flow_leg"]]

    if icon["flow_phase"] == "to_wall":
        var wall_target: Vector2 = icon["flow_wall"]
        var to_wall: Vector2 = wall_target - icon["pos"]
        var wall_dist: float = to_wall.length()
        var wall_step: float = FLOW_SPEED * delta
        if wall_step >= wall_dist or wall_dist < 0.5:
            icon["pos"]        = wall_target
            icon["resource"]   = leg["next"]   # transform right as it crosses the wall
            icon["flow_phase"] = "glide"
        else:
            icon["pos"] += to_wall.normalized() * wall_step
        return false

    # "glide" — a short, gentle drift past the wall into the new wedge
    # (or, for the settle terminal, toward the center). Target is this
    # icon's OWN randomized point (see _roll_flow_targets), not a single
    # shared point every icon on the leg converges on.
    var target: Vector2 = icon["flow_glide_to"]
    var to_target: Vector2 = target - icon["pos"]
    var dist: float = to_target.length()
    var step: float = FLOW_GLIDE_SPEED * delta
    if step < dist and dist >= 0.5:
        icon["pos"] += to_target.normalized() * step
        return false

    icon["pos"] = target
    # Arrival velocity is randomized the same way _spawn_icon() jitters a
    # fresh icon's initial drift — a straight-line stop-dead landing (the
    # old vel=ZERO) read as too uniform once several icons crossed at once.
    var arrive_dir: Vector2  = (icon["flow_glide_to"] - icon["flow_wall"]).normalized()
    var arrive_perp: Vector2 = Vector2(-arrive_dir.y, arrive_dir.x)
    var arrive_vel: Vector2  = arrive_dir * DRIFT_SPEED + arrive_perp * _rng.randf_range(-RANDOM_VEL, RANDOM_VEL)

    if leg["terminal"] == "settle":
        icon["vel"] = arrive_vel
        return true

    icon["wedge"] = leg["dest_wedge"]
    icon["vel"]   = arrive_vel
    icon.erase("flow_active")
    icon.erase("flow_phase")
    icon.erase("flow_leg")
    icon.erase("flow_delay")
    icon.erase("flow_wall")
    icon.erase("flow_glide_to")
    return false


func _confine_to_wedge(icon: Dictionary) -> void:
    var wedge: int = icon.get("wedge", 1)
    if wedge < 0 or wedge >= _wedge_bounds.size():
        return
    var icon_size = ICON_SIZES.get(icon["resource"], 7.0)
    var half      = icon_size * 0.5
    for edge in _wedge_bounds[wedge]:
        var point:   Vector2 = edge[0]
        var outward: Vector2 = edge[1]
        var to_icon = icon["pos"] - point
        var dist    = to_icon.dot(outward)
        if dist > -half:
            icon["pos"] -= outward * (dist + half + 0.5)
            var vel_out = icon["vel"].dot(outward)
            if vel_out > 0:
                icon["vel"] -= outward * vel_out * 1.6


# Bounce within the central octagon's 8 inner edges — mirrors
# _confine_to_wedge's outer-face case, just scoped to the full inner ring
# instead of one wedge, for Uonite icons that have settled centrally.
func _confine_to_center(icon: Dictionary) -> void:
    if _inner_face_midpoints.size() < 8:
        return
    var icon_size = ICON_SIZES.get(icon["resource"], 7.0)
    var half      = icon_size * 0.5
    for i in 8:
        var outward = Vector2(-_inner_face_normals[i].x, -_inner_face_normals[i].y)
        var to_icon = icon["pos"] - _inner_face_midpoints[i]
        var dist    = to_icon.dot(outward)
        if dist > -half:
            icon["pos"] -= outward * (dist + half + 0.5)
            var vel_out = icon["vel"].dot(outward)
            if vel_out > 0:
                icon["vel"] -= outward * vel_out * 1.6


# ==================================================
# FLOW TRIGGERING — repurposes EXISTING _icons entries (or spawns fresh
# ones only if none of the source resource are currently on hand) into the
# flow_active state machine driven by _advance_flow_icon(). Nothing is
# independently spawned-and-despawned anymore; see header changelog.
# ==================================================
func _start_flow_for_leg(leg_idx: int, count: int) -> void:
    if leg_idx < 0 or leg_idx >= _flow_legs.size() or count <= 0:
        return
    var leg: Dictionary = _flow_legs[leg_idx]
    var source: String = leg["source"]

    # Prefer repurposing existing storage icons of the source resource —
    # this is what makes the animation start from wherever that icon
    # actually is, instead of a fixed spawn point.
    var candidates: Array = []
    for icon in _icons:
        if icon["resource"] == source and not icon.get("flow_active", false) \
        and not icon["fading"] and not icon["spawning"]:
            candidates.append(icon)
            if candidates.size() >= count:
                break

    var started: int = 0
    for icon in candidates:
        var targets: Dictionary = _roll_flow_targets(leg)
        icon["flow_active"]   = true
        icon["flow_phase"]    = "to_wall"
        icon["flow_leg"]      = leg_idx
        icon["flow_delay"]    = started * FLOW_STAGGER
        icon["flow_wall"]     = targets["wall"]
        icon["flow_glide_to"] = targets["glide_to"]
        started += 1

    # Not enough existing icons on hand — spawn the remainder fresh at the
    # source wedge's face, then immediately mark them flow_active so they
    # animate straight into the crossing instead of drifting first.
    while started < count and _icons.size() < MAX_ICONS:
        var face_idx: int = RESOURCE_FACE.get(source, 1)
        if _face_midpoints.is_empty():
            break
        var targets: Dictionary = _roll_flow_targets(leg)
        var icon: Dictionary = {
            "resource":     source,
            "wedge":        face_idx,
            "pos":          _face_midpoints[face_idx],
            "vel":          Vector2.ZERO,
            "alpha":        1.0,
            "fading":       false,
            "spawning":     false,
            "spawn_t":      1.0,
            "flow_active":  true,
            "flow_phase":   "to_wall",
            "flow_leg":     leg_idx,
            "flow_delay":   started * FLOW_STAGGER,
            "flow_wall":    targets["wall"],
            "flow_glide_to": targets["glide_to"],
        }
        _icons.append(icon)
        started += 1


# Central-octagon population — Uonite icons that finished a "settle"
# terminal. Simple drift+damping+bounce, no state machine needed here;
# the wall-crossing animation itself lives in _advance_flow_icon().
func _update_center_icons(delta: float) -> void:
    for icon in _center_icons:
        icon["vel"]  = icon["vel"] * DAMPING
        icon["pos"] += icon["vel"] * delta
        _confine_to_center(icon)


# Maps a resource with an upstream "wedge"-terminal leg to that leg's
# index in _flow_legs — used by _sync_icons() to route a wedge's own
# needed-icon shortfall into a wall crossing instead of _spawn_icon().
# Monad has no entry (nothing flows into it — it's the root of the
# chain) and Uonite has no entry either, since its leg is "settle", not
# "wedge" (see SETTLE_LEG_INDEX below).
const WEDGE_LEG_FOR_RESOURCE: Dictionary = {
    "tetrad": 0, "particle": 1, "iota": 2, "mote": 3, "grain": 4,
}

# The Mote->Uonite leg is the one exception to "triggered by _sync_icons()'s
# wedge shortfall" — it settles into the central cavity, not a wedge, so
# there's no wedge storage-target it could be reconciled against. It's kept
# on the older totals_created-delta trigger instead, now scoped to just
# this one leg (see _drive_flow_production() below), representing a
# distinct "flowing toward the center" flourish tied to real Uonite
# creation events rather than to any wedge's population.
const SETTLE_LEG_INDEX:    int    = 5
const SETTLE_LEG_RESOURCE: String = "uonite"

# _settle_total_primed starts false so the very first call after
# load/ready never mistakes a save's entire lifetime Uonite total for one
# frame's production.
var _prev_settle_total:   BigNum = BigNum.zero()
var _settle_total_primed: bool   = false

func _drive_flow_production(_delta: float) -> void:
    if not _gc:
        return
    var current: BigNum = _gc.totals_created.get(SETTLE_LEG_RESOURCE, BigNum.zero())
    if _settle_total_primed and current.is_greater_than(_prev_settle_total):
        var delta_bn: BigNum = current.sub(_prev_settle_total)
        var burst: int = clampi(
            int(round(log(1.0 + float(delta_bn.to_int())))), 1, FLOW_BURST_MAX)
        _start_flow_for_leg(SETTLE_LEG_INDEX, burst)
    _prev_settle_total   = current.copy()
    _settle_total_primed = true


## Called by root_ui.gd on prestige reset — the whole flow stream
## represents pre-Expansion production, so it's cleared immediately rather
## than left to drain naturally (matching the resource wipe it visualizes).
func clear_flow_icons() -> void:
    _center_icons.clear()


func _draw_icon_at(pos: Vector2, key: String, alpha: float) -> void:
    var icon_size = ICON_SIZES.get(key, 7.0)
    var half      = icon_size * 0.5
    var col       = RESOURCE_COLORS.get(key, Color.WHITE)
    col.a         = alpha
    var rect      = Rect2(pos.x - half, pos.y - half, icon_size, icon_size)
    if _textures.has(key):
        draw_texture_rect(_textures[key], rect, false, col)
    else:
        draw_circle(pos, half, col)


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

    # Internal axial seams — each vertex→inner-vertex segment is split
    # across its width into two parallel sub-lines, color-coded to the two
    # wedges it borders. Wedge i (under face i) holds vertex i+1; the
    # opposite side of the segment borders wedge (i-1) holding vertex i-1.
    # These used to run all the way to _oct_center — now they stop at the
    # central octagon's boundary, leaving its interior empty space.
    for i in 8:
        var p        = _oct_verts[i]
        var ip       = _inner_verts[i]
        var dir      = (_oct_center - p).normalized()
        var perp     = Vector2(-dir.y, dir.x)
        var t_i_side = signf((_oct_verts[(i + 1) % 8] - p).dot(perp))
        var col_i    = _face_colors.get(i, Color(0.3, 0.3, 0.3, 0.2))
        var col_im   = _face_colors.get((i + 7) % 8, Color(0.3, 0.3, 0.3, 0.2))
        var off      = 0.75
        if t_i_side >= 0.0:
            draw_line(p + perp * off, ip + perp * off, col_i, 1.5)
            draw_line(p - perp * off, ip - perp * off, col_im, 1.5)
        else:
            draw_line(p - perp * off, ip - perp * off, col_i, 1.5)
            draw_line(p + perp * off, ip + perp * off, col_im, 1.5)

    # Central octagon — empty space where settled Uonite flow icons
    # collect, awaiting Expansion. Drawn after the seams so its border
    # sits cleanly on top of them.
    if _inner_verts.size() == 8:
        draw_colored_polygon(_inner_verts, Color(0.10, 0.09, 0.04, 0.92))
        for i in 8:
            draw_line(_inner_verts[i], _inner_verts[(i + 1) % 8],
                Color(1.0, 0.87, 0.33, 0.35), 1.5)

    # Icons — storage population (flow-active icons mid-crossing are
    # regular _icons members and draw here too, using their live
    # resource/pos/alpha), then settled central-octagon icons on top.
    for icon in _icons:
        _draw_icon_at(icon["pos"], icon["resource"], icon["alpha"])
    for icon in _center_icons:
        _draw_icon_at(icon["pos"], icon["resource"], icon["alpha"])

    # Volition assignment counter — lower-right corner (face 3)
    if _vol_center != Vector2.ZERO and _gc:
        var assigned = _gc._assignment_int("storage_overflow_volitions", 0) \
                     + _gc._assignment_int("storage_overflow_bonus_volitions", 0)
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
        var current  = _gc._assignment_int("storage_overflow_volitions", 0)
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
