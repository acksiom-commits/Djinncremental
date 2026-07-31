extends Control
# ================= CONSTELLATION POPOUT v2.0.0 =================
# v2.0.0: Moved from BottomPopoutsHBox to LeftEdgePopoutsVBox.
#         Slide direction changed from vertical (up from bottom)
#         to horizontal (right from left edge).
#         _pin_to_bottom removed — layout is now handled by the
#         VBoxContainer parent, matching right-edge popout pattern.
# v1.0.0: Bottom-edge slide-up from BottomPopoutsHBox.
#
# Left-edge slide-right popout for constellation selection.
# Outer Control occupies 22px in LeftEdgePopoutsVBox.
# Panel overflows rightward using layout_mode = Position on
# ConstellationSelectorPanel — same technique the right-edge
# popouts (Journal, Ages, settings) use horizontally.
# Emits constellation_selected(id) signal.
# root_ui.gd connects that to constellation_panel.on_constellation_selected().

const PANEL_WIDTH: float = 320.0   # ← must match ConstellationSelectorPanel offset_right
const ANIM_TIME:   float = 0.22

# Set true when Octant mechanics unlock in mid-game (permanent material resources +
# pocket dimension placement). Until then, the SpinBox hides and all unlocked
# constellations show in a single flat list regardless of octant assignment.
# Toggled at runtime by enable_octant_gating() when the player reaches that milestone.
# TODO: persist _octant_gating_enabled in save data when mid-game trigger is implemented.
var _octant_gating_enabled: bool = false

const SLOT_DARK:     Color = Color(0.08, 0.07, 0.12, 1.0)
const SLOT_STARS:    Color = Color(0.12, 0.11, 0.22, 1.0)
const SLOT_LINES:    Color = Color(0.15, 0.13, 0.28, 1.0)
const SLOT_ART:      Color = Color(0.20, 0.16, 0.35, 1.0)
const SLOT_SELECTED: Color = Color(0.25, 0.20, 0.42, 1.0)

const TIER_COLORS: Dictionary = {
    "dark":  Color(0.40, 0.38, 0.50),
    "stars": Color(0.65, 0.60, 0.90),
    "lines": Color(0.50, 0.75, 0.95),
    "art":   Color(0.85, 0.70, 0.95),
}

const BONUS_DESCRIPTIONS: Dictionary = {
    "cooldown_multiplier":  "Cooldown Reduction",
    "archon_title_slots":   "Archon Title Slots",
    "sparks_summon_bonus":  "Spark Summon Bonus",
    "monad_compress_bonus": "Monad Compress Bonus",
    "archon_foci_bonus":    "Archon Foci Bonus",
    "purity_lock_slots":    "Purity Lock Slots",
}

const FEED_COLORS: Array = [
    Color(0.35, 0.35, 0.35, 1.0),   # off — grey
    Color(0.25, 0.60, 0.90, 1.0),   # on  — blue
]

const MULTI_GRID: Array = [
    ["10X",  10],
    ["100X", 100],
    ["CSTM", -2],
    ["ALL",  -1],
]

const COLOR_MULTI_SEL:  Color = Color(UIAccentColors.CREAM, 1.00)
const COLOR_MULTI_NORM: Color = Color(UIAccentColors.CREAM, 0.40)

signal constellation_selected(id: int)
signal panel_first_opened()

var _has_been_opened_once: bool = false
var _close_locked:         bool = false

var _cd: Node = null
var _gc: Node = null

var _is_open:       bool  = false
var _tween:         Tween = null
var _selected_slot: int   = -1
var _selected_octant: int = 0
var _feed_buttons:  Array = []
var _selected_multiplier: int  = 1
var _multi_buttons:       Array = []
var _show_sparks_numeric:   bool = true

const PANEL_BASE_PATH:      String = "ConstellationSelectorPanel/SelectorMargin/SelectorVBox"
const ALLOCATION_BASE_PATH: String = PANEL_BASE_PATH + "/ConstellationAllocationVBox"
const INFO_BASE_PATH:       String = PANEL_BASE_PATH + "/ConstellationInfoVBox"

