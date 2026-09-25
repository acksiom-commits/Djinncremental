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

const PANEL_WIDTH:  float = 350.0   # ← must match ConstellationSelectorPanel's width (|offset_left|)
const PANEL_HEIGHT: float = 465.0   # ← must match ConstellationSelectorPanel's height (offset_bottom)
# Growth from the panel's original 380px height goes entirely to the TOP —
# the tab strip's own bottom, and everything anchored to it (Foci/Vol,
# Feed, Redistribute, MultiGrid), must stay exactly where it already is so
# it never gets pushed further down past the screen's bottom edge. Fixed
# distance from the tab button's Y to the panel's BOTTOM edge; unlike
# PANEL_HEIGHT, this does not change as the panel grows taller.
const PANEL_BOTTOM_OFFSET: float = 380.0
const ANIM_TIME:    float = 0.22

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

# Full per-tier breakdown display (InfoTierEffectsLabel) — always lists all
# four tiers regardless of the constellation's current progress, so the
# player can see the whole ladder at a glance, not just what's next.
const TIER_ORDER: Array = ["dark", "stars", "lines", "art"]
const TIER_DISPLAY_NAMES: Dictionary = {
    "dark": "Dark", "stars": "Stars", "lines": "Lines", "art": "Art",
}

const BONUS_DESCRIPTIONS: Dictionary = {
    "cooldown_multiplier":  "Cooldown Reduction",
    "archon_title_slots":   "Archon Title Slots",
    "sparks_summon_bonus":  "Spark Summon Bonus",
    "monad_compress_bonus": "Monad Compress Bonus",
    "archon_foci_bonus":    "Archon Foci Bonus",
    "purity_lock_slots":    "Purity Lock Slots",
}

## Every genuinely multiplicative bonus_key in constellation_data.gd's
## BUILT_IN array is named with this suffix (sparks_multiplier,
## cooldown_multiplier, storage_multiplier, click_volition_multiplier,
## endowment_multiplier) -- anything else (bonus_volitions, spark_bank_capacity)
## is an additive/flat quantity, not a multiplier, and must not be shown
## with a "×" prefix.
func _bonus_is_multiplier(bonus_key: String) -> bool:
    return bonus_key.ends_with("_multiplier")


## Additive bonus values (Archon's +1/+2/+3, Phial's +250/+500/+1000) are
## whole numbers stored as float -- str() on a whole float prints a
## trailing ".0" ("+1.0") that doesn't belong in front of the player.
## Multiplier values keep their real decimals (×1.5, ×0.25).
func _fmt_bonus_val(val: float) -> String:
    if val == floor(val):
        return str(int(val))
    return str(val)

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
var _slot_buttons: Dictionary = {}   # constellation id -> its selector Button (created once, kept)
var _selected_octant: int = 0
var _feed_buttons:  Array = []
var _selected_multiplier: int  = 1
var _multi_buttons:       Array = []
var _show_sparks_numeric:   bool = true

const SlotBorderFx = preload("res://slot_border_fx.gd")

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
## Manual spark endowment. Deliberately NOT part of _feed_buttons: those
## two are mutually-exclusive feed MODES, this is an action, and folding it
## into that array would make _refresh_feed_buttons treat it as a third
## mode and light it up as "active" whenever mode == 2.
@onready var _redistribute_btn : Button = get_node(ALLOCATION_BASE_PATH + "/MultiRedistributeHBox/RedistributeButton")

@onready var _info_vbox       : VBoxContainer = get_node(INFO_BASE_PATH)
@onready var _info_name_label : Label         = get_node(INFO_BASE_PATH + "/InfoNameLabel")
@onready var _info_lore_label : Label         = get_node(INFO_BASE_PATH + "/InfoLoreLabel")
@onready var _info_bonus_label: Label         = get_node(INFO_BASE_PATH + "/InfoBonusLabel")
@onready var _info_progress   : ProgressBar   = get_node(INFO_BASE_PATH + "/InfoProgressBar")
@onready var _info_tier_label : Label         = get_node(INFO_BASE_PATH + "/InfoTierLabel")
@onready var _info_tier_effects: RichTextLabel = get_node(INFO_BASE_PATH + "/InfoTierEffectsLabel")
@onready var _info_tier_effects_sep: HSeparator = get_node(INFO_BASE_PATH + "/InfoTierEffectsSeparator")

