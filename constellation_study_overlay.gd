extends Control
class_name ConstellationStudyOverlay
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
# Base paths shared by many of the lookups below — extracted 2026-07-28
# so a scene-hierarchy restructure only needs one edit per shared prefix
# instead of hunting through every literal path individually.
const PANEL_ROOT_PATH:      String = "CenterContainer/PanelContainer"
const HEADER_BASE_PATH:     String = PANEL_ROOT_PATH + "/OuterMargin/OuterVBox/HeaderHBox"
const PANE1_BASE_PATH:      String = PANEL_ROOT_PATH + "/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox"
const STAR_MAP_COLUMN_PATH: String = PANE1_BASE_PATH + "/StarMapColumn"
const MARKERS_BASE_PATH:    String = PANE1_BASE_PATH + "/MarkersVBox"

@onready var _title_label:         Label         = get_node(HEADER_BASE_PATH + "/TitleLabel")
@onready var _close_btn:           Button        = get_node(HEADER_BASE_PATH + "/CloseButton")
@onready var _fork_btn: Button = get_node(HEADER_BASE_PATH + "/TuningForkButton")
@onready var _pitch_listen_btn: Button = get_node(HEADER_BASE_PATH + "/PitchListenButton")
@onready var _selected_clue_display: RichTextLabel = get_node(HEADER_BASE_PATH + "/SelectedClueDisplay")
@onready var _synth:    Node   = get_node_or_null("../RootUI/PuzzleSynths")
@onready var _star_map_control:    Control = get_node(STAR_MAP_COLUMN_PATH + "/StarMapControl")

# Read only via _host.<name> from constellation_puzzle_widgets.gd's/
# constellation_puzzle_deduction.gd's composed helper objects, never from
# within this class body — Godot's static analyzer can't see the external
# use, so it flags each as unused (same false-positive class documented in
# constellation_fork_puzzle.gd's "COMPUTED PASS-THROUGHS" block).
@warning_ignore("unused_private_class_variable")
@onready var _markers_scroll:      ScrollContainer = get_node(MARKERS_BASE_PATH + "/MarkersScrollContainer")
@warning_ignore("unused_private_class_variable")
@onready var _markers_content:     VBoxContainer = get_node(MARKERS_BASE_PATH + "/MarkersScrollContainer/MarkersContentVBox")
@warning_ignore("unused_private_class_variable")
@onready var _sort_sub_tab_bar:    HBoxContainer = get_node(MARKERS_BASE_PATH + "/SortSubTabBar")
@onready var _melody_staff_panel:  Control = get_node(STAR_MAP_COLUMN_PATH + "/MelodyStaffPanel")

var _staff_popup: StaffPopup = null
@warning_ignore("unused_private_class_variable") # read only via _host. from constellation_puzzle_widgets.gd
var _staff_popup_seq_pos: int = -1
var _name_checklist_popup: NameChecklistPopup = null
var _pitch_checklist_popup: PitchChecklistPopup = null

# Widget-construction and deduction-engine halves of the Stage 2/3 file
# split — see constellation_puzzle_widgets.gd and
# constellation_puzzle_deduction.gd for what's moved out here so far.
var _widgets: ConstellationPuzzleWidgets = null
var _deduction: ConstellationPuzzleDeduction = null

const UNKNOWN_SEQ_COLOR := Color(0.35, 0.75, 0.45, 1.0)

# Shared puzzle-state color palette — see puzzle_state_colors.gd.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")
@onready var _tab_color:           Button        = get_node(MARKERS_BASE_PATH + "/MarkerTabBar/TabColor")
@onready var _tab_sequence:        Button        = get_node(MARKERS_BASE_PATH + "/MarkerTabBar/TabSequence")

@onready var _tab_pitch:           Button        = get_node(MARKERS_BASE_PATH + "/MarkerTabBar2/TabPitch")
@onready var _tab_proximity:       Button        = get_node(MARKERS_BASE_PATH + "/MarkerTabBar2/TabAdjacency")
@onready var _tab_name_clues:      Button        = get_node(MARKERS_BASE_PATH + "/MarkerTabBar/TabPlaceholder")

