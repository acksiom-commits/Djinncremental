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
@onready var _pitch_listen_btn: Button = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/HeaderHBox/PitchListenButton
@onready var _synth:    Node   = get_node_or_null("../RootUI/PuzzleSynths")
@onready var _star_map_control:    Control = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/StarMapColumn/StarMapControl

@onready var _markers_content:     VBoxContainer = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkersScrollContainer/MarkersContentVBox
@onready var _sort_sub_tab_bar:    HBoxContainer = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/SortSubTabBar
@onready var _melody_staff_panel:  Control = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/StarMapColumn/MelodyStaffPanel

var _staff_popup: PopupPanel = null
var _staff_popup_seq_pos: int = -1

const UNKNOWN_SEQ_COLOR := Color(0.35, 0.75, 0.45, 1.0)
@onready var _tab_color:           Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabColor
@onready var _tab_sequence:        Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabSequence

@onready var _tab_pitch:           Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar2/TabPitch
@onready var _tab_adjacency:       Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar2/TabAdjacency
@onready var _tab_name_clues:      Button        = $CenterContainer/PanelContainer/OuterMargin/OuterVBox/CarouselClip/Pane1StarMap/MapAndPickerHBox/MarkersVBox/MarkerTabBar/TabPlaceholder

# ── STYLE CACHE ──────────────────────────────────────────────────────
# Pulled from the scene's sub-resources rather than duplicated here.
const STAR_COLORS_BY_IDX: Array = [
    Color(0.45, 0.65, 1.00, 1.0),   # 0 BLUE
    Color(1.00, 1.00, 1.00, 1.0),   # 1 WHITE
    Color(1.00, 0.80, 0.30, 1.0),   # 2 YELLOW_ORANGE
    Color(1.00, 0.35, 0.25, 1.0),   # 3 RED
]
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
var _active_marker_tab:   int   = -1     # -1=Default(Matches) 0=Color 1=Sequence 2=Pitch 3=Adjacency 4=NameClues
# Adjacency marker states: key = "a:b" (a<b), value = int 0=neutral 1=✓ 2=✗
var _adjacency_states:    Dictionary = {}
var _protected_names:         Dictionary = {}   # key "star_idx:name" -> true; right-click "still possible" flags
var _star_name_list_expanded: Dictionary = {}   # star_idx -> bool, collapsed by default
var _widget_closed: Dictionary = {}             # star_idx -> bool, closed via X button
var _user_blocks: Dictionary = {}               # "star_idx:name" -> true; blocks placed by user clicking X, not by propagation
var _pitch_rank_solution:   Array = []     # Array[int], melody step per star
var _star_pitch_index:      Array = []     # Array[int], raw note index per star (ConstellationData)
var _pitch_freqs:           Array = []     # Array[float], frequency table for this constellation
var _matches_sort_mode:    int = -1       # -1/0=Name,1=Sequence,2=Color,3=Pitch
var _player_seed:          int = 0
var _puzzle_seed_used:      int = 0     # actual seed used for THIS cached puzzle instance
                                          # (differs from _player_seed after a dev regenerate)

# Match records — one per set of facts the player has asserted belong to the same star.
# Each record: {
#   "name": String,              # "" if unknown
#   "seq_lo": int, "seq_hi": int, # 0 if unknown; exact position known when seq_lo == seq_hi > 0
#   "color_states": Dictionary,   # {color_idx(int): state(int)} 0=neutral, 1=confirmed, 2=eliminated
#   "pitch_states": Dictionary,   # {note_name(String): state(int)}
#   "pitch_carousel_idx": int,    # transient UI state, not persisted
#   "star_idx": int,              # -1 until resolvable from seq_lo==seq_hi or map-widget confirm
# }
var _match_records: Array[Dictionary] = []

var _final_clues_cache:     Array = []     # cached final_clues dicts
var _final_identity_clues_cache: Array = [] # cached dist_color/between identity-anchor clue dicts
var _color_negation_cache: Array = []      # cached {"s":int,"text":String} negation clues
var _final_pitch_clues_cache: Array = []    # cached solver-validated Pitch-axis clue dicts

# ── PUZZLE NOTES STATE ───────────────────────────────────────────────
# Sequence range and per-star name elimination now live entirely on
# _match_records (seq_lo/seq_hi, and the new star_elim field) — there is
# no separate per-star array anymore. A single source of truth means
# nothing can silently fall out of sync between the map widgets and the
# Sort: tabs, which is what caused the color-elimination-doesn't-propagate
# bug this refactor fixes.
# Floating widget nodes, one Control per star.
var _star_widgets: Array = []
var _star_tags: Array = []
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


# ==================================================
# LIFECYCLE
# ==================================================
func _ready() -> void:
    visible = false
    _gc = get_node_or_null("/root/GameContext")
    _build_style_boxes()

    _tab_color.pressed.connect(func(): _set_marker_tab(0))
    _tab_sequence.pressed.connect(func(): _set_marker_tab(1))
    _tab_pitch.pressed.connect(func(): _set_marker_tab(2))
    _tab_adjacency.pressed.connect(func(): _set_marker_tab(3))
    _tab_name_clues.pressed.connect(func(): _set_marker_tab(4))

    _star_map_control.draw.connect(_draw_star_map)
    _star_map_control.gui_input.connect(_on_map_input)
    _melody_staff_panel.draw.connect(_draw_melody_staff)
    _melody_staff_panel.gui_input.connect(_on_melody_staff_input)
    _staff_popup = PopupPanel.new()
    add_child(_staff_popup)
    _star_map_control.resized.connect(_on_star_map_resized)
    _close_btn.pressed.connect(_on_close)
    _fork_btn.pressed.connect(_on_fork_toggle_pressed)
    if _synth and _synth.has_signal("sequence_note_played"):
        _synth.sequence_note_played.connect(_on_fork_fanfare_note)

    _pitch_listen_btn.pressed.connect(_on_pitch_listen_toggle_pressed)
    _pitch_reveal_label = Label.new()
    _pitch_reveal_label.add_theme_font_size_override("font_size", 18)
    _pitch_reveal_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
    _pitch_reveal_label.visible = false
    _pitch_reveal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _star_map_control.add_child(_pitch_reveal_label)


# ==================================================
# MELODY BAR SCORE — piano-roll style summary of confirmed Sequence×Pitch
# information. Purely a rendering query over _match_records: no ground
# truth is ever read here. A position only gets a notehead if the player
# has confirmed BOTH the exact sequence slot AND a pitch on that same
# record; a confirmed slot with unconfirmed pitch gets a "?" at neutral
# height; a wholly unconfirmed slot draws nothing.
# ==================================================

func _melody_marker_for_position(seq_pos: int) -> Dictionary:
    var has_position: bool = false
    for r in _match_records:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo == seq_pos and hi == seq_pos:
            has_position = true
            var pitch_states: Dictionary = r.get("pitch_states", {})
            for note_name in pitch_states:
                if int(pitch_states[note_name]) == 1:
                    return {"has_position": true, "pitch_known": true, "note_name": str(note_name)}
    return {"has_position": has_position, "pitch_known": false, "note_name": ""}


func _freq_for_note_name(note_name: String) -> float:
    for f in _pitch_freqs:
        if ConstellationLogicPuzzle.note_name_for_freq(f) == note_name:
            return f
    return -1.0


func _freq_to_y_fraction(freq: float) -> float:
    # 0.0 = lowest note in this constellation's scale, 1.0 = highest.
    if _pitch_freqs.is_empty() or freq < 0.0:
        return 0.5
    var min_f: float = _pitch_freqs[0]
    var max_f: float = _pitch_freqs[0]
    for f in _pitch_freqs:
        min_f = minf(min_f, f)
        max_f = maxf(max_f, f)
    if is_equal_approx(max_f, min_f):
        return 0.5
    return (freq - min_f) / (max_f - min_f)


func _known_color_for_seq_position(seq_pos: int) -> int:
    # A position's color counts as "known" either because the player
    # directly confirmed one, or because elimination (from here or
    # propagated in from a Sort: tab) has narrowed it down to the single
    # remaining candidate — that's the same "resolves by elimination"
    # pattern already used for identity anchors elsewhere in this panel.
    for r in _match_records:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo != seq_pos or hi != seq_pos:
            continue
        var cs: Dictionary = r.get("color_states", {})
        var confirmed: int = -1
        var eliminated_count: int = 0
        var remaining: int = -1
        for ci in COLOR_NAME_LABELS.size():
            var state: int = int(cs.get(ci, 0))
            if state == 1:
                confirmed = ci
            elif state == 2:
                eliminated_count += 1
            else:
                remaining = ci
        if confirmed >= 0:
            return confirmed
        if eliminated_count == COLOR_NAME_LABELS.size() - 1 and remaining >= 0:
            return remaining
    return -1


