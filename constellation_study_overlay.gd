extends Control
# ================ CONSTELLATION STUDY OVERLAY v1.0.0 ================
# Modal overlay presenting an enlarged, interactive star map for a
# single constellation alongside its logic puzzle clue list.
#
# PANE 1 — Star Map
#   Draws all stars at enlarged scale with their puzzle colors.
#   Clicking a star selects it and highlights it.
#   The right-side picker lists all generated star names for this
#   constellation. Clicking a name assigns it to the selected star.
#   Already-assigned names are greyed but visible (click to reassign).
#   A "Clear Assignment" button removes the selected star's assignment.
#
# PANE 2 — Clue List
#   Scrollable list of all generated logic puzzle clue strings.
#   Flavor clues (star color descriptions) shown first, then
#   deductive clues.
#
# CAROUSEL
#   ◀ / ▶ buttons in the header switch between panes.
#   Pane state (scroll position, selected star) persists between opens.
#
# WIRING (call from root_ui.gd or constellation_panel.gd):
#   study_overlay.show_for_constellation(constellation_id: int)

# ── AUTOLOAD REFS ────────────────────────────────────────────────────
var _cd: Node = null

# ── NODE REFS ────────────────────────────────────────────────────────
@onready var _title_label:         Label         = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/HeaderHBox/TitleLabel
@onready var _close_btn:           Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/HeaderHBox/CloseButton
@onready var _fork_btn: Button = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/HeaderHBox/TuningForkButton
@onready var _synth:    Node   = get_node_or_null("../RootUI/PuzzleSynths")
@onready var _star_map_control:    Control       = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/StarMapControl

@onready var _markers_content:     VBoxContainer = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkersScrollContainer/MarkersContentVBox
@onready var _markers_scroll:      ScrollContainer = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkersScrollContainer
@onready var _tab_color:           Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabColor
@onready var _tab_sequence:        Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabSequence
@onready var _tab_adjacency:       Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabAdjacency
@onready var _tab_pitch:           Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar2/TabPitch
@onready var _tab_name:            Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar2/TabName

# ── STYLE CACHE ──────────────────────────────────────────────────────
# Pulled from the scene's sub-resources rather than duplicated here.
const STAR_COLORS_BY_IDX: Array = [
    Color(0.45, 0.65, 1.00, 1.0),   # 0 BLUE
    Color(1.00, 1.00, 1.00, 1.0),   # 1 WHITE
    Color(1.00, 0.80, 0.30, 1.0),   # 2 YELLOW_ORANGE
    Color(1.00, 0.35, 0.25, 1.0),   # 3 RED
]
const COLOR_NAME_LABELS: Array = ["Blue", "White", "Yellow-Orange", "Red"]

const STAR_RADIUS:        float = 7.0
const STAR_SELECTED_RADIUS: float = 10.0
const HIT_RADIUS:         float = 18.0
const MAP_PADDING:        float = 40.0

# ── WIDGET LAYOUT CONSTANTS ──────────────────────────────────────────
const WIDGET_OFFSET_BELOW: float = 14.0   # px below dot centre when flipping down
const WIDGET_OFFSET_ABOVE: float = 6.0    # px above widget bottom when flipping up
const WIDGET_NAME_MAX_H:   float = 140.0  # max height of name-list scroll container

const TAG_OFFSET_BELOW:   float = 14.0   # px below dot centre when tag sits below
const TAG_OFFSET_ABOVE:   float = 6.0    # px above dot centre (tag bottom) when flipped up
const TAG_OFFSET_SIDE:    float = 12.0   # px horizontal gap from dot when flipped to side

const FORK_WRONG_FLASH_DURATION: float = 0.6
const FORK_COLOR_WRONG:   Color = Color(1.0, 0.2, 1.0, 1.0)
const FORK_COLOR_REPLAY:  Color = Color(0.3, 0.8, 1.0, 1.0)
const FORK_COLOR_FANFARE: Color = Color(1.0, 0.95, 0.5, 1.0)

const DRAG_SCROLL_EDGE:  float = 30.0    # px from scroll container top/bottom that triggers auto-scroll
const DRAG_SCROLL_SPEED: float = 240.0   # px/sec scrolled while pointer sits in the edge zone

# ── STATE ────────────────────────────────────────────────────────────
var _constellation_id:    int   = -1

func get_current_constellation_id() -> int:
    return _constellation_id
var _selected_star:       int   = -1
var _star_screen_pos:     Array = []     # Array[Vector2], map-space
var _star_names:          Array = []     # Array[String] from cache
var _star_colors:         Array = []     # Array[int] 0-3
var _name_assignments:    Array = []     # Array[String], per-star slot
var _active_marker_tab:   int   = 0      # 0=Color 1=Sequence 2=Adjacency 3=Name
# Adjacency marker states: key = "a:b" (a<b), value = int 0=neutral 1=✓ 2=✗
var _adjacency_states:    Dictionary = {}
var _pitch_rank_solution:   Array = []     # Array[int], melody step per star
var _star_pitch_index:      Array = []     # Array[int], raw note index per star (ConstellationData)
var _pitch_freqs:           Array = []     # Array[float], frequency table for this constellation
var _name_color_states:        Dictionary = {}  # name_str -> {color_idx(int): state(int)} 0=neutral,1=confirmed,2=eliminated
var _name_pitch_states:        Dictionary = {}  # name_str -> {note_name(String): state(int)}
var _name_pitch_carousel_idx:  Dictionary = {}  # name_str -> int, transient UI position, not persisted
var _matches_sort_mode:    int = -1       # -1=manual/unsorted, 0=Name,1=Sequence,2=Color,3=Pitch
var _final_clues_cache:     Array = []     # cached final_clues dicts
var _distance_flavor_cache: Array = []     # cached distance flavor texts
var _between_flavor_cache:  Array = []     # cached between flavor texts
var _color_negation_cache: Array = []      # cached {"s":int,"text":String} negation clues
var _pitch_flavor_cache:    Array = []      # cached pitch comparison/grouping flavor texts
var _pitch_negation_cache:  Array = []      # cached {"s":int,"text":String} pitch negation clues

# ── PUZZLE NOTES STATE ───────────────────────────────────────────────
# Per-star sequence range assertions (1-based, 0 = unset).
var _star_range_lo: Array[int] = []
var _star_range_hi: Array[int] = []
# Per-star name-state dicts: { name_string: int } where
#   0 = neutral, 1 = confirmed (✓), 2 = eliminated (✗).
var _name_states: Array = []
# Floating widget nodes, one Control per star.
var _star_widgets: Array = []
var _star_tags: Array = []
var _name_tab_order:    Array[String] = []   # player-deduced display order, Name tab
var _name_row_controls: Array = []           # HBoxContainer rows, parallel to _name_tab_order
var _name_drag_idx:     int = -1             # index currently being dragged, -1 = none
var _name_drag_mouse_y: float = 0.0    # last known global mouse Y while dragging, polled by _process
var _star_count: int = 0
var _gc: Node = null

enum ForkState { IDLE, ACTIVE, SUCCESS }
var _fork_mode:             bool      = false
var _fork_state:            ForkState = ForkState.IDLE
var _fork_step:             int       = 0
var _fork_note_assignment:  Array     = []
var _fork_correct_sequence: Array     = []
var _fork_tone_players:     Array     = []
var _fork_wrong_star:       int       = -1
var _fork_wrong_flash_timer: float    = 0.0
var _fork_replay_active:    bool      = false
var _fork_replay_step:      int       = 0
var _fork_replay_limit:     int       = 0
var _fork_replay_timer:     float     = 0.0
var _fork_replay_gap:       float     = 0.0
var _fork_replay_lit_star:  int       = -1
var _fork_high_water:       int       = 0
var _fork_fanfare_lit_star: int       = -1

# ── STYLE BOXES (loaded once) ─────────────────────────────────────────
var _sb_unassigned:   StyleBox = null
var _sb_assigned:     StyleBox = null
var _sb_selected:     StyleBox = null
var _sb_picker_free:  StyleBox = null
var _sb_picker_used:  StyleBox = null
var _sb_tab_active:   StyleBox = null
var _sb_tab_inactive: StyleBox = null


# ==================================================
# LIFECYCLE
# ==================================================
func _ready() -> void:
    visible = false
    _gc = get_node_or_null("/root/GameContext")
    _build_style_boxes()

    _tab_color.pressed.connect(func(): _set_marker_tab(0))
    _tab_sequence.pressed.connect(func(): _set_marker_tab(1))
    _tab_adjacency.pressed.connect(func(): _set_marker_tab(2))
    _tab_pitch.pressed.connect(func(): _set_marker_tab(4))
    _tab_name.pressed.connect(func(): _set_marker_tab(3))

    _star_map_control.draw.connect(_draw_star_map)
    _star_map_control.gui_input.connect(_on_map_input)
    _star_map_control.resized.connect(_on_star_map_resized)
    _close_btn.pressed.connect(_on_close)
    _fork_btn.pressed.connect(_on_fork_toggle_pressed)
    if _synth and _synth.has_signal("sequence_note_played"):
        _synth.sequence_note_played.connect(_on_fork_fanfare_note)