# ── STYLE CACHE ──────────────────────────────────────────────────────
# Shared with constellation_overlay.gd — see star_color_palette.gd.
const STAR_COLORS_BY_IDX: Array = preload("res://star_color_palette.tres").by_idx
const COLOR_NAME_LABELS: Array = ["Blue", "White", "Yellow", "Red"]

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
var _active_marker_tab:   int   = -1     # -1=Default(Matches) 0=Color 1=Sequence 2=Pitch 3=Proximity 4=NameClues
# Proximity marker states: key = "a:b" (a<b), value = int 0=neutral 1=✓ 2=✗
var _proximity_states:    Dictionary = {}
var _widget_closed: Dictionary = {}             # star_idx -> bool, closed via X button
var _pitch_rank_solution:   Array = []     # Array[int], melody step per star
var _star_pitch_index:      Array = []     # Array[int], raw note index per star (ConstellationData)
var _pitch_freqs:           Array = []     # Array[float], frequency table for this constellation
@warning_ignore("unused_private_class_variable") # read/written only via _host. from constellation_puzzle_widgets.gd
var _matches_sort_mode:    int = -1       # -1/0=Name,1=Sequence,2=Color,3=Pitch
var _player_seed:          int = 0
var _puzzle_seed_used:      int = 0     # actual seed used for THIS cached puzzle instance
                                          # (differs from _player_seed after a dev regenerate)

var _form_clues_cache: Array = []     # cached chosen_form_clues dicts: {form_id, form_name, text, characteristics}

# ── PUZZLE NOTES STATE ───────────────────────────────────────────────
# Sequence range and per-star name elimination now live entirely on
# _match_records (seq_lo/seq_hi, and the new star_elim field) — there is
# no separate per-star array anymore. A single source of truth means
# nothing can silently fall out of sync between the map widgets and the
# Sort: tabs, which is what caused the color-elimination-doesn't-propagate
# bug this refactor fixes.
# Floating widget nodes, one Control per star.
var _star_widgets: Array = []
@warning_ignore("unused_private_class_variable") # read/written only via _host. from constellation_puzzle_widgets.gd
var _star_tags: Array = []
var _star_count: int = 0
var _star_degrees: Array = []
var _gc: Node = null

# Fork minigame state/logic lives in ConstellationForkPuzzle
# (constellation_fork_puzzle.gd); this script only owns the instance and
# dispatches to it. See docs/early_game_architecture_overview.md, §4.
var _fork: ConstellationForkPuzzle = null

var _pitch_listen_mode:      bool  = false
var _pitch_reveal_label:     Label = null
var _pitch_reveal_timer:     float = 0.0

# ── STYLE BOXES (loaded once) ─────────────────────────────────────────
var _sb_unassigned:   StyleBox = null
var _sb_assigned:     StyleBox = null
var _sb_selected:     StyleBox = null
var _sb_picker_free:  StyleBox = null
var _sb_picker_used:  StyleBox = null
var _sb_tab_active:   StyleBox = null
var _sb_tab_inactive: StyleBox = null
var _sb_clue_normal:  StyleBox = null
var _selected_clue_text: String = ""   # raw (non-BBCode) text of the pinned clue, "" = none
var _selected_clue_tab:  int    = -1   # which marker tab it was pinned from, -1 = none