func _draw_melody_staff() -> void:
    var panel_size: Vector2 = _melody_staff_panel.size
    if _star_count <= 0 or panel_size.x <= 0.0 or panel_size.y <= 0.0:
        return

    var margin_x: float = 20.0
    var margin_top: float = 14.0
    var margin_bottom: float = 20.0
    var usable_w: float = panel_size.x - margin_x * 2.0
    var usable_h: float = panel_size.y - margin_top - margin_bottom
    var step_x: float = usable_w / float(maxi(_star_count - 1, 1))

    var baseline_y: float = margin_top + usable_h * 0.5
    var baseline_col := Color(0.55, 0.50, 0.65, 1.0)
    _melody_staff_panel.draw_line(
        Vector2(margin_x, baseline_y), Vector2(margin_x + usable_w, baseline_y), baseline_col, 1.0)

    # Faint measure dividers, every 4 notes — a piano-roll rhythm cue, not
    # tied to the actual melody's real phrase structure (which varies per
    # constellation and isn't something the UI should assume it knows).
    var bar_col := Color(0.55, 0.50, 0.65, 1.0)
    var pos: int = 4
    while pos < _star_count:
        var bx: float = margin_x + step_x * float(pos)
        _melody_staff_panel.draw_line(
            Vector2(bx, margin_top), Vector2(bx, margin_top + usable_h), bar_col, 1.0)
        pos += 4

    var note_col := Color(0.82, 0.78, 0.92, 1.0)
    var unknown_col := Color(0.55, 0.50, 0.65, 1.0)
    var font := ThemeDB.fallback_font
    var font_size_small := 16

    for seq_pos in range(1, _star_count + 1):
        var x: float = margin_x + step_x * float(seq_pos - 1)
        var marker: Dictionary = _melody_marker_for_position(seq_pos)

        if marker["has_position"] and marker["pitch_known"]:
            var freq: float = _freq_for_note_name(str(marker["note_name"]))
            var frac: float = _freq_to_y_fraction(freq)
            var y: float = margin_top + usable_h * (1.0 - frac)
            _melody_staff_panel.draw_circle(Vector2(x, y), 5.0, note_col)
            var label: String = str(marker["note_name"])
            var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
            _melody_staff_panel.draw_string(font, Vector2(x - label_w * 0.5, y - 9.0),
                label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, note_col)
        elif marker["has_position"]:
            var qw: float = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
            _melody_staff_panel.draw_string(font, Vector2(x - qw * 0.5, baseline_y + 4.0),
                "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, unknown_col)

        var num_label: String = str(seq_pos)
        var nw: float = font.get_string_size(num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
        var known_color: int = _known_color_for_seq_position(seq_pos)
        var num_col: Color = STAR_COLORS_BY_IDX[known_color] if known_color >= 0 else UNKNOWN_SEQ_COLOR
        _melody_staff_panel.draw_string(font, Vector2(x - nw * 0.5, margin_top + usable_h + 14.0),
            num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, num_col)


func _on_melody_staff_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
        return
    if _star_count <= 0:
        return

    var panel_size: Vector2 = _melody_staff_panel.size
    var margin_x: float = 20.0
    var usable_w: float = panel_size.x - margin_x * 2.0
    var step_x: float = usable_w / float(maxi(_star_count - 1, 1))

    var click_x: float = event.position.x
    var nearest_pos: int = 1
    var nearest_dist: float = INF
    for seq_pos in range(1, _star_count + 1):
        var x: float = margin_x + step_x * float(seq_pos - 1)
        var d: float = abs(click_x - x)
        if d < nearest_dist:
            nearest_dist = d
            nearest_pos = seq_pos

    if nearest_dist <= step_x * 0.5:
        _open_staff_popup(nearest_pos, _melody_staff_panel.global_position + Vector2(click_x, event.position.y))


func _open_staff_popup(seq_pos: int, screen_pos: Vector2) -> void:
    _staff_popup_seq_pos = seq_pos
    var record_idx: int = _get_or_create_match_record_for_seq(seq_pos)

    for child in _staff_popup.get_children():
        child.queue_free()

    var vbox := VBoxContainer.new()
    vbox.custom_minimum_size = Vector2(180, 0)
    vbox.add_theme_constant_override("separation", 4)
    _staff_popup.add_child(vbox)

    var title := Label.new()
    title.text = "Note %d" % seq_pos
    title.add_theme_font_size_override("font_size", 14)
    title.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92, 1))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    vbox.add_child(HSeparator.new())

    var pitch_hdr := Label.new()
    pitch_hdr.text = "PITCH"
    pitch_hdr.add_theme_font_size_override("font_size", 11)
    pitch_hdr.add_theme_color_override("font_color", Color(0.55, 0.50, 0.65, 1))
    vbox.add_child(pitch_hdr)

    var pitch_states: Dictionary = _match_records[record_idx].get("pitch_states", {})
    for f in _pitch_freqs:
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        var row := HBoxContainer.new()
        var lbl := Label.new()
        lbl.text = note_name
        lbl.custom_minimum_size = Vector2(50, 0)
        lbl.add_theme_font_size_override("font_size", 13)
        row.add_child(lbl)
        var btn_check := Button.new()
        btn_check.text = "\u2713"
        btn_check.custom_minimum_size = Vector2(28, 24)
        btn_check.focus_mode = Control.FOCUS_NONE
        row.add_child(btn_check)
        var btn_x := Button.new()
        btn_x.text = "\u2717"
        btn_x.custom_minimum_size = Vector2(28, 24)
        btn_x.focus_mode = Control.FOCUS_NONE
        row.add_child(btn_x)
        vbox.add_child(row)

        var state: int = int(pitch_states.get(note_name, 0))
        _apply_name_row_visual(state, lbl, btn_check, btn_x, Color(0.82, 0.78, 0.92, 1))

        var nn := note_name
        btn_check.pressed.connect(func(): _on_staff_pitch_check(record_idx, nn, lbl, btn_check, btn_x))
        btn_x.pressed.connect(func(): _on_staff_pitch_x(record_idx, nn, lbl, btn_check, btn_x))

    vbox.add_child(HSeparator.new())

    var color_hdr := Label.new()
    color_hdr.text = "COLOR"
    color_hdr.add_theme_font_size_override("font_size", 11)
    color_hdr.add_theme_color_override("font_color", Color(0.55, 0.50, 0.65, 1))
    vbox.add_child(color_hdr)

    var color_states: Dictionary = _match_records[record_idx].get("color_states", {})
    for ci in COLOR_NAME_LABELS.size():
        var crow := HBoxContainer.new()
        var clbl := Label.new()
        clbl.text = COLOR_NAME_LABELS[ci]
        clbl.custom_minimum_size = Vector2(50, 0)
        clbl.add_theme_font_size_override("font_size", 13)
        crow.add_child(clbl)
        var cbtn_check := Button.new()
        cbtn_check.text = "\u2713"
        cbtn_check.custom_minimum_size = Vector2(28, 24)
        cbtn_check.focus_mode = Control.FOCUS_NONE
        crow.add_child(cbtn_check)
        var cbtn_x := Button.new()
        cbtn_x.text = "\u2717"
        cbtn_x.custom_minimum_size = Vector2(28, 24)
        cbtn_x.focus_mode = Control.FOCUS_NONE
        crow.add_child(cbtn_x)
        vbox.add_child(crow)

        var cstate: int = int(color_states.get(ci, 0))
        _apply_name_row_visual(cstate, clbl, cbtn_check, cbtn_x, STAR_COLORS_BY_IDX[ci])

        var cidx := ci
        cbtn_check.pressed.connect(func(): _on_staff_color_check(record_idx, cidx))
        cbtn_x.pressed.connect(func(): _on_staff_color_x(record_idx, cidx))

    _staff_popup.position = Vector2i(screen_pos) - Vector2i(90, 0)
    _staff_popup.popup()


func _propagate_pitch_confirmed_same_record(record_idx: int, confirmed_note: String) -> void:
    var r: Dictionary = _match_records[record_idx]
    var pitch_states: Dictionary = r.get("pitch_states", {})
    for f in _pitch_freqs:
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        if note_name != confirmed_note:
            pitch_states[note_name] = 2
    pitch_states[confirmed_note] = 1
    r["pitch_states"] = pitch_states


func _on_staff_pitch_check(record_idx: int, note_name: String, _lbl: Label, _btn_check: Button, _btn_x: Button) -> void:
    if bool(_match_records[record_idx].get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _match_records[record_idx].get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    var new_state: int = 0 if cur == 1 else 1
    if new_state == 1:
        _propagate_pitch_confirmed_same_record(record_idx, note_name)
    else:
        pitch_states[note_name] = new_state
        _match_records[record_idx]["pitch_states"] = pitch_states
    _save_puzzle_notes()
    _full_propagation_refresh()
    _open_staff_popup(_staff_popup_seq_pos, _staff_popup.position)


func _on_staff_pitch_x(record_idx: int, note_name: String, _lbl: Label, _btn_check: Button, _btn_x: Button) -> void:
    if bool(_match_records[record_idx].get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _match_records[record_idx].get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    pitch_states[note_name] = 0 if cur == 2 else 2
    _match_records[record_idx]["pitch_states"] = pitch_states
    _save_puzzle_notes()
    _full_propagation_refresh()
    _open_staff_popup(_staff_popup_seq_pos, _staff_popup.position)


func _on_staff_color_check(record_idx: int, color_idx: int) -> void:
    var r: Dictionary = _match_records[record_idx]
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 1 else 1
    r["color_states"][color_idx] = new_state
    if new_state == 1:
        _propagate_color_confirmed_same_record(record_idx, color_idx)
    _apply_color_elimination_to_names(record_idx, color_idx, new_state)
    _save_puzzle_notes()
    _full_propagation_refresh()
    _open_staff_popup(_staff_popup_seq_pos, _staff_popup.position)


func _on_staff_color_x(record_idx: int, color_idx: int) -> void:
    var r: Dictionary = _match_records[record_idx]
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 2 else 2
    r["color_states"][color_idx] = new_state
    _apply_color_elimination_to_names(record_idx, color_idx, new_state)
    _save_puzzle_notes()
    _full_propagation_refresh()
    _open_staff_popup(_staff_popup_seq_pos, _staff_popup.position)


func _process(delta: float) -> void:
    if _pitch_reveal_timer > 0.0:
        _pitch_reveal_timer -= delta
        _pitch_reveal_label.modulate.a = clampf(_pitch_reveal_timer / 0.4, 0.0, 1.0)
        if _pitch_reveal_timer <= 0.0:
            _pitch_reveal_label.visible = false

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
    _player_seed = _cd.player_seed if _cd else 0
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
    _puzzle_seed_used = int(cache.get("player_seed_used", 0))

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

    # Puzzle notes.
    var notes: Dictionary = _cd.get_player_puzzle_notes(_constellation_id)

    _adjacency_states.clear()
    var raw_adj: Dictionary = notes.get("adjacency_states", {})
    for k in raw_adj:
        _adjacency_states[str(k)] = int(raw_adj[k])

    _protected_names.clear()
    var raw_prot: Dictionary = notes.get("protected_names", {})
    for k in raw_prot:
        _protected_names[str(k)] = true

    _user_blocks.clear()
    var raw_blocks: Dictionary = notes.get("user_blocks", {})
    for k in raw_blocks:
        _user_blocks[str(k)] = true

    _load_match_records(notes.get("match_records", []))

    # Sequence position + clue text caches (for Markers Panel display).
    _pitch_rank_solution = []
    for v in cache.get("pitch_rank_solution", []):
        _pitch_rank_solution.append(int(v))

    _star_pitch_index = []
    for v in _cd.get_note_assignment(_constellation_id):
        _star_pitch_index.append(int(v))
    _pitch_freqs = _cd.get_note_freqs(_constellation_id)

    _final_clues_cache = cache.get("final_clues", []).duplicate(true)
    _final_identity_clues_cache = cache.get("final_identity_clues", []).duplicate(true)
    _color_negation_cache = cache.get("color_negation_texts", []).duplicate(true)
    _final_pitch_clues_cache = cache.get("final_pitch_clues", []).duplicate(true)

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
    _reposition_star_widgets()
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
    _pitch_listen_btn.modulate = Color(0.3, 1.0, 0.4, 1.0) if _pitch_listen_mode else Color(1, 1, 1, 1)
    if _pitch_listen_mode:
        _fork_mode = false
        _fork_btn.modulate = Color(1, 1, 1, 1)
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
    var record_idx: int = _get_or_create_match_record_for_star_idx(star_idx)
    _propagate_pitch_confirmed_same_record(record_idx, note_name)
    _match_records[record_idx]["pitch_revealed"] = true
    _save_puzzle_notes()
    _full_propagation_refresh()

    if star_idx < _star_screen_pos.size():
        _pitch_reveal_label.text = note_name
        _pitch_reveal_label.visible = true
        _pitch_reveal_label.position = _star_screen_pos[star_idx] + Vector2(-12, -32)
        _pitch_reveal_timer = 1.4


# ==================================================
# FORK PUZZLE — TUNING-FORK SEQUENCE MODE
# ==================================================
func _on_fork_toggle_pressed() -> void:
    _fork_mode = not _fork_mode
    _fork_btn.modulate = Color(0.3, 1.0, 0.4, 1.0) if _fork_mode else Color(1, 1, 1, 1)
    if _fork_mode:
        _pitch_listen_mode = false
        _pitch_listen_btn.modulate = Color(1, 1, 1, 1)
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
    notes["adjacency_states"] = _adjacency_states.duplicate()
    notes["match_records"] = _save_match_records()
    notes["protected_names"] = _protected_names.duplicate()
    notes["user_blocks"] = _user_blocks.duplicate()
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
    _tab_pitch.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 2 else _sb_tab_inactive)
    _tab_adjacency.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 3 else _sb_tab_inactive)
    _tab_name_clues.add_theme_stylebox_override("normal",
        _sb_tab_active if tab_idx == 4 else _sb_tab_inactive)
    _populate_markers_panel()


func _populate_markers_panel() -> void:
    for child in _markers_content.get_children():
        child.queue_free()

    match _active_marker_tab:
        0: _populate_color_markers()
        1: _populate_sequence_markers()
        2: _populate_pitch_markers()
        3: _populate_adjacency_markers()
        4: _populate_name_clues_markers()
        _: _populate_name_markers()


