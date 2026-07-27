extends Control
# ================= DIALOGUE JOURNAL POPOUT v4.0.0 =================
# v4.0.0: Second tab row added — Achievements and Bonuses tabs.
#         All five tabs unified into single _switch_tab() system.
# v3.1.0: Notices tab added.
#         Append_notification rebuilds live when tab is active.
# v3.0.0: Restructured History tab — sequence list on left,
#         detail view below. Uses sequence_complete signal
#         to capture full dialogue sequences for reference.
# v2.1.0: Added autowrap on both labels so reference and history text
#         wraps correctly inside the scroll containers.
# v2.0.0: Two-tab layout — Reference (default) and History.
#         Reference contains static production chain and UI definitions.
#         History records all dialogue exchanges with clickable recall.
#         entry_selected signal fires to root_ui.gd for main label replay.

const TAB_WIDTH:   float = 22.0
const PANEL_WIDTH: float = 500.0
const ANIM_TIME:   float = 0.22

const ARCHON_COLOR:   String = "#aaddff"
const PLAYER_COLOR:   String = "#fff4dd"
const NOTIFY_COLOR:   String = "#ffdd88"
const RECALL_COLOR:   String = "#888888"
const HEADER_COLOR:   String = "#ff9933"
const SUBHEAD_COLOR:  String = "#ffcc77"
const BODY_COLOR:     String = "#dddddd"
const COMP_COLOR:     String = "#aaffaa"
const SELECTED_COLOR: String = "#88ff88"
const EARNED_COLOR:   String = "#ffdd44"
const BONUS_COLOR:    String = "#44ffaa"
const UNEARNED_COLOR: String = "#555555"

var _is_open:           bool   = false
var _tween:             Tween  = null
var _active_tab:        String = "reference"

var _sequences:         Array  = []
var _notifications:     Array  = []
var _selected_sequence: int    = -1

@onready var _tab_btn:            Button          = $JournalTabButton
@onready var _panel:              PanelContainer  = $JournalPanel
@onready var _ref_tab:            Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox/RefTabButton
@onready var _hist_tab:           Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox/HistoryTabButton
@onready var _notices_tab:        Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox/NoticesTabButton
@onready var _bonuses_tab:        Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox2/BonusesTabButton
@onready var _achieve_tab:        Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox2/AchievementsTabButton
@onready var _placeholder_tab:    Button          = $JournalPanel/JournalMargin/JournalVBox/JournalTabsHBox2/PlaceholderTabButton

@onready var _ref_scroll:         ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/ReferenceScroll
@onready var _hist_scroll:        ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/HistoryScroll
@onready var _notices_scroll:     ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/NoticesScroll
@onready var _bonuses_scroll:     ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/BonusesScroll
@onready var _achieve_scroll:     ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/AchievementsScroll
@onready var _placeholder_scroll: ScrollContainer = $JournalPanel/JournalMargin/JournalVBox/PlaceholderScroll
@onready var _ref_label:          RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/ReferenceScroll/ReferenceRichTextLabel
@onready var _hist_list_label:    RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/HistoryScroll/HistoryVBox/HistoryListLabel
@onready var _hist_detail_label:  RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/HistoryScroll/HistoryVBox/HistoryDetailLabel
@onready var _notices_label:      RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/NoticesScroll/NoticesLabel
@onready var _bonuses_label:      RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/BonusesScroll/BonusesLabel
@onready var _achieve_label:      RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/AchievementsScroll/AchievementsLabel
@onready var _placeholder_label:  RichTextLabel   = $JournalPanel/JournalMargin/JournalVBox/PlaceholderScroll/PlaceholderLabel