## Built in code, not the .tscn -- see constellation_study_overlay.gd's Easy/
## Hard toggle this same session for the same pattern. Appended last under
## _info_vbox, right after InfoTierEffectsLabel (the last existing child).
var _info_art_achievement: RichTextLabel = null
@onready var _spark_counter_label : Label     = get_node(ALLOCATION_BASE_PATH + "/SparkCounterLabel")
@onready var _octant_spin     : SpinBox       = get_node(PANEL_BASE_PATH + "/OctantSpinBox")

@onready var _title_label     : Label         = get_node(PANEL_BASE_PATH + "/ConstellationTitleLabel")

const DEFAULT_TITLE_TEXT: String = "The Constellation"


func _ready() -> void:
    _tab_btn.visible = false
    _cd = get_node_or_null("/root/ConstellationData")
    _gc = get_node_or_null("/root/GameContext")
    _panel.visible = true
    _panel.top_level = true
    call_deferred("_init_panel_position")
    # Y matches the panel's own top-anchor math (see PANEL_BOTTOM_OFFSET) so
    # the tab strip spans the exact same vertical range as the panel it
    # opens, top and bottom both flush.
    _tab_btn.position = Vector2(0.0, PANEL_BOTTOM_OFFSET - PANEL_HEIGHT)
    _tab_btn.pressed.connect(_on_tab_pressed)
    _foci_minus.pressed.connect(_on_foci_minus)
    _foci_plus.pressed.connect(_on_foci_plus)
    _vol_minus.pressed.connect(_on_vol_minus)
    _vol_plus.pressed.connect(_on_vol_plus)
    _octant_spin.value_changed.connect(_on_octant_changed)
    _octant_spin.visible = _octant_gating_enabled
    _connect_feed_buttons()
    _redistribute_btn.pressed.connect(_on_redistribute_pressed)
    _spark_counter_label.mouse_filter = Control.MOUSE_FILTER_STOP
    _spark_counter_label.gui_input.connect(_on_spark_counter_input)
    var multi_grid = get_node_or_null(ALLOCATION_BASE_PATH + "/MultiRedistributeHBox/MultiGrid")
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
    _build_art_achievement_label()
        
        
func _build_art_achievement_label() -> void:
    _info_art_achievement = RichTextLabel.new()
    _info_art_achievement.custom_minimum_size = Vector2(280, 0)
    _info_art_achievement.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    _info_art_achievement.add_theme_font_size_override("normal_font_size", 14)
    _info_art_achievement.bbcode_enabled = true
    _info_art_achievement.fit_content = true
    _info_art_achievement.scroll_active = false
    _info_art_achievement.visible = false
    _info_vbox.add_child(_info_art_achievement)


func _init_panel_position() -> void:
    # Y is anchored to this CONTROL's own origin, not the tab button's --
    # the tab button's own position.y now also derives from
    # PANEL_BOTTOM_OFFSET/PANEL_HEIGHT (see _ready()), so anchoring the
    # panel to the tab instead would double-apply that shift.
    _panel.global_position = Vector2(
        _tab_btn.global_position.x - PANEL_WIDTH,
        global_position.y + PANEL_BOTTOM_OFFSET - PANEL_HEIGHT
    )
    _set_panel_input(false)


func _set_panel_input(enabled: bool) -> void:
    var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
    _set_subtree_mouse_filter(_panel, filter)


func _set_subtree_mouse_filter(node: Node, filter: int) -> void:
    # Paint-only overlays (slot_border_fx.gd) carry this meta and must stay
    # MOUSE_FILTER_IGNORE always: forced to STOP they sit on top of their
    # button and swallow its clicks.
    if node is Control and not node.has_meta("paint_only"):
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
        # The panel's top now sits above this control's own local origin
        # (growth is applied at the top, see PANEL_BOTTOM_OFFSET), so the
        # hit-test rect's origin has to follow it up rather than starting
        # at local (0,0).
        var top_y: float = PANEL_BOTTOM_OFFSET - PANEL_HEIGHT
        var full_rect := Rect2(Vector2(0.0, top_y), Vector2(PANEL_WIDTH + 22.0, PANEL_HEIGHT))  # panel + tab width, panel height
        return full_rect.has_point(point)
    return Rect2(Vector2.ZERO, size).has_point(point)


# ==================================================
# SLOT CONSTRUCTION
# ==================================================
## The constellations the selector should list right now.
func _slot_defs() -> Array:
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
    return defs