@onready var _tab_btn    : Button         = $ConstellationTabButton
@onready var _panel      : PanelContainer = $ConstellationSelectorPanel
@onready var _slot_grid  : GridContainer  = get_node(PANEL_BASE_PATH + "/ConstellationSlotGrid")
@onready var _foci_minus : Button  = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/FociMinusButton")
@onready var _foci_value : Label   = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/FociValueLabel")
@onready var _foci_plus  : Button  = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/FociPlusButton")
@onready var _vol_minus  : Button  = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/VolMinusButton")
@onready var _vol_value  : Label   = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/VolValueLabel")
@onready var _vol_plus   : Button  = get_node(ALLOCATION_BASE_PATH + "/FociVolHBox/VolPlusButton")
@onready var _feed_hbox  : HBoxContainer = get_node(ALLOCATION_BASE_PATH + "/FeedHBox")

@onready var _info_vbox       : VBoxContainer = get_node(INFO_BASE_PATH)
@onready var _info_name_label : Label         = get_node(INFO_BASE_PATH + "/InfoNameLabel")
@onready var _info_lore_label : Label         = get_node(INFO_BASE_PATH + "/InfoLoreLabel")
@onready var _info_bonus_label: Label         = get_node(INFO_BASE_PATH + "/InfoBonusLabel")
@onready var _info_progress   : ProgressBar   = get_node(INFO_BASE_PATH + "/InfoProgressBar")
@onready var _info_tier_label : Label         = get_node(INFO_BASE_PATH + "/InfoTierLabel")
@onready var _spark_counter_label : Label     = get_node(ALLOCATION_BASE_PATH + "/SparkCounterLabel")
@onready var _octant_spin     : SpinBox       = get_node(PANEL_BASE_PATH + "/OctantSpinBox")

@warning_ignore("unused_private_class_variable")
@onready var _title_label     : Label         = get_node(PANEL_BASE_PATH + "/ConstellationTitleLabel")


func _ready() -> void:
    _tab_btn.visible = false
    _cd = get_node_or_null("/root/ConstellationData")
    _gc = get_node_or_null("/root/GameContext")
    _panel.visible = true
    _panel.top_level = true
    call_deferred("_init_panel_position")
    _tab_btn.position = Vector2(0.0, 0.0)
    _tab_btn.pressed.connect(_on_tab_pressed)
    _foci_minus.pressed.connect(_on_foci_minus)
    _foci_plus.pressed.connect(_on_foci_plus)
    _vol_minus.pressed.connect(_on_vol_minus)
    _vol_plus.pressed.connect(_on_vol_plus)
    _octant_spin.value_changed.connect(_on_octant_changed)
    _octant_spin.visible = _octant_gating_enabled
    _connect_feed_buttons()
    _spark_counter_label.mouse_filter = Control.MOUSE_FILTER_STOP
    _spark_counter_label.gui_input.connect(_on_spark_counter_input)
    var multi_grid = get_node_or_null(ALLOCATION_BASE_PATH + "/MultiGrid")
    if multi_grid:
        for i in MULTI_GRID.size():
            var amount: int = MULTI_GRID[i][1]
            var btn: Button = multi_grid.get_child(i)
            if btn:
                _multi_buttons.append([btn, amount])
                var captured := amount
                btn.pressed.connect(func(): _on_multi_pressed(captured))
    _update_multi_button_states()
    call_deferred("_init_panel_position")
    get_viewport().size_changed.connect(_init_panel_position)
    if _cd and _cd.has_signal("constellation_unlocked"):
        _cd.constellation_unlocked.connect(func(_id: int): _build_slots())
        
        
func _init_panel_position() -> void:
    _panel.global_position = Vector2(
        _tab_btn.global_position.x - PANEL_WIDTH,
        _tab_btn.global_position.y
    )
    _set_panel_input(false)


func _set_panel_input(enabled: bool) -> void:
    var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
    _set_subtree_mouse_filter(_panel, filter)


func _set_subtree_mouse_filter(node: Node, filter: int) -> void:
    if node is Control:
        node.mouse_filter = filter
    for child in node.get_children():
        _set_subtree_mouse_filter(child, filter)


func _process(_delta: float) -> void:
    if _is_open:
        _refresh_slots()
        _refresh_allocation_display()
        _refresh_info_panel()