func _ready() -> void:
    _tab_btn.pressed.connect(_on_tab_pressed)
    _ref_tab.pressed.connect(func():      _switch_tab("reference"))
    _hist_tab.pressed.connect(func():     _switch_tab("history"))
    _notices_tab.pressed.connect(func():  _switch_tab("notices"))
    _bonuses_tab.pressed.connect(func():  _switch_tab("bonuses"))
    _achieve_tab.pressed.connect(func():  _switch_tab("achievements"))
    _placeholder_tab.pressed.connect(func(): _switch_tab("placeholder"))
    _hist_list_label.gui_input.connect(_on_hist_list_gui_input)

    _ref_label.autowrap_mode          = TextServer.AUTOWRAP_WORD
    _hist_list_label.autowrap_mode    = TextServer.AUTOWRAP_WORD
    _hist_detail_label.autowrap_mode  = TextServer.AUTOWRAP_WORD
    _notices_label.autowrap_mode      = TextServer.AUTOWRAP_WORD
    _bonuses_label.autowrap_mode      = TextServer.AUTOWRAP_WORD
    _achieve_label.autowrap_mode      = TextServer.AUTOWRAP_WORD
    _placeholder_label.autowrap_mode  = TextServer.AUTOWRAP_WORD

    _panel.visible   = true
    _panel.position  = Vector2(22.0, 0.0)
    _tab_btn.position = Vector2(0.0, 0.0)

    _ref_label.text = _build_reference()
    _switch_tab("reference")


# ==================================================
# PUBLIC — called from root_ui.gd signal connections
# ==================================================
func append_sequence(sequence_name: String, lines: Array) -> void:
    _sequences.append({"name": sequence_name, "lines": lines})
    _rebuild_sequence_list()


func append_notification(text: String) -> void:
    _notifications.append(text.strip_edges())
    if _active_tab == "notices":
        _rebuild_notices()


# ==================================================
# SAVE / LOAD — called by SaveManager, which finds this node via
# get_tree().current_scene.find_child("JournalPopout", ...) since it's a
# scene node, not an autoload. _sequences/_notifications are both plain
# String/Array/Dictionary data, so they round-trip through JSON as-is.
# ==================================================
func get_save_data() -> Dictionary:
    return {
        "sequences":     _sequences,
        "notifications": _notifications,
    }


func load_save_data(data: Dictionary) -> void:
    _sequences     = data.get("sequences", [])
    _notifications = data.get("notifications", [])
    _rebuild_sequence_list()
    if _active_tab == "notices":
        _rebuild_notices()


# ==================================================
# HISTORY — sequence list and detail view
# ==================================================
func _rebuild_sequence_list() -> void:
    var text := ""
    for i in _sequences.size():
        var seq: Dictionary = _sequences[i]
        var is_selected: bool = (i == _selected_sequence)
        var color: String = SELECTED_COLOR if is_selected else SUBHEAD_COLOR
        text += "[color=%s]▶ %s[/color]\n" % [color, seq["name"]]
    _hist_list_label.text = text


func _rebuild_notices() -> void:
    var text := ""
    for i in range(_notifications.size() - 1, -1, -1):
        text += "[color=%s]%s[/color]\n" % [NOTIFY_COLOR, _notifications[i]]
    _notices_label.set("text", text)


func _show_sequence_detail(idx: int) -> void:
    if idx < 0 or idx >= _sequences.size():
        return
    var seq: Dictionary = _sequences[idx]
    var text := "[color=%s][b]%s[/b][/color]\n\n" % [HEADER_COLOR, seq["name"]]
    for line in seq["lines"]:
        if "||" in line:
            var parts = line.split("||", true, 1)
            text += "[color=%s]%s[/color]\n\n" % [ARCHON_COLOR, parts[0].strip_edges()]
            if parts.size() > 1 and parts[1].strip_edges() != "":
                text += "[color=%s]%s[/color]\n\n" % [PLAYER_COLOR, parts[1].strip_edges()]
        else:
            text += "[color=%s]%s[/color]\n\n" % [ARCHON_COLOR, line.strip_edges()]
    _hist_detail_label.text = text


func _on_hist_list_gui_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton: return
    if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
    var line_height = _hist_list_label.get_line_height(0)
    if line_height <= 0: return
    var idx = clamp(int(event.position.y / line_height), 0, _sequences.size() - 1)
    _selected_sequence = idx
    _rebuild_sequence_list()
    _show_sequence_detail(idx)


func _on_history_entry_clicked(_meta: Variant) -> void:
    var idx: int = int(str(_meta))
    if idx < 0 or idx >= _sequences.size():
        return
    _selected_sequence = idx
    _rebuild_sequence_list()
    _show_sequence_detail(idx)