## One button per constellation, created the first time it is listed and
## then KEPT. Callers (unlock, show, octant change) only change WHICH buttons
## are shown and in what order -- nothing is torn down and remade.
##
## This used to clear the grid and rebuild every button. queue_free() leaves
## the old buttons in the tree until frame end, so the replacements collided
## with them by name and were renamed "@Button@N"; the by-name lookup in
## _refresh_slots() then found nothing, so tints, labels and border effects
## silently stopped updating. Keeping the buttons removes the whole class:
## there is no window in which two buttons share a name.
func _build_slots() -> void:
    if not _slot_grid or not _cd:
        return
    _slot_grid.columns = 4
    var defs: Array = _slot_defs()
    var listed: Dictionary = {}
    for def in defs:
        var id: int = def["id"]
        listed[id] = true
        if not _slot_buttons.has(id):
            _slot_buttons[id] = _make_slot_button(id)
    var order: int = 0
    for def in defs:
        var btn: Button = _slot_buttons[int(def["id"])]
        btn.visible = true
        _slot_grid.move_child(btn, order)
        order += 1
    # A constellation not listed right now (another octant) keeps its button
    # but hides it; a hidden Control takes no space in a GridContainer.
    for id in _slot_buttons:
        if not listed.has(id):
            (_slot_buttons[id] as Button).visible = false


func _make_slot_button(id: int) -> Button:
    var slot := Button.new()
    slot.name                = "Slot%d" % id
    slot.custom_minimum_size = Vector2(80, 56)
    slot.add_theme_font_size_override("font_size", 11)
    slot.mouse_filter        = Control.MOUSE_FILTER_STOP
    slot.text                = _get_slot_label(id)
    slot.pressed.connect(_on_slot_pressed.bind(id))
    var fx := Control.new()
    fx.name = "BorderFx"
    fx.set_script(SlotBorderFx)
    slot.add_child(fx)
    _slot_grid.add_child(slot)
    return slot


## TEMPORARY (2026-09-24): prints what the selector-button border effects are
## being told to the editor Output, to confirm they now show in play.
## Printed only when the readout CHANGES, so it does not flood the log.
## Remove this const, _debug_lines, _debug_last, _show_debug_lines() and the
## DEBUG_SLOT_FX blocks in _refresh_slots() once that is confirmed.
const DEBUG_SLOT_FX: bool = true
var _debug_lines: Array[String] = []
var _debug_last: String = ""


func _show_debug_lines() -> void:
    var text: String = "[SLOT FX DEBUG] open=%s gc=%s buttons=%d vol_slots=%s\n%s" % [
        str(_is_open), str(_gc != null), _slot_buttons.size(),
        str(_gc.volition_slots) if _gc else "-", "\n".join(_debug_lines)]
    if text != _debug_last:
        _debug_last = text
        print(text)


func _refresh_slots() -> void:
    _debug_lines.clear()
    if not _slot_grid or not _cd:
        return
    for def in _slot_defs():
        var id: int = def["id"]
        var slot: Button = _slot_buttons.get(id)
        if not slot:
            # Not built yet (refresh can run before the first _build_slots).
            if DEBUG_SLOT_FX:
                _debug_lines.append("S%d: NO BUTTON YET" % id)
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
        var fx = slot.get_node_or_null("BorderFx")
        if fx and _gc:
            fx.set_effects(
                _gc.has_parent_volition_for_constellation(id),
                _gc._assignment_int("constellation_%d_foci" % id, 0) > 0)
        if DEBUG_SLOT_FX:
            _debug_lines.append("S%d parent=%s foci=%d fx=%s %s gold=%s arc=%s" % [
                id,
                str(_gc.has_parent_volition_for_constellation(id)) if _gc else "no-gc",
                _gc._assignment_int("constellation_%d_foci" % id, 0) if _gc else -1,
                str(fx != null),
                str(fx.size) if fx else "-",
                str(fx.parent_gold) if fx else "-",
                str(fx.foci_arc) if fx else "-"])
    if DEBUG_SLOT_FX:
        _show_debug_lines()