func _process(delta: float) -> void:
    if _fork_wrong_flash_timer > 0.0:
        _fork_wrong_flash_timer -= delta
        _star_map_control.queue_redraw()

    if _fork_replay_active:
        _fork_replay_timer += delta
        if _fork_replay_timer >= _fork_replay_gap:
            _fork_replay_timer = 0.0
            var def:       Dictionary = _cd.get_constellation_def(_constellation_id)
            var sequence:  Array      = def.get("puzzle_sequence", [])
            var durations: Array      = def.get("note_durations", [])
            if _fork_replay_step >= _fork_replay_limit:
                _fork_replay_active   = false
                _fork_replay_lit_star = -1
            else:
                var pitch_idx: int = sequence[_fork_replay_step]
                _play_fork_note_by_pitch_index(pitch_idx)
                _fork_replay_lit_star = _fork_correct_sequence[_fork_replay_step]
                if _fork_replay_step < durations.size():
                    _fork_replay_gap = durations[_fork_replay_step]
                else:
                    _fork_replay_gap = 0.65
                _fork_replay_step += 1
            _star_map_control.queue_redraw()

    if _name_drag_idx < 0:
        return
    var scroll_rect: Rect2 = _markers_scroll.get_global_rect()
    if _name_drag_mouse_y < scroll_rect.position.y + DRAG_SCROLL_EDGE:
        _markers_scroll.scroll_vertical -= int(DRAG_SCROLL_SPEED * delta)
    elif _name_drag_mouse_y > scroll_rect.position.y + scroll_rect.size.y - DRAG_SCROLL_EDGE:
        _markers_scroll.scroll_vertical += int(DRAG_SCROLL_SPEED * delta)


func _build_style_boxes() -> void:
    var make := func(bg: Color, border: Color, bw: int = 1, cr: int = 3) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.border_color = border
        sb.border_width_left   = bw
        sb.border_width_top    = bw
        sb.border_width_right  = bw
        sb.border_width_bottom = bw
        sb.corner_radius_top_left     = cr
        sb.corner_radius_top_right    = cr
        sb.corner_radius_bottom_right = cr
        sb.corner_radius_bottom_left  = cr
        sb.content_margin_left   = 6.0
        sb.content_margin_top    = 4.0
        sb.content_margin_right  = 6.0
        sb.content_margin_bottom = 4.0
        return sb

    _sb_unassigned  = make.call(Color(0.10, 0.07, 0.20, 0.8), Color(0.35, 0.25, 0.55, 0.6))
    _sb_assigned    = make.call(Color(0.14, 0.10, 0.28, 0.9), Color(0.55, 0.40, 0.80, 0.8))
    _sb_selected    = make.call(Color(0.22, 0.14, 0.42, 1.0), Color(0.80, 0.65, 1.00, 1.0), 2)
    _sb_picker_free = make.call(Color(0.10, 0.07, 0.20, 0.7), Color(0.32, 0.22, 0.52, 0.5))
    _sb_picker_used = make.call(Color(0.07, 0.05, 0.13, 0.5), Color(0.22, 0.15, 0.35, 0.4))
    _sb_tab_active   = make.call(Color(0.22, 0.14, 0.42, 1.0), Color(0.80, 0.65, 1.00, 1.0), 1, 3)
    _sb_tab_inactive = make.call(Color(0.08, 0.05, 0.16, 0.7), Color(0.32, 0.22, 0.52, 0.4), 1, 3)


# ==================================================
# PUBLIC API
# ==================================================
func show_for_constellation(constellation_id: int) -> void:
    if not _cd:
        _cd = get_node_or_null("/root/ConstellationData")
    _constellation_id = constellation_id
    _load_constellation_data()
    _update_header()
    _set_marker_tab(_active_marker_tab)
    _build_star_widgets()
    _build_star_tags()
    _reset_fork_puzzle()
    visible = true


# ==================================================
# DATA LOADING
# ==================================================
func _load_constellation_data() -> void:
    if not _cd or _constellation_id < 0:
        return

    var cache: Dictionary = _cd.get_puzzle_cache(_constellation_id)

    var raw_names = cache.get("star_names", [])
    _star_names = []
    for n in raw_names:
        _star_names.append(str(n))

    var raw_colors = cache.get("star_colors", [])
    _star_colors = []
    for c in raw_colors:
        _star_colors.append(int(c))

    _star_count = _star_names.size()

    # Name assignments (legacy positive-assignment slot).
    var raw_assign = cache.get("player_name_assignments", [])
    _name_assignments = []
    for i in _star_count:
        _name_assignments.append(str(raw_assign[i]) if i < raw_assign.size() else "")

    # Puzzle notes (range + name states).
    var notes: Dictionary = _cd.get_player_puzzle_notes(_constellation_id)
    _star_range_lo.clear()
    _star_range_hi.clear()
    _name_states.clear()
    for i in _star_count:
        var key: String = str(i)
        var slot: Dictionary = notes.get(key, {})
        _star_range_lo.append(int(slot.get("lo", 0)))
        _star_range_hi.append(int(slot.get("hi", 0)))
        _name_states.append(slot.get("name_states", {}).duplicate())

    # Name tab manual sort order — persisted, reconciled against current names.
    var raw_order: Array = notes.get("name_tab_order", [])
    _name_tab_order = []
    for v in raw_order:
        _name_tab_order.append(str(v))
    var all_names: Array = []
    for i in _star_count:
        all_names.append(_star_names[i] if i < _star_names.size() else "Star %d" % (i + 1))
    var missing: Array = []
    for n in all_names:
        if not _name_tab_order.has(n):
            missing.append(n)
    missing.sort()
    for n in missing:
        _name_tab_order.append(n)
    var order_i: int = _name_tab_order.size() - 1
    while order_i >= 0:
        if not all_names.has(_name_tab_order[order_i]):
            _name_tab_order.remove_at(order_i)
        order_i -= 1

    # Adjacency states
    _adjacency_states.clear()
    var raw_adj: Dictionary = notes.get("adjacency_states", {})
    for k in raw_adj:
        _adjacency_states[str(k)] = int(raw_adj[k])

    _name_color_states.clear()
    var raw_name_colors: Dictionary = notes.get("name_color_states", {})
    for k in raw_name_colors:
        var inner: Dictionary = {}
        for ck in raw_name_colors[k]:
            inner[int(ck)] = int(raw_name_colors[k][ck])
        _name_color_states[str(k)] = inner

    _name_pitch_states.clear()
    var raw_name_pitch: Dictionary = notes.get("name_pitch_states", {})
    for k in raw_name_pitch:
        var inner_p: Dictionary = {}
        for pk in raw_name_pitch[k]:
            inner_p[str(pk)] = int(raw_name_pitch[k][pk])
        _name_pitch_states[str(k)] = inner_p

    _name_pitch_carousel_idx.clear()

    # Sequence position + clue text caches (for Markers Panel display).
    _pitch_rank_solution = []
    for v in cache.get("pitch_rank_solution", []):
        _pitch_rank_solution.append(int(v))

    _star_pitch_index = []
    for v in _cd.get_note_assignment(_constellation_id):
        _star_pitch_index.append(int(v))
    _pitch_freqs = _cd.get_note_freqs(_constellation_id)

    _final_clues_cache = cache.get("final_clues", []).duplicate(true)
    _distance_flavor_cache = cache.get("distance_flavor_texts", []).duplicate()
    _between_flavor_cache = cache.get("between_flavor_texts", []).duplicate()
    _color_negation_cache = cache.get("color_negation_texts", []).duplicate(true)
    _pitch_flavor_cache = cache.get("pitch_flavor_texts", []).duplicate()
    _pitch_negation_cache = cache.get("pitch_negation_texts", []).duplicate(true)

    _compute_star_screen_positions()
    _selected_star = -1


func _compute_star_screen_positions() -> void:
    _star_screen_pos.clear()
    if not _cd or _constellation_id < 0:
        return

    var world_positions: Array = _cd.get_star_positions(_constellation_id)
    if world_positions.is_empty():
        return

    # Find the centroid direction so we can build a local tangent frame
    # and project stars into a flat 2D map coordinate.
    var centroid := Vector3.ZERO
    for wp in world_positions:
        centroid += wp as Vector3
    centroid = centroid.normalized()

    # Build a consistent local 2D frame at the centroid.
    var ref: Vector3 = Vector3.UP if absf(centroid.y) < 0.99 else Vector3.RIGHT
    var local_x: Vector3 = ref.cross(centroid).normalized()
    var local_y: Vector3 = centroid.cross(local_x).normalized()

    # Project each star onto the local plane and collect 2D coords.
    var raw_pts: Array = []
    for wp in world_positions:
        var v: Vector3 = (wp as Vector3) - centroid * (wp as Vector3).dot(centroid)
        raw_pts.append(Vector2(v.dot(local_x), -v.dot(local_y)))

    var map_size: Vector2 = _star_map_control.size
    if map_size.x < 10.0 or map_size.y < 10.0:
        # Control hasn't been sized yet; defer to first draw
        map_size = Vector2(540.0, 400.0)

    var usable_w: float = map_size.x - MAP_PADDING * 2.0
    var usable_h: float = map_size.y - MAP_PADDING * 2.0

    # ── Orientation search ────────────────────────────────────────
    # Rotating the constellation's 2D projection changes how tightly its
    # bounding box matches the panel's aspect ratio. A rotation that leaves
    # a tall narrow shape wastes horizontal space; the wrong rotation on
    # a wide shape wastes vertical space. Sweep candidate angles and keep
    # whichever rotation lets the constellation scale up the most before
    # its bounding box hits the panel edges.
    var best_angle: float = 0.0
    var best_scale: float = -1.0
    var step_count: int = 180   # 1-degree resolution; 180° covers all
                                 # distinct bounding boxes since a further
                                 # 180° rotation reproduces the same box.
    for step in step_count:
        var angle: float = deg_to_rad(float(step))
        var trial_ca: float = cos(angle)
        var trial_sa: float = sin(angle)

        var trial_min_x: float = INF; var trial_max_x: float = -INF
        var trial_min_y: float = INF; var trial_max_y: float = -INF
        for pt in raw_pts:
            var p := pt as Vector2
            var rx: float = p.x * trial_ca - p.y * trial_sa
            var ry: float = p.x * trial_sa + p.y * trial_ca
            trial_min_x = minf(trial_min_x, rx); trial_max_x = maxf(trial_max_x, rx)
            trial_min_y = minf(trial_min_y, ry); trial_max_y = maxf(trial_max_y, ry)

        var trial_span_x: float = maxf(trial_max_x - trial_min_x, 0.0001)
        var trial_span_y: float = maxf(trial_max_y - trial_min_y, 0.0001)
        var trial_scale: float = minf(usable_w / trial_span_x, usable_h / trial_span_y)

        if trial_scale > best_scale:
            best_scale = trial_scale
            best_angle = angle

    # Apply the winning rotation to the projected points.
    var ca: float = cos(best_angle)
    var sa: float = sin(best_angle)
    var rotated_pts: Array = []
    for pt in raw_pts:
        var p := pt as Vector2
        rotated_pts.append(Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca))

    # ── Fit rotated points to the panel ─────────────────────────────
    var min_x: float = rotated_pts[0].x; var max_x: float = rotated_pts[0].x
    var min_y: float = rotated_pts[0].y; var max_y: float = rotated_pts[0].y
    for pt in rotated_pts:
        min_x = minf(min_x, (pt as Vector2).x)
        max_x = maxf(max_x, (pt as Vector2).x)
        min_y = minf(min_y, (pt as Vector2).y)
        max_y = maxf(max_y, (pt as Vector2).y)

    var span_x: float = maxf(max_x - min_x, 0.0001)
    var span_y: float = maxf(max_y - min_y, 0.0001)
    var map_scale: float = minf(usable_w / span_x, usable_h / span_y)

    var cx: float = (min_x + max_x) * 0.5
    var cy: float = (min_y + max_y) * 0.5

    for pt in rotated_pts:
        var p := pt as Vector2
        var sx: float = (p.x - cx) * map_scale + map_size.x * 0.5
        var sy: float = (p.y - cy) * map_scale + map_size.y * 0.5
        _star_screen_pos.append(Vector2(sx, sy))

    _reposition_star_widgets()


