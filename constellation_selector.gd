extends Control
# ================= CONSTELLATION SELECTOR v0.8.0 =================
# v0.8.0: Replaced instapop with modulate.a fade tween.
#         No minimum-size manipulation — original scene values preserved.
#         No clip_contents or scene changes required.
# v0.7.0: Replaced mouse_exited close with CloseConstellationButton.
# v0.6.0: Added close delay timer to prevent snap-close.
# v0.5.0: Removed Top Level. Lives in ConstellationSelectorVBox.
# v0.4.0: Deferred slot and allocation control building.
# v0.1.0: Initial implementation.

# ===================== TUNING ====================
const ANIM_TIME: float = 0.22
# NEW — slide-up-from-bottom height (tune once in the editor)
const PANEL_HEIGHT: float = 210.0   # ← CHANGE THIS

const SLOT_DARK:     Color = Color(0.08, 0.07, 0.12, 1.0)
const SLOT_STARS:    Color = Color(0.12, 0.11, 0.22, 1.0)
const SLOT_LINES:    Color = Color(0.15, 0.13, 0.28, 1.0)
const SLOT_ART:      Color = Color(0.20, 0.16, 0.35, 1.0)
const SLOT_SELECTED: Color = Color(0.25, 0.20, 0.42, 1.0)
const SLOT_LOCKED:   Color = Color(0.05, 0.05, 0.08, 1.0)
const FEED_LABELS: Array = ["—", "Auto", "Click", "Both"]
const FEED_COLORS: Array = [
    Color(0.35, 0.35, 0.35, 1.0),   # none   — grey
    Color(0.25, 0.60, 0.90, 1.0),   # auto   — blue
    Color(0.90, 0.55, 0.20, 1.0),   # manual — amber
    Color(0.45, 0.80, 0.45, 1.0),   # both   — green
]


# ===================== AUTOLOAD REFS =============
var _cd: Node = null
var _gc: Node = null


# ===================== NODE REFS =================
@onready var _slot_grid:       GridContainer = $SelectorAllocationVBox/ConstellationSlotGrid
@onready var _close_button:    Button        = $SelectorAllocationVBox/CloseConstellationButton
@onready var _foci_minus:      Button        = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/FociMinusButton
@onready var _foci_value:      Label         = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/FociValueLabel
@onready var _foci_plus:       Button        = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/FociPlusButton
@onready var _vol_minus:       Button        = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/VolMinusButton
@onready var _vol_value:       Label         = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/VolValueLabel
@onready var _vol_plus:        Button        = $SelectorAllocationVBox/ConstellationAllocationVBox/FociVolHBox/VolPlusButton
@onready var _feed_hbox:       HBoxContainer = $SelectorAllocationVBox/ConstellationAllocationVBox/FeedHBox
var _feed_buttons: Array = []


# ===================== STATE =====================
var _selected_slot: int   = 0
var _is_open:       bool  = false
var _panel_node:    Node  = null
var _vbox:          Node  = null
var _tween                = null


# ============================
# READY
# ============================
func _ready() -> void:
    _cd = get_node_or_null("/root/ConstellationData")
    _gc = get_node_or_null("/root/GameContext")
    _panel_node = get_parent().get_parent().get_parent().get_parent()

    _vbox = get_parent()
    
    # Start completely hidden
    if _vbox:
        _vbox.visible = false
        _vbox.scale.y = 0.0

    var bg = get_node_or_null("ConstellationSelectorBackground")
    if bg:
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

    call_deferred("_deferred_setup")
    
    
func _deferred_setup() -> void:
    _build_slots()
    _connect_allocation_signals()
    if _close_button:
        _close_button.pressed.connect(close)
    if _cd:
        _cd.constellation_unlocked.connect(_on_constellation_unlocked)
        
        
func _on_constellation_unlocked(_id: int) -> void:
    _build_slots()

func _process(_delta: float) -> void:
    if _is_open:
        _refresh_slots()
        _refresh_allocation_display()



# ==================================================
# OPEN / CLOSE — scale version (no UI pushing + smooth open)
# ==================================================
func open() -> void:
    if _is_open:
        return
    _is_open = true
    if not _vbox:
        return
    _vbox.position.y = 0.0
    _vbox.visible = true
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _tween.tween_property(_vbox, "position:y", -PANEL_HEIGHT, ANIM_TIME)


func close() -> void:
    if not _is_open:
        return
    _is_open = false
    if not _vbox:
        return
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _tween.tween_property(_vbox, "position:y", 0.0, ANIM_TIME)
    _tween.tween_callback(func():
        if _vbox:
            _vbox.visible = false
    )
    
    
# ==================================================
# SLOT CONSTRUCTION
# ==================================================
func _build_slots() -> void:
    if not _slot_grid or not _cd:
        return
    for child in _slot_grid.get_children():
        child.queue_free()
    _slot_grid.columns = 4
    
    # Add DEFAULT/UNASSIGNED slot
    var default_slot := Button.new()
    default_slot.name                = "SlotDefault"
    default_slot.custom_minimum_size = Vector2(80, 56)
    default_slot.mouse_filter        = Control.MOUSE_FILTER_STOP
    default_slot.text                = "Unassigned\n—"
    default_slot.pressed.connect(_on_slot_pressed.bind(-1))
    _slot_grid.add_child(default_slot)
    
    # Add unlocked constellations
    for id in _cd.unlocked:
        var slot := Button.new()
        slot.name                = "Slot%d" % id
        slot.custom_minimum_size = Vector2(80, 56)
        slot.mouse_filter        = Control.MOUSE_FILTER_STOP
        slot.text                = _get_slot_label(id)
        slot.pressed.connect(_on_slot_pressed.bind(id))
        _slot_grid.add_child(slot)