## True while a constellation's identity is still hidden from the player --
## its name reads UNKNOWN everywhere in this panel (selector slot label AND
## the Info panel/title) until its reveal dialogue has actually been read
## to completion. This is now the DEFAULT for every constellation, not just
## Kaleb -- generalized from the original Kaleb-only check.
##
## Constellation 0 (Kaleb, The Archon) keeps his own pre-existing bespoke
## mechanism: game_context.ui_unlocks["kaleb_identity_revealed"], set by the
## Tier 1 Archon reveal dialogue ("it's a little me!"). Every other
## constellation checks game_context.constellation_identity_revealed[id]
## instead, set by root_ui.gd's _on_constellation_identity_reveal_complete()
## once archon_dialogue_manager's generic
## enqueue_constellation_identity_reveal() dialogue has been read. Both
## paths check completion, NOT the dialogue manager's own enqueue-time
## _done flags -- those go true the instant the dialogue is ENQUEUED,
## before the player has read it, which would spoil the reveal.
func _constellation_identity_hidden(constellation_id: int) -> bool:
    if not _gc:
        return true
    if constellation_id == 0:
        return not _gc.ui_unlocks.get("kaleb_identity_revealed", false)
    return not bool(_gc.constellation_identity_revealed.get(constellation_id, false))


## Shared by InfoNameLabel and the panel's top ConstellationTitleLabel --
## a 4th display surface for constellation names, so per the reveal-gating
## rule this MUST go through _constellation_identity_hidden() the same as
## the other three (see kaleb_identity_hidden_until_tier1_reveal memory).
func _display_name_for(constellation_id: int, def: Dictionary) -> String:
    if _constellation_identity_hidden(constellation_id):
        return "UNKNOWN"
    var designation: String = _coerce_string(def.get("designation"), "")
    if designation != "":
        return "%s — %s" % [designation.to_upper(), def.get("name", "Unknown")]
    return def.get("name", "Unknown")


## Reverts the top title to its pre-selection default -- called whenever
## _refresh_info_panel() bails out before it can compute a real selection
## name (nothing selected, bad/missing def, or the grid itself isn't shown
## yet), so the title never gets stuck showing a stale constellation name.
func _set_title_default() -> void:
    if _title_label:
        _title_label.text = DEFAULT_TITLE_TEXT


func _get_slot_label(constellation_id: int) -> String:
    if not _cd or not _cd.unlocked.has(constellation_id):
        return "???"
    if _constellation_identity_hidden(constellation_id):
        return "UNKNOWN"
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
        _refresh_redistribute_button()
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
    _refresh_redistribute_button()


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
    _refresh_redistribute_button()


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


## Manual endowment: push Sparks from the pool into the selected
## Constellation now, rather than waiting for the auto-feed tick.
##
## Scales with the Volumitions click multiplier and NOT with the
## 10X/100X/CSTM/ALL selector — that selector sizes *automation resource*
## assignment (Foci, Volitions, later high-tier Uonites) via the +/-
## buttons, which is a separate axis. See
## game_context.endow_constellation_sparks_manual().
func _on_redistribute_pressed() -> void:
    if not _gc or _selected_slot < 0:
        return
    if _gc.endow_constellation_sparks_manual(_selected_slot) <= 0.0:
        # Capped or out of Sparks — the button should already be disabled,
        # so just re-sync rather than repainting the panel for a no-op.
        _refresh_redistribute_button()
        return
    _refresh_spark_counter()
    _refresh_info_panel()
    _refresh_redistribute_button()