func _on_star_map_resized() -> void:
    if _constellation_id < 0:
        return
    _compute_star_screen_positions()
    _reposition_star_tags()
    _star_map_control.queue_redraw()


# ==================================================
# DRAWING — STAR MAP
# ==================================================
func _draw_star_map() -> void:
    if _star_screen_pos.is_empty():
        return

    var def: Dictionary = _cd.get_constellation_def(_constellation_id) if _cd else {}
    var line_pairs: Array = def.get("line_pairs", [])

    var line_color := Color(0.55, 0.45, 0.75, 0.35)
    var k: int = 0
    while k < line_pairs.size() - 1:
        var ai: int = int(line_pairs[k])
        var bi: int = int(line_pairs[k + 1])
        k += 2
        if ai >= _star_screen_pos.size() or bi >= _star_screen_pos.size():
            continue
        _star_map_control.draw_line(
            _star_screen_pos[ai], _star_screen_pos[bi], line_color, 1.5, true)

    for i in _star_screen_pos.size():
        var p: Vector2 = _star_screen_pos[i]
        var is_selected: bool = (i == _selected_star)

        var base_col: Color
        if i < _star_colors.size():
            base_col = STAR_COLORS_BY_IDX[clamp(_star_colors[i], 0, 3)]
        else:
            base_col = Color(1.0, 1.0, 1.0, 1.0)

        if is_selected:
            var glow_col := Color(base_col.r, base_col.g, base_col.b, 0.25)
            _star_map_control.draw_circle(p, STAR_SELECTED_RADIUS * 2.2, glow_col)
            _star_map_control.draw_circle(p, STAR_SELECTED_RADIUS, base_col)
        else:
            _star_map_control.draw_circle(p, STAR_RADIUS, base_col)

        if not _fork_mode:
            continue

        if i == _fork_replay_lit_star:
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.4, Color(FORK_COLOR_REPLAY.r, FORK_COLOR_REPLAY.g, FORK_COLOR_REPLAY.b, 0.45))
            _star_map_control.draw_circle(p, 6.0, FORK_COLOR_REPLAY)
        if i == _fork_wrong_star and _fork_wrong_flash_timer > 0.0:
            var t: float = _fork_wrong_flash_timer / FORK_WRONG_FLASH_DURATION
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.6, Color(FORK_COLOR_WRONG.r, FORK_COLOR_WRONG.g, FORK_COLOR_WRONG.b, 0.4 * t))
            _star_map_control.draw_circle(p, 5.0, Color(FORK_COLOR_WRONG.r, FORK_COLOR_WRONG.g, FORK_COLOR_WRONG.b, 0.9 * t))
        if i == _fork_fanfare_lit_star and _fork_state == ForkState.SUCCESS:
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.6, Color(FORK_COLOR_FANFARE.r, FORK_COLOR_FANFARE.g, FORK_COLOR_FANFARE.b, 0.50))
            _star_map_control.draw_circle(p, 7.0, FORK_COLOR_FANFARE)


# ==================================================
# INPUT — STAR MAP CLICK
# ==================================================
func _on_map_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    var mbe := event as InputEventMouseButton
    if not mbe.pressed or mbe.button_index != MOUSE_BUTTON_LEFT:
        return
    if _star_screen_pos.is_empty():
        return

    var best_idx: int   = -1
    var best_dist: float = HIT_RADIUS
    for i in _star_screen_pos.size():
        var d: float = mbe.position.distance_to(_star_screen_pos[i])
        if d < best_dist:
            best_dist = d
            best_idx  = i
    if best_idx < 0:
        return

    if _fork_mode:
        _on_fork_star_clicked(best_idx)
        get_viewport().set_input_as_handled()
        return

    _selected_star = -1 if best_idx == _selected_star else best_idx
    _star_map_control.queue_redraw()
    for wi in _star_widgets.size():
        if is_instance_valid(_star_widgets[wi]):
            _star_widgets[wi].visible = (wi == _selected_star)
    _reposition_star_widgets()
    get_viewport().set_input_as_handled()


# ==================================================
# FORK PUZZLE — TUNING-FORK SEQUENCE MODE
# ==================================================
func _on_fork_toggle_pressed() -> void:
    _fork_mode = not _fork_mode
    _fork_btn.modulate = Color(0.3, 1.0, 0.4, 1.0) if _fork_mode else Color(1, 1, 1, 1)
    if _fork_mode:
        _selected_star = -1
        for wi in _star_widgets.size():
            if is_instance_valid(_star_widgets[wi]):
                _star_widgets[wi].visible = false
        _check_fork_availability()
    _star_map_control.queue_redraw()


func _reset_fork_puzzle() -> void:
    _fork_mode = false
    if is_instance_valid(_fork_btn):
        _fork_btn.modulate = Color(1, 1, 1, 1)
    _fork_step = 0
    _fork_note_assignment.clear()
    _fork_correct_sequence.clear()
    _fork_wrong_star = -1
    _fork_wrong_flash_timer = 0.0
    _fork_replay_active = false
    _fork_replay_lit_star = -1
    _fork_fanfare_lit_star = -1
    _fork_state = ForkState.IDLE
    if is_instance_valid(_star_map_control):
        _star_map_control.queue_redraw()


func _check_fork_availability() -> void:
    if not _cd or not _gc or _constellation_id < 0:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    if not def.has("puzzle_sequence"):
        _fork_state = ForkState.IDLE
        return
    var solve_key: String = "constellation_%d_solve_count" % _constellation_id
    var solves: int = _gc.assignments.get(solve_key, 0)
    if solves > 0:
        _fork_state = ForkState.IDLE
        return
    var visual: String = _cd.get_visual_state(_constellation_id)
    if visual == "dark":
        _fork_state = ForkState.IDLE
        return
    _fork_state = ForkState.ACTIVE
    _fork_step  = 0
    var hw_key := "constellation_%d_high_water" % _constellation_id
    _fork_high_water = _gc.assignments.get(hw_key, 0)
    if _fork_note_assignment.is_empty():
        _fork_note_assignment = _cd.get_note_assignment(_constellation_id)
    if _fork_correct_sequence.is_empty():
        _build_fork_correct_sequence()
    if _fork_tone_players.is_empty():
        _build_fork_tone_players()


func _build_fork_correct_sequence() -> void:
    _fork_correct_sequence.clear()
    if not _cd or _fork_note_assignment.is_empty():
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    var sequence: Array = def.get("puzzle_sequence", [])
    var used: Array = []
    for step in sequence.size():
        var pitch: int = sequence[step]
        var best_star: int = -1
        for si in _fork_note_assignment.size():
            if _fork_note_assignment[si] == pitch and si not in used:
                best_star = si
                break
        if best_star == -1:
            for si in _fork_note_assignment.size():
                if _fork_note_assignment[si] == pitch:
                    best_star = si
                    break
        if best_star >= 0:
            used.append(best_star)
        _fork_correct_sequence.append(best_star)


func _on_fork_star_clicked(star_index: int) -> void:
    if _fork_replay_active:
        return
    if _fork_correct_sequence.is_empty() or not _cd:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    if not def.has("puzzle_sequence"):
        return
    var sequence: Array = def["puzzle_sequence"]
    var clicked: int = _fork_note_assignment[star_index]
    var correct_star: int = _fork_correct_sequence[_fork_step]

    _play_fork_note_by_pitch_index(clicked)

    if star_index == correct_star:
        _fork_step += 1
        _fork_wrong_star        = -1
        _fork_wrong_flash_timer = 0.0
        if _fork_step > _fork_high_water:
            _fork_high_water = _fork_step
            if _gc:
                var hw_key := "constellation_%d_high_water" % _constellation_id
                _gc.assignments[hw_key] = _fork_high_water
        if _fork_step >= sequence.size():
            _on_fork_puzzle_complete()
    else:
        _fork_wrong_star        = star_index
        _fork_wrong_flash_timer = FORK_WRONG_FLASH_DURATION
        _fork_step               = 0
        if _fork_high_water > 0:
            _fork_replay_active   = true
            _fork_replay_step     = 0
            _fork_replay_limit    = _fork_high_water
            _fork_replay_timer    = 0.0
            _fork_replay_gap      = FORK_WRONG_FLASH_DURATION + 0.3
            _fork_replay_lit_star = -1
    _star_map_control.queue_redraw()