# ==================================================
# PUBLIC
# ==================================================
func reveal() -> void:
    var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    t.tween_property(self, "modulate:a", 1.0, 1.5)
    

func show_tab() -> void:
    _tab_btn.visible = true
    call_deferred("_init_panel_position")


func enable_octant_gating() -> void:
    # Called by root_ui.gd when the player reaches the mid-game milestone that
    # introduces pocket dimension placement and permanent material resources.
    # Rebuilds the slot grid with octant filtering active.
    _octant_gating_enabled = true
    _octant_spin.visible = true
    _build_slots()


func show_slot_grid() -> void:
    # Called when enqueue_archon_volition_constellation() or
    # enqueue_no_archon_volition_constellation() completes — reveals the
    # constellation selector buttons for the first time (Hourglass unlock).
    if not _slot_grid:
        return
    _slot_grid.visible = true
    _build_slots()


# ==================================================
# SLIDE TOGGLE — panel slides RIGHT from the left-edge tab strip
# ==================================================
func _on_tab_pressed() -> void:
    if _is_open:
        _close()
        return
    _is_open = true
    _set_panel_input(true)
    if not _has_been_opened_once:
        _has_been_opened_once = true
        emit_signal("panel_first_opened")
    if _slot_grid and not _slot_grid.visible and _selected_slot == -1:
        if _cd and _cd.unlocked.has(0):
            _selected_slot = 0
    var tab_x: float = _tab_btn.global_position.x
    _tween = SlidePanelToggle.run(_tab_btn, "position:x", PANEL_WIDTH,
        _panel, "global_position:x", tab_x, ANIM_TIME, _tween)


func _on_octant_changed(value: float) -> void:
    var v := int(round(value))
    if v > 8:
        _octant_spin.value = 1
        return
    elif v < 1:
        _octant_spin.value = 8
        return
    _selected_octant = v - 1
    _selected_slot = -1
    _build_slots()
    _refresh_info_panel()
    _refresh_allocation_display()


func _close() -> void:
    if not _is_open:
        return
    if _close_locked:
        return
    _is_open = false
    var closed_x: float = global_position.x - PANEL_WIDTH
    _tween = SlidePanelToggle.run(_tab_btn, "position:x", 0.0,
        _panel, "global_position:x", closed_x, ANIM_TIME, _tween)
    _tween.tween_callback(func(): _set_panel_input(false))


func set_close_locked(locked: bool) -> void:
    _close_locked = locked


func _input(event: InputEvent) -> void:
    if not _is_open:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _panel.get_global_rect().has_point(event.global_position):
            return
        if _tab_btn.get_global_rect().has_point(event.global_position):
            return
        if _close_locked:
            return
        _close()
        get_viewport().set_input_as_handled()
        
        
func _has_point(point: Vector2) -> bool:
    if _is_open:
        var full_rect := Rect2(Vector2.ZERO, Vector2(342, 380))  # panel + tab width, panel height
        return full_rect.has_point(point)
    return Rect2(Vector2.ZERO, size).has_point(point)


# ==================================================
# SLOT CONSTRUCTION
# ==================================================
func _build_slots() -> void:
    if not _slot_grid or not _cd:
        return
    for child in _slot_grid.get_children():
        child.queue_free()
    _slot_grid.columns = 4
    var defs: Array
    if _octant_gating_enabled:
        defs = _cd.get_constellations_in_octant(_selected_octant)
    else:
        # Octant mechanics not yet introduced — show all unlocked constellations
        # in a flat list. Octant assignment data is preserved for when gating enables.
        defs = []
        for c in _cd.BUILT_IN:
            if _cd.unlocked.has(c["id"]):
                defs.append(c)
        # player_constellations/patron_constellations round-trip through
        # save data (constellation_data.gd's load_save_data() only checks
        # the outer Array's type) — an element that isn't a Dictionary
        # crashes outright on bracket-indexing (confirmed: c["id"] on a
        # non-Dictionary Variant exits the process, no catchable error),
        # so guard the type before ever touching "id".
        for c in _cd.player_constellations:
            if c is Dictionary and _cd.unlocked.has(_coerce_int(c.get("id"), -1)):
                defs.append(c)
        for c in _cd.patron_constellations:
            if c is Dictionary and c.get("approved", false) \
                    and _cd.unlocked.has(_coerce_int(c.get("id"), -1)):
                defs.append(c)
    for def in defs:
        var id: int = def["id"]
        var slot := Button.new()
        slot.name                = "Slot%d" % id
        slot.custom_minimum_size = Vector2(80, 56)
        slot.add_theme_font_size_override("font_size", 11)
        slot.mouse_filter        = Control.MOUSE_FILTER_STOP
        slot.text                = _get_slot_label(id)
        slot.pressed.connect(_on_slot_pressed.bind(id))
        _slot_grid.add_child(slot)