## Greys the button out when a press could not do anything: no
## Constellation selected, no Sparks left, or this one already at its cap.
## Checked against the same cap the endowment itself honours, so the button
## cannot claim to be usable when the transfer would return 0.
func _refresh_redistribute_button() -> void:
    if not _redistribute_btn:
        return
    var usable: bool = false
    if _gc and _selected_slot >= 0 and not _gc.sparks.is_zero():
        usable = true
        if _cd:
            var cap: float = _cd.get_spark_cap(_selected_slot)
            var current: float = _gc.constellation_spark_totals.get(str(_selected_slot), 0.0)
            usable = current < cap
    _redistribute_btn.disabled = not usable
    _redistribute_btn.add_theme_color_override("font_color",
        Color(0.85, 0.78, 1.0) if usable else Color(0.40, 0.38, 0.48))


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
    var state:          String = _cd.get_visual_state(_selected_slot)
    var counter_text: String

    if _show_sparks_numeric:
        if fraction >= 1.0:
            # Fully invested — Kaleb now knows the total cap for this constellation.
            counter_text = "%s / %s Sparks" % [
                _fmt_sparks(raw_invested), _fmt_sparks(cap)]
        else:
            counter_text = "%s Sparks Endowed" % _fmt_sparks(raw_invested)
    else:
        # Percent progress toward the next visual tier uses the hardcoded
        # absolute spark amounts (SPARKS_TIER_STARS / LINES / ART). The old
        # fraction-based THRESHOLD_STARS / line_threshold ranges were retired
        # with the rebalance (see constellation_data.gd constants).
        match state:
            "dark":
                var pct := int((raw_invested / _cd.SPARKS_TIER_STARS) * 100.0) \
                    if _cd.SPARKS_TIER_STARS > 0.0 else 0
                counter_text = "%d%% to Stars" % clampi(pct, 0, 100)
            "stars":
                var range_size: float = _cd.SPARKS_TIER_LINES - _cd.SPARKS_TIER_STARS
                var pct := int(((raw_invested - _cd.SPARKS_TIER_STARS) / range_size) * 100.0) \
                    if range_size > 0.0 else 100
                counter_text = "%d%% to Lines" % clampi(pct, 0, 100)
            "lines":
                var range_size: float = _cd.SPARKS_TIER_ART - _cd.SPARKS_TIER_LINES
                var pct := int(((raw_invested - _cd.SPARKS_TIER_LINES) / range_size) * 100.0) \
                    if range_size > 0.0 else 100
                counter_text = "%d%% to Art" % clampi(pct, 0, 100)
            "art":
                counter_text = "Complete"
            _:
                counter_text = ""

    _spark_counter_label.text = counter_text
    _spark_counter_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _on_spark_counter_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
        return
    _show_sparks_numeric = not _show_sparks_numeric
    _refresh_spark_counter()


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
        _set_title_default()
        return
    var def: Dictionary = _cd.get_constellation_def(_selected_slot)
    if def.is_empty():
        _info_vbox.visible = false
        _set_title_default()
        return
    if not _slot_grid.visible:
        _info_vbox.visible = false
        _set_title_default()
        return
    _info_vbox.visible = true

    # ── Name ── shared with the panel's top title label, so both surfaces
    # stay in lockstep with the current selection (and both honor the
    # identity-hidden gate the same way -- see _constellation_identity_hidden).
    var display_name: String = _display_name_for(_selected_slot, def)
    _info_name_label.text = display_name
    if _title_label:
        _title_label.text = display_name

    # ── Lore ──
    _info_lore_label.text = ""

    # ── Bonus ──
    var bonus_key: String = _coerce_string(def.get("bonus_key"), "")
    var state:     String = _cd.get_visual_state(_selected_slot)
    var bonus_desc: String = BONUS_DESCRIPTIONS.get(
        bonus_key, bonus_key.capitalize().replace("_", " "))
    var solved: bool = false
    if _gc:
        var solve_key := "constellation_%d_solve_count" % _selected_slot
        solved = _gc._assignment_int(solve_key, 0) > 0
    if def.has("bonus_levels"):
        if solved:
            # def["bonus_levels"] is a save-derived field too — a wrong
            # type there would crash calling .get() on it the same way
            # bracket-indexing a non-Dictionary does (see the id-read fix
            # above), and def["bonus_value"]/the state's entry could be
            # wrong-typed even when bonus_levels itself is a real Dictionary.
            var bonus_levels: Dictionary = _coerce_dict(def.get("bonus_levels"), {})
            var default_bonus: float = _coerce_float(def.get("bonus_value"), 1.0)
            var current_val: float = _coerce_float(bonus_levels.get(state, default_bonus), default_bonus)
            var val_fmt: String = ("×%s" % str(current_val)) if _bonus_is_multiplier(bonus_key) \
                else ("+%s" % _fmt_bonus_val(current_val))
            _info_bonus_label.text = "%s: %s" % [bonus_desc, val_fmt]
            _info_bonus_label.add_theme_color_override("font_color",
                TIER_COLORS.get(state, Color.WHITE))
        else:
            # bonus_desc itself is withheld too -- what the constellation's
            # effect even IS stays a mystery until the puzzle is solved,
            # not just its amount.
            _info_bonus_label.text = "??? (puzzle unsolved)"
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

    _refresh_tier_effects_display(def, bonus_key, bonus_desc, state, solved)
    _refresh_art_achievement_display(_selected_slot)