func _populate_color_markers() -> void:
    var entries: Array = []
    for i in _star_count:
        var ci: int = clamp(_star_colors[i] if i < _star_colors.size() else 1, 0, 3)
        entries.append({"seq": _sequence_number(i), "color": ci, "idx": i})
    entries.sort_custom(func(a, b): return a["seq"] < b["seq"])

    var reveal_count: int = maxi(2, int(_star_count * 0.4))
    var reveal_order: Array = range(_star_count)
    var seed_mix: int = (_puzzle_seed_used ^ (_constellation_id * 40503)) & 0x7FFFFFFF
    reveal_order.sort_custom(func(a, b):
        var ha: int = (int(a) * 2654435761 + seed_mix) & 0x7FFFFFFF
        var hb: int = (int(b) * 2654435761 + seed_mix) & 0x7FFFFFFF
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
        if kind != "cmp" and kind != "adj_seq" and kind != "extreme" and kind != "exact" and kind != "range" and kind != "group_cmp" and kind != "count_before" and kind != "neg_exact" and kind != "neg_adjacent":
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
    for iclue in _final_identity_clues_cache:
        var itext: String = str(iclue.get("text", ""))
        if itext == "":
            continue
        _markers_content.add_child(_make_clue_label(itext, Color(0.82, 0.78, 0.92, 1)))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Adjacency clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _sort_matches(mode: int) -> void:
    if mode < 0 or mode > 3:
        push_warning("StudyOverlay: _sort_matches called with invalid mode %d, ignoring" % mode)
        return
    _matches_sort_mode = mode
    # Route through _set_marker_tab so _active_marker_tab correctly lands on
    # -1 (Matches/default) and the top-level tab highlighting clears. Without
    # this, _active_marker_tab stayed at whatever top tab was last active,
    # so any later refresh (e.g. a color toggle) would dispatch back to that
    # stale tab instead of staying on the Sort: view.
    _set_marker_tab(-1)


func _populate_name_markers() -> void:
    for child in _markers_content.get_children():
        child.queue_free()

    # Sort: sub-tab buttons live in SortSubTabBar, a sibling of the scroll
    # container — NOT inside _markers_content — so they stay pinned in view
    # regardless of scroll position. Rebuilt here (rather than once in
    # _ready) since _sort_matches() calls this function directly on every
    # button press, same as the dispatcher path does.
    for child in _sort_sub_tab_bar.get_children():
        child.queue_free()
    _sort_sub_tab_bar.visible = true
    _sort_sub_tab_bar.add_theme_constant_override("separation", 6)
    var sort_labels: Array = ["Name", "Sequence", "Color", "Pitch"]
    for i in sort_labels.size():
        var btn := Button.new()
        btn.text = "Sort: %s" % sort_labels[i]
        btn.add_theme_font_size_override("font_size", 16)
        btn.custom_minimum_size = Vector2(0, 40)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.focus_mode = Control.FOCUS_NONE
        var mode := i
        btn.pressed.connect(func(): _sort_matches(mode))
        _sort_sub_tab_bar.add_child(btn)

    match _matches_sort_mode:
        0, -1:
            _populate_name_rows()
        1:
            _populate_sequence_slot_rows()
        2:
            _populate_color_group_rows()
        3:
            _populate_pitch_group_rows()
        _:
            push_warning("StudyOverlay: unknown _matches_sort_mode %d, resetting to Name" % _matches_sort_mode)
            _matches_sort_mode = 0
            _populate_name_rows()


func _text_mentions_star_name(text: String) -> bool:
    for n in _star_names:
        var name_str: String = str(n)
        if name_str != "" and text.find(name_str) != -1:
            return true
    return false


func _populate_name_clues_markers() -> void:
    var shown: bool = false

    for clue in _final_clues_cache:
        var text: String = str(clue.get("text", ""))
        if text == "" or not _text_mentions_star_name(text):
            continue
        _markers_content.add_child(_make_clue_label(text, Color(0.82, 0.78, 0.92, 1)))
        shown = true

    var neutral_col := Color(0.55, 0.50, 0.65, 1)
    for pclue in _final_pitch_clues_cache:
        var text2: String = str(pclue.get("text", ""))
        if text2 == "" or not _text_mentions_star_name(text2):
            continue
        var pkind: String = str(pclue.get("kind", ""))
        var col2: Color = neutral_col if pkind == "pitch_neg" else Color(0.82, 0.78, 0.92, 1)
        _markers_content.add_child(_make_clue_label(text2, col2))
        shown = true

    for iclue in _final_identity_clues_cache:
        var itext2: String = str(iclue.get("text", ""))
        if itext2 == "" or not _text_mentions_star_name(itext2):
            continue
        _markers_content.add_child(_make_clue_label(itext2, Color(0.82, 0.78, 0.92, 1)))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Name clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _populate_pitch_markers() -> void:
    var shown: bool = false
    var neutral_col := Color(0.55, 0.50, 0.65, 1)
    for pclue in _final_pitch_clues_cache:
        var text: String = str(pclue.get("text", ""))
        if text == "":
            continue
        var pkind: String = str(pclue.get("kind", ""))
        var col: Color = neutral_col if pkind == "pitch_neg" else Color(0.82, 0.78, 0.92, 1)
        _markers_content.add_child(_make_clue_label(text, col))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Pitch clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _markers_content.add_child(lbl)


func _on_adjacency_check(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_adjacency_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 1 else 1
    _adjacency_states[edge_key] = new_state
    btn_check.modulate = Color(0.3, 1.0, 0.4, 1.0) if new_state == 1 else Color(1,1,1,1.0)
    btn_x.modulate = Color(1,1,1,1.0)
    _save_puzzle_notes()


func _on_adjacency_x(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_adjacency_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 2 else 2
    _adjacency_states[edge_key] = new_state
    btn_x.modulate = Color(1.0, 0.35, 0.25, 1.0) if new_state == 2 else Color(1,1,1,1.0)
    btn_check.modulate = Color(1,1,1,1.0)
    _save_puzzle_notes()



# ==================================================
# FLOATING STAR WIDGETS
# ==================================================
func _build_star_widgets() -> void:
    # Always deferred: this tears down and rebuilds every star widget,
    # including whichever one's own LineEdit/Button signal may currently be
    # mid-dispatch on the call stack that triggered this (e.g. a range
    # field's focus_exited firing as part of the very rebuild it causes).
    # Mutating a node's ancestor tree synchronously from inside its own
    # signal handler is a hard Godot error ("Parent node is busy setting up
    # children") — deferring by one frame, imperceptible for a UI rebuild,
    # removes the race entirely rather than requiring every call site to
    # remember to defer it themselves.
    call_deferred("_build_star_widgets_impl")


func _build_star_widgets_impl() -> void:
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
        root.z_index = 10
        _star_map_control.add_child(root)
        _star_widgets.append(root)
        root.visible = (i == _selected_star) and not _widget_closed.get(i, false)

        # ── Range row ──────────────────────────────────────────────
        var range_row := HBoxContainer.new()
        range_row.mouse_filter = Control.MOUSE_FILTER_PASS
        range_row.add_theme_constant_override("separation", 3)

        var existing_record: int = _get_or_create_match_record_for_star_idx(i)
        var star_bounds: Array = _effective_seq_bounds(existing_record)

        var edit_lo := LineEdit.new()
        edit_lo.custom_minimum_size = Vector2(20, 28)
        edit_lo.max_length = 2
        edit_lo.placeholder_text = "\u2013"
        var display_lo: int = _exclusive_display_lo(int(star_bounds[0]), int(star_bounds[1]))
        edit_lo.text = str(display_lo) if display_lo > 0 else ""
        edit_lo.add_theme_font_size_override("font_size", 13)
        edit_lo.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_lo, star_color)
        range_row.add_child(edit_lo)

        var lbl_lt := Label.new()
        lbl_lt.text = "<"
        lbl_lt.add_theme_font_size_override("font_size", 14)
        lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_lt)

        var edit_mid := LineEdit.new()
        edit_mid.custom_minimum_size = Vector2(62, 28)
        edit_mid.max_length = 12
        edit_mid.placeholder_text = "\u2013"
        edit_mid.text = _compressed_possible_positions_str(existing_record)
        edit_mid.add_theme_font_size_override("font_size", 11)
        edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
        _style_range_edit(edit_mid, star_color)
        range_row.add_child(edit_mid)

        var lbl_gt := Label.new()
        lbl_gt.text = "<"
        lbl_gt.add_theme_font_size_override("font_size", 14)
        lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_gt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_gt)

        var edit_hi := LineEdit.new()
        edit_hi.custom_minimum_size = Vector2(20, 28)
        edit_hi.max_length = 2
        edit_hi.placeholder_text = "\u2013"
        var display_hi: int = _exclusive_display_hi(int(star_bounds[0]), int(star_bounds[1]))
        edit_hi.text = str(display_hi) if display_hi > 0 else ""
        edit_hi.add_theme_font_size_override("font_size", 13)
        edit_hi.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_hi, star_color)
        range_row.add_child(edit_hi)

        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        range_row.add_child(spacer)

        var btn_close := Button.new()
        btn_close.text = "\u2715"
        btn_close.custom_minimum_size = Vector2(28, 28)
        btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_close.focus_mode = Control.FOCUS_NONE
        btn_close.add_theme_font_size_override("font_size", 14)
        btn_close.flat = false
        range_row.add_child(btn_close)

        root.add_child(range_row)

        # Capture index for lambdas.
        var si := i
        var lo_ref := edit_lo
        var mid_ref := edit_mid
        var hi_ref := edit_hi
        edit_lo.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_lo.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_hi.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_hi.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_mid.text_submitted.connect(func(_t): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))
        edit_mid.focus_exited.connect(func(): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))

        var close_si := i
        btn_close.pressed.connect(func(): _widget_closed[close_si] = true; root.visible = false)

        # ── Reset buttons ──────────────────────────────────────────
        var reset_row := HBoxContainer.new()
        reset_row.mouse_filter = Control.MOUSE_FILTER_PASS
        reset_row.add_theme_constant_override("separation", 3)
        root.add_child(reset_row)

        var btn_undo_sel := Button.new()
        btn_undo_sel.text = "Undo selects"
        btn_undo_sel.focus_mode = Control.FOCUS_NONE
        btn_undo_sel.custom_minimum_size = Vector2(0, 30)
        btn_undo_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_sel.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_sel)

        var btn_undo_block := Button.new()
        btn_undo_block.text = "Undo blocks"
        btn_undo_block.focus_mode = Control.FOCUS_NONE
        btn_undo_block.custom_minimum_size = Vector2(0, 30)
        btn_undo_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_block.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_block)

        var btn_undo_all := Button.new()
        btn_undo_all.text = "Undo all"
        btn_undo_all.focus_mode = Control.FOCUS_NONE
        btn_undo_all.custom_minimum_size = Vector2(0, 30)
        btn_undo_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_all.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_all)

        var si_reset := i
        btn_undo_sel.pressed.connect(func(): _on_undo_name_selects(si_reset))
        btn_undo_block.pressed.connect(func(): _on_undo_name_blocks(si_reset))
        btn_undo_all.pressed.connect(func(): _on_undo_name_all(si_reset))

        # ── Full candidate checklist (check/X/protect) — always visible ──
        var all_star_names: Array[String] = []
        for j in _star_count:
            all_star_names.append(_star_names[j] if j < _star_names.size() else "?")
        all_star_names.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)

        if not all_star_names.is_empty():
            var panel := PanelContainer.new()
            var panel_sb := StyleBoxFlat.new()
            panel_sb.bg_color = Color(0.06, 0.04, 0.14, 1.0)
            panel_sb.border_color = Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 1.0)
            panel_sb.border_width_left = 1
            panel_sb.border_width_top = 1
            panel_sb.border_width_right = 1
            panel_sb.border_width_bottom = 1
            panel_sb.corner_radius_top_left = 4
            panel_sb.corner_radius_top_right = 4
            panel_sb.corner_radius_bottom_right = 4
            panel_sb.corner_radius_bottom_left = 4
            panel_sb.content_margin_left = 4
            panel_sb.content_margin_right = 4
            panel_sb.content_margin_top = 4
            panel_sb.content_margin_bottom = 4
            panel.add_theme_stylebox_override("panel", panel_sb)
            panel.self_modulate = Color(1, 1, 1, 1)
            panel.custom_minimum_size = Vector2(300, 0)
            root.add_child(panel)

            var name_hbox := HBoxContainer.new()
            name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            name_hbox.add_theme_constant_override("separation", 6)
            panel.add_child(name_hbox)

            @warning_ignore("integer_division")
            var half: int = (all_star_names.size() + 1) / 2
            for col_i in 2:
                var col_vbox := VBoxContainer.new()
                col_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                name_hbox.add_child(col_vbox)

                var start: int = col_i * half
                var end: int = mini(start + half, all_star_names.size())
                for ci in range(start, end):
                    var name_str: String = all_star_names[ci]
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

                    col_vbox.add_child(row)

                    var captured_name := name_str
                    btn_check.pressed.connect(func(): _on_name_check(si, captured_name, name_lbl, btn_check, btn_x))
                    btn_check.gui_input.connect(func(event: InputEvent):
                        if event is InputEventMouseButton:
                            print("[DEBUG] btn_check gui_input: button=%d pressed=%s star=%d name=%s" %
                                [event.button_index, event.pressed, si, captured_name])
                        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                            _on_name_protect_toggle(si, captured_name)
                            get_viewport().set_input_as_handled())
                    btn_x.pressed.connect(func(): _on_name_x(si, captured_name, name_lbl, btn_check, btn_x))

            # Refresh all rows across both columns — pass full name list for correct cross-referencing.
            for col_i in 2:
                var col_vbox: VBoxContainer = name_hbox.get_child(col_i)
                _refresh_name_widget(i, col_vbox, all_star_names, star_color, col_i * half)

    _reposition_star_widgets()