func _refresh_slots() -> void:
    if not _slot_grid or not _cd:
        return
    var defs: Array
    if _octant_gating_enabled:
        defs = _cd.get_constellations_in_octant(_selected_octant)
    else:
        defs = []
        for c in _cd.BUILT_IN:
            if _cd.unlocked.has(c["id"]):
                defs.append(c)
        # player_constellations/patron_constellations round-trip through
        # save data (constellation_data.gd's load_save_data() only checks
        # the outer Array's type) — an element that isn't a Dictionary
        # crashes outright on bracket-indexing (confirmed: c["id"] on a
        # non-Dictionary Variant exits the process, no catchable error),
        # so guard the type before ever touching "id".
        for c in _cd.player_constellations:
            if c is Dictionary and _cd.unlocked.has(_coerce_int(c.get("id"), -1)):
                defs.append(c)
        for c in _cd.patron_constellations:
            if c is Dictionary and c.get("approved", false) \
                    and _cd.unlocked.has(_coerce_int(c.get("id"), -1)):
                defs.append(c)
    for def in defs:
        var id: int = def["id"]
        var slot = _slot_grid.get_node_or_null("Slot%d" % id)
        if not slot:
            continue
        slot.text = _get_slot_label(id)
        var state: String = _cd.get_visual_state(id)
        var tint: Color
        if id == _selected_slot:
            tint = SLOT_SELECTED
        else:
            match state:
                "stars": tint = SLOT_STARS
                "lines": tint = SLOT_LINES
                "art":   tint = SLOT_ART
                _:       tint = SLOT_DARK
        slot.add_theme_stylebox_override("normal", _make_slot_style(tint))


func _get_slot_label(constellation_id: int) -> String:
    if not _cd or not _cd.unlocked.has(constellation_id):
        return "???"
    var def = _cd.get_constellation_def(constellation_id)
    if def.is_empty():
        return "???"
    var designation: String = _coerce_string(def.get("designation"), "")
    var name_str:    String = _coerce_string(def.get("name"), "???")
    if designation != "":
        return "%s\n%s" % [designation.to_upper(), name_str]
    return name_str


# ==================================================
# SLOT SELECTION
# ==================================================
func _on_slot_pressed(id: int) -> void:
    if _selected_slot == id:
        _selected_slot = -1
    else:
        _selected_slot = id
    constellation_selected.emit(_selected_slot)
    _refresh_slots()
    _refresh_allocation_display()
    _refresh_info_panel()


# ==================================================
# ALLOCATION DISPLAY
# ==================================================
func _refresh_allocation_display() -> void:
    if not _gc:
        return
    if _selected_slot < 0:
        if _foci_value: _foci_value.text = "-"
        if _vol_value:  _vol_value.text  = "-"
        _refresh_feed_buttons()
        return
    var id_str    := str(_selected_slot)
    var foci:      int = _gc._assignment_int("constellation_" + id_str + "_foci",      0)
    var volitions: int = _gc._assignment_int("constellation_" + id_str + "_volitions",  0)
    var bonus_vol: int = _gc._assignment_int("constellation_" + id_str + "_bonus_volitions", 0)
    var vol_total: int = volitions + bonus_vol
    if _foci_value: _foci_value.text = str(foci)
    if _vol_value:
        _vol_value.text = str(vol_total)
        if volitions > 0:
            _vol_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
        else:
            _vol_value.remove_theme_color_override("font_color")
    _refresh_feed_buttons()