func _refresh_slots() -> void:
    if not _slot_grid or not _cd:
        return
    for id in _cd.unlocked:
        var slot = _slot_grid.get_node_or_null("Slot%d" % id)
        if not slot:
            continue
        slot.text         = _get_slot_label(id)
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
    if not _cd:
        return "???"
    if not _cd.unlocked.has(constellation_id):
        return "???"
    var def = _cd.get_constellation_def(constellation_id)
    if def.is_empty():
        return "???"
    var fraction = _cd.get_spark_fraction(constellation_id)
    var pct      = int(fraction * 100.0)
    var name_str: String = def.get("name", "???")
    if name_str.length() > 12:
        name_str = name_str.substr(0, 11) + "…"
    return "%s\n%d%%" % [name_str, pct]


# ==================================================
# ALLOCATION CONTROLS
# ==================================================
func _connect_allocation_signals() -> void:
    _foci_minus.pressed.connect(_on_foci_minus)
    _foci_plus.pressed.connect(_on_foci_plus)
    _vol_minus.pressed.connect(_on_vol_minus)
    _vol_plus.pressed.connect(_on_vol_plus)

    _feed_buttons.clear()
    var feed_nodes := [
        _feed_hbox.get_node("FeedNoneButton"),
        _feed_hbox.get_node("FeedAutoButton"),
        _feed_hbox.get_node("FeedClickButton"),
        _feed_hbox.get_node("FeedBothButton"),
    ]
    for i in 4:
        var btn: Button = feed_nodes[i]
        btn.mouse_filter = Control.MOUSE_FILTER_STOP
        var captured := i
        btn.pressed.connect(func(): _on_feed_mode_set(captured))
        _feed_buttons.append(btn)


func _refresh_allocation_display() -> void:
    if not _gc:
        return
    var id_str    = str(_selected_slot)
    var foci      = _gc.assignments.get("constellation_" + id_str + "_foci",      0)
    var volitions = _gc.assignments.get("constellation_" + id_str + "_volitions",  0)
    var bonus_vol = _gc.assignments.get("constellation_" + id_str + "_bonus_volitions", 0)
    var vol_total = volitions + bonus_vol
    if _foci_value: _foci_value.text = str(foci)
    if _vol_value:
        _vol_value.text = str(vol_total)
        if volitions > 0:
            _vol_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
        else:
            _vol_value.remove_theme_color_override("font_color")
    _refresh_feed_buttons()

# ==================================================
# SLOT SELECTION
# ==================================================
func _on_slot_pressed(slot_index: int) -> void:
    _selected_slot = slot_index
    if _panel_node and _panel_node.has_method("on_constellation_selected"):
        _panel_node.on_constellation_selected(slot_index)
    _refresh_slots()
    _refresh_allocation_display()


# ==================================================
# ALLOCATION BUTTON HANDLERS
# ==================================================
func _on_foci_plus() -> void:
    if not _gc: return
    var available = _gc.archon_foci - _gc.get_total_foci_assigned()
    if available <= 0: return
    var key = "constellation_%d_foci" % _selected_slot
    _gc.assignments[key] = _gc.assignments.get(key, 0) + 1


func _on_foci_minus() -> void:
    if not _gc: return
    var key     = "constellation_%d_foci" % _selected_slot
    var current = _gc.assignments.get(key, 0)
    if current <= 0: return
    _gc.assignments[key] = current - 1


func _on_vol_plus() -> void:
    if not _gc: return
    var idx = _gc.get_first_free_parent_index()
    if idx >= 0:
        _gc.assign_parent_volition(idx, "constellation", _selected_slot)
    else:
        _gc.assign_next_child_in_category("constellation", _selected_slot)


func _on_vol_minus() -> void:
    if not _gc: return
    if _gc.unassign_last_child_with_target("constellation", _selected_slot):
        return
    var idx = _gc.get_first_parent_index_with_target("constellation", _selected_slot)
    if idx >= 0:
        _gc.unassign_parent_volition(idx)
    
    
func _on_feed_mode_set(mode: int) -> void:
    if not _gc: return
    var key := "constellation_%d_feed_mode" % _selected_slot
    _gc.assignments[key] = mode
    _refresh_feed_buttons()


func _refresh_feed_buttons() -> void:
    if not _gc or _feed_buttons.is_empty(): return
    var key  := "constellation_%d_feed_mode" % _selected_slot
    var mode_raw = _gc.assignments.get(key)
    var mode: int = mode_raw as int if mode_raw != null else 0
    for i in _feed_buttons.size():
        var btn: Button = _feed_buttons[i]
        var is_active := (i == mode)
        btn.add_theme_color_override("font_color",
            FEED_COLORS[i] if is_active else FEED_COLORS[i].darkened(0.45))
        btn.add_theme_stylebox_override("normal",
            _make_slot_style(Color(0.15, 0.13, 0.28, 1.0) if is_active \
                             else Color(0.05, 0.05, 0.08, 1.0)))


# ==================================================
# STYLE HELPER
# ==================================================
func _make_slot_style(color: Color) -> StyleBoxFlat:
    var s = StyleBoxFlat.new()
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

# func _force_show_for_test() -> void:
#     print("=== FORCING SLIDEOUT VISIBLE FOR TEST ===")
#     var slideout = get_node_or_null("SelectorAllocationVBox/SlideoutPanel")
#     if slideout:
#         slideout.visible = true
#         slideout.position.y = 0
#         print("Slideout forced visible at y=0")
#     else:
#         print("ERROR: Could not find SlideoutPanel even in force test")