# ==================================================
# LIFECYCLE
# ==================================================
func _ready() -> void:
    visible = false
    _gc = get_node_or_null("/root/GameContext")
    _widgets = ConstellationPuzzleWidgets.new()
    _deduction = ConstellationPuzzleDeduction.new()
    _deduction.setup(self, Callable(_widgets, "_show_conflict_choice"))
    _widgets.setup(self, _deduction)
    _build_style_boxes()

    _tab_color.pressed.connect(func(): _widgets._set_marker_tab(0))
    _tab_sequence.pressed.connect(func(): _widgets._set_marker_tab(1))
    _tab_pitch.pressed.connect(func(): _widgets._set_marker_tab(2))
    _tab_proximity.pressed.connect(func(): _widgets._set_marker_tab(3))
    _tab_name_clues.pressed.connect(func(): _widgets._set_marker_tab(4))

    _star_map_control.draw.connect(_draw_star_map)
    _star_map_control.gui_input.connect(_on_map_input)
    _melody_staff_panel.draw.connect(_widgets._draw_melody_staff)
    _melody_staff_panel.gui_input.connect(_widgets._on_melody_staff_input)
    _staff_popup = preload("res://StaffPopup.tscn").instantiate()
    add_child(_staff_popup)
    _staff_popup.pitch_check_pressed.connect(_widgets._on_staff_pitch_check)
    _staff_popup.pitch_x_pressed.connect(_widgets._on_staff_pitch_x)
    _staff_popup.pitch_row_right_clicked.connect(_widgets._on_staff_pitch_protect)
    _staff_popup.color_check_pressed.connect(_widgets._on_staff_color_check)
    _staff_popup.color_x_pressed.connect(_widgets._on_staff_color_x)
    _staff_popup.color_row_right_clicked.connect(_widgets._on_staff_color_protect)
    _staff_popup.name_check_pressed.connect(_widgets._on_staff_name_check)
    _staff_popup.name_x_pressed.connect(_widgets._on_staff_name_x)
    _staff_popup.name_row_right_clicked.connect(_widgets._on_staff_name_protect)
    _staff_popup.pitch_undo_selects_pressed.connect(_widgets._on_staff_pitch_undo_selects)
    _staff_popup.pitch_undo_blocks_pressed.connect(_widgets._on_staff_pitch_undo_blocks)
    _staff_popup.pitch_undo_all_pressed.connect(_widgets._on_staff_pitch_undo_all)
    _staff_popup.color_undo_selects_pressed.connect(_widgets._on_staff_color_undo_selects)
    _staff_popup.color_undo_blocks_pressed.connect(_widgets._on_staff_color_undo_blocks)
    _staff_popup.color_undo_all_pressed.connect(_widgets._on_staff_color_undo_all)
    _staff_popup.name_undo_selects_pressed.connect(_widgets._on_staff_name_undo_selects)
    _staff_popup.name_undo_blocks_pressed.connect(_widgets._on_staff_name_undo_blocks)
    _staff_popup.name_undo_all_pressed.connect(_widgets._on_staff_name_undo_all)
    _name_checklist_popup = preload("res://NameChecklistPopup.tscn").instantiate()
    add_child(_name_checklist_popup)
    _name_checklist_popup.name_check_pressed.connect(_widgets._on_slot_name_check)
    _name_checklist_popup.name_x_pressed.connect(_widgets._on_slot_name_x)
    _name_checklist_popup.name_row_right_clicked.connect(_widgets._on_slot_name_protect)
    _name_checklist_popup.undo_selects_pressed.connect(_widgets._on_slot_name_undo_selects)
    _name_checklist_popup.undo_blocks_pressed.connect(_widgets._on_slot_name_undo_blocks)
    _name_checklist_popup.undo_all_pressed.connect(_widgets._on_slot_name_undo_all)
    _pitch_checklist_popup = preload("res://PitchChecklistPopup.tscn").instantiate()
    add_child(_pitch_checklist_popup)
    _pitch_checklist_popup.pitch_check_pressed.connect(_widgets._on_pitch_checklist_check)
    _pitch_checklist_popup.pitch_x_pressed.connect(_widgets._on_pitch_checklist_x)
    _pitch_checklist_popup.pitch_row_right_clicked.connect(_widgets._on_pitch_checklist_protect)
    _pitch_checklist_popup.undo_selects_pressed.connect(_widgets._on_pitch_checklist_undo_selects)
    _pitch_checklist_popup.undo_blocks_pressed.connect(_widgets._on_pitch_checklist_undo_blocks)
    _pitch_checklist_popup.undo_all_pressed.connect(_widgets._on_pitch_checklist_undo_all)
    _star_map_control.resized.connect(_on_star_map_resized)
    _close_btn.pressed.connect(_on_close)
    # Click-to-jump: clicking the pinned-clue readout switches to whichever
    # marker tab shows that clue and scrolls it into view — see
    # _widgets._jump_to_selected_clue(). RichTextLabel doesn't pass mouse
    # input through by default; STOP + gui_input is the same pattern
    # _make_clue_label() uses for the clue rows themselves.
    _selected_clue_display.mouse_filter = Control.MOUSE_FILTER_STOP
    _selected_clue_display.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    _selected_clue_display.gui_input.connect(_on_selected_clue_display_gui_input)
    _fork = ConstellationForkPuzzle.new()
    _fork.setup(_synth, _star_map_control, _fork_btn)
    _fork_btn.pressed.connect(_on_fork_toggle_pressed)

    _pitch_listen_btn.pressed.connect(_on_pitch_listen_toggle_pressed)
    _pitch_reveal_label = Label.new()
    _pitch_reveal_label.add_theme_font_size_override("font_size", 18)
    _pitch_reveal_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
    _pitch_reveal_label.visible = false
    _pitch_reveal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _star_map_control.add_child(_pitch_reveal_label)