func _on_foci_plus() -> void:
    if not _gc or _selected_slot < 0: return
    var available: int = _gc.archon_foci - _gc.get_total_foci_assigned()
    if available <= 0: return
    var key    := "constellation_%d_foci" % _selected_slot
    var current: int = _gc._assignment_int(key, 0)
    var amount: int  = available if _selected_multiplier == -1 \
                       else mini(_selected_multiplier, available)
    _gc.assignments[key] = current + amount


func _on_foci_minus() -> void:
    if not _gc or _selected_slot < 0: return
    var key    := "constellation_%d_foci" % _selected_slot
    var current: int = _gc._assignment_int(key, 0)
    if current <= 0: return
    var amount: int = current if _selected_multiplier == -1 \
                      else mini(_selected_multiplier, current)
    _gc.assignments[key] = current - amount


func _on_vol_plus() -> void:
    if not _gc or _selected_slot < 0: return
    var free_parents: int = _gc.get_volitions_free()
    var free_children: int = _gc.get_total_free_children_in_category("constellation")
    var available: int = free_parents + free_children
    if available <= 0: return
    var amount: int = available if _selected_multiplier == -1 \
                      else mini(_selected_multiplier, available)
    for i in amount:
        var idx = _gc.get_first_free_parent_index()
        if idx >= 0:
            _gc.assign_parent_volition(idx, "constellation", _selected_slot)
        elif not _gc.assign_next_child_in_category("constellation", _selected_slot):
            break


func _on_vol_minus() -> void:
    if not _gc or _selected_slot < 0: return
    var id_str := str(_selected_slot)
    var parent_count: int = _gc._assignment_int("constellation_" + id_str + "_volitions", 0)
    var child_count: int = _gc._assignment_int("constellation_" + id_str + "_bonus_volitions", 0)
    var total: int = parent_count + child_count
    if total <= 0: return
    var amount: int = total if _selected_multiplier == -1 \
                      else mini(_selected_multiplier, total)
    for i in amount:
        if _gc.unassign_last_child_with_target("constellation", _selected_slot):
            continue
        var idx = _gc.get_first_parent_index_with_target("constellation", _selected_slot)
        if idx >= 0:
            _gc.unassign_parent_volition(idx)
        else:
            break


func _on_feed_mode_set(mode: int) -> void:
    if not _gc or _selected_slot < 0: return
    var key := "constellation_%d_feed_mode" % _selected_slot
    _gc.assignments[key] = mode
    _refresh_feed_buttons()


func _connect_feed_buttons() -> void:
    _feed_buttons.clear()
    var names := ["FeedNoneButton", "FeedAutoButton"]
    for i in 2:
        var btn: Button = _feed_hbox.get_node_or_null(names[i])
        if not btn: continue
        btn.mouse_filter = Control.MOUSE_FILTER_STOP
        var captured := i
        btn.pressed.connect(func(): _on_feed_mode_set(captured))
        _feed_buttons.append(btn)
    # Hide the now-unused Click and Both buttons
    for old_name in ["FeedClickButton", "FeedBothButton"]:
        var old_btn: Button = _feed_hbox.get_node_or_null(old_name)
        if old_btn:
            old_btn.visible = false


func _refresh_feed_buttons() -> void:
    if not _gc or _feed_buttons.is_empty(): return
    if _selected_slot < 0:
        for btn in _feed_buttons:
            if btn:
                btn.add_theme_color_override("font_color", FEED_COLORS[0].darkened(0.45))
                btn.add_theme_stylebox_override("normal",
                    _make_slot_style(Color(0.05, 0.05, 0.08, 1.0)))
        return
    var key      := "constellation_%d_feed_mode" % _selected_slot
    var mode: int = clampi(_gc._assignment_int(key, 0), 0, 1)
    for i in _feed_buttons.size():
        var btn: Button = _feed_buttons[i]
        if not btn: continue
        var is_active := (i == mode)
        btn.add_theme_color_override("font_color",
            FEED_COLORS[i] if is_active else FEED_COLORS[i].darkened(0.45))
        btn.add_theme_stylebox_override("normal",
            _make_slot_style(Color(0.15, 0.13, 0.28, 1.0) if is_active \
                             else Color(0.05, 0.05, 0.08, 1.0)))