func _style_range_edit(edit: LineEdit, star_color: Color) -> void:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.06, 0.04, 0.14, 1.0)
    sb.border_color = Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 1.0)
    sb.border_width_left = 1; sb.border_width_top = 1
    sb.border_width_right = 1; sb.border_width_bottom = 1
    sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
    sb.corner_radius_bottom_right = 2; sb.corner_radius_bottom_left = 2
    sb.content_margin_left = 3; sb.content_margin_right = 3
    sb.content_margin_top = 1; sb.content_margin_bottom = 1
    edit.add_theme_stylebox_override("normal", sb)
    edit.add_theme_stylebox_override("focus", sb)
    edit.add_theme_color_override("font_color", Color(0.90, 0.87, 1.00, 1.0))
    edit.add_theme_color_override("font_placeholder_color", Color(0.40, 0.35, 0.60, 1.0))


func _sequence_number(star_idx: int) -> int:
    if star_idx >= 0 and star_idx < _pitch_rank_solution.size():
        return _pitch_rank_solution[star_idx] + 1
    return star_idx + 1


func _confirmed_sequence_str(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    var lo_i: int = int(_match_records[idx].get("seq_lo", 0))
    var hi_i: int = int(_match_records[idx].get("seq_hi", 0))
    if lo_i > 0 and lo_i == hi_i:
        return str(lo_i)
    return "?"


func _confirmed_pitch_str_for_star(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    var pitch_states: Dictionary = _match_records[idx].get("pitch_states", {})
    for note in pitch_states:
        if int(pitch_states[note]) == 1:
            return str(note)
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


func _style_color_toggle_btn(btn: Button, color_idx: int, state: int) -> void:
    var base_col: Color = STAR_COLORS_BY_IDX[color_idx]
    var letter: String = COLOR_NAME_LABELS[color_idx].substr(0, 1)
    match state:
        1:  # confirmed
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter + "\u2713"
        2:  # eliminated
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter + "\u2717"
        _:  # neutral
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter


func _confirmed_name_for_star(star_idx: int) -> String:
    if star_idx < 0:
        return ""
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return ""
    return str(_match_records[idx].get("name", ""))


func _reposition_star_widgets() -> void:
    var map_h: float = _star_map_control.size.y
    var map_w: float = _star_map_control.size.x
    for i in _star_widgets.size():
        if i >= _star_screen_pos.size():
            break
        var w: Control = _star_widgets[i]
        if not is_instance_valid(w):
            continue
        w.reset_size()
        var wh: float = w.get_combined_minimum_size().y
        var ww: float = w.get_combined_minimum_size().x
        var dot: Vector2 = _star_screen_pos[i]
        # Flip above dot if widget would overflow bottom, else place below.
        var flip_up: bool = dot.y + WIDGET_OFFSET_BELOW + wh > map_h
        var pos_y: float
        if flip_up:
            pos_y = dot.y - wh - WIDGET_OFFSET_ABOVE
        else:
            pos_y = dot.y + WIDGET_OFFSET_BELOW
        # Clamp Y to keep widget fully inside map bounds.
        pos_y = clampf(pos_y, 0.0, maxf(0.0, map_h - wh))
        # Centre the widget horizontally on the dot, clamped to map bounds.
        var pos_x: float = clampf(dot.x - ww * 0.5, 0.0, maxf(0.0, map_w - ww))
        w.position = Vector2(pos_x, pos_y)


func _build_star_tags() -> void:
    call_deferred("_build_star_tags_impl")


func _build_star_tags_impl() -> void:
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
        var pitch_str: String = _confirmed_pitch_str_for_star(i)

        var name_lbl := Label.new()
        name_lbl.name = "NameLabel"
        name_lbl.text = name_str
        name_lbl.add_theme_font_size_override("font_size", 16)
        name_lbl.add_theme_color_override("font_color", star_color)
        name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var seq_lbl := Label.new()
        seq_lbl.name = "SeqLabel"
        seq_lbl.text = "%s" % _ordinal_str(seq_str)
        seq_lbl.add_theme_font_size_override("font_size", 16)
        seq_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        seq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var pitch_lbl := Label.new()
        pitch_lbl.name = "PitchLabel"
        pitch_lbl.text = pitch_str
        pitch_lbl.add_theme_font_size_override("font_size", 16)
        pitch_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        pitch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        vbox.add_child(name_lbl.duplicate())
        vbox.add_child(seq_lbl.duplicate())
        vbox.add_child(pitch_lbl.duplicate())
        hbox.add_child(name_lbl)
        hbox.add_child(seq_lbl)
        hbox.add_child(pitch_lbl)

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
        all_star_names: Array[String], star_color: Color, col_start: int = 0) -> void:
    var rows: Array = name_vbox.get_children()
    for ri in rows.size():
        var name_idx: int = col_start + ri
        if name_idx >= all_star_names.size():
            break
        var row: HBoxContainer = rows[ri]
        var name_lbl: Label = row.get_child(0)
        var btn_check: Button = row.get_child(1)
        var btn_x: Button = row.get_child(2)
        var captured_name: String = all_star_names[name_idx]
        var state: int = _effective_name_display_state(star_idx, captured_name, all_star_names)
        _apply_name_row_visual(state, name_lbl, btn_check, btn_x, star_color)


func _apply_name_row_visual(state: int, name_lbl: Label,
        btn_check: Button, btn_x: Button, star_color: Color) -> void:
    match state:
        1:  # confirmed ✓ (hard)
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(0.3, 1.0, 0.4, 1.0)
            btn_x.modulate = Color(1, 1, 1, 1.0)
        2:  # eliminated ✗ (hard)
            name_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.45, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1.0)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = Color(1.0, 0.35, 0.25, 1.0)
        3:  # soft-eliminated — another candidate in this row is protected
            name_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.55, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1.0)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = Color(1.0, 0.6, 0.5, 1.0)
        4:  # protected — TEMP debug: impossible to miss
            name_lbl.add_theme_color_override("font_color", Color(1, 0, 1, 1))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(1, 0, 1, 1)
            btn_x.modulate = Color(1, 0, 1, 1)
        _:  # neutral
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = Color(1, 1, 1, 1.0)


# ==================================================
# NAME STATE CALLBACKS
# ==================================================
func _on_name_check(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = _star_elim_state(star_idx, star_name)
    var new_state: int = 0 if cur == 1 else 1

    if new_state == 1:
        var name_record: int = _find_match_record_by_name(star_name)
        if name_record >= 0:
            var existing_star: int = int(_match_records[name_record].get("star_idx", -1))
            if existing_star >= 0 and existing_star != star_idx:
                _apply_name_row_visual(2, name_lbl, btn_check, btn_x, star_color)
                return
        var record_idx: int = _get_or_create_match_record_for_name(star_name)
        record_idx = await _confirm_match_record_identity(record_idx, star_idx, star_name)
        if record_idx < 0:
            _apply_name_row_visual(_star_elim_state(star_idx, star_name), name_lbl, btn_check, btn_x, star_color)
            return
        var resolved_name: String = str(_match_records[record_idx]["name"])
        _propagate_name_confirmed(star_idx, resolved_name)
        _save_puzzle_notes()
        _full_propagation_refresh()
        return

    var record_idx2: int = _get_or_create_match_record_for_name(star_name)
    var elim2: Dictionary = _match_records[record_idx2].get("star_elim", {})
    elim2[star_idx] = new_state
    _match_records[record_idx2]["star_elim"] = elim2
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)
    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_name_x(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var star_color: Color = STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = _star_elim_state(star_idx, star_name)
    var new_state: int = 0 if cur == 2 else 2

    var record_idx: int = _get_or_create_match_record_for_name(star_name)
    var elim: Dictionary = _match_records[record_idx].get("star_elim", {})
    elim[star_idx] = new_state
    _match_records[record_idx]["star_elim"] = elim
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)

    var ukey: String = "%d:%s" % [star_idx, star_name]
    if new_state == 2:
        _user_blocks[ukey] = true
    else:
        _user_blocks.erase(ukey)

    _save_puzzle_notes()
    _build_star_tags()
    if _active_marker_tab < 0:
        _populate_markers_panel()


# ==================================================
# UNDO NAME-SELECTION/NAME-BLOCK CALLBACKS
# ==================================================
func _clear_protected_names_for_star(star_idx: int) -> void:
    var to_erase: Array[String] = []
    for key in _protected_names.keys():
        var parts: PackedStringArray = key.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            to_erase.append(key)
    for k in to_erase:
        _protected_names.erase(k)


func _on_undo_name_selects(star_idx: int) -> void:
    var own_record: int = _find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _match_records[own_record]
        r["star_idx"] = -1
        var own_elim: Dictionary = r.get("star_elim", {})
        if own_elim.has(star_idx):
            own_elim.erase(star_idx)
            r["star_elim"] = own_elim
    for i in _match_records.size():
        if i == own_record:
            continue
        var other: Dictionary = _match_records[i]
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var other_name: String = str(other.get("name", ""))
        var ukey: String = "%d:%s" % [star_idx, other_name]
        if _user_blocks.has(ukey):
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if int(elim2.get(star_idx, 0)) == 2:
            elim2.erase(star_idx)
            other["star_elim"] = elim2
    _clear_protected_names_for_star(star_idx)
    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_undo_name_blocks(star_idx: int) -> void:
    var user_blocked_names: Array[String] = []
    for ukey in _user_blocks.keys():
        var parts: PackedStringArray = ukey.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            user_blocked_names.append(parts[1])
    for name_str in user_blocked_names:
        var rec: int = _find_match_record_by_name(name_str)
        if rec >= 0:
            var elim: Dictionary = _match_records[rec].get("star_elim", {})
            if elim.has(star_idx):
                elim.erase(star_idx)
                _match_records[rec]["star_elim"] = elim
        _user_blocks.erase("%d:%s" % [star_idx, name_str])
    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_undo_name_all(star_idx: int) -> void:
    var own_record: int = _find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _match_records[own_record]
        r["star_idx"] = -1
        var own_elim: Dictionary = r.get("star_elim", {})
        if own_elim.has(star_idx):
            own_elim.erase(star_idx)
            r["star_elim"] = own_elim

    # Union of "Undo selects" + "Undo blocks", scoped to this star's row only.
    # Names confirmed at a DIFFERENT star are left alone — that elimination
    # is structural (the name belongs elsewhere), not part of this star's row.
    for i in _match_records.size():
        if i == own_record:
            continue
        var other: Dictionary = _match_records[i]
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if elim2.has(star_idx):
            elim2.erase(star_idx)
            other["star_elim"] = elim2

    _clear_protected_names_for_star(star_idx)

    var user_blocked_names: Array[String] = []
    for ukey in _user_blocks.keys():
        var parts: PackedStringArray = ukey.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            user_blocked_names.append(parts[1])
    for name_str in user_blocked_names:
        _user_blocks.erase("%d:%s" % [star_idx, name_str])

    _save_puzzle_notes()
    _full_propagation_refresh()