## Fibonacci-tier art achievement readout: how many times this constellation
## has crossed into "art" tier (game_context.gd's constellation_art_tier_
## crossings, edge-triggered there) and the resulting stacking Spark
## Endowment bonus. Hidden entirely at 0 crossings -- nothing earned yet.
## Not gated on `solved` like the bonus ladder above: this bonus applies
## uniformly regardless of bonus_key/bonus_levels, so there's no mystery to
## withhold, and reaching "art" always happens well after the puzzle-
## independent Stars-tier identity reveal.
func _refresh_art_achievement_display(constellation_id: int) -> void:
    if not _info_art_achievement or not _gc:
        return
    var crossings: int = int(_gc.constellation_art_tier_crossings.get(constellation_id, 0))
    if crossings <= 0:
        _info_art_achievement.visible = false
        return
    var bonus_mult: float = _gc.get_constellation_art_tier_bonus(constellation_id)
    var pct: float = (bonus_mult - 1.0) * 100.0
    _info_art_achievement.visible = true
    _info_art_achievement.text = "[font_size=13]Art-Tier Achievements:[/font_size]\n[color=#ffd27f]%d full-tier crossing%s — Spark Endowment +%.1f%%[/color]" \
        % [crossings, "" if crossings == 1 else "s", pct]


## Always-visible ladder of this constellation's bonus at all four tiers
## (Dark/Stars/Lines/Art), with the current tier picked out — separate from
## InfoBonusLabel above, which only ever shows the CURRENT tier's value.
## Only meaningful for constellations with a tiered bonus_levels Dictionary
## (every BUILT_IN one has it); player/patron-authored constellations that
## fall back to a flat bonus_value have no per-tier ladder to show, so the
## label is hidden for those, same as it is before any slot is selected.
func _refresh_tier_effects_display(def: Dictionary, bonus_key: String,
        bonus_desc: String, current_state: String, solved: bool) -> void:
    if not _info_tier_effects:
        return
    if not def.has("bonus_levels") or bonus_key == "":
        _info_tier_effects.text = ""
        _info_tier_effects.visible = false
        if _info_tier_effects_sep:
            _info_tier_effects_sep.visible = false
        return
    _info_tier_effects.visible = true
    if _info_tier_effects_sep:
        _info_tier_effects_sep.visible = true
    if not solved:
        # Same "??? (puzzle unsolved)" rule as InfoBonusLabel above --
        # bonus_desc itself (what the effect IS) is withheld too, not just
        # the per-tier amounts. Only the fact that a tiered bonus exists
        # at all is shown.
        _info_tier_effects.text = "[font_size=13]Effects by Tier:[/font_size]\n[color=#%s]??? (puzzle unsolved)[/color]" \
            % Color(0.45, 0.42, 0.55).to_html(false)
        return
    var bonus_levels:  Dictionary = _coerce_dict(def.get("bonus_levels"), {})
    var default_bonus: float      = _coerce_float(def.get("bonus_value"), 1.0)
    # The other tiers run horizontally in one row; the constellation's
    # CURRENT tier is pulled out of that row and shown alone on the line
    # below, still bold/arrow/tier-colored like before -- just no longer
    # inline with the others, so it reads as "here — of these" rather than
    # one more item in the same list.
    var row_parts:    Array  = []
    var current_line: String = ""
    var is_multiplier: bool = _bonus_is_multiplier(bonus_key)
    for tier in TIER_ORDER:
        var val: float = _coerce_float(bonus_levels.get(tier), default_bonus) \
            if bonus_levels.has(tier) else default_bonus
        var tier_name: String = TIER_DISPLAY_NAMES.get(tier, tier)
        var row_text:  String = ("%s  ×%s" % [tier_name, str(val)]) if is_multiplier \
            else ("%s  +%s" % [tier_name, _fmt_bonus_val(val)])
        if tier == current_state:
            var hi_color: Color = TIER_COLORS.get(tier, Color.WHITE)
            current_line = "[color=#%s][b]▶ %s[/b][/color]" % [hi_color.to_html(false), row_text]
        else:
            var dim_color: Color = TIER_COLORS.get(tier, Color.WHITE).darkened(0.35)
            row_parts.append("[color=#%s]%s[/color]" % [dim_color.to_html(false), row_text])
    _info_tier_effects.text = "[font_size=13]%s — Effects by Tier:[/font_size]\n%s\n%s" \
        % [bonus_desc, "    ".join(row_parts), current_line]


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