func _on_multi_pressed(amount: int) -> void:
    if amount == -2:
        # DEV: CSTM requires a custom LineEdit node in the panel scene — not
        # yet added. Toggle visual only until the input field exists.
        _update_multi_button_states()
        return
    if _selected_multiplier == amount:
        _selected_multiplier = 1
        _update_multi_button_states()
        return
    _selected_multiplier = amount
    _update_multi_button_states()


func _update_multi_button_states() -> void:
    for entry in _multi_buttons:
        var btn: Button = entry[0]
        var amount: int = entry[1]
        var is_custom_active: bool = _selected_multiplier not in [1, 10, 100, -1]
        var is_active: bool = is_custom_active if amount == -2 \
            else (amount != 1 and amount == _selected_multiplier)
        btn.add_theme_color_override("font_color",
            COLOR_MULTI_SEL if is_active else COLOR_MULTI_NORM)
            
            
func _refresh_spark_counter() -> void:
    if not _spark_counter_label or not _cd or _selected_slot < 0:
        if _spark_counter_label:
            _spark_counter_label.text = ""
        return
    var cap:            float = _cd.get_spark_cap(_selected_slot)
    var raw_invested:   float = _gc.constellation_spark_totals.get(
                                    str(_selected_slot), 0.0) if _gc else 0.0
    var fraction:       float = _cd.get_spark_fraction(_selected_slot)
    var def:            Dictionary = _cd.get_constellation_def(_selected_slot)
    var line_threshold: float = _coerce_float(def.get("line_threshold"), 0.3)
    var state:          String = _cd.get_visual_state(_selected_slot)
    var toggle_unlocked: bool = _is_numeric_toggle_unlocked()
    var counter_text: String

    if _show_sparks_numeric:
        if fraction >= 1.0:
            # Fully invested — Kaleb now knows the total cap for this constellation.
            counter_text = "%s / %s Sparks" % [
                _fmt_sparks(raw_invested), _fmt_sparks(cap)]
        else:
            counter_text = "%s Sparks Endowed" % _fmt_sparks(raw_invested)
    else:
        match state:
            "dark":
                var pct := int((fraction / _cd.THRESHOLD_STARS) * 100.0) \
                    if _cd.THRESHOLD_STARS > 0.0 else 0
                counter_text = "%d%% to Stars" % clampi(pct, 0, 100)
            "stars":
                var range_size: float = line_threshold - _cd.THRESHOLD_STARS
                var pct := int(((fraction - _cd.THRESHOLD_STARS) / range_size) * 100.0) \
                    if range_size > 0.0 else 100
                counter_text = "%d%% to Lines" % clampi(pct, 0, 100)
            "lines":
                var range_size: float = _cd.THRESHOLD_ART - line_threshold
                var pct := int(((fraction - line_threshold) / range_size) * 100.0) \
                    if range_size > 0.0 else 100
                counter_text = "%d%% to Art" % clampi(pct, 0, 100)
            "art":
                counter_text = "Complete"
            _:
                counter_text = ""

    _spark_counter_label.text = counter_text
    _spark_counter_label.mouse_default_cursor_shape = \
        Control.CURSOR_POINTING_HAND if toggle_unlocked else Control.CURSOR_ARROW


func _is_numeric_toggle_unlocked() -> bool:
    if not _gc:
        return false
    var c0_solved: bool = _gc._assignment_int("constellation_0_solve_count", 0) > 0
    var c2_solved: bool = _gc._assignment_int("constellation_2_solve_count", 0) > 0
    return c0_solved and c2_solved


func _on_spark_counter_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
        return
    if not _is_numeric_toggle_unlocked():
        return
    _show_sparks_numeric = not _show_sparks_numeric


func _fmt_sparks(amount: float) -> String:
    var n: int = int(amount)
    var s := str(n)
    var result := ""
    var count  := 0
    for i in range(s.length() - 1, -1, -1):
        if count > 0 and count % 3 == 0:
            result = "," + result
        result = s[i] + result
        count += 1
    return result