# ==================================================
# NAME-PROPAGATION HELPERS
# ==================================================
func _propagate_name_confirmed(confirmed_star: int, star_name: String) -> void:
    # A name belongs to exactly one star in the WHOLE constellation. Now that
    # star_elim lives on _match_records instead of a separate per-star array,
    # this one write is visible from every display surface that reads the
    # same record — the map widgets, and any future Sort: tab that shows
    # name/star candidates — with nothing left to fall out of sync.
    var this_record: int = _get_or_create_match_record_for_name(star_name)
    var this_elim: Dictionary = _match_records[this_record].get("star_elim", {})
    for j in _star_count:
        this_elim[j] = 1 if j == confirmed_star else 2
    _match_records[this_record]["star_elim"] = this_elim

    for i in _match_records.size():
        if i == this_record:
            continue
        var r: Dictionary = _match_records[i]
        var elim: Dictionary = r.get("star_elim", {})
        var cur: int = int(elim.get(confirmed_star, 0))
        if cur != 1:
            elim[confirmed_star] = 2
        r["star_elim"] = elim

    _save_puzzle_notes()


# ==================================================
# RECORD IDENTITY LOOKUPS
# ==================================================

func _find_match_record_by_name(name_str: String) -> int:
    if name_str == "":
        return -1
    for i in _match_records.size():
        if _match_records[i]["name"] == name_str:
            return i
    return -1