func _on_fork_puzzle_complete() -> void:
    _fork_state = ForkState.SUCCESS
    if _gc:
        var solve_key: String = "constellation_%d_solve_count" % _constellation_id
        _gc.assignments[solve_key] = 1

    var solve_path: String = "res://sequences/constellation_%d_solve.tres" % _constellation_id
    var solve_seq = load(solve_path) as PuzzleSequenceResource
    if solve_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(solve_seq, _play_fork_completion_reward)
    else:
        _finish_fork_sequences()


func _on_fork_fanfare_note(freq: float) -> void:
    if _fork_state != ForkState.SUCCESS:
        return
    _fork_fanfare_lit_star = _freq_to_fork_star(freq)
    _star_map_control.queue_redraw()


func _freq_to_fork_star(freq: float) -> int:
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
    var best_pitch: int = -1
    var best_diff: float = 2.0
    for pitch_idx in freqs.size():
        var f: float = freqs[pitch_idx]
        if f <= 0.0:
            continue
        if absf(f - freq) < best_diff:
            best_diff = absf(f - freq)
            best_pitch = pitch_idx
    if best_pitch == -1:
        return -1
    for si in _fork_note_assignment.size():
        if _fork_note_assignment[si] == best_pitch:
            return si
    return -1


func _play_fork_completion_reward() -> void:
    var reward_path: String = "res://sequences/constellation_%d_reward.tres" % _constellation_id
    var reward_seq = load(reward_path) as PuzzleSequenceResource
    if reward_seq and _synth and _synth.has_method("play_sequence"):
        _synth.play_sequence(reward_seq, _finish_fork_sequences)
    else:
        _finish_fork_sequences()


func _finish_fork_sequences() -> void:
    _fork_fanfare_lit_star = -1
    _fork_state             = ForkState.IDLE
    _check_fork_availability()
    _star_map_control.queue_redraw()


func _play_fork_note_by_pitch_index(pitch_index: int) -> void:
    if not _synth:
        if pitch_index < 0 or pitch_index >= _fork_tone_players.size():
            return
        _fork_tone_players[pitch_index].stop()
        _fork_tone_players[pitch_index].play()
        return
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
    if pitch_index < 0 or pitch_index >= freqs.size():
        return
    var freq: float = freqs[pitch_index]
    if freq == 0.0:
        if _synth.has_method("play_thud"):
            _synth.play_thud()
        return
    if _synth.has_method("play_bell_note"):
        _synth.play_bell_note(freq)


func _build_fork_tone_players() -> void:
    for p in _fork_tone_players:
        p.queue_free()
    _fork_tone_players.clear()
    var freqs: Array = _cd.get_note_freqs(_constellation_id)
    for freq in freqs:
        var p: AudioStreamPlayer = AudioStreamPlayer.new()
        p.stream    = _make_fork_tone_wav(freq, 0.35)
        p.volume_db = -6.0
        add_child(p)
        _fork_tone_players.append(p)


func _make_fork_tone_wav(freq: float, duration: float) -> AudioStreamWAV:
    const SAMPLE_RATE: int = 22050
    var n: int = int(duration * SAMPLE_RATE)
    var buf: PackedByteArray = PackedByteArray()
    buf.resize(n * 2)
    for i in n:
        var t: float = float(i) / SAMPLE_RATE
        var env: float = 1.0
        if t < 0.01:
            env = t / 0.01
        elif t > duration - 0.05:
            env = clamp((duration - t) / 0.05, 0.0, 1.0)
        var s: int = int(sin(TAU * freq * t) * 32767.0 * env * 0.38)
        s = clamp(s, -32768, 32767)
        buf[i * 2]     = s & 0xFF
        buf[i * 2 + 1] = (s >> 8) & 0xFF
    var wav: AudioStreamWAV = AudioStreamWAV.new()
    wav.data     = buf
    wav.format   = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = SAMPLE_RATE
    wav.stereo   = false
    return wav


# ==================================================
# PICKER — NAME ASSIGNMENT
# ==================================================

func _save_puzzle_notes() -> void:
    if not _cd or _constellation_id < 0:
        return
    var notes: Dictionary = {}
    for i in _star_count:
        notes[str(i)] = {
            "lo": _star_range_lo[i] if i < _star_range_lo.size() else 0,
            "hi": _star_range_hi[i] if i < _star_range_hi.size() else 0,
            "name_states": (_name_states[i] if i < _name_states.size() else {}).duplicate(),
        }
    notes["adjacency_states"] = _adjacency_states.duplicate()
    notes["name_tab_order"] = _name_tab_order.duplicate()
    notes["name_color_states"] = _name_color_states.duplicate(true)
    notes["name_pitch_states"] = _name_pitch_states.duplicate(true)
    _cd.set_player_puzzle_notes(_constellation_id, notes)


# ==================================================
# MARKERS PANEL
# ==================================================
func _set_marker_tab(tab_idx: int) -> void:
    _active_marker_tab = tab_idx
    _tab_color.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 0 else _sb_tab_inactive)
    _tab_sequence.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 1 else _sb_tab_inactive)
    _tab_adjacency.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 2 else _sb_tab_inactive)
    _tab_name.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 3 else _sb_tab_inactive)
    _tab_pitch.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 4 else _sb_tab_inactive)
    _populate_markers_panel()


func _populate_markers_panel() -> void:
    for child in _markers_content.get_children():
        child.queue_free()

    match _active_marker_tab:
        0: _populate_color_markers()
        1: _populate_sequence_markers()
        2: _populate_adjacency_markers()
        3: _populate_name_markers()
        4: _populate_pitch_markers()


func _populate_color_markers() -> void:
    var entries: Array = []
    for i in _star_count:
        var ci: int = clamp(_star_colors[i] if i < _star_colors.size() else 1, 0, 3)
        entries.append({"seq": _sequence_number(i), "color": ci, "idx": i})
    entries.sort_custom(func(a, b): return a["seq"] < b["seq"])

    var reveal_count: int = maxi(2, int(_star_count * 0.4))
    var reveal_order: Array = range(_star_count)
    reveal_order.sort_custom(func(a, b):
        var ha: int = (int(a) * 2654435761 + _constellation_id * 40503) & 0x7FFFFFFF
        var hb: int = (int(b) * 2654435761 + _constellation_id * 40503) & 0x7FFFFFFF
        return ha < hb)
    var revealed: Dictionary = {}
    for i in mini(reveal_count, reveal_order.size()):
        revealed[reveal_order[i]] = true

    var negation_by_star: Dictionary = {}
    for entry in _color_negation_cache:
        negation_by_star[int(entry.get("s", -1))] = str(entry.get("text", ""))

    for entry in entries:
        var idx: int = entry["idx"]
        var ci: int = entry["color"]
        if revealed.has(idx):
            var col: Color = STAR_COLORS_BY_IDX[ci]
            var text: String = "The %s is a %s star." % [_ordinal(entry["seq"]), COLOR_NAME_LABELS[ci]]
            _markers_content.add_child(_make_clue_label(text, col))
        elif negation_by_star.has(idx):
            var neutral_col := Color(0.55, 0.50, 0.65, 1)
            _markers_content.add_child(_make_clue_label(str(negation_by_star[idx]), neutral_col))


func _populate_sequence_markers() -> void:
    var shown: bool = false
    for clue in _final_clues_cache:
        var kind: String = str(clue.get("kind", ""))
        if kind != "cmp" and kind != "adj_seq" and kind != "extreme" and kind != "exact" and kind != "cmp_dist" and kind != "neg_exact" and kind != "neg_adjacent":
            continue
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        _markers_content.add_child(_make_clue_label(text, Color(0.82, 0.78, 0.92, 1)))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Sequence clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _populate_adjacency_markers() -> void:
    var shown: bool = false
    for text in _distance_flavor_cache:
        if str(text) == "":
            continue
        _markers_content.add_child(_make_clue_label(str(text), Color(0.82, 0.78, 0.92, 1)))
        shown = true
    for text in _between_flavor_cache:
        if str(text) == "":
            continue
        _markers_content.add_child(_make_clue_label(str(text), Color(0.82, 0.78, 0.92, 1)))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Adjacency clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _sort_matches(mode: int) -> void:
    _matches_sort_mode = mode
    match mode:
        0:  # Alphabetical Name
            _name_tab_order.sort_custom(func(a, b): return a.nocasecmp_to(b) < 0)
        1:  # Ordinal Sequence
            _name_tab_order.sort_custom(func(a, b):
                var sa: int = _find_star_for_confirmed_name(a)
                var sb: int = _find_star_for_confirmed_name(b)
                if sa < 0 and sb < 0: return a.nocasecmp_to(b) < 0
                if sa < 0: return false
                if sb < 0: return true
                return _sequence_number(sa) < _sequence_number(sb))
        2:  # Alphabetical Color
            _name_tab_order.sort_custom(func(a, b):
                var sa: int = _find_star_for_confirmed_name(a)
                var sb: int = _find_star_for_confirmed_name(b)
                if sa < 0 and sb < 0: return a.nocasecmp_to(b) < 0
                if sa < 0: return false
                if sb < 0: return true
                var ca: String = COLOR_NAME_LABELS[clamp(_star_colors[sa] if sa < _star_colors.size() else 1, 0, 3)]
                var cb: String = COLOR_NAME_LABELS[clamp(_star_colors[sb] if sb < _star_colors.size() else 1, 0, 3)]
                if ca == cb: return a.nocasecmp_to(b) < 0
                return ca.nocasecmp_to(cb) < 0)
        3:  # High-Low Pitch
            _name_tab_order.sort_custom(func(a, b):
                var sa: int = _find_star_for_confirmed_name(a)
                var sb: int = _find_star_for_confirmed_name(b)
                if sa < 0 and sb < 0: return a.nocasecmp_to(b) < 0
                if sa < 0: return false
                if sb < 0: return true
                var pa: int = _star_pitch_index[sa] if sa < _star_pitch_index.size() else -1
                var pb: int = _star_pitch_index[sb] if sb < _star_pitch_index.size() else -1
                var fa: float = _pitch_freqs[pa] if pa >= 0 and pa < _pitch_freqs.size() else 0.0
                var fb: float = _pitch_freqs[pb] if pb >= 0 and pb < _pitch_freqs.size() else 0.0
                if fa == fb: return a.nocasecmp_to(b) < 0
                return fa < fb)
    _save_puzzle_notes()
    _populate_name_markers()