# ==================================================
# INFO PANEL — refresh
# ==================================================
func _refresh_info_panel() -> void:
    _refresh_spark_counter()
    if not _info_vbox:
        return
    if _selected_slot < 0 or not _cd:
        _info_vbox.visible = false
        return
    var def: Dictionary = _cd.get_constellation_def(_selected_slot)
    if def.is_empty():
        _info_vbox.visible = false
        return
    if not _slot_grid.visible:
        _info_vbox.visible = false
        return
    _info_vbox.visible = true

    # ── Name ──
    var designation: String = _coerce_string(def.get("designation"), "")
    if designation != "":
        _info_name_label.text = "%s — %s" % [designation.to_upper(), def.get("name", "Unknown")]
    else:
        _info_name_label.text = def.get("name", "Unknown")

    # ── Lore ──
    _info_lore_label.text = ""

    # ── Bonus ──
    var bonus_key: String = _coerce_string(def.get("bonus_key"), "")
    var state:     String = _cd.get_visual_state(_selected_slot)
    var bonus_desc: String = BONUS_DESCRIPTIONS.get(
        bonus_key, bonus_key.capitalize().replace("_", " "))
    if def.has("bonus_levels"):
        var solved: bool = false
        if _gc:
            var solve_key := "constellation_%d_solve_count" % _selected_slot
            solved = _gc._assignment_int(solve_key, 0) > 0
        if solved:
            # def["bonus_levels"] is a save-derived field too — a wrong
            # type there would crash calling .get() on it the same way
            # bracket-indexing a non-Dictionary does (see the id-read fix
            # above), and def["bonus_value"]/the state's entry could be
            # wrong-typed even when bonus_levels itself is a real Dictionary.
            var bonus_levels: Dictionary = _coerce_dict(def.get("bonus_levels"), {})
            var default_bonus: float = _coerce_float(def.get("bonus_value"), 1.0)
            var current_val: float = _coerce_float(bonus_levels.get(state, default_bonus), default_bonus)
            _info_bonus_label.text = "%s: ×%s" % [bonus_desc, str(current_val)]
            _info_bonus_label.add_theme_color_override("font_color",
                TIER_COLORS.get(state, Color.WHITE))
        else:
            _info_bonus_label.text = "%s (puzzle unsolved)" % bonus_desc
            _info_bonus_label.add_theme_color_override("font_color",
                Color(0.45, 0.42, 0.55))
    elif bonus_key != "":
        _info_bonus_label.text = "%s: +%s" % [bonus_desc, str(def.get("bonus_value", 0.0))]
        _info_bonus_label.add_theme_color_override("font_color", Color(0.70, 0.65, 0.85))
    else:
        _info_bonus_label.text = ""

    # ── Progress bar fill color by tier ──
    var fill_color: Color = TIER_COLORS.get(state, Color(0.35, 0.30, 0.60))
    var fill_style := StyleBoxFlat.new()
    fill_style.bg_color                   = fill_color.darkened(0.15)
    fill_style.corner_radius_top_left     = 3
    fill_style.corner_radius_top_right    = 3
    fill_style.corner_radius_bottom_left  = 3
    fill_style.corner_radius_bottom_right = 3
    _info_progress.add_theme_stylebox_override("fill", fill_style)
    _info_progress.value = _cd.get_spark_fraction(_selected_slot) * 100.0

    # ── Tier label — qualitative status only; quantities live in SparkCounterLabel ──
    var tier_text: String
    match state:
        "dark":   tier_text = "Dark → Stars"
        "stars":  tier_text = "★ Stars → Lines"
        "lines":  tier_text = "╱ Lines → Art"
        "art":    tier_text = "✦ Art"
        _:        tier_text = ""
    _info_tier_label.text = tier_text
    _info_tier_label.add_theme_color_override("font_color",
        TIER_COLORS.get(state, Color.WHITE))


func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


func _coerce_float(val, default: float) -> float:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return float(val)
    return default


func _coerce_string(val, default: String) -> String:
    if typeof(val) == TYPE_STRING:
        return val
    return default


func _coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


func _make_slot_style(color: Color) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color                   = color
    s.border_color               = Color(0.3, 0.25, 0.45, 0.6)
    s.border_width_left          = 1
    s.border_width_right         = 1
    s.border_width_top           = 1
    s.border_width_bottom        = 1
    s.corner_radius_top_left     = 3
    s.corner_radius_top_right    = 3
    s.corner_radius_bottom_left  = 3
    s.corner_radius_bottom_right = 3
    return s