func _star_elim_state(star_idx: int, name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx < 0:
        return 0
    var r: Dictionary = _match_records[idx]
    if int(r.get("star_idx", -1)) == star_idx:
        return 1
    return int(r.get("star_elim", {}).get(star_idx, 0))


func _star_confirmed_name(star_idx: int) -> String:
    for r in _match_records:
        if int(r.get("star_idx", -1)) == star_idx:
            return str(r.get("name", ""))
    return ""


func _on_star_name_expand_toggle(star_idx: int) -> void:
    _star_name_list_expanded[star_idx] = not _star_name_list_expanded.get(star_idx, false)
    _build_star_widgets()


func _on_star_name_dropdown_selected(star_idx: int, chosen_name: String) -> void:
    if chosen_name == "":
        var confirmed_name: String = _star_confirmed_name(star_idx)
        if confirmed_name == "":
            return
        var unassign_record_idx: int = _get_or_create_match_record_for_name(confirmed_name)
        var elim: Dictionary = _match_records[unassign_record_idx].get("star_elim", {})
        elim[star_idx] = 0
        _match_records[unassign_record_idx]["star_elim"] = elim
        if int(_match_records[unassign_record_idx].get("star_idx", -1)) == star_idx:
            _match_records[unassign_record_idx]["star_idx"] = -1
        _save_puzzle_notes()
        _full_propagation_refresh()
        return

    var record_idx: int = _get_or_create_match_record_for_name(chosen_name)
    record_idx = await _confirm_match_record_identity(record_idx, star_idx, chosen_name)
    if record_idx < 0:
        _full_propagation_refresh()
        return
    var resolved_name: String = str(_match_records[record_idx]["name"])
    _propagate_name_confirmed(star_idx, resolved_name)
    _save_puzzle_notes()
    _full_propagation_refresh()


func _possible_names_for_record(record_idx: int) -> Array[String]:
    var r: Dictionary = _match_records[record_idx]
    var this_star_idx: int = int(r.get("star_idx", -1))
    var this_name: String = str(r.get("name", ""))
    var this_seq_lo: int = int(r.get("seq_lo", 0))
    var this_seq_hi: int = int(r.get("seq_hi", 0))
    var this_seq_exact: int = this_seq_lo if this_seq_lo > 0 and this_seq_lo == this_seq_hi else -1
    var this_color_label: String = str(r.get("color_slot_label", ""))
    var this_pitch_label: String = str(r.get("pitch_slot_label", ""))

    var result: Array[String] = []
    for n in _star_names:
        var name_str: String = str(n)
        if name_str == this_name:
            result.append(name_str)
            continue

        var other_idx: int = _find_match_record_by_name(name_str)
        if other_idx >= 0 and other_idx != record_idx:
            var other: Dictionary = _match_records[other_idx]
            var other_star: int = int(other.get("star_idx", -1))
            var other_seq_lo: int = int(other.get("seq_lo", 0))
            var other_seq_hi: int = int(other.get("seq_hi", 0))
            var other_seq_exact: int = other_seq_lo if other_seq_lo > 0 and other_seq_lo == other_seq_hi else -1
            var other_color_label: String = str(other.get("color_slot_label", ""))
            var other_pitch_label: String = str(other.get("pitch_slot_label", ""))

            var conflict: bool = false
            var conflict_reason: String = ""
            if this_star_idx >= 0 and other_star >= 0 and other_star != this_star_idx:
                conflict = true
                conflict_reason = "star %d vs %d" % [this_star_idx, other_star]
            if this_seq_exact > 0 and other_seq_exact > 0 and other_seq_exact != this_seq_exact:
                conflict = true
                conflict_reason = "seq %d vs %d" % [this_seq_exact, other_seq_exact]
            if this_color_label != "" and other_color_label != "" and other_color_label != this_color_label:
                conflict = true
                conflict_reason = "color slot '%s' vs '%s'" % [this_color_label, other_color_label]
            if this_pitch_label != "" and other_pitch_label != "" and other_pitch_label != this_pitch_label:
                conflict = true
                conflict_reason = "pitch slot '%s' vs '%s'" % [this_pitch_label, other_pitch_label]
            if conflict:
                print("[DEBUG] possible_names: record %d excludes '%s' — %s" % [record_idx, name_str, conflict_reason])
                continue

        if this_star_idx >= 0 and _star_elim_state(this_star_idx, name_str) == 2:
            print("[DEBUG] possible_names: record %d excludes '%s' — X'd for this slot's star %d" % [record_idx, name_str, this_star_idx])
            continue

        result.append(name_str)
    result.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    return result


func _protect_key(star_idx: int, name_str: String) -> String:
    return "%d:%s" % [star_idx, name_str]


func _is_name_protected(star_idx: int, name_str: String) -> bool:
    return _protected_names.has(_protect_key(star_idx, name_str))


func _star_has_any_protected(star_idx: int, all_names_for_star: Array) -> bool:
    # Ignores stale protect flags on names that got hard-decided by some
    # other means since being protected (e.g. a later color elimination) —
    # only a name still sitting at neutral counts toward "protected."
    for n in all_names_for_star:
        var name_str: String = str(n)
        if _is_name_protected(star_idx, name_str) and _star_elim_state(star_idx, name_str) == 0:
            return true
    return false


func _effective_name_display_state(star_idx: int, name_str: String, all_names_for_star: Array) -> int:
    var base: int = _star_elim_state(star_idx, name_str)
    if base != 0:
        return base   # hard confirm (1) or hard eliminate (2) always wins
    if not _star_has_any_protected(star_idx, all_names_for_star):
        return 0       # neutral, nobody's protected anything yet in this row
    return 4 if _is_name_protected(star_idx, name_str) else 3


func _on_name_protect_toggle(star_idx: int, star_name: String) -> void:
    var base: int = _star_elim_state(star_idx, star_name)
    if base != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    var key: String = _protect_key(star_idx, star_name)
    if _protected_names.has(key):
        _protected_names.erase(key)
    else:
        _protected_names[key] = true
    _save_puzzle_notes()
    _full_propagation_refresh()


func _apply_color_elimination_to_names(record_idx: int, color_idx: int, new_state: int) -> void:
    # Color is the one axis directly visible per star, so it's the one axis
    # that can safely auto-propagate into the name/star grid without leaking
    # anything the player hasn't earned. Sequence and pitch are themselves
    # unknowns from the player's perspective, so they intentionally do NOT
    # get this treatment — they only unify through record merging once
    # identity is independently confirmed.
    var r: Dictionary = _match_records[record_idx]
    var elim: Dictionary = r.get("star_elim", {})
    var name_str: String = str(r.get("name", ""))
    if name_str == "":
        return
    if new_state == 2:
        for s in _star_count:
            var sc: int = _star_colors[s] if s < _star_colors.size() else 1
            if sc == color_idx and int(elim.get(s, 0)) != 1:
                elim[s] = 2
    elif new_state == 1:
        for s in _star_count:
            var sc2: int = _star_colors[s] if s < _star_colors.size() else 1
            if sc2 != color_idx and int(elim.get(s, 0)) != 1:
                elim[s] = 2
    r["star_elim"] = elim


func _slot_letter(idx: int) -> String:
    return char(65 + idx) if idx < 26 else str(idx + 1)


func _anonymous_star_label(star_idx: int) -> String:
    var color_idx: int = _star_colors[star_idx] if star_idx < _star_colors.size() else 1
    var color_name: String = COLOR_NAME_LABELS[clamp(color_idx, 0, COLOR_NAME_LABELS.size() - 1)]
    var ordinal: int = 0
    for s in _star_count:
        var sc: int = _star_colors[s] if s < _star_colors.size() else 1
        if sc == color_idx and s < star_idx:
            ordinal += 1
    return "%s star %s" % [color_name, _slot_letter(ordinal)]




func _known_color_for_record(record_idx: int) -> int:
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        return _star_colors[star_idx] if star_idx < _star_colors.size() else -1
    var cs: Dictionary = r.get("color_states", {})
    for ci in COLOR_NAME_LABELS.size():
        if int(cs.get(ci, 0)) == 1:
            return ci
    return -1


func _sync_color_states_from_star_idx(record_idx: int) -> void:
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx < 0 or star_idx >= _star_colors.size():
        return
    var true_color: int = clamp(_star_colors[star_idx], 0, 3)
    for ci in COLOR_NAME_LABELS.size():
        r["color_states"][ci] = 1 if ci == true_color else 2


func _get_or_create_match_record_for_color_slot(color_idx: int, position_in_group: int) -> int:
    var label: String = "%s %s" % [COLOR_NAME_LABELS[color_idx], _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("color_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("color_slot_label", "")) != "":
            continue
        if int(r.get("color_states", {}).get(color_idx, 0)) == 1:
            r["color_slot_label"] = label
            return i
    _match_records.append({
        "name": "",
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": label,
        "pitch_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_pitch_slot(pitch_freq: float, position_in_group: int) -> int:
    var pitch_name: String = ConstellationLogicPuzzle.note_name_for_freq(pitch_freq)
    var label: String = "%s %s" % [pitch_name, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("pitch_slot_label", "")) == label:
            return i
    var note_name: String = pitch_name
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("pitch_slot_label", "")) != "":
            continue
        if int(r.get("pitch_states", {}).get(note_name, 0)) == 1:
            r["pitch_slot_label"] = label
            return i
    _match_records.append({
        "name": "",
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": label,
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_name(name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx >= 0:
        return idx
    _match_records.append({
        "name": name_str,
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_seq(slot: int) -> int:
    var idx: int = _find_match_record_by_exact_seq(slot)
    if idx >= 0:
        return idx
    _match_records.append({
        "name": "",
        "seq_lo": slot, "seq_hi": slot,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_star_idx(star_idx: int) -> int:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        return idx
    _match_records.append({
        "name": "",
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": star_idx,
        "color_slot_label": "",
        "pitch_slot_label": "",
    })
    return _match_records.size() - 1


func _find_match_record_by_exact_seq(seq: int) -> int:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r["seq_lo"]) > 0 and int(r["seq_lo"]) == int(r["seq_hi"]) and int(r["seq_lo"]) == seq:
            return i
    return -1


func _find_match_record_by_star_idx(star_idx: int) -> int:
    if star_idx < 0:
        return -1
    for i in _match_records.size():
        if int(_match_records[i]["star_idx"]) == star_idx:
            return i
    return -1


func _show_conflict_choice(what: String, value_a: String, value_b: String) -> String:
    var dlg := AcceptDialog.new()
    dlg.title = "Conflicting %s" % what
    dlg.dialog_text = "Two entries disagree on %s. Which is correct?" % what
    dlg.get_ok_button().hide()
    dlg.add_button("Keep: %s" % value_a, false, "choice_a")
    dlg.add_button("Keep: %s" % value_b, false, "choice_b")
    add_child(dlg)
    dlg.popup_centered()
    var chosen_action: String = await dlg.custom_action
    dlg.queue_free()
    var winner: String = value_a if chosen_action == "choice_a" else value_b
    var loser: String = value_b if chosen_action == "choice_a" else value_a
    print("[CONFLICT] %s: kept '%s', discarded '%s'" % [what, winner, loser])
    return winner


func _merge_match_records(target_idx: int, source_idx: int) -> int:
    if target_idx == source_idx:
        return target_idx
    var target: Dictionary = _match_records[target_idx]
    var source: Dictionary = _match_records[source_idx]

    # Tracks a name that lost the "Keep: X / Keep: Y" conflict below, so it can
    # be explicitly re-eliminated for the resolved star after its own record
    # gets deleted by this merge — otherwise that elimination is lost entirely
    # and the checklist row comes back up neutral next rebuild.
    var discarded_name: String = ""

    if target["name"] == "" and source["name"] != "":
        target["name"] = source["name"]
    elif target["name"] != "" and source["name"] != "" and target["name"] != source["name"]:
        var kept_name: String = await _show_conflict_choice("name", target["name"], source["name"])
        discarded_name = source["name"] if kept_name == target["name"] else target["name"]
        target["name"] = kept_name

    if int(target["seq_lo"]) == 0 and int(source["seq_lo"]) > 0:
        target["seq_lo"] = source["seq_lo"]
        target["seq_hi"] = source["seq_hi"]
    elif int(target["seq_lo"]) > 0 and int(source["seq_lo"]) > 0 and int(target["seq_lo"]) != int(source["seq_lo"]):
        var winning_seq: int = int(await _show_conflict_choice(
            "sequence position", str(int(target["seq_lo"])), str(int(source["seq_lo"]))))
        target["seq_lo"] = winning_seq
        target["seq_hi"] = winning_seq

    var target_cand: Array = target.get("seq_candidates", [])
    var source_cand: Array = source.get("seq_candidates", [])
    if target_cand.is_empty() and not source_cand.is_empty():
        target["seq_candidates"] = source_cand.duplicate()
    elif not target_cand.is_empty() and not source_cand.is_empty():
        var merged_cand: Array = []
        for v in target_cand:
            if source_cand.has(v):
                merged_cand.append(v)
        target["seq_candidates"] = merged_cand

    for ck in source["color_states"]:
        var sv: int = int(source["color_states"][ck])
        var tv: int = int(target["color_states"].get(ck, 0))
        if sv == 1 or tv == 1:
            target["color_states"][ck] = 1
        elif sv == 2 or tv == 2:
            target["color_states"][ck] = 2

    var target_confirmed_note: String = ""
    for pk0 in target["pitch_states"]:
        if int(target["pitch_states"][pk0]) == 1:
            target_confirmed_note = str(pk0)
            break
    var source_confirmed_note: String = ""
    for pk1 in source["pitch_states"]:
        if int(source["pitch_states"][pk1]) == 1:
            source_confirmed_note = str(pk1)
            break
    if target_confirmed_note != "" and source_confirmed_note != "" and target_confirmed_note != source_confirmed_note:
        var winning_note: String = await _show_conflict_choice(
            "confirmed pitch", target_confirmed_note, source_confirmed_note)
        if winning_note == source_confirmed_note:
            target["pitch_states"][target_confirmed_note] = 0
            target_confirmed_note = source_confirmed_note
        else:
            source["pitch_states"][source_confirmed_note] = 0
            source_confirmed_note = ""

    for pk in source["pitch_states"]:
        var sv2: int = int(source["pitch_states"][pk])
        var tv2: int = int(target["pitch_states"].get(pk, 0))
        if pk == source_confirmed_note and target_confirmed_note != "" and pk != target_confirmed_note:
            continue
        if sv2 == 1 or tv2 == 1:
            target["pitch_states"][pk] = 1
        elif sv2 == 2 or tv2 == 2:
            target["pitch_states"][pk] = 2

    if bool(source.get("pitch_revealed", false)):
        target["pitch_revealed"] = true

    var target_elim: Dictionary = target.get("star_elim", {})
    var source_elim: Dictionary = source.get("star_elim", {})
    for sk in source_elim:
        var sv3: int = int(source_elim[sk])
        var tv3: int = int(target_elim.get(sk, 0))
        if sv3 == 1 or tv3 == 1:
            target_elim[sk] = 1
        elif sv3 == 2 or tv3 == 2:
            target_elim[sk] = 2
    target["star_elim"] = target_elim

    if int(target["star_idx"]) < 0 and int(source["star_idx"]) >= 0:
        target["star_idx"] = source["star_idx"]

    var target_label: String = str(target.get("color_slot_label", ""))
    var source_label: String = str(source.get("color_slot_label", ""))
    if target_label == "" and source_label != "":
        target["color_slot_label"] = source_label
    elif target_label != "" and source_label != "" and target_label != source_label:
        target["color_slot_label"] = await _show_conflict_choice("color slot label", target_label, source_label)

    var target_pitch_label: String = str(target.get("pitch_slot_label", ""))
    var source_pitch_label: String = str(source.get("pitch_slot_label", ""))
    if target_pitch_label == "" and source_pitch_label != "":
        target["pitch_slot_label"] = source_pitch_label
    elif target_pitch_label != "" and source_pitch_label != "" and target_pitch_label != source_pitch_label:
        target["pitch_slot_label"] = await _show_conflict_choice("pitch slot label", target_pitch_label, source_pitch_label)

    _sync_color_states_from_star_idx(target_idx)

    _match_records.remove_at(source_idx)
    if source_idx < target_idx:
        target_idx -= 1

    # The name that lost the conflict above no longer has any record of its own —
    # whichever side it came from was just deleted. Re-create a blank record for
    # it now and immediately mark it eliminated for the star this merged record
    # ended up representing, so the checklist row stays darkened instead of
    # reverting to a fresh, unmarked neutral candidate on the next rebuild.
    if discarded_name != "" and int(_match_records[target_idx]["star_idx"]) >= 0:
        var resolved_star: int = int(_match_records[target_idx]["star_idx"])
        var loser_record_idx: int = _get_or_create_match_record_for_name(discarded_name)
        if loser_record_idx != target_idx:
            var loser_elim: Dictionary = _match_records[loser_record_idx].get("star_elim", {})
            loser_elim[resolved_star] = 2
            _match_records[loser_record_idx]["star_elim"] = loser_elim

    return target_idx


func _confirm_match_record_identity(record_idx: int, star_idx: int, star_name: String) -> int:
    var existing_by_star: int = _find_match_record_by_star_idx(star_idx)
    if existing_by_star >= 0 and existing_by_star != record_idx:
        record_idx = await _merge_match_records(record_idx, existing_by_star)

    var r: Dictionary = _match_records[record_idx]
    if int(r["star_idx"]) >= 0 and int(r["star_idx"]) != star_idx:
        var old_label: String = "%s (current)" % _anonymous_star_label(int(r["star_idx"]))
        var new_label: String = "%s (just checked)" % _anonymous_star_label(star_idx)
        var winner: String = await _show_conflict_choice(
            "star identity for '%s'" % star_name, old_label, new_label)
        if winner == old_label:
            return -1

    if str(r["name"]) == "":
        r["name"] = star_name
    r["star_idx"] = star_idx

    var true_color: int = clamp(_star_colors[star_idx] if star_idx < _star_colors.size() else 1, 0, 3)
    for ci in COLOR_NAME_LABELS.size():
        r["color_states"][ci] = 1 if ci == true_color else 2

    var elim: Dictionary = r.get("star_elim", {})
    for j in _star_count:
        elim[j] = 1 if j == star_idx else 2
    r["star_elim"] = elim

    return record_idx


func _save_match_records() -> Array:
    var out: Array = []
    for r in _match_records:
        out.append({
            "name": r["name"],
            "seq_lo": r["seq_lo"], "seq_hi": r["seq_hi"],
            "seq_candidates": (r.get("seq_candidates", []) as Array).duplicate(),
            "color_states": (r["color_states"] as Dictionary).duplicate(),
            "pitch_states": (r["pitch_states"] as Dictionary).duplicate(),
            "pitch_revealed": bool(r.get("pitch_revealed", false)),
            "star_elim": (r.get("star_elim", {}) as Dictionary).duplicate(),
            "star_idx": r["star_idx"],
            "color_slot_label": str(r.get("color_slot_label", "")),
            "pitch_slot_label": str(r.get("pitch_slot_label", "")),
        })
    return out


func _load_match_records(data: Array) -> void:
    _match_records.clear()
    for entry in data:
        var e: Dictionary = entry
        var color_states: Dictionary = {}
        for ck in e.get("color_states", {}):
            color_states[int(ck)] = int(e["color_states"][ck])
        var pitch_states: Dictionary = {}
        for pk in e.get("pitch_states", {}):
            pitch_states[str(pk)] = int(e["pitch_states"][pk])
        var star_elim: Dictionary = {}
        for sk in e.get("star_elim", {}):
            star_elim[int(sk)] = int(e["star_elim"][sk])
        var seq_candidates: Array = []
        for v in e.get("seq_candidates", []):
            seq_candidates.append(int(v))
        _match_records.append({
            "name": str(e.get("name", "")),
            "seq_lo": int(e.get("seq_lo", 0)), "seq_hi": int(e.get("seq_hi", 0)),
            "seq_candidates": seq_candidates,
            "color_states": color_states,
            "pitch_states": pitch_states,
            "pitch_revealed": bool(e.get("pitch_revealed", false)),
            "star_elim": star_elim,
            "pitch_carousel_idx": 0,
            "star_idx": int(e.get("star_idx", -1)),
            "color_slot_label": str(e.get("color_slot_label", "")),
            "pitch_slot_label": str(e.get("pitch_slot_label", "")),
        })


func _display_color_for_record(record_idx: int) -> Color:
    if record_idx < 0 or record_idx >= _match_records.size():
        return Color(0.2, 0.9, 0.2, 1)
    var r: Dictionary = _match_records[record_idx]
    for ck in r["color_states"]:
        if int(r["color_states"][ck]) == 1:
            return STAR_COLORS_BY_IDX[int(ck)]
    return Color(0.2, 0.9, 0.2, 1)


func _debug_dump_named_records() -> void:
    for watch_name in ["Eosaara", "Pyrios"]:
        var idx: int = _find_match_record_by_name(watch_name)
        if idx < 0:
            print("[DEBUG] record for '%s': NOT FOUND" % watch_name)
            continue
        var r: Dictionary = _match_records[idx]
        print("[DEBUG] record for '%s': star_idx=%d color_slot_label='%s' color_states=%s" %
            [watch_name, int(r.get("star_idx", -1)), str(r.get("color_slot_label", "")), str(r.get("color_states", {}))])


func _make_color_toggle_row_for_record(record_idx: int) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    # Alphabetical order: Blue(0), Red(3), White(1), Yellow(2)
    var btn_order: Array = [0, 3, 1, 2]
    for ci in btn_order:
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(26, 24)
        btn.focus_mode = Control.FOCUS_NONE
        btn.add_theme_font_size_override("font_size", 13)
        var cidx: int = int(ci)
        var ridx := record_idx
        btn.pressed.connect(func(): _on_record_color_toggle(ridx, cidx, btn))
        var cur_state: int = int(_match_records[record_idx]["color_states"].get(ci, 0))
        _style_color_toggle_btn(btn, ci, cur_state)
        row.add_child(btn)
    return row


func _propagate_color_confirmed_same_record(record_idx: int, confirmed_color_idx: int) -> void:
    # Confirming one color on a record means every OTHER color is
    # automatically eliminated on that SAME record — a slot/name/star can
    # only be one color.
    var r: Dictionary = _match_records[record_idx]
    for ci in COLOR_NAME_LABELS.size():
        if ci != confirmed_color_idx:
            r["color_states"][ci] = 2


func _on_record_color_toggle(record_idx: int, color_idx: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = (cur + 1) % 3
    r["color_states"][color_idx] = new_state
    _style_color_toggle_btn(btn, color_idx, new_state)
    _apply_color_elimination_to_names(record_idx, color_idx, new_state)

    if new_state == 1:
        _propagate_color_confirmed_same_record(record_idx, color_idx)

    _save_puzzle_notes()
    _full_propagation_refresh()


func _make_pitch_carousel_row_for_record(record_idx: int) -> HBoxContainer:
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

    var ridx := record_idx

    var refresh_carousel := func():
        var r: Dictionary = _match_records[ridx]
        var confirmed_note: String = ""
        for n in notes_list:
            if int(r["pitch_states"].get(n, 0)) == 1:
                confirmed_note = n
                break
        if confirmed_note != "":
            r["pitch_carousel_idx"] = notes_list.find(confirmed_note)

        var i: int = int(r["pitch_carousel_idx"]) % notes_list.size()
        var note: String = notes_list[i]
        var state: int = int(r["pitch_states"].get(note, 0))
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
        var r: Dictionary = _match_records[ridx]
        var i: int = int(r["pitch_carousel_idx"])
        r["pitch_carousel_idx"] = (i - 1 + notes_list.size()) % notes_list.size()
        refresh_carousel.call())
    btn_next.pressed.connect(func():
        var r: Dictionary = _match_records[ridx]
        var i: int = int(r["pitch_carousel_idx"])
        r["pitch_carousel_idx"] = (i + 1) % notes_list.size()
        refresh_carousel.call())
    btn_mark.pressed.connect(func():
        var r: Dictionary = _match_records[ridx]
        if bool(r.get("pitch_revealed", false)):
            return
        var i: int = int(r["pitch_carousel_idx"]) % notes_list.size()
        var note: String = notes_list[i]
        var cur: int = int(r["pitch_states"].get(note, 0))
        r["pitch_states"][note] = (cur + 1) % 3
        _save_puzzle_notes()
        refresh_carousel.call())

    refresh_carousel.call()
    return row


func _compressed_possible_positions_str(record_idx: int) -> String:
    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return ""
    if candidates.size() == _star_count:
        return ""
    candidates.sort()
    if candidates.size() == 1:
        return str(candidates[0])

    var segments: Array = []
    var seg_start: int = candidates[0]
    var prev: int = candidates[0]
    for idx in range(1, candidates.size()):
        var c: int = candidates[idx]
        if c == prev + 1:
            prev = c
        else:
            segments.append([seg_start, prev])
            seg_start = c
            prev = c
    segments.append([seg_start, prev])

    var parts: Array = []
    for seg in segments:
        parts.append(str(seg[0]) if seg[0] == seg[1] else "%d-%d" % [seg[0], seg[1]])
    return ",".join(parts)


func _make_sequence_range_row_for_record(record_idx: int, row_color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 2)

    var bounds: Array = _effective_seq_bounds(record_idx)

    var edit_lo := LineEdit.new()
    edit_lo.custom_minimum_size = Vector2(20, 24)
    edit_lo.max_length = 2
    edit_lo.placeholder_text = "\u2013"
    var lo_val: int = _exclusive_display_lo(int(bounds[0]), int(bounds[1]))
    edit_lo.text = str(lo_val) if lo_val > 0 else ""
    edit_lo.add_theme_font_size_override("font_size", 12)
    edit_lo.add_theme_constant_override("minimum_character_width", 2)
    _style_range_edit(edit_lo, row_color)
    row.add_child(edit_lo)

    var lbl_lt := Label.new()
    lbl_lt.text = "<"
    lbl_lt.add_theme_font_size_override("font_size", 13)
    lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_lt)

    var edit_mid := LineEdit.new()
    edit_mid.custom_minimum_size = Vector2(58, 24)
    edit_mid.max_length = 12
    edit_mid.placeholder_text = "\u2013"
    edit_mid.text = _compressed_possible_positions_str(record_idx)
    edit_mid.add_theme_font_size_override("font_size", 11)
    edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _style_range_edit(edit_mid, row_color)
    row.add_child(edit_mid)

    var lbl_gt := Label.new()
    lbl_gt.text = "<"
    lbl_gt.add_theme_font_size_override("font_size", 13)
    lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_gt)

    var edit_hi := LineEdit.new()
    edit_hi.custom_minimum_size = Vector2(20, 24)
    edit_hi.max_length = 2
    edit_hi.placeholder_text = "\u2013"
    var hi_val: int = _exclusive_display_hi(int(bounds[0]), int(bounds[1]))
    edit_hi.text = str(hi_val) if hi_val > 0 else ""
    edit_hi.add_theme_font_size_override("font_size", 12)
    edit_hi.add_theme_constant_override("minimum_character_width", 2)
    _style_range_edit(edit_hi, row_color)
    row.add_child(edit_hi)

    var ridx := record_idx
    edit_lo.text_submitted.connect(func(_t): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_lo.focus_exited.connect(func(): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_hi.text_submitted.connect(func(_t): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_hi.focus_exited.connect(func(): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_mid.text_submitted.connect(func(_t): _on_record_middle_committed(ridx, edit_lo, edit_mid, edit_hi))
    edit_mid.focus_exited.connect(func(): _on_record_middle_committed(ridx, edit_lo, edit_mid, edit_hi))

    return row


func _on_record_range_committed(record_idx: int, lo_edit: LineEdit, hi_edit: LineEdit) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    var typed_lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var typed_hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    if typed_lo < 1 or typed_lo > _star_count: typed_lo = 0
    if typed_hi < 1 or typed_hi > _star_count: typed_hi = 0

    if typed_lo > 0 and typed_hi > 0 and typed_lo > typed_hi:
        var tmp := typed_lo; typed_lo = typed_hi; typed_hi = tmp

    var converted: Array = _parse_exclusive_bounds(typed_lo, typed_hi)
    var lo: int = int(converted[0])
    var hi: int = int(converted[1])

    var r: Dictionary = _match_records[record_idx]
    r["seq_lo"] = lo
    r["seq_hi"] = hi
    r["seq_candidates"] = []

    lo_edit.text = str(_exclusive_display_lo(lo, hi)) if lo > 0 else ""
    hi_edit.text = str(_exclusive_display_hi(lo, hi)) if hi > 0 else ""

    if lo > 0 and lo == hi:
        var existing_idx: int = _find_match_record_by_exact_seq(lo)
        if existing_idx >= 0 and existing_idx != record_idx:
            record_idx = await _merge_match_records(record_idx, existing_idx)

    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_record_middle_committed(record_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    var raw: String = mid_edit.text.strip_edges()
    if raw == "":
        _match_records[record_idx]["seq_candidates"] = []
        mid_edit.text = _compressed_possible_positions_str(record_idx)
        return

    var parsed: Array = _parse_candidate_list(raw)
    var valid: Array = []
    for p in parsed:
        if p >= 1 and p <= _star_count:
            valid.append(p)

    if valid.is_empty():
        mid_edit.text = _compressed_possible_positions_str(record_idx)
        return

    if valid.size() == 1:
        lo_edit.text = str(valid[0])
        hi_edit.text = str(valid[0])
        _on_record_range_committed(record_idx, lo_edit, hi_edit)
        return

    _match_records[record_idx]["seq_candidates"] = valid
    _match_records[record_idx]["seq_lo"] = 0
    _match_records[record_idx]["seq_hi"] = 0
    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_record_name_selected(record_idx: int, selected_name: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    if str(_match_records[record_idx].get("name", "")) == selected_name:
        return

    if selected_name == "":
        _match_records[record_idx]["name"] = ""
        _save_puzzle_notes()
        _full_propagation_refresh()
        return

    _match_records[record_idx]["name"] = selected_name

    var existing_idx: int = _find_match_record_by_name(selected_name)
    if existing_idx >= 0 and existing_idx != record_idx:
        record_idx = await _merge_match_records(record_idx, existing_idx)

    _save_puzzle_notes()
    _full_propagation_refresh()


# ==================================================
# RANGE CALLBACKS
# ==================================================
func _on_widget_range_committed(star_idx: int, lo_edit: LineEdit, hi_edit: LineEdit) -> void:
    if star_idx < 0 or star_idx >= _star_count:
        return
    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    var typed_lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var typed_hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    if typed_lo < 1 or typed_lo > _star_count: typed_lo = 0
    if typed_hi < 1 or typed_hi > _star_count: typed_hi = 0

    if typed_lo > 0 and typed_hi > 0 and typed_lo > typed_hi:
        var tmp := typed_lo; typed_lo = typed_hi; typed_hi = tmp

    var converted: Array = _parse_exclusive_bounds(typed_lo, typed_hi)
    var lo: int = int(converted[0])
    var hi: int = int(converted[1])

    lo_edit.text = str(_exclusive_display_lo(lo, hi)) if lo > 0 else ""
    hi_edit.text = str(_exclusive_display_hi(lo, hi)) if hi > 0 else ""

    var record_idx: int = _get_or_create_match_record_for_star_idx(star_idx)
    _match_records[record_idx]["seq_lo"] = lo
    _match_records[record_idx]["seq_hi"] = hi
    _match_records[record_idx]["seq_candidates"] = []

    if lo > 0 and lo == hi:
        var existing_idx: int = _find_match_record_by_exact_seq(lo)
        if existing_idx >= 0 and existing_idx != record_idx:
            record_idx = await _merge_match_records(record_idx, existing_idx)

    _save_puzzle_notes()
    _full_propagation_refresh()


func _on_widget_middle_committed(star_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    var record_idx: int = _get_or_create_match_record_for_star_idx(star_idx)
    var raw: String = mid_edit.text.strip_edges()
    if raw == "":
        _match_records[record_idx]["seq_candidates"] = []
        mid_edit.text = _compressed_possible_positions_str(record_idx)
        return
    var parsed: Array = _parse_candidate_list(raw)
    var valid: Array = []
    for p in parsed:
        if p >= 1 and p <= _star_count:
            valid.append(p)
    if valid.is_empty():
        mid_edit.text = _compressed_possible_positions_str(record_idx)
        return
    if valid.size() == 1:
        lo_edit.text = str(valid[0])
        hi_edit.text = str(valid[0])
        _on_widget_range_committed(star_idx, lo_edit, hi_edit)
        return
    _match_records[record_idx]["seq_candidates"] = valid
    _match_records[record_idx]["seq_lo"] = 0
    _match_records[record_idx]["seq_hi"] = 0
    _save_puzzle_notes()
    _full_propagation_refresh()


func _effective_color_state(record_idx: int, color_idx: int) -> int:
    # Three sources of "known color" for a record, checked in order of
    # certainty: ground-truth visible color (star-anchored), the slot label
    # itself (a "Blue A" row is structurally Blue even though nothing ever
    # writes that into color_states), then whatever the player has actually
    # toggled.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        var true_color: int = _star_colors[star_idx] if star_idx < _star_colors.size() else -1
        return 1 if true_color == color_idx else 2

    var label: String = str(r.get("color_slot_label", ""))
    if label != "":
        var label_color: int = COLOR_NAME_LABELS.find(label.get_slice(" ", 0))
        if label_color >= 0:
            return 1 if label_color == color_idx else 2

    return int(r.get("color_states", {}).get(color_idx, 0))


func _records_provably_distinct(idx_a: int, idx_b: int) -> bool:
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var a_star: int = int(a.get("star_idx", -1))
    var b_star: int = int(b.get("star_idx", -1))
    if a_star >= 0 and b_star >= 0:
        return a_star != b_star

    var a_name: String = str(a.get("name", ""))
    var b_name: String = str(b.get("name", ""))
    if a_name != "" and b_name != "" and a_name != b_name:
        return true

    for ci in COLOR_NAME_LABELS.size():
        var sa: int = _effective_color_state(idx_a, ci)
        var sb: int = _effective_color_state(idx_b, ci)
        if (sa == 1 and sb == 2) or (sb == 1 and sa == 2):
            return true

    return false


func _parse_candidate_list(raw: String) -> Array:
    var result: Dictionary = {}
    for chunk in raw.split(",", false):
        var c: String = chunk.strip_edges()
        if c == "":
            continue
        var dash: int = c.find("-")
        if dash > 0:
            var a_str: String = c.substr(0, dash).strip_edges()
            var b_str: String = c.substr(dash + 1).strip_edges()
            if a_str.is_valid_int() and b_str.is_valid_int():
                var a: int = int(a_str)
                var b: int = int(b_str)
                if a > b:
                    var tmp := a; a = b; b = tmp
                for p in range(a, b + 1):
                    result[p] = true
        elif c.is_valid_int():
            result[int(c)] = true
    var out: Array = result.keys()
    out.sort()
    return out


func _effective_seq_candidates(record_idx: int) -> Array:
    var r: Dictionary = _match_records[record_idx]
    var explicit: Array = r.get("seq_candidates", [])
    var base: Array = []
    if not explicit.is_empty():
        base = explicit.duplicate()
    else:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo <= 0:
            lo = 1
        if hi <= 0:
            hi = _star_count
        for p in range(lo, hi + 1):
            base.append(p)

    var excluded: Array = _compute_excluded_positions_for(record_idx)
    var result: Array = []
    for p in base:
        if not excluded.has(p):
            result.append(p)
    return result


func _compute_excluded_positions_for(record_idx: int) -> Array:
    # Scans the CURRENT full set of records live, every call. Nothing is
    # stored or pushed, so a record created AFTER some other record's
    # position was confirmed still sees the exclusion correctly — proven
    # necessary by the Sort:Color test: color-slot records created after
    # the Blue/15 confirmation never received a one-time push, because a
    # push cannot reach something that doesn't exist yet.
    var excluded: Array = []
    for i in _match_records.size():
        if i == record_idx:
            continue
        var r: Dictionary = _match_records[i]
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo > 0 and lo == hi and _records_provably_distinct(record_idx, i):
            excluded.append(lo)
    return excluded


func _exclusive_display_lo(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_lo <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_lo
    return inclusive_lo - 1


func _exclusive_display_hi(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_hi <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_hi
    var shown: int = inclusive_hi + 1
    return 0 if shown > _star_count else shown


func _parse_exclusive_bounds(raw_lo: int, raw_hi: int) -> Array:
    if raw_lo > 0 and raw_hi > 0 and raw_lo == raw_hi:
        return [raw_lo, raw_hi]
    var lo: int = raw_lo + 1 if raw_lo > 0 else 0
    var hi: int = raw_hi - 1 if raw_hi > 0 else 0
    if lo > 0 and hi > 0 and lo > hi:
        return [0, 0]
    return [lo, hi]


func _effective_seq_bounds(record_idx: int) -> Array:
    var r: Dictionary = _match_records[record_idx]
    var stored_lo: int = int(r.get("seq_lo", 0))
    var stored_hi: int = int(r.get("seq_hi", 0))
    if stored_lo > 0 and stored_lo == stored_hi and (r.get("seq_candidates", []) as Array).is_empty():
        return [stored_lo, stored_hi, []]

    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return [0, 0, []]

    candidates.sort()
    var eff_lo: int = candidates[0]
    var eff_hi: int = candidates[candidates.size() - 1]

    var mid_excluded: Array = []
    for p in range(eff_lo, eff_hi + 1):
        if not candidates.has(p):
            mid_excluded.append(p)

    var display_lo: int = eff_lo if (stored_lo > 0 or eff_lo > 1) else 0
    var display_hi: int = eff_hi if (stored_hi > 0 or eff_hi < _star_count) else 0
    return [display_lo, display_hi, mid_excluded]


func _full_propagation_refresh() -> void:
    _build_star_widgets()
    _build_star_tags()
    _melody_staff_panel.queue_redraw()
    call_deferred("_populate_markers_panel")





# ==================================================
# CLUE LIST
# ==================================================

var _color_regexes: Array = []

func _bbcode_for_clue_text(text: String) -> String:
    if _color_regexes.is_empty():
        for color_name in COLOR_NAME_LABELS:
            var re := RegEx.new()
            re.compile("(?i)\\b%s\\b" % color_name.replace("-", "\\-"))
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
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 1.0))
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





func _build_sequence_slot_row(slot: int) -> void:
    var record_idx: int = _get_or_create_match_record_for_seq(slot)
    var row_color: Color = _display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _markers_content.add_child(row)

    var seq_lbl := Label.new()
    seq_lbl.text = _ordinal(slot)
    seq_lbl.custom_minimum_size = Vector2(64, 0)
    seq_lbl.add_theme_font_size_override("font_size", 16)
    seq_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(seq_lbl)

    var name_dropdown := OptionButton.new()
    name_dropdown.custom_minimum_size = Vector2(120, 0)
    var possible_names: Array[String] = _possible_names_for_record(record_idx)
    var current_name: String = str(_match_records[record_idx]["name"])
    name_dropdown.add_item("— none —")
    name_dropdown.set_item_metadata(0, "")
    var selected_idx: int = 0
    for pn in possible_names:
        name_dropdown.add_item(pn)
        var item_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(item_idx, pn)
        if pn == current_name:
            selected_idx = item_idx
    if current_name != "" and not possible_names.has(current_name):
        name_dropdown.add_item(current_name)
        var extra_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(extra_idx, current_name)
        selected_idx = extra_idx
    name_dropdown.selected = selected_idx

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", name_dropdown, row_color))
    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row_for_record(record_idx), row_color))

    var ridx := record_idx
    var dropdown_ref := name_dropdown
    name_dropdown.item_selected.connect(func(idx: int):
        var chosen: String = str(dropdown_ref.get_item_metadata(idx))
        await _on_record_name_selected(ridx, chosen))

    _markers_content.add_child(HSeparator.new())


func _populate_sequence_slot_rows() -> void:
    for slot in range(1, _star_count + 1):
        _build_sequence_slot_row(slot)


func _build_color_group_row(color_idx: int, position_in_group: int) -> void:
    var record_idx: int = _get_or_create_match_record_for_color_slot(color_idx, position_in_group)
    var row_color: Color = _display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _markers_content.add_child(row)

    var color_lbl := Label.new()
    color_lbl.text = COLOR_NAME_LABELS[color_idx]
    color_lbl.custom_minimum_size = Vector2(64, 0)
    color_lbl.add_theme_font_size_override("font_size", 16)
    color_lbl.add_theme_color_override("font_color", STAR_COLORS_BY_IDX[color_idx])
    row.add_child(color_lbl)

    var name_dropdown := OptionButton.new()
    name_dropdown.custom_minimum_size = Vector2(120, 0)
    var possible_names: Array[String] = _possible_names_for_record(record_idx)
    var current_name: String = str(_match_records[record_idx]["name"])
    name_dropdown.add_item("— none —")
    name_dropdown.set_item_metadata(0, "")
    var selected_idx: int = 0
    for pn in possible_names:
        name_dropdown.add_item(pn)
        var item_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(item_idx, pn)
        if pn == current_name:
            selected_idx = item_idx
    if current_name != "" and not possible_names.has(current_name):
        name_dropdown.add_item(current_name)
        var extra_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(extra_idx, current_name)
        selected_idx = extra_idx
    name_dropdown.selected = selected_idx

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", name_dropdown, row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row_for_record(record_idx), row_color))

    var ridx := record_idx
    var dropdown_ref := name_dropdown
    name_dropdown.item_selected.connect(func(idx: int):
        var chosen: String = str(dropdown_ref.get_item_metadata(idx))
        await _on_record_name_selected(ridx, chosen))

    _markers_content.add_child(HSeparator.new())


func _populate_color_group_rows() -> void:
    _debug_dump_named_records()
    var color_order: Array = range(COLOR_NAME_LABELS.size())
    color_order.sort_custom(func(a, b):
        return String(COLOR_NAME_LABELS[a]).nocasecmp_to(String(COLOR_NAME_LABELS[b])) > 0)
    for ci in color_order:
        var count_in_color: int = 0
        for i in _star_count:
            if clamp(_star_colors[i] if i < _star_colors.size() else 1, 0, 3) == ci:
                count_in_color += 1
        for pos in count_in_color:
            _build_color_group_row(ci, pos)




func _build_pitch_group_row(pitch_freq: float, position_in_group: int) -> void:
    var record_idx: int = _get_or_create_match_record_for_pitch_slot(pitch_freq, position_in_group)
    var row_color: Color = _display_color_for_record(record_idx)
    var known_star_color: int = _known_color_for_record(record_idx)
    print("[DEBUG] pitch row %s pos=%d record=%d star_idx=%d known_color=%d color_states=%s" %
        [ConstellationLogicPuzzle.note_name_for_freq(pitch_freq), position_in_group, record_idx,
         int(_match_records[record_idx].get("star_idx", -1)), known_star_color,
         str(_match_records[record_idx].get("color_states", {}))])

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _markers_content.add_child(row)

    var pitch_lbl := Label.new()
    pitch_lbl.text = ConstellationLogicPuzzle.note_name_for_freq(pitch_freq)
    pitch_lbl.custom_minimum_size = Vector2(64, 0)
    pitch_lbl.add_theme_font_size_override("font_size", 16)
    pitch_lbl.add_theme_color_override("font_color",
        STAR_COLORS_BY_IDX[known_star_color] if known_star_color >= 0 else row_color)
    row.add_child(pitch_lbl)
    if known_star_color >= 0:
        var swatch := ColorRect.new()
        swatch.color = STAR_COLORS_BY_IDX[known_star_color]
        swatch.custom_minimum_size = Vector2(10, 10)
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(swatch)

    var name_dropdown := OptionButton.new()
    name_dropdown.custom_minimum_size = Vector2(120, 0)
    var possible_names: Array[String] = _possible_names_for_record(record_idx)
    var current_name: String = str(_match_records[record_idx]["name"])
    name_dropdown.add_item("— none —")
    name_dropdown.set_item_metadata(0, "")
    var selected_idx: int = 0
    for pn in possible_names:
        name_dropdown.add_item(pn)
        var item_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(item_idx, pn)
        if pn == current_name:
            selected_idx = item_idx
    if current_name != "" and not possible_names.has(current_name):
        name_dropdown.add_item(current_name)
        var extra_idx: int = name_dropdown.item_count - 1
        name_dropdown.set_item_metadata(extra_idx, current_name)
        selected_idx = extra_idx
    name_dropdown.selected = selected_idx

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", name_dropdown, row_color))
    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))

    var ridx := record_idx
    var dropdown_ref := name_dropdown
    name_dropdown.item_selected.connect(func(idx: int):
        var chosen: String = str(dropdown_ref.get_item_metadata(idx))
        await _on_record_name_selected(ridx, chosen))

    _markers_content.add_child(HSeparator.new())


func _populate_pitch_group_rows() -> void:
    var pitch_freqs: Array = []
    for pf in _pitch_freqs:
        if not pitch_freqs.has(pf):
            pitch_freqs.append(pf)
    pitch_freqs.sort_custom(func(a, b): return float(a) < float(b))

    for pf in pitch_freqs:
        var count_in_pitch: int = 0
        for i in _star_count:
            if i < _star_pitch_index.size() and _star_pitch_index[i] < _pitch_freqs.size():
                if _pitch_freqs[int(_star_pitch_index[i])] == pf:
                    count_in_pitch += 1
        for pos in count_in_pitch:
            _build_pitch_group_row(pf, pos)


func _build_name_row(name_str: String) -> void:
    var record_idx: int = _get_or_create_match_record_for_name(name_str)
    var row_color: Color = _display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _markers_content.add_child(row)

    var name_lbl := Label.new()
    name_lbl.text = name_str
    name_lbl.custom_minimum_size = Vector2(90, 0)
    name_lbl.clip_text = true
    name_lbl.add_theme_font_size_override("font_size", 16)
    name_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(name_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_carousel_row_for_record(record_idx), row_color))

    _markers_content.add_child(HSeparator.new())


func _populate_name_rows() -> void:
    var names_sorted: Array = _star_names.duplicate()
    names_sorted.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    for n in names_sorted:
        _build_name_row(String(n))