func _populate_sequence_ordinal_rows() -> void:
    var header_row := HBoxContainer.new()
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(58, 0)
    header_row.add_child(spacer)
    var names_heading := Label.new()
    names_heading.text = "Names"
    names_heading.add_theme_font_size_override("font_size", 14)
    names_heading.add_theme_color_override("font_color", Color(0.75, 0.7, 0.9, 0.9))
    header_row.add_child(names_heading)
    _markers_content.add_child(header_row)
    _markers_content.add_child(HSeparator.new())

    for slot in range(1, _star_count + 1):
        var star_idx: int = _star_for_exact_sequence(slot)
        var confirmed_name: String = _confirmed_name_for_star(star_idx) if star_idx >= 0 else ""

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _markers_content.add_child(row)

        var ord_lbl := Label.new()
        ord_lbl.text = _ordinal(slot)
        ord_lbl.custom_minimum_size = Vector2(50, 0)
        ord_lbl.add_theme_font_size_override("font_size", 18)
        row.add_child(ord_lbl)

        var name_edit := LineEdit.new()
        name_edit.custom_minimum_size = Vector2(110, 0)
        name_edit.editable = star_idx >= 0
        name_edit.placeholder_text = "pin sequence first" if star_idx < 0 else "type a name"
        name_edit.text = confirmed_name
        row.add_child(name_edit)

        var facts_vbox := VBoxContainer.new()
        facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        facts_vbox.add_theme_constant_override("separation", 1)
        row.add_child(facts_vbox)

        if star_idx < 0 or confirmed_name.is_empty():
            var unknown_col := Color(0.55, 0.50, 0.65, 1)
            ord_lbl.add_theme_color_override("font_color", Color(0.65, 0.60, 0.75, 1))
            facts_vbox.add_child(_make_fact_line("Color: ?", unknown_col))
            facts_vbox.add_child(_make_fact_line("Pitch: ?", unknown_col))
            facts_vbox.add_child(_make_fact_line("Adjacent: ?", unknown_col))
        else:
            var ci: int = clamp(_star_colors[star_idx] if star_idx < _star_colors.size() else 1, 0, 3)
            var col: Color = STAR_COLORS_BY_IDX[ci]
            ord_lbl.add_theme_color_override("font_color", col)
            facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row(confirmed_name), col))
            facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row(confirmed_name), col))
            facts_vbox.add_child(_make_fact_line("Adjacent: %s" % _describe_neighbors(star_idx), col))

        var si := star_idx
        var edit_ref := name_edit
        name_edit.text_submitted.connect(func(_t): _on_ordinal_name_committed(si, edit_ref))
        name_edit.focus_exited.connect(func(): _on_ordinal_name_committed(si, edit_ref))

        _markers_content.add_child(HSeparator.new())


func _populate_name_markers() -> void:
    for child in _markers_content.get_children():
        child.queue_free()
    _name_row_controls.clear()

    var sort_row := HBoxContainer.new()
    sort_row.add_theme_constant_override("separation", 4)
    sort_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sort_labels: Array = ["Name", "Sequence", "Color", "Pitch"]
    for i in sort_labels.size():
        var btn := Button.new()
        btn.text = "Sort: %s" % sort_labels[i]
        btn.add_theme_font_size_override("font_size", 12)
        btn.focus_mode = Control.FOCUS_NONE
        var mode := i
        btn.pressed.connect(func(): _sort_matches(mode))
        sort_row.add_child(btn)
    _markers_content.add_child(sort_row)
    _markers_content.add_child(HSeparator.new())

    if _matches_sort_mode == 1:
        _populate_sequence_ordinal_rows()
        return

    for name_str in _name_tab_order:
        var confirmed_star: int = _find_star_for_confirmed_name(name_str)

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.mouse_filter = Control.MOUSE_FILTER_STOP
        _markers_content.add_child(row)
        _name_row_controls.append(row)

        var grip_lbl := Label.new()
        grip_lbl.text = "\u2261"
        grip_lbl.custom_minimum_size = Vector2(18, 0)
        grip_lbl.add_theme_font_size_override("font_size", 16)
        grip_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.65, 0.7))
        grip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(grip_lbl)

        var name_lbl := Label.new()
        name_lbl.text = name_str
        name_lbl.custom_minimum_size = Vector2(90, 0)
        name_lbl.add_theme_font_size_override("font_size", 18)
        name_lbl.clip_text = true
        name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(name_lbl)

        var facts_vbox := VBoxContainer.new()
        facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        facts_vbox.add_theme_constant_override("separation", 1)
        facts_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(facts_vbox)

        if confirmed_star < 0:
            var unknown_col := Color(0.55, 0.50, 0.65, 1)
            name_lbl.add_theme_color_override("font_color", Color(0.65, 0.60, 0.75, 1))
            facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row(name_str), unknown_col))
            facts_vbox.add_child(_make_fact_line("Sequence: ?", unknown_col))
            facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row(name_str), unknown_col))
            facts_vbox.add_child(_make_fact_line("Adjacent: ?", unknown_col))
        else:
            var ci: int = clamp(_star_colors[confirmed_star] if confirmed_star < _star_colors.size() else 1, 0, 3)
            var col: Color = STAR_COLORS_BY_IDX[ci]
            name_lbl.add_theme_color_override("font_color", col)
            facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row(name_str), col))
            facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row(confirmed_star, col), col))
            facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row(name_str), col))
            facts_vbox.add_child(_make_fact_line("Adjacent: %s" % _describe_neighbors(confirmed_star), col))

        if _name_drag_idx >= 0 and _name_drag_idx < _name_tab_order.size() and _name_tab_order[_name_drag_idx] == name_str:
            row.modulate = Color(1, 1, 1, 0.55)

        var row_idx := _name_row_controls.size() - 1
        row.gui_input.connect(func(event):
            if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                _on_name_row_pressed(row_idx))

        _markers_content.add_child(HSeparator.new())


func _populate_pitch_markers() -> void:
    var shown: bool = false
    for text in _pitch_flavor_cache:
        if str(text) == "":
            continue
        _markers_content.add_child(_make_clue_label(str(text), Color(0.82, 0.78, 0.92, 1)))
        shown = true

    var neutral_col := Color(0.55, 0.50, 0.65, 1)
    for entry in _pitch_negation_cache:
        var text: String = str(entry.get("text", ""))
        if text == "":
            continue
        _markers_content.add_child(_make_clue_label(text, neutral_col))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Pitch clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _on_name_confirmed(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, col: Color) -> void:
    if star_idx >= _name_states.size():
        return
    var ci: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var cur: int = int(_name_states[star_idx].get(star_name, 0))
    var new_state: int = 0 if cur == 1 else 1
    _name_states[star_idx][star_name] = new_state
    btn_check.modulate = Color(0.3, 1.0, 0.4, 1.0) if new_state == 1 else Color(1,1,1,0.45)
    name_lbl.add_theme_color_override("font_color", col if new_state != 2 else Color(0.35,0.30,0.45,0.5))
    if new_state == 1:
        _propagate_name_confirmed(star_idx, star_name, ci)
        return
    _save_puzzle_notes()