func _process(delta: float) -> void:
    if _pitch_reveal_timer > 0.0:
        _pitch_reveal_timer -= delta
        _pitch_reveal_label.modulate.a = clampf(_pitch_reveal_timer / 0.4, 0.0, 1.0)
        if _pitch_reveal_timer <= 0.0:
            _pitch_reveal_label.visible = false

    _fork.tick(delta)


func _coerce_int(val, default: int) -> int:
    # This overlay's puzzle-solving state is populated straight from the
    # puzzle cache (constellation_data.gd's _puzzle_cache), which round-
    # trips through save data. Only the cache's top-level dict-ness is
    # validated at the source — individual field values and array elements
    # aren't — and a typed variable/parameter assignment or the global
    # int()/float() constructors hang the engine on a wrong-typed value
    # (Dictionary/Array) rather than raising a catchable error, confirmed
    # repeatedly this session. str() is safe for any type (verified
    # directly), which is why the many str(k)/str(n) calls in this file
    # don't need the same treatment.
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


func _coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


func _coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


func _coerce_string(val, default: String) -> String:
    if typeof(val) == TYPE_STRING:
        return val
    return default


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
    _sb_clue_normal  = make.call(Color(0.04, 0.03, 0.09, 0.6), Color(0.25, 0.18, 0.42, 0.4), 1, 4)


# ==================================================
# PUBLIC API
# ==================================================
func show_for_constellation(constellation_id: int) -> void:
    if not _cd:
        _cd = get_node_or_null("/root/ConstellationData")
    _constellation_id = constellation_id
    _player_seed = _cd.player_seed if _cd else 0
    _load_constellation_data()
    _update_header()
    _widgets._set_marker_tab(_active_marker_tab)
    _widgets._build_star_widgets()
    _widgets._build_star_tags()
    _fork.set_constellation(_constellation_id, _cd, _gc)
    visible = true