# ==================================================
# ACHIEVEMENTS TAB
# ==================================================
func _rebuild_achievements() -> void:
    var ar: Node = get_node_or_null("/root/AchievementRegistry")
    if not ar:
        _achieve_label.text = "[color=%s]Achievement Registry unavailable.[/color]" % BODY_COLOR
        return
    var text := ""
    var all: Array = ar.get_all_achievements()
    for def in all:
        var earned: bool = ar.is_earned(def["key"])
        if earned:
            text += "[color=%s]★ %s[/color]\n" % [EARNED_COLOR, def["name"]]
            text += "[color=%s]%s[/color]\n\n" % [BODY_COLOR, def["description"]]
        else:
            text += "[color=%s]☆ %s[/color]\n\n" % [UNEARNED_COLOR, def["name"]]
    if text == "":
        text = "[color=%s]No achievements defined yet.[/color]" % BODY_COLOR
    _achieve_label.text = text


# ==================================================
# BONUSES TAB
# ==================================================
func _rebuild_bonuses() -> void:
    var ar: Node = get_node_or_null("/root/AchievementRegistry")
    if not ar:
        _bonuses_label.text = "[color=%s]Achievement Registry unavailable.[/color]" % BODY_COLOR
        return
    var text := ""
    var earned: Array = ar.get_earned_achievements()

    if earned.is_empty():
        _bonuses_label.text = "[color=%s]No bonuses earned yet.[/color]" % BODY_COLOR
        return

    # Group by bonus_type for clean display
    var grouped: Dictionary = {}
    for def in earned:
        if def["bonus_type"] == "":
            continue
        if not grouped.has(def["bonus_type"]):
            grouped[def["bonus_type"]] = []
        grouped[def["bonus_type"]].append(def)

    # Friendly display names for bonus types
    var type_labels: Dictionary = {
        "spark_summon_mult": "Spark Summoning Multiplier",
    }

    for bonus_type in grouped:
        var label: String = type_labels.get(bonus_type, bonus_type)
        var total: float = ar.get_total_multiplier(bonus_type)
        text += "[color=%s][b]%s[/b][/color]\n" % [SUBHEAD_COLOR, label]
        text += "[color=%s]Combined: ×%.4f[/color]\n" % [BONUS_COLOR, total]
        for def in grouped[bonus_type]:
            text += "  [color=%s]%s: ×%.4f[/color]\n" % [BODY_COLOR, def["name"], def["bonus_value"]]
        text += "\n"

    _bonuses_label.text = text
    
    
# ==================================================
# PLACEHOLDER TAB
# ==================================================
func _rebuild_placeholder() -> void:
    _placeholder_label.text = "[color=%s]Coming soon.[/color]" % BODY_COLOR


# ==================================================
# TAB SWITCHING
# ==================================================
func _switch_tab(tab: String) -> void:
    _active_tab = tab
    _ref_scroll.visible         = (tab == "reference")
    _hist_scroll.visible        = (tab == "history")
    _notices_scroll.visible     = (tab == "notices")
    _bonuses_scroll.visible     = (tab == "bonuses")
    _achieve_scroll.visible     = (tab == "achievements")
    _placeholder_scroll.visible = (tab == "placeholder")

    var all_tabs: Array = [_ref_tab, _hist_tab, _notices_tab, _bonuses_tab, _achieve_tab, _placeholder_tab]
    var tab_keys: Array = ["reference", "history", "notices", "bonuses", "achievements", "placeholder"]
    for i in all_tabs.size():
        all_tabs[i].modulate = Color(1, 1, 1, 1.0 if tab_keys[i] == tab else 0.45)

    match tab:
        "history":      _rebuild_sequence_list()
        "notices":      _rebuild_notices()
        "achievements": _rebuild_achievements()
        "bonuses":      _rebuild_bonuses()
        "placeholder":  _rebuild_placeholder()


# ==================================================
# SLIDE TOGGLE
# ==================================================
func _on_tab_pressed() -> void:
    if _is_open:
        _close()
        return
    _is_open = true
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _tween.tween_property(_tab_btn, "position:x", -500.0, ANIM_TIME)
    _tween.parallel().tween_property(_panel, "position:x", -478.0, ANIM_TIME)


func _close() -> void:
    if not _is_open:
        return
    _is_open = false
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _tween.tween_property(_tab_btn, "position:x", 0.0, ANIM_TIME)
    _tween.parallel().tween_property(_panel, "position:x", 22.0, ANIM_TIME)