func _on_adjacency_check(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_adjacency_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 1 else 1
    _adjacency_states[edge_key] = new_state
    btn_check.modulate = Color(0.3, 1.0, 0.4, 1.0) if new_state == 1 else Color(1,1,1,0.45)
    btn_x.modulate = Color(1,1,1,0.45)
    _save_puzzle_notes()


func _on_adjacency_x(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_adjacency_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 2 else 2
    _adjacency_states[edge_key] = new_state
    btn_x.modulate = Color(1.0, 0.35, 0.25, 1.0) if new_state == 2 else Color(1,1,1,0.45)
    btn_check.modulate = Color(1,1,1,0.45)
    _save_puzzle_notes()



# ==================================================
# FLOATING STAR WIDGETS
# ==================================================
func _build_star_widgets() -> void:
    # Tear down any previous widgets.
    for w in _star_widgets:
        if is_instance_valid(w):
            w.queue_free()
    _star_widgets.clear()

    if _star_screen_pos.is_empty():
        return

    for i in _star_count:
        var color_idx: int = _star_colors[i] if i < _star_colors.size() else 1
        var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

        # Root container — no background, just a layout anchor.
        var root := VBoxContainer.new()
        root.mouse_filter = Control.MOUSE_FILTER_PASS
        root.add_theme_constant_override("separation", 4)
        _star_map_control.add_child(root)
        _star_widgets.append(root)
        root.visible = (i == _selected_star)

        # ── Range row ──────────────────────────────────────────────
        var range_row := HBoxContainer.new()
        range_row.mouse_filter = Control.MOUSE_FILTER_PASS
        range_row.add_theme_constant_override("separation", 3)

        var lbl_gt := Label.new()
        lbl_gt.text = ">"
        lbl_gt.add_theme_font_size_override("font_size", 15)
        lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
        lbl_gt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_gt)

        var edit_lo := LineEdit.new()
        edit_lo.custom_minimum_size = Vector2(38, 28)
        edit_lo.max_length = 2
        edit_lo.placeholder_text = "\u2013"
        edit_lo.text = str(_star_range_lo[i]) if _star_range_lo[i] > 0 else ""
        edit_lo.add_theme_font_size_override("font_size", 15)
        _style_range_edit(edit_lo, star_color)
        range_row.add_child(edit_lo)

        var lbl_lt := Label.new()
        lbl_lt.text = "<"
        lbl_lt.add_theme_font_size_override("font_size", 15)
        lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
        lbl_lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_lt)

        var edit_hi := LineEdit.new()
        edit_hi.custom_minimum_size = Vector2(38, 28)
        edit_hi.max_length = 2
        edit_hi.placeholder_text = "\u2013"
        edit_hi.text = str(_star_range_hi[i]) if _star_range_hi[i] > 0 else ""
        edit_hi.add_theme_font_size_override("font_size", 15)
        _style_range_edit(edit_hi, star_color)
        range_row.add_child(edit_hi)

        root.add_child(range_row)

        # Capture index for lambdas.
        var si := i
        var lo_ref := edit_lo
        var hi_ref := edit_hi
        edit_lo.text_submitted.connect(func(_t): _on_range_committed(si, lo_ref, hi_ref))
        edit_lo.focus_exited.connect(func(): _on_range_committed(si, lo_ref, hi_ref))
        edit_hi.text_submitted.connect(func(_t): _on_range_committed(si, lo_ref, hi_ref))
        edit_hi.focus_exited.connect(func(): _on_range_committed(si, lo_ref, hi_ref))

        # ── Name checklist ─────────────────────────────────────────
        # List every star name — color is one of the facts to deduce,
        # so the checklist must not pre-filter by it.
        var all_star_names: Array[String] = []
        for j in _star_count:
            all_star_names.append(_star_names[j] if j < _star_names.size() else "?")

        if not all_star_names.is_empty():
            var scroll := ScrollContainer.new()
            scroll.custom_minimum_size = Vector2(0, 0)
            scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            # Height capped at WIDGET_NAME_MAX_H but shrinks if fewer names.
            var row_h: float = 30.0
            var natural_h: float = all_star_names.size() * row_h
            scroll.custom_minimum_size = Vector2(160, minf(natural_h, WIDGET_NAME_MAX_H))
            scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
            root.add_child(scroll)

            var name_vbox := VBoxContainer.new()
            name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            scroll.add_child(name_vbox)

            for name_str in all_star_names:
                var row := HBoxContainer.new()
                row.mouse_filter = Control.MOUSE_FILTER_PASS
                row.add_theme_constant_override("separation", 3)

                var name_lbl := Label.new()
                name_lbl.text = name_str
                name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                name_lbl.add_theme_font_size_override("font_size", 16)
                name_lbl.add_theme_color_override("font_color", star_color)
                name_lbl.clip_text = true
                row.add_child(name_lbl)

                var btn_check := Button.new()
                btn_check.text = "\u2713"
                btn_check.custom_minimum_size = Vector2(28, 26)
                btn_check.focus_mode = Control.FOCUS_NONE
                btn_check.add_theme_font_size_override("font_size", 15)
                row.add_child(btn_check)

                var btn_x := Button.new()
                btn_x.text = "\u2717"
                btn_x.custom_minimum_size = Vector2(28, 26)
                btn_x.focus_mode = Control.FOCUS_NONE
                btn_x.add_theme_font_size_override("font_size", 15)
                row.add_child(btn_x)

                name_vbox.add_child(row)

                # Capture for lambda — name_str is already a value copy in for loop.
                var captured_name := name_str
                btn_check.pressed.connect(func(): _on_name_check(si, captured_name, name_lbl, btn_check, btn_x))
                btn_x.pressed.connect(func(): _on_name_x(si, captured_name, name_lbl, btn_check, btn_x))

            # Apply saved state to name rows immediately.
            _refresh_name_widget(i, name_vbox, all_star_names, star_color)

    _reposition_star_widgets()


func _style_range_edit(edit: LineEdit, star_color: Color) -> void:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.06, 0.04, 0.14, 0.85)
    sb.border_color = Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 0.7)
    sb.border_width_left = 1; sb.border_width_top = 1
    sb.border_width_right = 1; sb.border_width_bottom = 1
    sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
    sb.corner_radius_bottom_right = 2; sb.corner_radius_bottom_left = 2
    sb.content_margin_left = 3; sb.content_margin_right = 3
    sb.content_margin_top = 1; sb.content_margin_bottom = 1
    edit.add_theme_stylebox_override("normal", sb)
    edit.add_theme_stylebox_override("focus", sb)
    edit.add_theme_color_override("font_color", Color(0.90, 0.87, 1.00, 1.0))
    edit.add_theme_color_override("font_placeholder_color", Color(0.40, 0.35, 0.60, 0.6))


func _sequence_number(star_idx: int) -> int:
    if star_idx >= 0 and star_idx < _pitch_rank_solution.size():
        return _pitch_rank_solution[star_idx] + 1
    return star_idx + 1


func _confirmed_sequence_str(star_idx: int) -> String:
    if star_idx < 0 or star_idx >= _star_range_lo.size() or star_idx >= _star_range_hi.size():
        return "?"
    var lo_i: int = _star_range_lo[star_idx]
    var hi_i: int = _star_range_hi[star_idx]
    if lo_i > 0 and lo_i == hi_i:
        return str(lo_i)
    return "?"


func _ordinal(n: int) -> String:
    var mod100: int = n % 100
    if mod100 >= 11 and mod100 <= 13:
        return "%dth note" % n
    match n % 10:
        1: return "%dst note" % n
        2: return "%dnd note" % n
        3: return "%drd note" % n
        _: return "%dth note" % n


func _ordinal_str(raw: String) -> String:
    if raw == "?" or not raw.is_valid_int():
        return raw
    return _ordinal(int(raw))


func _find_star_for_confirmed_name(name_str: String) -> int:
    for i in _star_count:
        if i < _name_states.size() and int(_name_states[i].get(name_str, 0)) == 1:
            return i
    return -1


func _note_name_for_star(star_idx: int) -> String:
    if star_idx < 0 or star_idx >= _star_pitch_index.size():
        return "?"
    var p: int = _star_pitch_index[star_idx]
    if p < 0 or p >= _pitch_freqs.size():
        return "?"
    return ConstellationLogicPuzzle.note_name_for_freq(_pitch_freqs[p])


func _distinct_note_names() -> Array[String]:
    var uniq_freqs: Array = []
    for f in _pitch_freqs:
        if not uniq_freqs.has(f):
            uniq_freqs.append(f)
    uniq_freqs.sort()
    var names: Array[String] = []
    for f in uniq_freqs:
        names.append(ConstellationLogicPuzzle.note_name_for_freq(f))
    return names


func _star_for_exact_sequence(slot: int) -> int:
    for i in _star_count:
        if i < _star_range_lo.size() and i < _star_range_hi.size():
            if _star_range_lo[i] == slot and _star_range_hi[i] == slot:
                return i
    return -1


func _on_ordinal_name_committed(star_idx: int, name_edit: LineEdit) -> void:
    if star_idx < 0:
        return
    var entered: String = name_edit.text.strip_edges()
    if entered.is_empty() or not _star_names.has(entered):
        return
    if star_idx >= _name_states.size():
        return
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    _name_states[star_idx][entered] = 1
    _propagate_name_confirmed(star_idx, entered, color_idx)


func _make_color_toggle_row(name_str: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    for ci in COLOR_NAME_LABELS.size():
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(26, 24)
        btn.focus_mode = Control.FOCUS_NONE
        btn.add_theme_font_size_override("font_size", 13)
        var cidx := ci
        btn.pressed.connect(func(): _on_name_color_toggle(name_str, cidx, btn))
        _style_color_toggle_btn(btn, cidx, int(_name_color_states.get(name_str, {}).get(cidx, 0)))
        row.add_child(btn)
    return row


func _style_color_toggle_btn(btn: Button, color_idx: int, state: int) -> void:
    var base_col: Color = STAR_COLORS_BY_IDX[color_idx]
    var letter: String = COLOR_NAME_LABELS[color_idx].substr(0, 1)
    match state:
        1:  # confirmed
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter + "\u2713"
        2:  # eliminated
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 0.3)
            btn.text = letter + "\u2717"
        _:  # neutral
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 0.6)
            btn.text = letter


func _on_name_color_toggle(name_str: String, color_idx: int, btn: Button) -> void:
    if not _name_color_states.has(name_str):
        _name_color_states[name_str] = {}
    var cur: int = int(_name_color_states[name_str].get(color_idx, 0))
    var new_state: int = (cur + 1) % 3
    _name_color_states[name_str][color_idx] = new_state
    _style_color_toggle_btn(btn, color_idx, new_state)
    _save_puzzle_notes()


func _make_pitch_carousel_row(name_str: String) -> HBoxContainer:
    var notes_list: Array[String] = _distinct_note_names()
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    if notes_list.is_empty():
        var empty_lbl := Label.new()
        empty_lbl.text = "?"
        row.add_child(empty_lbl)
        return row

    var btn_prev := Button.new()
    btn_prev.text = "\u25c0"
    btn_prev.custom_minimum_size = Vector2(24, 24)
    btn_prev.focus_mode = Control.FOCUS_NONE
    row.add_child(btn_prev)

    var note_lbl := Label.new()
    note_lbl.custom_minimum_size = Vector2(36, 0)
    note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note_lbl.add_theme_font_size_override("font_size", 14)
    row.add_child(note_lbl)

    var btn_next := Button.new()
    btn_next.text = "\u25b6"
    btn_next.custom_minimum_size = Vector2(24, 24)
    btn_next.focus_mode = Control.FOCUS_NONE
    row.add_child(btn_next)

    var btn_mark := Button.new()
    btn_mark.custom_minimum_size = Vector2(28, 24)
    btn_mark.focus_mode = Control.FOCUS_NONE
    btn_mark.add_theme_font_size_override("font_size", 13)
    row.add_child(btn_mark)

    var refresh_carousel := func():
        var i: int = int(_name_pitch_carousel_idx.get(name_str, 0)) % notes_list.size()
        var note: String = notes_list[i]
        var state: int = int(_name_pitch_states.get(name_str, {}).get(note, 0))
        note_lbl.text = note
        match state:
            1:
                note_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
                btn_mark.text = "\u2713"
            2:
                note_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25, 1.0))
                btn_mark.text = "\u2717"
            _:
                note_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.95, 1.0))
                btn_mark.text = "\u2022"

    btn_prev.pressed.connect(func():
        var i: int = int(_name_pitch_carousel_idx.get(name_str, 0))
        _name_pitch_carousel_idx[name_str] = (i - 1 + notes_list.size()) % notes_list.size()
        refresh_carousel.call())
    btn_next.pressed.connect(func():
        var i: int = int(_name_pitch_carousel_idx.get(name_str, 0))
        _name_pitch_carousel_idx[name_str] = (i + 1) % notes_list.size()
        refresh_carousel.call())
    btn_mark.pressed.connect(func():
        var i: int = int(_name_pitch_carousel_idx.get(name_str, 0)) % notes_list.size()
        var note: String = notes_list[i]
        if not _name_pitch_states.has(name_str):
            _name_pitch_states[name_str] = {}
        var cur: int = int(_name_pitch_states[name_str].get(note, 0))
        _name_pitch_states[name_str][note] = (cur + 1) % 3
        _save_puzzle_notes()
        refresh_carousel.call())

    refresh_carousel.call()
    return row