# ==================================================
# DATA LOADING
# ==================================================
func _load_constellation_data() -> void:
    if not _cd or _constellation_id < 0:
        return

    var cache: Dictionary = _cd.get_puzzle_cache(_constellation_id)
    _puzzle_seed_used = _coerce_int(cache.get("player_seed_used"), 0)

    var raw_names = _coerce_array(cache.get("star_names"), [])
    _star_names = []
    for n in raw_names:
        _star_names.append(str(n))

    var raw_colors = _coerce_array(cache.get("star_colors"), [])
    _star_colors = []
    for c in raw_colors:
        _star_colors.append(_coerce_int(c, 0))

    var raw_degrees = _coerce_array(cache.get("star_degrees"), [])
    _star_degrees = []
    for d in raw_degrees:
        _star_degrees.append(_coerce_int(d, 0))

    _star_count = _star_names.size()

    # Name assignments (legacy positive-assignment slot).
    var raw_assign: Array = _coerce_array(cache.get("player_name_assignments"), [])
    _name_assignments = []
    for i in _star_count:
        _name_assignments.append(str(raw_assign[i]) if i < raw_assign.size() else "")

    # Puzzle notes.
    var notes: Dictionary = _cd.get_player_puzzle_notes(_constellation_id)

    _proximity_states.clear()
    var raw_adj: Dictionary = _coerce_dict(notes.get("adjacency_states"), {})
    for k in raw_adj:
        _proximity_states[str(k)] = _coerce_int(raw_adj[k], 0)

    _deduction._protected_names.clear()
    var raw_prot: Dictionary = _coerce_dict(notes.get("protected_names"), {})
    for k in raw_prot:
        _deduction._protected_names[str(k)] = true

    _deduction._user_blocks.clear()
    var raw_blocks: Dictionary = _coerce_dict(notes.get("user_blocks"), {})
    for k in raw_blocks:
        _deduction._user_blocks[str(k)] = true

    # _load_match_records(data: Array) has a typed parameter — a wrong-
    # typed value would hang at the call boundary, one hop before that
    # function's own body (not yet reviewed this session) ever runs.
    _deduction._load_match_records(_coerce_array(notes.get("match_records"), []))

    # Sequence position + clue text caches (for Markers Panel display).
    _pitch_rank_solution = []
    for v in _coerce_array(cache.get("pitch_rank_solution"), []):
        _pitch_rank_solution.append(_coerce_int(v, 0))

    _star_pitch_index = []
    for v in _cd.get_note_assignment(_constellation_id):
        _star_pitch_index.append(_coerce_int(v, 0))
    _pitch_freqs = _cd.get_note_freqs(_constellation_id)

    var raw_form_clues = _coerce_array(cache.get("chosen_form_clues"), [])
    _form_clues_cache = raw_form_clues.duplicate(true)

    _compute_star_screen_positions()
    _selected_star = -1


func _compute_star_screen_positions() -> void:
    _star_screen_pos.clear()
    if not _cd or _constellation_id < 0:
        return

    var world_positions: Array = _cd.get_star_positions(_constellation_id)
    if world_positions.is_empty():
        return

    # Same canonical orientation as the starfield's whirl-to-select
    # animation (see get_canonical_display_basis()) — this used to build
    # its own arbitrary world-UP-based frame and then search 180
    # candidate angles for whichever best filled the panel, which meant
    # this map never reliably matched any specific "up" direction. Using
    # the shared canonical basis directly (same X/Y-direct convention as
    # constellation_overlay.gd's own _world_to_screen) keeps this map
    # consistent with what the starfield settles into, at the cost of
    # occasionally not filling the panel quite as tightly as the old
    # best-fit search did for oddly-shaped constellations — the intended
    # tradeoff, since showing the correct orientation matters more here.
    var canonical_basis: Basis = _cd.get_canonical_display_basis(_constellation_id)
    var canonical_inv: Basis = canonical_basis.inverse()
    var rotated_pts: Array = []
    for wp in world_positions:
        var view_pos: Vector3 = canonical_inv * (wp as Vector3)
        rotated_pts.append(Vector2(view_pos.x, view_pos.y))

    var map_size: Vector2 = _star_map_control.size
    if map_size.x < 10.0 or map_size.y < 10.0:
        # Control hasn't been sized yet; defer to first draw
        map_size = Vector2(540.0, 400.0)

    var usable_w: float = map_size.x - MAP_PADDING * 2.0
    var usable_h: float = map_size.y - MAP_PADDING * 2.0

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

    _widgets._reposition_star_widgets()