func _input(event: InputEvent) -> void:
    if not _is_open:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if not _panel.get_global_rect().has_point(event.global_position) \
        and not _tab_btn.get_global_rect().has_point(event.global_position):
            _close()
            get_viewport().set_input_as_handled()


# ==================================================
# REFERENCE CONTENT
# ==================================================
func _build_reference() -> String:
    var t := ""

    t += "[color=%s][b]PRODUCTION CHAIN[/b][/color]\n" % HEADER_COLOR
    t += "[color=%s]Each step compresses or assembles the tier below.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Sparks[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Base resource. Summoned manually or via Foci/Uonites. Cost: free. Consumed by all production steps.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Monads[/color]  [color=%s](Solid / Liquid / Gas)[/color]\n" % [SUBHEAD_COLOR, BODY_COLOR]
    t += "[color=%s]Smallest matter unit. Compress 5 Sparks → 1 Monad (random type). Foundation of Tetrads.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Tetrads[/color]  [color=%s](15 varieties)[/color]\n" % [SUBHEAD_COLOR, BODY_COLOR]
    t += "[color=%s]Assemble 1 Spark + 4 Monads → 1 Tetrad. Variety set by Solid/Liquid/Gas ratio.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Compositions:[/color]\n" % SUBHEAD_COLOR
    var comps := [
        ["Adaemant", "S4"],       ["Aquae",  "L4"],         ["Aethyr", "G4"],
        ["Earth",    "S2/L1/G1"], ["Water",  "L2/S1/G1"],   ["Air",    "G2/S1/L1"],
        ["Mud",      "S2/L2"],    ["Dust",   "S2/G2"],       ["Cloud",  "L2/G2"],
        ["Dirt",     "S3/L1"],    ["Sand",   "S3/G1"],
        ["Haze",     "G3/S1"],    ["Mist",   "G3/L1"],
        ["Ooze",     "L3/S1"],    ["Foam",   "L3/G1"],
    ]
    for c in comps:
        t += "  [color=%s]%s[/color] [color=%s]%s[/color]\n" % [BODY_COLOR, c[0], COMP_COLOR, c[1]]
    t += "\n"

    t += "[color=%s]Particle[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Compress 5 Tetrads → 1 Particle.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Iota[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Assemble 5 Sparks + 16 Monads + 4 Particles → 1 Iota.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Mote[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Compress 5 Iotas → 1 Mote.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Grain[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Assemble 25 Sparks + 64 Monads + 16 Particles + 4 Motes → 1 Grain.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Uonite[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Create 1 Spark + 20 Grains → 1 Uonite. Smallest active intelligence. Used for automation.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]──────────────────[/color]\n\n" % RECALL_COLOR

    t += "[color=%s][b]ARCHON RESOURCES[/b][/color]\n\n" % HEADER_COLOR

    t += "[color=%s]Foci[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Granted per milestone (first creations, quantity thresholds). Assign in the Allocation Wheel to increase automation speed. Every 5 Foci earned grants 1 Volition.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Volitions[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Higher-order assignments. Each active Purity Lock costs 1 Volition. Assignable to operations. Can trigger storage overflow production.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]──────────────────[/color]\n\n" % RECALL_COLOR

    t += "[color=%s][b]UI ELEMENTS[/b][/color]\n\n" % HEADER_COLOR

    t += "[color=%s]Allocation Wheel[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Circular selector. Choose a resource icon, then use +/- to assign Uonites, Foci, or Volitions to that resource's production operation. Multiplier buttons (10×, 100×, ALL) control assignment amount.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Purity Locks  🔒[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Click any resource row or Tetrad label to lock it. Locked resources are excluded from production consumption. Each lock costs 1 Volition. Category locks cover all varieties at once.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Storage Bar[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Shows total resources vs. cap. Cap expands when Sparks overflow it. Assign a Volition to Storage Overflow to allow net-negative operations when storage is full.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Generation Bars[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Show production rate per resource. Left number: workers assigned. Right number: net change per second. Flashing bar means production is outpacing supply.[/color]\n\n" % BODY_COLOR

    t += "[color=%s]Constellations[/color]\n" % SUBHEAD_COLOR
    t += "[color=%s]Unlock post-prestige. Assign Foci/Volitions to octant slots to route Spark production into bonus effects.[/color]\n\n" % BODY_COLOR

    return t