func _make_sequence_range_row(star_idx: int, star_color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)

    var lbl_gt := Label.new()
    lbl_gt.text = ">"
    lbl_gt.add_theme_font_size_override("font_size", 14)
    lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_gt)

    var edit_lo := LineEdit.new()
    edit_lo.custom_minimum_size = Vector2(34, 24)
    edit_lo.max_length = 2
    edit_lo.placeholder_text = "\u2013"
    edit_lo.text = str(_star_range_lo[star_idx]) if star_idx < _star_range_lo.size() and _star_range_lo[star_idx] > 0 else ""
    edit_lo.add_theme_font_size_override("font_size", 13)
    _style_range_edit(edit_lo, star_color)
    row.add_child(edit_lo)

    var lbl_lt := Label.new()
    lbl_lt.text = "<"
    lbl_lt.add_theme_font_size_override("font_size", 14)
    lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_lt)

    var edit_hi := LineEdit.new()
    edit_hi.custom_minimum_size = Vector2(34, 24)
    edit_hi.max_length = 2
    edit_hi.placeholder_text = "\u2013"
    edit_hi.text = str(_star_range_hi[star_idx]) if star_idx < _star_range_hi.size() and _star_range_hi[star_idx] > 0 else ""
    edit_hi.add_theme_font_size_override("font_size", 13)
    _style_range_edit(edit_hi, star_color)
    row.add_child(edit_hi)

    edit_lo.text_submitted.connect(func(_t): _on_range_committed(star_idx, edit_lo, edit_hi))
    edit_lo.focus_exited.connect(func(): _on_range_committed(star_idx, edit_lo, edit_hi))
    edit_hi.text_submitted.connect(func(_t): _on_range_committed(star_idx, edit_lo, edit_hi))
    edit_hi.focus_exited.connect(func(): _on_range_committed(star_idx, edit_lo, edit_hi))

    return row


func _confirmed_name_for_star(star_idx: int) -> String:
    if star_idx < 0 or star_idx >= _name_states.size():
        return ""
    for key in _name_states[star_idx].keys():
        if int(_name_states[star_idx][key]) == 1:
            return str(key)
    return ""


func _describe_neighbors(star_idx: int) -> String:
    if not _cd or _constellation_id < 0:
        return "none"
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    var line_pairs: Array = def.get("line_pairs", [])
    var parts: Array[String] = []
    var lk: int = 0
    while lk < line_pairs.size() - 1:
        var ea: int = int(line_pairs[lk])
        var eb: int = int(line_pairs[lk + 1])
        lk += 2
        if ea != star_idx and eb != star_idx:
            continue
        var other: int = eb if ea == star_idx else ea
        var other_ci: int = clamp(_star_colors[other] if other < _star_colors.size() else 1, 0, 3)
        var other_seq: String = _ordinal_str(_confirmed_sequence_str(other))
        var other_name: String = _confirmed_name_for_star(other)
        if other_name == "":
            other_name = "?"
        parts.append("%s (%s, Seq %s)" % [other_name, COLOR_NAME_LABELS[other_ci], other_seq])

    if parts.is_empty():
        return "none"
    var joined: String = ""
    for k in parts.size():
        joined += parts[k]
        if k < parts.size() - 1:
            joined += "; "
    return joined


func _reposition_star_widgets() -> void:
    var map_h: float = _star_map_control.size.y
    for i in _star_widgets.size():
        if i >= _star_screen_pos.size():
            break
        var w: Control = _star_widgets[i]
        if not is_instance_valid(w):
            continue
        # Force a minimum size pass so we know the widget's height.
        w.reset_size()
        var wh: float = w.get_combined_minimum_size().y
        var dot: Vector2 = _star_screen_pos[i]
        var flip_up: bool = dot.y + WIDGET_OFFSET_BELOW + wh > map_h
        var pos_y: float
        if flip_up:
            pos_y = dot.y - wh - WIDGET_OFFSET_ABOVE
        else:
            pos_y = dot.y + WIDGET_OFFSET_BELOW
        # Centre the widget horizontally on the dot, clamped to map bounds.
        var ww: float = w.get_combined_minimum_size().x
        var pos_x: float = clampf(dot.x - ww * 0.5, 0.0, maxf(0.0, _star_map_control.size.x - ww))
        w.position = Vector2(pos_x, pos_y)


func _build_star_tags() -> void:
    for t in _star_tags:
        if is_instance_valid(t):
            t.queue_free()
    _star_tags.clear()

    if _star_screen_pos.is_empty():
        return

    for i in _star_count:
        var color_idx: int = _star_colors[i] if i < _star_colors.size() else 1
        var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

        var root := Control.new()
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _star_map_control.add_child(root)
        _star_tags.append(root)

        var vbox := VBoxContainer.new()
        vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        vbox.add_theme_constant_override("separation", 1)
        root.add_child(vbox)

        var hbox := HBoxContainer.new()
        hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hbox.add_theme_constant_override("separation", 4)
        root.add_child(hbox)

        var name_str: String = _confirmed_name_for_star(i)
        if name_str == "":
            name_str = "?"
        var seq_str: String = _confirmed_sequence_str(i)

        var name_lbl := Label.new()
        name_lbl.name = "NameLabel"
        name_lbl.text = name_str
        name_lbl.add_theme_font_size_override("font_size", 12)
        name_lbl.add_theme_color_override("font_color", star_color)
        name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var seq_lbl := Label.new()
        seq_lbl.name = "SeqLabel"
        seq_lbl.text = "%s" % _ordinal_str(seq_str)
        seq_lbl.add_theme_font_size_override("font_size", 11)
        seq_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        seq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        vbox.add_child(name_lbl.duplicate())
        vbox.add_child(seq_lbl.duplicate())
        hbox.add_child(name_lbl)
        hbox.add_child(seq_lbl)

    _reposition_star_tags()


func _reposition_star_tags() -> void:
    var map_w: float = _star_map_control.size.x
    var map_h: float = _star_map_control.size.y
    for i in _star_tags.size():
        if i >= _star_screen_pos.size():
            break
        var root: Control = _star_tags[i]
        if not is_instance_valid(root):
            continue
        var vbox: VBoxContainer = root.get_child(0)
        var hbox: HBoxContainer = root.get_child(1)
        var dot: Vector2 = _star_screen_pos[i]

        vbox.reset_size()
        var stacked_h: float = vbox.get_combined_minimum_size().y
        var fits_below: bool = dot.y + TAG_OFFSET_BELOW + stacked_h <= map_h
        var fits_above: bool = dot.y - TAG_OFFSET_ABOVE - stacked_h >= 0.0

        if fits_below or fits_above:
            vbox.visible = true
            hbox.visible = false
            var vw: float = vbox.get_combined_minimum_size().x
            var pos_y: float = dot.y + TAG_OFFSET_BELOW if fits_below else dot.y - TAG_OFFSET_ABOVE - stacked_h
            var pos_x: float = clampf(dot.x - vw * 0.5, 0.0, maxf(0.0, map_w - vw))
            root.position = Vector2(pos_x, pos_y)
        else:
            vbox.visible = false
            hbox.visible = true
            hbox.reset_size()
            var hw: float = hbox.get_combined_minimum_size().x
            var hh: float = hbox.get_combined_minimum_size().y
            var pos_y2: float = dot.y - hh * 0.5
            var fits_right: bool = dot.x + TAG_OFFSET_SIDE + hw <= map_w
            var pos_x2: float
            if fits_right:
                pos_x2 = dot.x + TAG_OFFSET_SIDE
            else:
                pos_x2 = dot.x - TAG_OFFSET_SIDE - hw
            root.position = Vector2(pos_x2, pos_y2)


func _refresh_name_widget(star_idx: int, name_vbox: VBoxContainer,
        all_star_names: Array[String], star_color: Color) -> void:
    if star_idx >= _name_states.size():
        return
    var states: Dictionary = _name_states[star_idx]
    var rows: Array = name_vbox.get_children()
    for ri in rows.size():
        if ri >= all_star_names.size():
            break
        var row: HBoxContainer = rows[ri]
        var name_lbl: Label = row.get_child(0)
        var btn_check: Button = row.get_child(1)
        var btn_x: Button = row.get_child(2)
        var captured_name: String = all_star_names[ri]
        var state: int = int(states.get(captured_name, 0))
        _apply_name_row_visual(state, name_lbl, btn_check, btn_x, star_color)