func _on_star_map_resized() -> void:
    if _constellation_id < 0:
        return
    _compute_star_screen_positions()
    _widgets._reposition_star_tags()
    _star_map_control.queue_redraw()


# ==================================================
# DRAWING — STAR MAP
# ==================================================
func _draw_star_map() -> void:
    if _star_screen_pos.is_empty():
        return

    var def: Dictionary = _cd.get_constellation_def(_constellation_id) if _cd else {}
    var line_pairs: Array = _coerce_array(def.get("line_pairs"), [])

    var line_color := Color(0.55, 0.45, 0.75, 0.35)
    var k: int = 0
    while k < line_pairs.size() - 1:
        var ai: int = _coerce_int(line_pairs[k], -1)
        var bi: int = _coerce_int(line_pairs[k + 1], -1)
        k += 2
        if ai < 0 or bi < 0 or ai >= _star_screen_pos.size() or bi >= _star_screen_pos.size():
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

        if not _fork._fork_mode:
            continue

        if i == _fork._fork_replay_lit_star:
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.4, Color(_fork.FORK_COLOR_REPLAY.r, _fork.FORK_COLOR_REPLAY.g, _fork.FORK_COLOR_REPLAY.b, 0.45))
            _star_map_control.draw_circle(p, 6.0, _fork.FORK_COLOR_REPLAY)
        if i == _fork._fork_wrong_star and _fork._fork_wrong_flash_timer > 0.0:
            var t: float = _fork._fork_wrong_flash_timer / _fork.FORK_WRONG_FLASH_DURATION
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.6, Color(_fork.FORK_COLOR_WRONG.r, _fork.FORK_COLOR_WRONG.g, _fork.FORK_COLOR_WRONG.b, 0.4 * t))
            _star_map_control.draw_circle(p, 5.0, Color(_fork.FORK_COLOR_WRONG.r, _fork.FORK_COLOR_WRONG.g, _fork.FORK_COLOR_WRONG.b, 0.9 * t))
        if i == _fork._fork_fanfare_lit_star and _fork._fork_state == ConstellationForkPuzzle.ForkState.SUCCESS:
            _star_map_control.draw_circle(p, HIT_RADIUS * 1.6, Color(_fork.FORK_COLOR_FANFARE.r, _fork.FORK_COLOR_FANFARE.g, _fork.FORK_COLOR_FANFARE.b, 0.50))
            _star_map_control.draw_circle(p, 7.0, _fork.FORK_COLOR_FANFARE)


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

    if _fork._fork_mode:
        _fork._on_fork_star_clicked(best_idx)
        get_viewport().set_input_as_handled()
        return

    if _pitch_listen_mode:
        _on_pitch_listen_star_clicked(best_idx)
        get_viewport().set_input_as_handled()
        return

    _selected_star = -1 if best_idx == _selected_star else best_idx
    _star_map_control.queue_redraw()
    for wi in _star_widgets.size():
        if is_instance_valid(_star_widgets[wi]):
            if wi == _selected_star:
                _widget_closed.erase(wi)
            _star_widgets[wi].visible = (wi == _selected_star) and not _widget_closed.get(wi, false)
    _widgets._reposition_star_widgets()
    get_viewport().set_input_as_handled()


# ==================================================
# TUNING-FORK LISTEN MODE — free-form pitch confirmation. Hearing a star's
# ACTUAL tone is directly perceivable ground truth, same category as color
# being visible on the map — so writing it straight into the record system
# is not a leak, it's the player using their ears as a legitimate sensor.
# The note NAME is revealed on click too, since most players can't name a
# pitch by ear alone; that's a deliberate difficulty choice, not a bug.
# ==================================================
func _on_pitch_listen_toggle_pressed() -> void:
    _pitch_listen_mode = not _pitch_listen_mode
    _pitch_listen_btn.modulate = STATE_COLORS.confirmed if _pitch_listen_mode else Color(1, 1, 1, 1)
    if _pitch_listen_mode:
        _fork.force_off()
        _selected_star = -1
        for wi in _star_widgets.size():
            if is_instance_valid(_star_widgets[wi]):
                _star_widgets[wi].visible = false
    _star_map_control.queue_redraw()


func _on_pitch_listen_star_clicked(star_idx: int) -> void:
    if star_idx < 0 or star_idx >= _star_pitch_index.size():
        return
    var p: int = _star_pitch_index[star_idx]
    if p < 0 or p >= _pitch_freqs.size():
        return
    var freq: float = _pitch_freqs[p]
    if _synth and _synth.has_method("play_bell_note"):
        _synth.play_bell_note(freq)

    var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(freq)
    var record_idx: int = _deduction._get_or_create_match_record_for_star_idx(star_idx)
    _deduction._propagate_pitch_confirmed_same_record(record_idx, note_name)
    _deduction._match_records[record_idx]["pitch_revealed"] = true
    # Reconciles this record with a stale, blank Sort:Pitch-tab slot
    # record for the same note, if the tab was opened before this star
    # was ever listened to — see _reconcile_unique_pitch_slot for why
    # this is only safe/needed for notes with exactly one star.
    record_idx = await _deduction._reconcile_unique_pitch_slot(record_idx, note_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()

    if star_idx < _star_screen_pos.size():
        _pitch_reveal_label.text = note_name
        _pitch_reveal_label.visible = true
        _pitch_reveal_label.position = _star_screen_pos[star_idx] + Vector2(-12, -32)
        _pitch_reveal_timer = 1.4


# ==================================================
# FORK PUZZLE — TUNING-FORK SEQUENCE MODE
# State/logic lives in ConstellationForkPuzzle (constellation_fork_puzzle.gd);
# this handler only owns the cross-mode UI concerns (pitch-listen mutual
# exclusion, star deselection, widget hiding) that the Fork class has no
# business knowing about.
# ==================================================
func _on_fork_toggle_pressed() -> void:
    _fork.toggle_mode()
    if _fork._fork_mode:
        _pitch_listen_mode = false
        _pitch_listen_btn.modulate = Color(1, 1, 1, 1)
        _selected_star = -1
        for wi in _star_widgets.size():
            if is_instance_valid(_star_widgets[wi]):
                _star_widgets[wi].visible = false


# ==================================================
# HEADER
# ==================================================
const SELECTED_CLUE_PLACEHOLDER := "Select a clue below to pin it here."

func _update_header() -> void:
    if not _cd or _constellation_id < 0:
        return
    var def: Dictionary = _cd.get_constellation_def(_constellation_id)
    var name_str: String = _coerce_string(def.get("name"), "Constellation")
    var desig: String = _coerce_string(def.get("designation"), "")
    _title_label.text = "%s  •  %s" % [name_str, desig] if desig != "" else name_str
    _selected_clue_text = ""
    _selected_clue_tab = -1
    _selected_clue_display.text = SELECTED_CLUE_PLACEHOLDER


func _select_clue(bbcode_text: String) -> void:
    _selected_clue_display.text = bbcode_text if bbcode_text != "" else SELECTED_CLUE_PLACEHOLDER


func _on_selected_clue_display_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _widgets._jump_to_selected_clue()
        get_viewport().set_input_as_handled()


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

    if event is InputEventKey and (event as InputEventKey).pressed:
        if (event as InputEventKey).keycode == KEY_ESCAPE:
            visible = false
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        var mpos: Vector2 = get_local_mouse_position()
        var panel_rect: Rect2 = get_node(PANEL_ROOT_PATH).get_global_rect()
        var local_panel_rect := Rect2(
            panel_rect.position - global_position,
            panel_rect.size
        )
        if not local_panel_rect.has_point(mpos):
            visible = false
            get_viewport().set_input_as_handled()