func _apply_name_row_visual(state: int, name_lbl: Label,
        btn_check: Button, btn_x: Button, star_color: Color) -> void:
    match state:
        1:  # confirmed ✓
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(0.3, 1.0, 0.4, 1.0)
            btn_x.modulate = Color(1, 1, 1, 0.4)
        2:  # eliminated ✗
            name_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.45, 0.5))
            name_lbl.modulate = Color(1, 1, 1, 0.45)
            btn_check.modulate = Color(1, 1, 1, 0.4)
            btn_x.modulate = Color(1.0, 0.35, 0.25, 1.0)
        _:  # neutral
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 0.85))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(1, 1, 1, 0.55)
            btn_x.modulate = Color(1, 1, 1, 0.55)


# ==================================================
# NAME STATE CALLBACKS
# ==================================================
func _on_name_check(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    if star_idx >= _name_states.size():
        return
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = int(_name_states[star_idx].get(star_name, 0))
    var new_state: int = 0 if cur == 1 else 1
    _name_states[star_idx][star_name] = new_state

    if new_state == 1:
        _propagate_name_confirmed(star_idx, star_name, color_idx)
        return

    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)
    _save_puzzle_notes()
    _build_star_tags()
    if _active_marker_tab == 3:
        _populate_markers_panel()


func _on_name_x(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    if star_idx >= _name_states.size():
        return
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = int(_name_states[star_idx].get(star_name, 0))
    var new_state: int = 0 if cur == 2 else 2
    _name_states[star_idx][star_name] = new_state
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)

    _save_puzzle_notes()
    _build_star_tags()


func _propagate_name_confirmed(confirmed_star: int, star_name: String, color_idx: int) -> void:
    # Cross-star: this name can no longer belong to any other same-color star.
    for j in _star_count:
        if j == confirmed_star:
            continue
        var jcol: int = _star_colors[j] if j < _star_colors.size() else 1
        if jcol != color_idx:
            continue
        if j >= _name_states.size():
            continue
        var cur_j: int = int(_name_states[j].get(star_name, 0))
        if cur_j != 2:
            _name_states[j][star_name] = 2

    # Within-star: confirming one name rules out every other same-color
    # candidate name for THIS star — a star can only have one name.
    if confirmed_star < _name_states.size():
        for j in _star_count:
            var jcol2: int = _star_colors[j] if j < _star_colors.size() else 1
            if jcol2 != color_idx:
                continue
            var other_name: String = _star_names[j] if j < _star_names.size() else ""
            if other_name == "" or other_name == star_name:
                continue
            _name_states[confirmed_star][other_name] = 2

    _save_puzzle_notes()

    call_deferred("_build_star_widgets")
    call_deferred("_build_star_tags")
    if _active_marker_tab == 3:
        call_deferred("_populate_markers_panel")


# ==================================================
# RANGE CALLBACKS
# ==================================================
func _on_range_committed(star_idx: int, lo_edit: LineEdit, hi_edit: LineEdit) -> void:
    if star_idx >= _star_range_lo.size():
        return

    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    var lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    # Clamp to valid 1..star_count range; 0 means unset.
    if lo < 1 or lo > _star_count: lo = 0
    if hi < 1 or hi > _star_count: hi = 0

    # Swap if inverted.
    if lo > 0 and hi > 0 and lo > hi:
        var tmp := lo; lo = hi; hi = tmp

    _star_range_lo[star_idx] = lo
    _star_range_hi[star_idx] = hi

    # Sync display back (normalised values).
    lo_edit.text = str(lo) if lo > 0 else ""
    hi_edit.text = str(hi) if hi > 0 else ""

    # Propagate exact assertions: if lo == hi, that position is claimed.
    if lo > 0 and lo == hi:
        _propagate_range_exact(star_idx, lo)

    _save_puzzle_notes()
    _build_star_tags()
    if _active_marker_tab == 1:
        _populate_markers_panel()
    if _active_marker_tab == 3:
        _populate_markers_panel()


func _propagate_range_exact(confirmed_star: int, exact_pos: int) -> void:
    # If another star has a range that is exactly this position, clear it
    # (contradiction). If their lo or hi equals this position, clamp them away.
    for j in _star_count:
        if j == confirmed_star:
            continue
        if j >= _star_range_lo.size():
            continue
        var jlo: int = _star_range_lo[j]
        var jhi: int = _star_range_hi[j]
        if jlo == exact_pos and jhi == exact_pos:
            # Exact contradiction \u2014 clear.
            _star_range_lo[j] = 0
            _star_range_hi[j] = 0
        elif jlo == exact_pos:
            _star_range_lo[j] = exact_pos + 1 if exact_pos + 1 <= _star_count else 0
        elif jhi == exact_pos:
            _star_range_hi[j] = exact_pos - 1 if exact_pos - 1 >= 1 else 0
        # Rebuild that star's LineEdit displays.
        if j < _star_widgets.size() and is_instance_valid(_star_widgets[j]):
            var range_row: HBoxContainer = _star_widgets[j].get_child(0)
            if range_row and range_row.get_child_count() >= 4:
                var lo_edit: LineEdit = range_row.get_child(1)
                var hi_edit: LineEdit = range_row.get_child(3)
                lo_edit.text = str(_star_range_lo[j]) if _star_range_lo[j] > 0 else ""
                hi_edit.text = str(_star_range_hi[j]) if _star_range_hi[j] > 0 else ""



# ==================================================
# CLUE LIST
# ==================================================

var _color_regexes: Array = []

func _bbcode_for_clue_text(text: String) -> String:
    if _color_regexes.is_empty():
        for name in COLOR_NAME_LABELS:
            var re := RegEx.new()
            re.compile("(?i)\\b%s\\b" % name.replace("-", "\\-"))
            _color_regexes.append(re)
    var bb: String = text
    for i in _color_regexes.size():
        var col_hex: String = STAR_COLORS_BY_IDX[i].to_html()
        bb = (_color_regexes[i] as RegEx).sub(bb, "[color=#%s]$0[/color]" % col_hex, true)
    return bb


func _make_clue_label(text: String, _color: Color) -> PanelContainer:
    var pc := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.04, 0.03, 0.09, 0.6)
    sb.border_color = Color(0.25, 0.18, 0.42, 0.4)
    sb.border_width_left   = 1
    sb.border_width_top    = 1
    sb.border_width_right  = 1
    sb.border_width_bottom = 1
    sb.corner_radius_top_left     = 4
    sb.corner_radius_top_right    = 4
    sb.corner_radius_bottom_right = 4
    sb.corner_radius_bottom_left  = 4
    sb.content_margin_left   = 8.0
    sb.content_margin_top    = 5.0
    sb.content_margin_right  = 8.0
    sb.content_margin_bottom = 5.0
    pc.add_theme_stylebox_override("panel", sb)
    var rtl := RichTextLabel.new()
    rtl.bbcode_enabled = true
    rtl.fit_content = true
    rtl.scroll_active = false
    rtl.text = _bbcode_for_clue_text(text)
    rtl.add_theme_color_override("default_color", Color(0.2, 0.9, 0.2, 1))
    rtl.add_theme_font_size_override("normal_font_size", 18)
    rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pc.add_child(rtl)
    return pc


func _make_fact_row(label_text: String, control: Control, color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    var lbl := Label.new()
    lbl.text = label_text
    lbl.add_theme_font_size_override("font_size", 13)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.75))
    row.add_child(lbl)
    row.add_child(control)
    return row


func _make_fact_line(text: String, color: Color) -> Label:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.9))
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return lbl


# ==================================================
# HEADER
# ==================================================
func _update_header() -> void:
    if not _cd or _constellation_id < 0:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    var name_str: String = def.get("name", "Constellation")
    var desig: String = def.get("designation", "")
    _title_label.text = "%s  •  %s" % [name_str, desig] if desig != "" else name_str


# ==================================================
# CLOSE
# ==================================================
func _on_close() -> void:
    visible = false


func _on_backdrop_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        visible = false


func _input(event: InputEvent) -> void:
    if not visible:
        return

    if _name_drag_idx >= 0:
        if event is InputEventMouseMotion:
            _name_drag_mouse_y = (event as InputEventMouseMotion).global_position.y
            _update_name_drag_hover(_name_drag_mouse_y)
            get_viewport().set_input_as_handled()
            return
        elif event is InputEventMouseButton:
            var mbe_drag := event as InputEventMouseButton
            if mbe_drag.button_index == MOUSE_BUTTON_LEFT and not mbe_drag.pressed:
                _end_name_drag()
                get_viewport().set_input_as_handled()
                return

    if event is InputEventKey and (event as InputEventKey).pressed:
        if (event as InputEventKey).keycode == KEY_ESCAPE:
            visible = false
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        var mpos: Vector2 = get_local_mouse_position()
        var panel_rect: Rect2 = $CenterContainer/PanelContainer.get_global_rect()
        var local_panel_rect := Rect2(
            panel_rect.position - global_position,
            panel_rect.size
        )
        if not local_panel_rect.has_point(mpos):
            visible = false
            get_viewport().set_input_as_handled()


func _on_name_row_pressed(row_idx: int) -> void:
    _name_drag_idx = row_idx
    _name_drag_mouse_y = get_viewport().get_mouse_position().y


func _update_name_drag_hover(global_mouse_y: float) -> void:
    if _name_drag_idx < 0 or _name_drag_idx >= _name_row_controls.size():
        return
    var hover_idx: int = -1
    for i in _name_row_controls.size():
        var row: Control = _name_row_controls[i]
        if not is_instance_valid(row):
            continue
        var r: Rect2 = row.get_global_rect()
        if global_mouse_y >= r.position.y and global_mouse_y <= r.position.y + r.size.y:
            hover_idx = i
            break
    if hover_idx < 0 or hover_idx == _name_drag_idx:
        return
    var moved_name: String = _name_tab_order[_name_drag_idx]
    _name_tab_order.remove_at(_name_drag_idx)
    _name_tab_order.insert(hover_idx, moved_name)
    _name_drag_idx = hover_idx
    _populate_name_markers()


func _end_name_drag() -> void:
    _name_drag_idx = -1
    _save_puzzle_notes()
    _populate_name_markers()
