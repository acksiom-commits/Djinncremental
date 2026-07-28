extends VBoxContainer

# ================= ROOT UI v3.9.0 =================
# v3.9.0: _check_resource_milestones removed entirely — pow(5,n) current-stock
#         thresholds replaced by the totals milestone system at powers of 1000.
#         Call sites removed from both monad and tetrad triggers. Dead function
#         deleted. _check_particle/iota/mote/grain/uonite_trigger functions
#         added, each granting +1 Focus on first creation. Particle/Iota/Mote/
#         Grain triggers also post "First X: +1 Focus." to notification_queue.
# v3.8.0: enqueue_first_particle wired. _first_particle_triggered flag added.
# v3.6.0: enqueue_all_fundaments wired. _all_fundaments_triggered flag added.
# v3.5.0  First Fundament dialogue trigger wired to _check_tetrad_upgrade_trigger
#         First_volition call removed from _check_volition_grant
# v3.4.0  Expression signal wired from ArchonDialogueManager to ArchonTetrahedron
# v3.3.0: All session changes integrated. Dialogue journal
#         popout wired. Tetrad assembly gate added. Category/
#         all-tetrads Foci grants wired. Totals milestones added.
#         Volitions counter accounts for lock costs. Tetrad
#         tooltips via mouse motion. monad_sequence_complete
#         signal removed (dead code). Missing middle section
#         restored after truncation.
# v3.2.0: Progressive UI reveal system.
# v3.1.0: Tutorial alert pulse system, input blocking.
# v3.0.0: Foci/Refinement unified, milestone triggers.
# v2.9.0: Cooldown bar integration.

# COMPLETE FILE — NO PLACEHOLDERS, NO OMISSIONS

# === RESOURCE COLORS ===
const RESOURCE_COLORS = {
    "sparks":   Color("#ffffff"),
    "monad":    Color("#ee4444"),
    "tetrad":   Color("#ff9933"),
    "particle": Color("#eecc00"),
    "iota":     Color("#55ff88"),
    "mote":     Color("#55aaff"),
    "grain":    Color("#9944ee"),
    "uonite":   Color("#ffdd55")
}

# === MANAGER REFERENCES ===
var game_context:            Node = null
var production_manager:      Node = null
var save_manager:            Node = null
var game_data:               Node = null
var archon_dialogue_manager: Node = null
var _uonite_icosa:           Node = null
var _journal_popout:         Node = null
var _ages_popout:            Node = null
var _settings_popout:        Node = null
var _constellation_popout:   Node = null
var _archon_tetra:           Node = null


# === SAVE MANAGEMENT ===
var _autosave_accum: float = 0.0


# === AGE GATES ===
var _firmament_threshold_revealed: bool = false


# === Resource Button Tooltip Totals
var _tooltip_buttons: Dictionary = {}
var _tooltip_accum:   float      = 0.0


# === DIALOGUE TRIGGER FLAGS ===
var _monad_upgrade_triggered:       bool = false
var _second_monad_triggered:        bool = false
var _tetrad_upgrade_triggered:      bool = false
var _all_monads_triggered:          bool = false
var _tetrad_assembly_ready:         bool = false
var _first_fundament_triggered:     bool = false
var _all_fundaments_triggered:      bool = false
var _first_non_fundament_category_triggered: bool = false
var _first_particle_triggered:      bool = false
var _first_iota_triggered:          bool = false
var _first_mote_triggered:          bool = false
var _first_grain_triggered:         bool = false
var _nineteenth_grain_triggered:    bool = false
var _twentieth_grain_triggered:     bool = false
var _first_uonite_triggered:        bool = false

var _end_first_prestige_triggered:  bool = false
var _archon_volition_constellation_triggered: bool = false
var _no_archon_volition_constellation_triggered: bool = false

var _spark_movement_triggered:      bool = false
var _star_in_view_triggered:        bool  = false
var _tier1_archon_complete_triggered:   bool = false
var _star_in_view_time:             float = 0.0
var _first_constellation_triggered: bool = false
var _post_constellation_spark_count:            int  = 0
var _constellation_panel_creation_triggered:    bool = false
var _open_constellation_panel_triggered:        bool = false
var _study_panel_reveal_triggered:              bool = false

var _monad_type_triggered: Dictionary = {
    "solid":  false,
    "liquid": false,
    "gas":    false,
}


var _tetrad_variety_triggered: Dictionary = {
    "adaemant": false, "aquae": false, "aethyr": false,
    "earth":    false, "water": false, "air":    false,
    "mud":      false, "dust":  false, "cloud":  false,
    "dirt":     false, "sand":  false, "haze":   false,
    "mist":     false, "ooze":  false, "foam":   false,
}


# === SUMMON SPARK EFFECT ===
const SPARK_EFFECT = preload("res://effects/spark_effect.tscn")


# === FIRST UONITE NAME LIST ===
const UONITE_NAMES: Array = [
    "Sprocket", "Wobblesworth", "Clanketty", "Fizzlewick", "Grumblecog",
    "Zibzab", "Thunkerton", "Puddlejump", "Noodlecrank", "Wibbleflux",
    "Blibbering", "Squonk", "Frumple", "Dinglepop", "Zygmunt",
    "Pifflewick", "Crumblethwaite", "Snorkelton", "Bumblecog", "Whifflecrank",
]

# === ICOSAHEDRON DISPLAY ===
var _icosa_grain_display: int = 0

# === TETRAD DISPLAY LABELS ===
var _left_tetrad_label: RichTextLabel = null
var _middle_label:      RichTextLabel = null
var _medials2_label:    RichTextLabel = null

const TETRAD_NAMES = {
    "adaemant": "Adaemant", "aquae": "Aquae",  "aethyr": "Aethyr",
    "earth":    "Earth",    "water": "Water",   "air":    "Air",
    "mud":      "Mud",      "dust":  "Dust",    "cloud":  "Cloud",
    "dirt":     "Dirt",     "sand":  "Sand",    "haze":   "Haze",
    "mist":     "Mist",     "ooze":  "Ooze",    "foam":   "Foam",
}

const LEFT_LINE_MAP = [
    "cat_fundament",
    "adaemant", "adaemant",
    "aquae",    "aquae",
    "aethyr",   "aethyr",
    "cat_medial",
    "dirt",     "dirt",
    "sand",     "sand",
]

const MIDDLE_LINE_MAP = [
    "cat_element",
    "earth",    "earth",
    "water",    "water",
    "air",      "air",
    "cat_medial",
    "haze",     "haze",
    "mist",     "mist",
]

const MEDIALS2_LINE_MAP = [
    "cat_symmetric",
    "mud",   "mud",
    "dust",  "dust",
    "cloud", "cloud",
    "cat_medial",
    "ooze", "ooze",
    "foam", "foam",
]

# === BAR NODE REFERENCES ===
var bars: Dictionary = {}

const BAR_LABEL_COLOR     = Color(0.85, 0.85, 0.85, 0.65)
const BAR_LABEL_FONT_SIZE = 16

# === BAR DISPLAY STATE ===
var _bar_smoothed_rates: Dictionary = {}
var _time:               float      = 0.0
var _timer_intervals:    Dictionary = {}
var _bar_fill_styles:    Dictionary = {}

const BAR_SMOOTH_RATE:     float = 3.5
const BAR_FLASH_THRESHOLD: float = 1.05
const BAR_FLASH_SPEED:     float = 4.0
const BAR_ASYMPTOTE_SCALE: float = 10.0

# === STORAGE DISPLAY ===
var _storage_display: Node = null

# === CLICK VOLITIONS ===
var _click_vol_label: Label = null
var _click_vol_plus_btn:  Button = null
var _click_vol_minus_btn: Button = null
var _vol_btn_style_on:    StyleBoxFlat = null
var _vol_btn_style_hover: StyleBoxFlat = null
var _vol_btn_style_off:   StyleBoxFlat = null

# === TUTORIAL PULSE ===
var _archon_panel:     Node  = null
var _dialogue_panel:   Node  = null
var _pulse_tween:      Tween = null
var _tutorial_pending: bool  = false

# === UI REVEAL ===
var _panel_nodes: Dictionary = {}
const REVEAL_DURATION: float = 1.5

# === FIRST UONITE NAME ===
var _name_picker_vbox:    Control = null
var _name_picker_label:   Label   = null
var _name_picker_next:    Button  = null
var _name_picker_confirm: Button  = null
var _name_picker_index:   int     = 0

# === DEV ===
const DEV_UONITE_CHUNK = [1.11, 33]

# === HIDDEN UI CLICK TRANSPARENCY ===
var _saved_mouse_filters: Dictionary = {}

# === KALEB TIME OUT UI LOCK
var _ui_lock_blocker: Control = null
var _archon_minigame: ArchonPokeMinigame = null

# === MINIMAL UI MODE ===
var _ui_minimal_active: bool  = false
var _ui_minimal_hidden: Array = []

# === EXPANSION ANIMATION ===
const _EXPANSION_SHADER_SRC := """
shader_type canvas_item;

uniform float distortion_strength : hint_range(0.0, 3.0) = 0.0;
uniform float white_amount        : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
    vec2  center = vec2(0.5, 0.5);
    vec2  offset = SCREEN_UV - center;
    float r      = length(offset);

    // Barrel distortion: sample UV is pulled toward center.
    // Output pixels at the edges show content from near-center,
    // so the center content appears to rush outward — toward the player.
    float warp_scale = 1.0 / (1.0 + distortion_strength * r * r * 3.0);
    vec2  sample_uv  = center + offset * warp_scale;

    // Radial vignette: white blooms inward from the screen boundary
    // as distortion grows, completing the enveloping sensation.
    // At distortion_strength = 0 the threshold sits beyond the screen
    // corners (~0.707) so no white is visible at rest.
    float inner     = 0.75 - distortion_strength * 0.65;
    float outer     = inner + 0.14;
    float edge_white = smoothstep(inner, outer, r);

    vec4 screen_col = texture(SCREEN_TEXTURE, sample_uv);

    // edge_white closes in from outside; white_amount takes everything
    // to full white at the peak regardless of remaining distortion.
    COLOR = mix(screen_col, vec4(1.0), max(white_amount, edge_white));
}
"""

var _expansion_anim_active: bool           = false
var _expansion_overlay:     ColorRect      = null
var _expansion_shader_mat:  ShaderMaterial = null

# ==================================================
# READY
# ==================================================
func _ready() -> void:
    game_context            = get_node_or_null("/root/GameContext")
    production_manager      = get_node_or_null("/root/ProductionManager")
    save_manager            = get_node_or_null("/root/SaveManager")
    game_data               = get_node_or_null("/root/GameData")
    archon_dialogue_manager = get_node_or_null("/root/ArchonDialogueManager")
    _uonite_icosa           = find_child("UoniteIcosahedron", true, false)
    _storage_display        = find_child("StorageDisplay",    true, false)
    _archon_tetra           = find_child("ArchonTetrahedron", true, false)
    var _archon_panel_node := find_child("ArchonGraphicPanel", true, false)
    _ui_lock_blocker = get_node_or_null("../UILockBlocker")
    _archon_minigame = ArchonPokeMinigame.new()
    _archon_minigame.setup(self, game_context, archon_dialogue_manager, _archon_tetra, _ui_lock_blocker)
    if _archon_panel_node:
        _archon_panel_node.gui_input.connect(_archon_minigame.on_gui_input)
    var _picker_base := "TopBandHBox/RightStackVBox/DialoguePanelContainer/DialogueMargin/DialogueVBox/"
    _name_picker_vbox    = get_node_or_null(_picker_base + "NamePickerVBox")
    _name_picker_label   = get_node_or_null(_picker_base + "NamePickerVBox/NamePickerHBox/NamePickerCurrentLabel")
    _name_picker_next    = get_node_or_null(_picker_base + "NamePickerVBox/NamePickerHBox/NamePickerNextButton")
    _name_picker_confirm = get_node_or_null(_picker_base + "NamePickerVBox/NamePickerConfirmButton")
    if _name_picker_next:
        _name_picker_next.pressed.connect(_on_name_picker_next)
    if _name_picker_confirm:
        _name_picker_confirm.pressed.connect(_on_name_picker_confirm)
    
    if production_manager:
        _timer_intervals = production_manager.get_timer_intervals()

    _setup_resource_rows()
    _setup_bars()
    _connect_tetrad_signals()
    call_deferred("_setup_dialogue")
    call_deferred("_load_on_start")
    _connect_action_buttons()
    _cache_tooltip_buttons()
    

    _journal_popout = find_child("JournalPopout", true, false)
    if _journal_popout and archon_dialogue_manager:
        archon_dialogue_manager.sequence_complete.connect(
            _journal_popout.append_sequence)
        archon_dialogue_manager.sequence_complete.connect(
            _on_sequence_complete)
        archon_dialogue_manager.notification_shown.connect(
            _journal_popout.append_notification)

    _ages_popout = find_child("AgesPopout", true, false)
    if not _ages_popout:
        push_warning("RootUI: AgesPopout not found")
    else:
        _ages_popout.age_selected.connect(_on_age_selected)
        _ages_popout.call_deferred("set_active_age", "primordial")
        
    _settings_popout = find_child("SettingsPopout", true, false)
    if _settings_popout:
        _settings_popout.save_requested.connect(save_game)
        _settings_popout.load_requested.connect(load_game)
        _settings_popout.reset_requested.connect(_on_reset_requested)
        _settings_popout.quit_requested.connect(func(): get_tree().quit())
        _settings_popout.ui_minimal_requested.connect(_on_ui_minimal_requested)
        
    _constellation_popout = find_child("ConstellationPopout", true, false)
    if _constellation_popout:
        var _cp := find_child("ConstellationPanel", true, false)
        if _cp:
            _constellation_popout.constellation_selected.connect(_cp.on_constellation_selected)
            _constellation_popout.constellation_selected.connect(_on_constellation_selected_logic_puzzle)
            _constellation_popout.panel_first_opened.connect(_on_constellation_first_opened)
    else:
        push_warning("RootUI: ConstellationPopout not found")

    var _overlay := get_node_or_null("/root/Node2D/CanvasLayer/ConstellationOverlay")
    if _overlay:
        _overlay.puzzle_star_clicked.connect(_on_puzzle_star_clicked)
        
    if save_manager:
        save_manager.game_loaded.connect(_on_game_loaded)
        

    _archon_panel   = find_child("ArchonTetrahedronContainer", true, false)
    _dialogue_panel = find_child("DialoguePanelContainer",     true, false)
    if archon_dialogue_manager:
        
        archon_dialogue_manager.tutorial_dialogue_started.connect(_on_tutorial_started)
        archon_dialogue_manager.tutorial_dialogue_cleared.connect(_on_tutorial_cleared)
        archon_dialogue_manager.tutorial_dialogue_acknowledged.connect(_on_tutorial_acknowledged)
        archon_dialogue_manager.monad_random_dialogue_ended.connect(_on_monad_random_dialogue_ended)
        archon_dialogue_manager.second_monad_sequence_complete.connect(_on_second_monad_complete)
        archon_dialogue_manager.all_monads_sequence_complete.connect(_on_all_monads_complete)
        archon_dialogue_manager.first_particle_sequence_complete.connect(_on_first_particle_complete)
        archon_dialogue_manager.ui_reveal_requested.connect(_reveal_panel)
        archon_dialogue_manager.tetrad_category_complete.connect(_on_tetrad_category_complete)
        archon_dialogue_manager.all_tetrads_complete.connect(_on_all_tetrads_complete)
        if _archon_tetra:
            archon_dialogue_manager.expression_requested.connect(_archon_tetra.play_expression)
        archon_dialogue_manager.first_prestige_sequence_complete.connect(_on_first_prestige_complete)
        archon_dialogue_manager.second_prestige_sequence_complete.connect(_on_second_prestige_complete)
        archon_dialogue_manager.third_prestige_sequence_complete.connect(_on_third_prestige_complete)
        archon_dialogue_manager.fourth_prestige_sequence_complete.connect(_on_fourth_prestige_complete)
        archon_dialogue_manager.fifth_prestige_sequence_complete.connect(_on_fifth_prestige_complete)
        archon_dialogue_manager.start_second_prestige_sequence_complete.connect(_on_start_second_prestige_complete)
        archon_dialogue_manager.archon_volition_constellation_sequence_complete.connect(_on_archon_volition_constellation_complete)
        archon_dialogue_manager.no_archon_volition_constellation_sequence_complete.connect(_on_no_archon_volition_constellation_complete)
        archon_dialogue_manager.spark_movement_sequence_complete.connect(_on_spark_movement_complete)
        archon_dialogue_manager.star_chase_sequence_complete.connect(_on_star_chase_complete)
        archon_dialogue_manager.tier1_archon_complete_sequence_complete.connect(_on_tier1_archon_complete_complete)
        archon_dialogue_manager.uonite_name_requested.connect(_on_uonite_name_requested)
        archon_dialogue_manager.first_constellation_sequence_complete.connect(_on_first_constellation_complete)
        archon_dialogue_manager.constellation_panel_creation_sequence_complete.connect(_on_constellation_panel_created)
        archon_dialogue_manager.open_constellation_panel_sequence_complete.connect(_on_constellation_panel_opened)
        archon_dialogue_manager.study_panel_reveal_sequence_complete.connect(_on_study_panel_reveal_complete)
    _build_simple_triggers()
    _setup_panel_nodes()
    _hide_all_panels()
    _apply_unlock_visibility()
    
    
# ==================================================
# PROGRESSIVE UI REVEAL
# ==================================================
func _setup_panel_nodes() -> void:
    _panel_nodes = {
        "monad_panel":      find_child("CompressPanelContainer",       true, false),
        "direct_readouts":  find_child("DirectReadoutsPanelContainer", true, false),
        "allocation_wheel": find_child("AllocationWheelControl",       true, false),
        "tetrad_panel":     find_child("AssembleTetradVBox",           true, false),
        "particle":         find_child("ParticleIotaMoteGrainVBox",    true, false),
        "genbars":          find_child("GenBarsVBox",                  true, false),
        "uonite_creation":  find_child("UoniteCreationPanel",          true, false),
        "constellation":    find_child("ConstellationPanel",           true, false),
        "uonite_button":    find_child("CreateUoniteButton",           true, false),
        "uonite_cooldown":  find_child("UoniteCooldownBar",            true, false),
        "volumition":       find_child("ClickVolAssistVBox",           true, false),
        "stoctagon":        _storage_display,
    }


func _hide_all_panels() -> void:
    for key in _panel_nodes:
        var node = _panel_nodes[key]
        if node:
            node.modulate.a = 0.0
            node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_unlock_visibility() -> void:
    if not game_context:
        return
    for key in _panel_nodes:
        var node = _panel_nodes[key]
        if not node:
            continue
        if _ui_minimal_active and _ui_minimal_hidden.has(node):
            continue
        if game_context.ui_unlocks.get(key, false):
            node.modulate.a   = 1.0
            node.mouse_filter = Control.MOUSE_FILTER_STOP
            _restore_subtree_input(node)
        else:
            node.modulate.a   = 0.0
            node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Restore tetrad assembly gate for saves past the all-monads sequence
    if archon_dialogue_manager and archon_dialogue_manager.all_monads_upgrade_done:
        _tetrad_assembly_ready = true


func _reveal_panel(unlock_key: String) -> void:
    if not game_context:
        return
    if game_context.ui_unlocks.get(unlock_key, false):
        return
    game_context.ui_unlocks[unlock_key] = true
    var node = _panel_nodes.get(unlock_key)
    if not node:
        return
    node.mouse_filter = Control.MOUSE_FILTER_STOP
    _restore_subtree_input(node)
    var tween = create_tween()
    tween.tween_property(node, "modulate:a", 1.0, REVEAL_DURATION) \
        .set_trans(Tween.TRANS_SINE) \
        .set_ease(Tween.EASE_OUT)
        
        
func _restore_subtree_input(node: Node) -> void:
    for child in node.get_children():
        if child is Button:
            child.mouse_filter = Control.MOUSE_FILTER_STOP
        elif child is Container:
            child.mouse_filter = Control.MOUSE_FILTER_PASS
        elif child is Control:
            if child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
                child.mouse_filter = Control.MOUSE_FILTER_PASS
        _restore_subtree_input(child)
        
        
func _on_ui_minimal_requested(minimal: bool) -> void:
    _ui_minimal_active = minimal
    var hide_nodes: Array = [
        get_node_or_null("TopBandHBox/BarsPanelContainer"),
        get_node_or_null("TopBandHBox/LeftStackVBox"),
        get_node_or_null("TopBandHBox/RightStackVBox"),
        get_node_or_null("TopBandHBox/AllocationConstellationVBox/AllocationWheelControl"),
        get_node_or_null("TopBandHBox/AllocationConstellationVBox/ConstellationLeftMargin"),
        get_node_or_null("BottomPopoutsHBox/ConstellationPopout"),
        get_node_or_null("TopBandHBox/RightEdgePopoutsVBox/JournalPopout"),
        get_node_or_null("TopBandHBox/LeftEdgePopoutsVBox/AgesPopout"),
    ]
    if minimal:
        _ui_minimal_hidden.clear()
        _saved_mouse_filters.clear()
        var fade := Color(1.0, 1.0, 1.0, 0.0)
        for n in hide_nodes:
            if not n:
                continue
            _ui_minimal_hidden.append(n)
            n.modulate = fade
            _hide_subtree(n)
    else:
        for n in hide_nodes:
            if not n:
                continue
            n.modulate = Color(1.0, 1.0, 1.0, 1.0)
            _show_subtree(n)
        _ui_minimal_hidden.clear()
        _saved_mouse_filters.clear()
    _apply_unlock_visibility()


# ==================================================
# DIALOGUE
# ==================================================
func _setup_dialogue() -> void:
    if not archon_dialogue_manager:
        push_warning("RootUI: ArchonDialogueManager not found")
        return

    var dialogue_base = "TopBandHBox/RightStackVBox/DialoguePanelContainer/DialogueMargin/DialogueVBox/"
    var label = get_node_or_null(dialogue_base + "ArchonDialogueRichTextLabel")
    if not label:
        push_warning("RootUI: ArchonDialogueRichTextLabel not found")
        return

    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    archon_dialogue_manager.set_display_nodes(label, null)

    var panel = get_node_or_null("TopBandHBox/RightStackVBox/DialoguePanelContainer")
    if panel:
        panel.mouse_filter = Control.MOUSE_FILTER_STOP
        if panel.gui_input.is_connected(_on_dialogue_panel_clicked):
            panel.gui_input.disconnect(_on_dialogue_panel_clicked)
        panel.gui_input.connect(_on_dialogue_panel_clicked)
    else:
        push_warning("RootUI: DialoguePanelContainer not found for click wiring")


func _on_dialogue_panel_clicked(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if archon_dialogue_manager:
            archon_dialogue_manager.advance_dialogue()
            
            
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            if archon_dialogue_manager and archon_dialogue_manager.current_index >= 0:
                archon_dialogue_manager.advance_dialogue()
                get_viewport().set_input_as_handled()
            
            

# ==================================================
# TUTORIAL PULSE
# ==================================================
func _on_tutorial_started() -> void:
    _tutorial_pending = true
    _start_pulse()


func _on_tutorial_cleared() -> void:
    if not archon_dialogue_manager._tutorial_active:
        _tutorial_pending = false
        _stop_pulse()


func _on_tutorial_acknowledged() -> void:
    _stop_pulse()


func _start_pulse() -> void:
    if _pulse_tween:
        _pulse_tween.kill()
    var bright = Color(1.6, 1.4, 0.8, 1.0)
    var normal = Color(1.0, 1.0, 1.0, 1.0)
    _pulse_tween = create_tween()
    _pulse_tween.set_parallel(true)
    _pulse_tween.set_loops()
    _pulse_tween.set_trans(Tween.TRANS_SINE)
    _pulse_tween.set_ease(Tween.EASE_IN_OUT)
    if _archon_panel:
        _pulse_tween.tween_property(_archon_panel,   "modulate", bright, 0.6)
        _pulse_tween.chain().tween_property(_archon_panel,   "modulate", normal, 0.6)
    if _dialogue_panel:
        _pulse_tween.tween_property(_dialogue_panel, "modulate", bright, 0.6)
        _pulse_tween.chain().tween_property(_dialogue_panel, "modulate", normal, 0.6)


func _stop_pulse() -> void:
    if _pulse_tween:
        _pulse_tween.kill()
        _pulse_tween = null
    if _archon_panel:
        _archon_panel.modulate   = Color(1.0, 1.0, 1.0, 1.0)
    if _dialogue_panel:
        _dialogue_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _is_tutorial_blocking() -> bool:
    if not archon_dialogue_manager:
        return false
    return archon_dialogue_manager.current_index >= 0 and archon_dialogue_manager._tutorial_pending


# ==================================================
# MILESTONE FOCI TRIGGERS + UI REVEALS
# ==================================================
func _grant_foci(amount: int = 1) -> void:
    if not game_context:
        return
    game_context.archon_foci += amount
    _check_volition_grant()


func _on_monad_random_dialogue_ended() -> void:
    _reveal_panel("allocation_wheel")


func _check_volition_grant() -> void:
    if not game_context or not archon_dialogue_manager:
        return
    var foci             = game_context.archon_foci
    var threshold        = 5
    var volitions_earned = 0
    while foci >= threshold:
        volitions_earned += 1
        threshold        *= 5
    if volitions_earned > game_context.volitions:
        var to_grant = volitions_earned - game_context.volitions
        game_context.volitions += to_grant
        game_context._ensure_slot_count(game_context.volitions)
        if not game_context.purity_locks_unlocked and volitions_earned > 0:
            game_context.purity_locks_unlocked = true
    # Uonite reveal is checked independently — TAB-granted volitions
    # can push game_context.volitions past the foci-earned threshold,
    # so the reveal must not rely on the volitions comparison gate.
    if game_context.archon_foci >= 25:
        _reveal_panel("uonite_creation")
        _reveal_panel("uonite_button")
        _reveal_panel("uonite_cooldown")


func _on_sequence_complete(sequence_name: String, _lines: Array) -> void:
    if sequence_name == "First Tetrad Created":
        _reveal_panel("volumition")


func _check_monad_upgrade_trigger() -> void:
    if not archon_dialogue_manager or not game_context:
        return
    if not game_context.ui_unlocks.get("monad_panel", false):
        if game_context.sparks.is_greater_or_equal(BigNum.from_int(5)):
            _reveal_panel("monad_panel")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_monad_panel_dialogue()
    for type_key in _monad_type_triggered:
        if _monad_type_triggered[type_key]:
            continue
        if not game_context.monad[type_key].is_zero():
            _monad_type_triggered[type_key] = true
            game_context.record_first_creation(type_key)
            if not _monad_upgrade_triggered:
                _monad_upgrade_triggered = true
                _reveal_panel("direct_readouts")
            _grant_foci()
            if not archon_dialogue_manager.monad_random_done:
                archon_dialogue_manager.enqueue_monad_random_dialogue(type_key)
            if not _second_monad_triggered:
                var types_found = _monad_type_triggered.values().filter(func(v): return v == true).size()
                if types_found == 2:
                    _second_monad_triggered = true
                    archon_dialogue_manager.enqueue_second_monad()
    if not _all_monads_triggered:
        var wm = game_context.watermarks
        if not wm["monad_solid"].is_zero() and \
           not wm["monad_liquid"].is_zero() and \
           not wm["monad_gas"].is_zero():
            _all_monads_triggered = true
            archon_dialogue_manager.enqueue_all_monads_upgrade()
            _grant_foci()
            game_context.ui_unlocks["wheel_full_access"] = true


func _on_second_monad_complete() -> void:
    _reveal_panel("tetrad_panel")


func _on_first_particle_complete() -> void:
    _reveal_panel("genbars")
    _reveal_panel("particle")
    var chain: Control = find_child("IotaMoteGrainVBox", true, false)
    if chain:
        chain.mouse_filter = Control.MOUSE_FILTER_STOP
        var tween = create_tween()
        tween.tween_property(chain, "modulate:a", 1.0, REVEAL_DURATION) \
            .set_trans(Tween.TRANS_SINE) \
            .set_ease(Tween.EASE_OUT)
    

func _on_all_monads_complete() -> void:
    _tetrad_assembly_ready = true


func _on_tetrad_category_complete(_category_name: String) -> void:
    _grant_foci()


func _on_all_tetrads_complete() -> void:
    _grant_foci()
    if archon_dialogue_manager:
        archon_dialogue_manager.enqueue_all_tetrads()
        
        
func _on_first_prestige_complete() -> void:
    _start_puzzle_generation(1)  # pre-generate Spark (id 1)


func _on_second_prestige_complete() -> void:
    _start_puzzle_generation(2)  # pre-generate Hourglass (id 2)


func _on_third_prestige_complete() -> void:
    _start_puzzle_generation(3)  # pre-generate Satchel (id 3)


func _on_fourth_prestige_complete() -> void:
    _start_puzzle_generation(4)  # pre-generate Bellows (id 4)


func _on_fifth_prestige_complete() -> void:
    pass  # no sixth constellation yet; add when id 5 is defined


func _on_start_second_prestige_complete() -> void:
    pass


func _on_archon_volition_constellation_complete() -> void:
    if _constellation_popout:
        _constellation_popout.show_slot_grid()


func _on_no_archon_volition_constellation_complete() -> void:
    if _constellation_popout:
        _constellation_popout.show_slot_grid()


func _on_spark_movement_complete() -> void:
    pass


func _on_star_chase_complete() -> void:
    pass


func _on_tier1_archon_complete_complete() -> void:
    pass


func _on_first_constellation_complete() -> void:
    if game_context:
        game_context.hint_bias_enabled = true
        
        
func _on_constellation_panel_created() -> void:
    if _constellation_popout:
        _constellation_popout.show_tab()


func _on_constellation_first_opened() -> void:
    if _open_constellation_panel_triggered:
        return
    _open_constellation_panel_triggered = true
    if _constellation_popout:
        _constellation_popout.set_close_locked(true)
    if archon_dialogue_manager:
        archon_dialogue_manager.enqueue_open_constellation_panel()


func _on_puzzle_star_clicked(_star_index: int) -> void:
    if _study_panel_reveal_triggered or not archon_dialogue_manager:
        return
    _study_panel_reveal_triggered = true
    archon_dialogue_manager.enqueue_study_panel_reveal()


func _on_study_panel_reveal_complete() -> void:
    var cp := find_child("ConstellationPanel", true, false)
    if cp and cp.has_method("reveal_study_button"):
        cp.reveal_study_button()


func _on_constellation_panel_opened() -> void:
    if _constellation_popout:
        _constellation_popout.set_close_locked(false)


func _on_constellation_selected_logic_puzzle(constellation_id: int) -> void:
    if constellation_id < 0:
        return
    var cd = get_node_or_null("/root/ConstellationData")
    if not cd or not archon_dialogue_manager:
        return

    # Serve from cache if already generated.
    var cached: Dictionary = cd.get_puzzle_cache(constellation_id)
    if not cached.is_empty():
        var puzzle := ConstellationLogicPuzzle.new()
        if puzzle.from_cache_dict(cached):
            return

    # Cache miss — generate now (should only happen on first run before
    # pre-generation has completed, or after a save with missing cache).
    _start_puzzle_generation(constellation_id)


func _start_puzzle_generation(constellation_id: int) -> void:
    var cd = get_node_or_null("/root/ConstellationData")
    if not cd:
        return
    var def: Dictionary = cd.get_constellation_def(constellation_id)
    _generate_puzzle(constellation_id, cd, def, cd.player_seed,
        "puzzle generation",
        func(cid: int, puzzle: ConstellationLogicPuzzle): _on_puzzle_generation_complete(cid, puzzle))


func _on_puzzle_generation_complete(constellation_id: int,
        puzzle: ConstellationLogicPuzzle) -> void:
    var cd = get_node_or_null("/root/ConstellationData")
    if not cd:
        return
    cd.set_puzzle_cache(constellation_id, puzzle.to_cache_dict())
    var study := get_node_or_null("/root/Node2D/CanvasLayer/ConstellationStudyOverlay")
    if study and study.visible and study.has_method("show_for_constellation") \
            and study.has_method("get_current_constellation_id") \
            and study.get_current_constellation_id() == constellation_id:
        study.show_for_constellation(constellation_id)


func _dev_recompute_puzzle(constellation_id: int) -> void:
    var cd = get_node_or_null("/root/ConstellationData")
    if not cd or not game_context:
        return
    cd.clear_puzzle_cache(constellation_id)
    var solve_key: String = "constellation_%d_solve_count" % constellation_id
    var hw_key: String = "constellation_%d_high_water" % constellation_id
    game_context.assignments.erase(solve_key)
    game_context.assignments.erase(hw_key)

    var def: Dictionary = cd.get_constellation_def(constellation_id)
    var dev_seed: int = randi()
    _generate_puzzle(constellation_id, cd, def, dev_seed,
        "puzzle recompute",
        func(cid: int, puzzle: ConstellationLogicPuzzle):
            cd.set_puzzle_cache(cid, puzzle.to_cache_dict())
            print("[DEV] Constellation %d puzzle recomputed, seed=%d" % [cid, dev_seed])
            var study := get_node_or_null("/root/Node2D/CanvasLayer/ConstellationStudyOverlay")
            if study and study.visible and study.has_method("show_for_constellation"):
                study.show_for_constellation(cid))


# ==================================================
# SHARED — validates a constellation def, builds a ConstellationLogicPuzzle,
# and kicks off async generation. Extracted 2026-07-27 from
# _start_puzzle_generation/_dev_recompute_puzzle, which used to reimplement
# this ~17-line block near-verbatim; each caller keeps its own guard,
# pre-work (cache/state reset or none), seed, and completion callback —
# only the mechanical lookup+construction part was shared.
# ==================================================
func _generate_puzzle(constellation_id: int, cd: Node, def: Dictionary,
        puzzle_seed: int, warning_context: String, on_complete: Callable) -> void:
    if def.is_empty():
        return
    var star_count: int = def.get("star_count", 0)
    if star_count <= 0:
        return
    var overlay := get_parent().find_child("ConstellationOverlay", true, false)
    if not overlay or not overlay.has_method("get_correct_star_sequence"):
        push_warning("RootUI: ConstellationOverlay not found for %s." % warning_context)
        return
    var line_pairs: Array = def.get("line_pairs", [])
    var correct_star_sequence: Array = overlay.get_correct_star_sequence(constellation_id)
    var name_theme: Dictionary = def.get("name_theme", {})
    var star_pitch_index: Array = cd.get_note_assignment(constellation_id)
    var pitch_freqs: Array = cd.get_note_freqs(constellation_id)

    var puzzle := ConstellationLogicPuzzle.new()
    puzzle.setup(star_count, line_pairs, correct_star_sequence,
            puzzle_seed, constellation_id, name_theme,
            star_pitch_index, pitch_freqs, self)
    puzzle.generation_complete.connect(
        func(cid: int): on_complete.call(cid, puzzle))
    puzzle.generate_clues_async.call_deferred()


func _on_uonite_name_requested() -> void:
    _name_picker_index = 0
    _update_name_picker_display()
    var dialogue_label = get_node_or_null(
        "TopBandHBox/RightStackVBox/DialoguePanelContainer/DialogueMargin/DialogueVBox/ArchonDialogueRichTextLabel")
    if dialogue_label:
        dialogue_label.visible = false
    if _name_picker_vbox:
        _name_picker_vbox.visible = true


func _on_name_picker_next() -> void:
    if _name_picker_index < UONITE_NAMES.size() - 1:
        _name_picker_index += 1
        _update_name_picker_display()


func _update_name_picker_display() -> void:
    if _name_picker_label:
        _name_picker_label.text = UONITE_NAMES[_name_picker_index]
    if _name_picker_next:
        _name_picker_next.disabled = (_name_picker_index >= UONITE_NAMES.size() - 1)
    if _name_picker_confirm:
        _name_picker_confirm.disabled = false


func _on_name_picker_confirm() -> void:
    if not game_context or _name_picker_index >= UONITE_NAMES.size():
        return
    game_context.uonite_name = UONITE_NAMES[_name_picker_index]
    if _name_picker_vbox:
        _name_picker_vbox.visible = false
    var dialogue_label = get_node_or_null(
        "TopBandHBox/RightStackVBox/DialoguePanelContainer/DialogueMargin/DialogueVBox/ArchonDialogueRichTextLabel")
    if dialogue_label:
        dialogue_label.visible = true
    if archon_dialogue_manager:
        archon_dialogue_manager.advance_dialogue()


func _on_age_selected(key: String) -> void:
    match key:
        "firmament":
            _transition_to_age("res://FirmamentUI.tscn")
        "world":
            _transition_to_age("res://WorldUI.tscn")
        "civilization":
            _transition_to_age("res://CivilizationUI.tscn")

func _on_game_loaded(offline_seconds: float) -> void:
    _sync_trigger_flags_from_loaded_state()
    _apply_unlock_visibility()
    # Bootstrap Archon puzzle (id 0) if not cached, version mismatch, or player seed changed.
    var cd_boot = get_node_or_null("/root/ConstellationData")
    if cd_boot:
        var cached_boot: Dictionary = cd_boot.get_puzzle_cache(0)
        var seed_matches: bool = cached_boot.get("player_seed_used", -1) == cd_boot.player_seed
        # FIXED 2026-07-27 — was hardcoded to 3, a stale literal that never
        # matched ConstellationLogicPuzzle.CACHE_VERSION (2). That meant this
        # check was ALWAYS false, silently discarding a perfectly valid
        # cache and fully regenerating constellation 0 on every single boot.
        # Harmless when generation was fast, but became visibly broken
        # (blank star map/tabs) once generation was deliberately spread
        # across more frames to fix input lag — players could open the
        # Study panel before the wasted regeneration finished. Referencing
        # the real constant instead of a literal so this can't drift again.
        var version_matches: bool = cached_boot.get("version", 0) == ConstellationLogicPuzzle.CACHE_VERSION
        if cached_boot.is_empty() or not seed_matches or not version_matches:
            cd_boot.clear_puzzle_cache(0)
            _start_puzzle_generation(0)
    _archon_minigame.restore_on_load()
    if offline_seconds < 30.0 or not production_manager:
        return
    var results: Dictionary = production_manager.apply_offline_progress(offline_seconds)
    if results.is_empty():
        return
    var minutes := int(results.get("time_simulated", 0)) / 60.0
    var lines   := ["Away for ~%d min. Offline gains:" % minutes]
    for key in ["sparks", "monad", "tetrad", "particle", "iota", "mote", "grain"]:
        if results.has(key):
            lines.append("  +%s %s" % [results[key], key.capitalize()])
    if archon_dialogue_manager:
        archon_dialogue_manager.notification_queue.append("\n".join(lines))
        archon_dialogue_manager.try_show_next_notification()


func _sync_trigger_flags_from_loaded_state() -> void:
    if not game_context or not archon_dialogue_manager:
        return


    # --- Monad type flags ---
    # Use watermarks: if a type was ever created, its watermark is non-zero.
    for type_key in _monad_type_triggered:
        var wm_key = "monad_" + type_key
        if not game_context.watermarks.get(wm_key, BigNum.zero()).is_zero():
            _monad_type_triggered[type_key] = true

    # --- Monad milestone flags ---
    # _monad_type_triggered entries are already set above — derive from them.
    _monad_upgrade_triggered = _monad_type_triggered.values().any(func(v): return v == true)
    _second_monad_triggered  = archon_dialogue_manager.second_monad_done
    _all_monads_triggered    = archon_dialogue_manager.all_monads_upgrade_done
    _tetrad_assembly_ready   = archon_dialogue_manager.all_monads_upgrade_done

    # --- Tetrad variety flags ---
    # Use totals_created: survives prestige, is non-zero once ever created.
    for variety_key in _tetrad_variety_triggered:
        if not game_context.totals_created.get(variety_key, BigNum.zero()).is_zero():
            _tetrad_variety_triggered[variety_key] = true

    # --- Tetrad milestone flags ---
    _tetrad_upgrade_triggered  = archon_dialogue_manager.tetrad_upgrade_done
    _first_fundament_triggered = archon_dialogue_manager.first_fundament_done
    _all_fundaments_triggered  = archon_dialogue_manager.all_fundaments_done

    # --- Chain resource flags ---
    # If uonite has ever been produced, every upstream chain resource
    # was also produced. Use this as a blanket guard for all five triggers
    # in addition to their own totals, to handle saves predating totals tracking.
    var uonite_ever_made: bool = not game_context.totals_created.get("uonite", BigNum.zero()).is_zero() \
                              or not game_context.uonite.is_zero()
    _first_particle_triggered = uonite_ever_made or not game_context.totals_created.get("particle", BigNum.zero()).is_zero()
    _first_iota_triggered     = uonite_ever_made or not game_context.totals_created.get("iota",     BigNum.zero()).is_zero()
    _first_mote_triggered     = uonite_ever_made or not game_context.totals_created.get("mote",     BigNum.zero()).is_zero()
    _first_grain_triggered    = uonite_ever_made or not game_context.totals_created.get("grain",    BigNum.zero()).is_zero()
    _first_uonite_triggered   = uonite_ever_made
    _nineteenth_grain_triggered = uonite_ever_made or (not game_context.grain.is_zero() and game_context.grain.is_greater_or_equal(BigNum.from_int(19)))
    _twentieth_grain_triggered  = uonite_ever_made or (not game_context.grain.is_zero() and game_context.grain.is_greater_or_equal(BigNum.from_int(20)))
    _end_first_prestige_triggered   = game_context.expansions >= 1 and \
        (archon_dialogue_manager.second_prestige_done if archon_dialogue_manager else false)
    _archon_volition_constellation_triggered = archon_dialogue_manager.archon_volition_constellation_done if archon_dialogue_manager else false
    _no_archon_volition_constellation_triggered = archon_dialogue_manager.no_archon_volition_constellation_done if archon_dialogue_manager else false
    _star_in_view_triggered         = archon_dialogue_manager.star_chase_done
    _tier1_archon_complete_triggered = archon_dialogue_manager.tier1_archon_complete_done
    _spark_movement_triggered   = archon_dialogue_manager.spark_movement_done
    _first_constellation_triggered = archon_dialogue_manager.first_constellation_done
    _constellation_panel_creation_triggered = archon_dialogue_manager.constellation_panel_creation_done
    _open_constellation_panel_triggered     = archon_dialogue_manager.open_constellation_panel_done
    _study_panel_reveal_triggered           = archon_dialogue_manager.study_panel_reveal_done
    if _study_panel_reveal_triggered:
        var _cp_reveal := find_child("ConstellationPanel", true, false)
        if _cp_reveal and _cp_reveal.has_method("reveal_study_button"):
            _cp_reveal.reveal_study_button()
    if _constellation_panel_creation_triggered and _constellation_popout:
        _constellation_popout.show_tab()
    if _open_constellation_panel_triggered and _constellation_popout:
        _constellation_popout._has_been_opened_once = true
    if (_archon_volition_constellation_triggered or _no_archon_volition_constellation_triggered) \
            and _constellation_popout:
        _constellation_popout.show_slot_grid()
    # _firmament_threshold_revealed had no re-derivation here previously —
    # confirmed gap during the refactor-order item #10 research: it reset
    # to false on every load, so a save with Uonite already produced would
    # never re-apply the Firmament age reveal/unlock after reloading.
    _firmament_threshold_revealed = not game_context.uonite.is_zero()
    if _firmament_threshold_revealed and _ages_popout:
        _ages_popout.reveal()
        _ages_popout.unlock_age("firmament")


func _transition_to_age(scene_path: String) -> void:
    if save_manager:
        save_manager.save_game()
    var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tween.tween_property(get_tree().current_scene, "modulate:a", 0.0, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(scene_path))


func _get_completing_category() -> String:
    var category_map = {
        "fundament": ["adaemant", "aquae", "aethyr"],
        "element":   ["earth", "water", "air"],
        "symmetric": ["mud", "dust", "cloud"],
        "medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
    }
    for cat in category_map:
        var all_done = true
        for v in category_map[cat]:
            if not _tetrad_variety_triggered.get(v, false):
                all_done = false
                break
        if all_done:
            return cat
    return ""


# ==================================================
# DATA-DRIVEN TRIGGER TABLE
# ==================================================
# The ~16 _check_*_trigger functions that fit a uniform "guard bool ->
# single condition -> effect" shape were collapsed into this table
# (refactor-order item #10 in docs/early_game_architecture_overview.md).
# Functions needing a loop (multiple fires per tick), extra parameters,
# or a per-frame accumulator stayed hand-written and are still called
# directly from _process(): _check_monad_upgrade_trigger,
# _check_totals_milestones, _check_star_in_view_trigger.
#
# Each entry: {"guard": <String field name>, "condition": Callable[]->bool,
# "effect": Callable[]->void}. _run_simple_triggers() checks each guard
# field via get()/set() dynamic property access (the field names are all
# real `var` members) and fires effect() the one time condition() first
# becomes true.
var _simple_triggers: Array[Dictionary] = []

func _build_simple_triggers() -> void:
    _simple_triggers = [
        {
            "guard": "_firmament_threshold_revealed",
            "condition": func(): return _ages_popout != null and not game_context.uonite.is_zero(),
            "effect": func():
                _ages_popout.reveal()
                _ages_popout.unlock_age("firmament"),
        },
        {
            "guard": "_all_fundaments_triggered",
            "condition": func(): return _tetrad_variety_triggered["adaemant"] and _tetrad_variety_triggered["aquae"] and _tetrad_variety_triggered["aethyr"],
            "effect": func(): archon_dialogue_manager.enqueue_all_fundaments(),
        },
        {
            "guard": "_first_non_fundament_category_triggered",
            "condition": func():
                if _all_fundaments_triggered:
                    return false
                var cat = _get_completing_category()
                return cat != "" and cat != "fundament",
            "effect": func(): archon_dialogue_manager.enqueue_first_non_fundament(_get_completing_category()),
        },
        {
            "guard": "_first_particle_triggered",
            "condition": func(): return not game_context.particle.is_zero(),
            "effect": func():
                _grant_foci()
                archon_dialogue_manager.notification_queue.append("First Particle: +1 Focus.")
                archon_dialogue_manager.enqueue_first_particle(),
        },
        {
            "guard": "_first_iota_triggered",
            "condition": func(): return not game_context.iota.is_zero(),
            "effect": func():
                _grant_foci()
                archon_dialogue_manager.notification_queue.append("First Iota: +1 Focus.")
                archon_dialogue_manager.try_show_next_notification(),
        },
        {
            "guard": "_first_mote_triggered",
            "condition": func(): return not game_context.mote.is_zero(),
            "effect": func():
                _grant_foci()
                archon_dialogue_manager.notification_queue.append("First Mote: +1 Focus.")
                archon_dialogue_manager.try_show_next_notification(),
        },
        {
            "guard": "_first_grain_triggered",
            "condition": func(): return not game_context.grain.is_zero(),
            "effect": func():
                _grant_foci()
                archon_dialogue_manager.notification_queue.append("First Grain: +1 Focus.")
                archon_dialogue_manager.enqueue_first_grain(),
        },
        {
            "guard": "_nineteenth_grain_triggered",
            "condition": func(): return game_context.grain.is_greater_or_equal(BigNum.from_int(19)) and game_context.uonite.is_zero(),
            "effect": func(): archon_dialogue_manager.enqueue_nineteenth_grain(),
        },
        {
            "guard": "_twentieth_grain_triggered",
            "condition": func(): return game_context.grain.is_greater_or_equal(BigNum.from_int(20)) and game_context.uonite.is_zero(),
            "effect": func(): archon_dialogue_manager.enqueue_twentieth_grain(),
        },
        {
            "guard": "_end_first_prestige_triggered",
            "condition": func(): return game_context.expansions >= 1 and game_context.grains_this_cycle >= 20,
            "effect": func(): archon_dialogue_manager.enqueue_end_first_prestige(),
        },
        {
            "guard": "_archon_volition_constellation_triggered",
            "condition": func(): return game_context.expansions >= 2 and game_context.sparks.is_greater_or_equal(BigNum.from_int(150)) and game_context.has_parent_volition_for_constellation(0),
            "effect": func(): archon_dialogue_manager.enqueue_archon_volition_constellation(),
        },
        {
            "guard": "_no_archon_volition_constellation_triggered",
            "condition": func(): return game_context.expansions >= 2 and game_context.sparks.is_greater_or_equal(BigNum.from_int(1500)) and not game_context.has_parent_volition_for_constellation(0),
            "effect": func(): archon_dialogue_manager.enqueue_no_archon_volition_constellation(),
        },
        {
            "guard": "_first_uonite_triggered",
            "condition": func(): return not game_context.uonite.is_zero(),
            "effect": func():
                game_context.refinements_completed += 1
                _grant_foci()
                archon_dialogue_manager.notification_queue.append("First Uonite: +1 Focus, +1 Refinement.")
                archon_dialogue_manager.try_show_next_notification()
                var cd := get_node_or_null("/root/ConstellationData")
                if cd and cd.has_method("on_achievement"):
                    cd.on_achievement("first_uonite"),
        },
        {
            "guard": "_spark_movement_triggered",
            "condition": func(): return game_context.expansions > 0 and game_context.sparks_since_first_prestige >= 1000.0,
            "effect": func(): archon_dialogue_manager.enqueue_spark_movement(),
        },
        {
            "guard": "_tier1_archon_complete_triggered",
            "condition": func():
                var cd := get_node_or_null("/root/ConstellationData")
                return cd != null and cd.get_spark_fraction(0) >= cd.THRESHOLD_STARS,
            "effect": func(): archon_dialogue_manager.enqueue_tier1_archon_complete(),
        },
        {
            "guard": "_first_constellation_triggered",
            "condition": func(): return archon_dialogue_manager.spark_movement_done and game_context.expansions > 0 and game_context.sparks.is_greater_or_equal(BigNum.from_int(3000)),
            "effect": func():
                _reveal_panel("constellation")
                var cd := get_node_or_null("/root/ConstellationData")
                if cd:
                    cd._unlock_constellation(0)
                    cd.set_active_constellation(0, 0)
                    game_context.constellation_spark_totals["0"] = 150.0
                archon_dialogue_manager.enqueue_first_constellation(),
        },
    ]


func _run_simple_triggers() -> void:
    if not game_context or not archon_dialogue_manager:
        return
    for entry in _simple_triggers:
        if get(entry["guard"]):
            continue
        if entry["condition"].call():
            set(entry["guard"], true)
            entry["effect"].call()


func _check_first_fundament_trigger(variety_key: String) -> void:
    if _first_fundament_triggered:
        return
    if variety_key in ["adaemant", "aquae", "aethyr"]:
        _first_fundament_triggered = true
        archon_dialogue_manager.enqueue_first_fundament(variety_key)


func _check_tetrad_upgrade_trigger() -> void:
    if not archon_dialogue_manager or not game_context:
        return
    for variety_key in _tetrad_variety_triggered:
        if _tetrad_variety_triggered[variety_key]:
            continue
        if not game_context.tetrad[variety_key].is_zero():
            _tetrad_variety_triggered[variety_key] = true
            game_context.record_first_creation(variety_key)
            
            _check_first_fundament_trigger(variety_key)
            if not _tetrad_upgrade_triggered:
                _tetrad_upgrade_triggered = true
                archon_dialogue_manager.enqueue_tetrad_upgrade(variety_key)
            else:
                archon_dialogue_manager.notify_tetrad_created(variety_key, _tetrad_variety_triggered)
            _grant_foci()

# _check_particle_trigger, _check_iota_trigger, _check_mote_trigger,
# _check_grain_trigger, _check_nineteenth_grain_trigger,
# _check_twentieth_grain_trigger, _check_end_first_prestige_trigger,
# _check_archon_volition_constellation_trigger,
# _check_no_archon_volition_constellation_trigger, and _check_uonite_trigger
# used to live here as hand-written functions — folded into
# _simple_triggers (see _build_simple_triggers(), refactor-order item #10)
# 2026-07-26. _check_end_first_prestige_trigger's commented-out debug
# print block was dropped as dead scaffolding, not carried into the table.


func _do_prestige_reset() -> void:
    var leftover_sparks: BigNum = game_context.sparks.copy()
    var cap_delta: BigNum       = game_context.do_prestige_reset()
    if production_manager:
        production_manager.reset_for_prestige()
    _tetrad_assembly_ready = false
    if archon_dialogue_manager and archon_dialogue_manager.all_monads_upgrade_done:
        _tetrad_assembly_ready = true

    # Foci award at Expansion milestones: 1st, 100th, 10000th, etc. (10^0, 10^2, 10^4...)
    var threshold: int = int(pow(10.0, float(game_context.next_expansion_foci_exp)))
    if game_context.expansions >= threshold:
        _grant_foci()
        game_context.next_expansion_foci_exp += 2
        if archon_dialogue_manager:
            var msg := "Expansion %d: +1 Focus. %s Sparks → Storage +%s" % [
                game_context.expansions,
                leftover_sparks.to_display_string(),
                cap_delta.to_display_string()
            ]
            archon_dialogue_manager.notification_queue.append(msg)
            archon_dialogue_manager.try_show_next_notification()
    else:
        if archon_dialogue_manager:
            var msg := "Expansion %d: %s Sparks → Storage +%s" % [
                game_context.expansions,
                leftover_sparks.to_display_string(),
                cap_delta.to_display_string()
            ]
            archon_dialogue_manager.notification_queue.append(msg)
            archon_dialogue_manager.try_show_next_notification()
    # Fire prestige achievements for constellation unlocks
    var cd = get_node_or_null("/root/ConstellationData")
    if cd and cd.has_method("on_achievement"):
        if game_context.expansions == 1:
            cd.on_achievement("first_prestige")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_first_prestige()
        elif game_context.expansions == 2:
            cd.on_achievement("second_prestige")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_start_second_prestige()
        elif game_context.expansions == 3:
            cd.on_achievement("third_prestige")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_third_prestige()
        elif game_context.expansions == 4:
            cd.on_achievement("fourth_prestige")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_fourth_prestige()
        elif game_context.expansions == 5:
            cd.on_achievement("fifth_prestige")
            if archon_dialogue_manager:
                archon_dialogue_manager.enqueue_fifth_prestige()
    # Re-grant volitions earned from lifetime foci after reset wipes them
    _check_volition_grant()
    _update_click_vol_label()


func _min_totals(keys: Array) -> BigNum:
    var result: BigNum = null
    for k in keys:
        var v: BigNum = game_context.totals_created.get(k, BigNum.zero())
        if result == null or v.is_less_than(result):
            result = v
    return result if result != null else BigNum.zero()


func _sum_totals(keys: Array) -> BigNum:
    var result := BigNum.zero()
    for k in keys:
        var v: BigNum = game_context.totals_created.get(k, BigNum.zero())
        result = result.add(v)
    return result


func _check_totals_milestones() -> void:
    if not game_context or not archon_dialogue_manager:
        return
    # --- Individual keys already in totals_created ---
    for key in game_context.totals_created.keys().filter(func(k): return k != "sparks_summoned"):
        var total: BigNum = game_context.totals_created[key]
        if total.is_zero():
            continue
        var next_exp: int = game_context.totals_milestones.get(key, 2)
        var threshold := BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        while total.is_greater_or_equal(threshold):
            archon_dialogue_manager.notification_queue.append(
                "%s — %s total created: +1 Focus." % [
                    _totals_display_name(key),
                    threshold.to_display_string()])
            _grant_foci()
            next_exp  += 2
            threshold  = BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        game_context.totals_milestones[key] = next_exp
    # --- All-three-monad milestone ---
    var monad_min := _min_totals(["monad_solid", "monad_liquid", "monad_gas"])
    if not monad_min.is_zero():
        var next_exp: int = game_context.totals_milestones.get("monad_all", 2)
        var threshold := BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        while monad_min.is_greater_or_equal(threshold):
            archon_dialogue_manager.notification_queue.append(
                "All Monads — %s of each type created: +1 Focus." % threshold.to_display_string())
            _grant_foci()
            next_exp  += 2
            threshold  = BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        game_context.totals_milestones["monad_all"] = next_exp
    # --- Tetrad category milestones ---
    const TETRAD_CATEGORIES := {
        "tetrad_fundament": ["adaemant", "aquae", "aethyr"],
        "tetrad_element":   ["earth", "water", "air"],
        "tetrad_symmetric": ["mud", "dust", "cloud"],
        "tetrad_medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
        "tetrad_all":       ["adaemant", "aquae", "aethyr",
                             "earth", "water", "air",
                             "mud", "dust", "cloud",
                             "dirt", "sand", "haze", "mist", "ooze", "foam"],
    }
    for cat_key in TETRAD_CATEGORIES:
        var cat_min := _min_totals(TETRAD_CATEGORIES[cat_key])
        if cat_min.is_zero():
            continue
        var next_exp: int = game_context.totals_milestones.get(cat_key, 2)
        var threshold := BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        while cat_min.is_greater_or_equal(threshold):
            archon_dialogue_manager.notification_queue.append(
                "%s — %s of each variety created: +1 Focus." % [
                    _totals_display_name(cat_key),
                    threshold.to_display_string()])
            _grant_foci()
            next_exp  += 2
            threshold  = BigNum.from_me(pow(10.0, float(next_exp % 3)), int(next_exp / 3.0))
        game_context.totals_milestones[cat_key] = next_exp
    archon_dialogue_manager.try_show_next_notification()


# _check_spark_movement_trigger and _check_tier1_archon_complete_trigger
# used to live here — folded into _simple_triggers, see
# _build_simple_triggers() (refactor-order item #10, 2026-07-26).


func _check_star_in_view_trigger(delta: float) -> void:
    if _star_in_view_triggered or not game_context or not archon_dialogue_manager:
        return
    if not archon_dialogue_manager.first_constellation_done:
        return
    if not game_context.hint_bias_enabled:
        return
    var sf := get_node_or_null("StarfieldBackground")
    var cd := get_node_or_null("/root/ConstellationData")
    if not sf or not cd:
        return
    var positions: Array = cd.get_star_positions(0)
    if positions.is_empty():
        return
    var eff_mat: Basis = sf.get_effective_view_matrix()
    var vp_size: Vector2 = get_viewport_rect().size
    var aspect: float = vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.0
    # Check if any constellation 0 star is within the viewport
    var any_visible := false
    for world_dir in positions:
        var local_ray: Vector3 = eff_mat.inverse() * (world_dir as Vector3)
        if local_ray.z <= 0.001:
            continue
        var inv_2tan: float = 1.0 / (2.0 * tan(deg_to_rad(75.0 * 0.5)))
        var sx: float = local_ray.x / local_ray.z * inv_2tan + 0.5
        var sy: float = local_ray.y / local_ray.z * aspect * inv_2tan + 0.5
        if sx >= 0.0 and sx <= 1.0 and sy >= 0.0 and sy <= 1.0:
            any_visible = true
            break
    if any_visible:
        _star_in_view_time += delta
        if _star_in_view_time >= 15.0:
            _star_in_view_triggered = true
            archon_dialogue_manager.enqueue_star_chase()


# _check_constellation_trigger used to live here — folded into
# _simple_triggers, see _build_simple_triggers() (refactor-order item #10,
# 2026-07-26).


# ==================================================
# DEV INPUT
# ==================================================
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        # if event.keycode == KEY_TAB:
          #  if game_context:
           #     var chunk = BigNum.from_me(DEV_UONITE_CHUNK[0], DEV_UONITE_CHUNK[1])
            #    game_context.uonite = game_context.uonite.add(chunk)
       # if event.keycode == KEY_F:
           # if game_context:
             #  _grant_foci(10)
        if event.keycode == KEY_TAB:
            if game_context:
                game_context.volitions += 100
                game_context._ensure_slot_count(game_context.volitions)
                _update_click_vol_label()
            get_viewport().set_input_as_handled()
        if event.keycode == KEY_D:
            print("=== CONSTELLATION TRIGGER DEBUG ===")
            print("_first_constellation_triggered: ", _first_constellation_triggered)
            print("expansions: ", game_context.expansions if game_context else "NO GC")
            print("sparks: ", game_context.sparks.to_string() if game_context else "NO GC")
            print("sparks >= 100: ", game_context.sparks.is_greater_or_equal(BigNum.from_int(100)) if game_context else "NO GC")
            print("ui_unlocks constellation: ", game_context.ui_unlocks.get("constellation", false) if game_context else "NO GC")
            print("archon_dialogue_manager: ", archon_dialogue_manager != null)
            print("first_constellation_done: ", archon_dialogue_manager.first_constellation_done if archon_dialogue_manager else "NO ADM")
        if event.keycode == KEY_V:
            if game_context:
                for _dv in 100:
                    var idx = game_context.get_first_free_parent_index()
                    if idx < 0: break
                    game_context.assign_parent_volition(idx, "volumitions", "")
                _update_click_vol_label()
        if event.keycode == KEY_S:
            _on_summon_spark_pressed()
        if event.keycode == KEY_R:
            _reveal_panel("direct_readouts")
        if event.keycode == KEY_C:
            _reveal_panel("constellation")
            if _constellation_popout:
                _constellation_popout.reveal()
        if event.keycode == KEY_H:
            if game_context:
                var cd = get_node_or_null("/root/ConstellationData")
                if cd:
                    var is_unlocked: bool = cd.unlocked.has(0)
                    if is_unlocked:
                        cd.unlocked.erase(0)
                        cd.active_per_octant[0] = -1
                        game_context.constellation_spark_totals["0"] = 0.0
                        game_context.assignments.erase("constellation_0_solve_count")
                    else:
                        cd._unlock_constellation(0)
                        cd.set_active_constellation(0, 0)
                        game_context.constellation_spark_totals["0"] = cd.get_spark_cap(0) * 0.15
                    cd.active_constellation_changed.emit(0, cd.active_per_octant[0])
        if event.keycode == KEY_U:
            var study_overlay := get_node_or_null("/root/Node2D/CanvasLayer/ConstellationStudyOverlay")
            var target_id: int = 0
            if study_overlay and study_overlay.has_method("get_current_constellation_id"):
                var open_id: int = study_overlay.get_current_constellation_id()
                if open_id >= 0:
                    target_id = open_id
            _dev_recompute_puzzle(target_id)
            get_viewport().set_input_as_handled()
        if event.keycode == KEY_G and production_manager:
            production_manager.dev_inject_ten_grains()
            get_viewport().set_input_as_handled()
        if event.keycode == KEY_T and production_manager:
            var seconds: float = 300.0 if event.shift_pressed else 60.0
            var diff: Dictionary = production_manager.apply_offline_progress(seconds)
            print("=== TIME ADVANCE: %d seconds ===" % int(seconds))
            for key in diff:
                print("  %s: %s" % [key, str(diff[key])])


        # ── EXPRESSION TEST KEYS ──────────────────────────────────────────
        # Edit values in archon_tetrahedron.gd → placeh_express()
        # Keys currently used elsewhere: TAB V R C H ENTER
        # Available: X Z 1 2 3 4 etc.
        if event.keycode == KEY_E:
            if _archon_tetra:
                _archon_tetra.placeh_express()
        if event.keycode == KEY_X:
            if _archon_tetra:
                _archon_tetra.play_expression("next_expression_name", 2.0)
        # ─────────────────────────────────────────────────────────────────


# ==================================================
# TETRAD LABEL SIGNALS
# ==================================================
func _connect_tetrad_signals() -> void:
    _left_tetrad_label = find_child("LeftTetradLabel",         true, false)
    _middle_label      = find_child("Medials1SymmetricsLabel", true, false)
    _medials2_label    = find_child("Medials2Label",           true, false)

    for label in [_left_tetrad_label, _middle_label, _medials2_label]:
        if label and label is RichTextLabel:
            label.mouse_filter = Control.MOUSE_FILTER_STOP
            var line_map = LEFT_LINE_MAP if label == _left_tetrad_label else \
                           MIDDLE_LINE_MAP if label == _middle_label else \
                           MEDIALS2_LINE_MAP
            if not label.gui_input.is_connected(_on_tetrad_label_gui_input):
                label.gui_input.connect(func(event): _on_tetrad_label_gui_input(event, label, line_map))


func _on_tetrad_label_gui_input(event: InputEvent, label: RichTextLabel, line_map: Array) -> void:
    var y: float = event.position.y
    var cumulative: float = 0.0
    var line: int = line_map.size() - 1
    for i in line_map.size():
        var h: float = label.get_line_height(i)
        if h <= 0: continue
        if y < cumulative + h:
            line = i
            break
        cumulative += h
    var key = line_map[line]

    if event is InputEventMouseMotion:
        if _settings_popout and not _settings_popout.tooltips_enabled:
            label.tooltip_text = ""
        else:
            label.tooltip_text = _get_tetrad_tooltip(key)
        return

    if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
    if not game_context or not game_context.purity_locks_unlocked: return
    if key == "": return
    if key.begins_with("cat_"):
        game_context.toggle_category_lock(key)
    else:
        game_context.toggle_lock(key)


# ==================================================
# BUTTON CONNECTIONS
# ==================================================
func _connect_action_buttons() -> void:
    _try_connect_button("SummonSparkButton",      "pressed", _on_summon_spark_pressed)
    _try_connect_button("MonadCompressButton",    "pressed", _on_monad_compress_pressed)
    _try_connect_button("IotaAssembleButton",     "pressed", _on_iota_assemble_pressed)
    _try_connect_button("ParticleCompressButton", "pressed", _on_particle_compress_pressed)
    _try_connect_button("CreateUoniteButton",     "pressed", _on_create_uonite_pressed)
    _try_connect_button("TetradAssembleButton",   "pressed", _on_tetrad_assemble_pressed)
    _try_connect_button("MoteCompressButton",     "pressed", _on_mote_compress_pressed)
    _try_connect_button("GrainAssembleButton",    "pressed", _on_grain_assemble_pressed)
    _try_connect_button("ClickVolMinusButton",    "pressed", _on_click_vol_minus_pressed)
    _try_connect_button("ClickVolPlusButton",     "pressed", _on_click_vol_plus_pressed)
    _click_vol_label = find_child("ClickVolLabel", true, false)
    _click_vol_plus_btn  = find_child("ClickVolPlusButton",  true, false)
    _click_vol_minus_btn = find_child("ClickVolMinusButton", true, false)
    _vol_btn_style_on = StyleBoxFlat.new()
    _vol_btn_style_on.bg_color     = Color(0.12, 0.10, 0.20, 0.55)
    _vol_btn_style_on.border_color = Color(1.00, 0.85, 0.20, 0.80)
    _vol_btn_style_on.set_border_width_all(1)

    _vol_btn_style_hover = StyleBoxFlat.new()
    _vol_btn_style_hover.bg_color     = Color(1.00, 1.00, 1.00, 0.18)
    _vol_btn_style_hover.border_color = Color(1.00, 0.85, 0.20, 0.80)
    _vol_btn_style_hover.set_border_width_all(1)

    _vol_btn_style_off = StyleBoxFlat.new()
    _vol_btn_style_off.bg_color     = Color(0.12, 0.10, 0.20, 0.55)
    _vol_btn_style_off.border_color = Color(0.40, 0.40, 0.40, 0.25)
    _vol_btn_style_off.set_border_width_all(1)


func _try_connect_button(button_name: String, signal_name: String, callable: Callable) -> void:
    var button = find_child(button_name, true, false)
    if button:
        if button.has_signal(signal_name) and not button.is_connected(signal_name, callable):
            button.connect(signal_name, callable)
    else:
        push_warning("RootUI: Button not found: " + button_name)



# ==================================================
# COOLDOWN BAR HELPER
# ==================================================
func _get_cooldown_bar(bar_name: String) -> Node:
    return find_child(bar_name, true, false)


# ==================================================
# CLICK VOLITIONS HELPERS
# ==================================================

func _refresh_click_vol_buttons() -> void:
    if not game_context: return
    var assigned: int  = game_context.assignments.get("click_volitions", 0)
    var can_add:  bool = game_context.get_volitions_free() > 0
    var can_sub:  bool = assigned > 0
    const GOLD_ON  := Color(1.00, 0.85, 0.20, 0.90)
    const GOLD_HOV := Color(1.00, 0.95, 0.55, 1.00)
    const GOLD_OFF := Color(0.35, 0.35, 0.40, 0.40)
    if _click_vol_plus_btn:
        _click_vol_plus_btn.add_theme_stylebox_override("normal", _vol_btn_style_on  if can_add else _vol_btn_style_off)
        _click_vol_plus_btn.add_theme_stylebox_override("hover",  _vol_btn_style_hover if can_add else _vol_btn_style_off)
        _click_vol_plus_btn.add_theme_color_override("font_color",       GOLD_ON  if can_add else GOLD_OFF)
        _click_vol_plus_btn.add_theme_color_override("font_hover_color", GOLD_HOV if can_add else GOLD_OFF)
    if _click_vol_minus_btn:
        _click_vol_minus_btn.add_theme_stylebox_override("normal", _vol_btn_style_on   if can_sub else _vol_btn_style_off)
        _click_vol_minus_btn.add_theme_stylebox_override("hover",  _vol_btn_style_hover if can_sub else _vol_btn_style_off)
        _click_vol_minus_btn.add_theme_color_override("font_color",       GOLD_ON  if can_sub else GOLD_OFF)
        _click_vol_minus_btn.add_theme_color_override("font_hover_color", GOLD_HOV if can_sub else GOLD_OFF)


func _get_click_multiplier() -> int:
    if not game_context: return 1
    var base: int = 1 + game_context.assignments.get("click_volitions", 0) \
                      + game_context.assignments.get("click_bonus_volitions", 0)
    var cd: Node = get_node_or_null("/root/ConstellationData")
    if not cd:
        return base
    var tier_mult: float = cd.get_active_level_bonus("click_volition_multiplier")
    if tier_mult <= 1.0:
        return base
    return int(float(base) * tier_mult)


func _update_click_vol_label() -> void:
    if not _click_vol_label or not game_context: return
    _click_vol_label.text = "x%d" % _get_click_multiplier()
    var parent_count: int = game_context.assignments.get("click_volitions", 0)
    if parent_count > 0:
        _click_vol_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    else:
        _click_vol_label.remove_theme_color_override("font_color")
    _refresh_click_vol_buttons()

func _on_click_vol_minus_pressed() -> void:
    if not game_context: return
    var idx = game_context.get_first_parent_index_with_target("volumitions", "")
    if idx < 0: return
    game_context.unassign_parent_volition(idx)
    _update_click_vol_label()


func _on_click_vol_plus_pressed() -> void:
    if not game_context: return
    var idx = game_context.get_first_free_parent_index()
    if idx < 0: return
    game_context.assign_parent_volition(idx, "volumitions", "")
    _update_click_vol_label()


# === TOOLTIP RESOURCE FORMULA HELPER ===
func _fmt_recipe(op_key: String) -> String:
    if not game_data:
        return ""
    var recipe: Dictionary = game_data.RECIPES.get(op_key, {})
    if recipe.is_empty():
        return ""
    var inputs: Dictionary  = recipe.get("inputs",  {})
    var outputs: Dictionary = recipe.get("outputs", {})
    var in_parts: Array = []
    for res in inputs:
        in_parts.append("%d %s" % [inputs[res], game_data.get_resource_name(res)])
    var out_parts: Array = []
    for res in outputs:
        out_parts.append("%d %s" % [outputs[res], game_data.get_resource_name(res)])
    return "%s → %s" % [" + ".join(in_parts), " + ".join(out_parts)]



# ==================================================
# BUTTON HANDLERS
# ==================================================
func _on_summon_spark_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("SparksCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    for i in _get_click_multiplier():
        production_manager.manual_summon_spark(1)
    _spawn_spark_effect()
    if bar: bar.notify_clicked()
    if game_context and game_context.hint_bias_enabled \
       and not _constellation_panel_creation_triggered \
       and archon_dialogue_manager:
        _post_constellation_spark_count += 1
        if _post_constellation_spark_count >= 10:
            _constellation_panel_creation_triggered = true
            archon_dialogue_manager.enqueue_constellation_panel_creation()


func _on_monad_compress_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("MonadCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        if production_manager.manual_monad_compress():
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
        _check_monad_upgrade_trigger()
    else:
        if bar: bar.flash_not_ready()


func _on_tetrad_assemble_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not _tetrad_assembly_ready: return
    if not production_manager: return
    var bar = _get_cooldown_bar("TetradCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        var result = production_manager.manual_tetrad_assemble()
        
        #print("manual_tetrad_assemble result: ", result,
              #" monads_s: ", game_context.monad["solid"].to_int(),
              #" monads_l: ", game_context.monad["liquid"].to_int(),
              #" monads_g: ", game_context.monad["gas"].to_int(),
              #" sparks: ", game_context.sparks.to_int(),
              #" storage: ", game_context.get_storage_total().to_int(),
              #"/", game_context.get_effective_storage_cap().to_int(),
              #" locked_s: ", game_context.is_locked("monad_solid"),
              #" locked_l: ", game_context.is_locked("monad_liquid"),
              #" locked_g: ", game_context.is_locked("monad_gas"))
        
        
        
        if result:
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
        _check_tetrad_upgrade_trigger()
    else:
        if bar: bar.flash_not_ready()


func _on_iota_assemble_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("IotaCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        if production_manager.manual_iota_assemble():
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
    else:
        if bar: bar.flash_not_ready()


func _on_mote_compress_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("MoteCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        if production_manager.manual_mote_compress():
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
    else:
        if bar: bar.flash_not_ready()


func _on_particle_compress_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("ParticleCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        if production_manager.manual_particle_compress():
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
    else:
        if bar: bar.flash_not_ready()


func _on_grain_assemble_pressed() -> void:
    if _is_tutorial_blocking(): return
    if not production_manager: return
    var bar = _get_cooldown_bar("GrainCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success := false
    for i in _get_click_multiplier():
        if production_manager.manual_grain_assemble():
            any_success = true
    if any_success:
        if bar: bar.notify_clicked()
    else:
        if bar: bar.flash_not_ready()


func _on_create_uonite_pressed() -> void:
    if _is_tutorial_blocking(): return
    if _expansion_anim_active: return
    if not production_manager: return
    var bar = _get_cooldown_bar("UoniteCooldownBar")
    if bar and not bar.is_ready():
        bar.flash_not_ready()
        return
    var any_success: bool = production_manager.manual_create_uonite()
    if any_success:
        if bar: bar.notify_clicked()
        _play_expansion_animation()
    else:
        if bar: bar.flash_not_ready()
        

func _get_or_create_expansion_overlay() -> ColorRect:
    if _expansion_overlay and is_instance_valid(_expansion_overlay):
        return _expansion_overlay

    var shader := Shader.new()
    shader.code = _EXPANSION_SHADER_SRC
    _expansion_shader_mat = ShaderMaterial.new()
    _expansion_shader_mat.shader = shader

    _expansion_overlay = ColorRect.new()
    _expansion_overlay.color        = Color(1.0, 1.0, 1.0, 1.0)
    _expansion_overlay.material     = _expansion_shader_mat
    _expansion_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _expansion_overlay.z_index      = 4096
    _expansion_overlay.visible      = false
    _expansion_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    get_parent().add_child(_expansion_overlay)
    return _expansion_overlay


func _play_expansion_animation() -> void:
    _expansion_anim_active = true
    var overlay := _get_or_create_expansion_overlay()

    # Reset state in case the animation was interrupted mid-run.
    _expansion_shader_mat.set_shader_parameter("distortion_strength", 0.0)
    _expansion_shader_mat.set_shader_parameter("white_amount",        0.0)
    scale        = Vector2.ONE
    pivot_offset = Vector2.ZERO
    pivot_offset = get_local_mouse_position()
    overlay.visible = true

    var tween := create_tween()

    # ── Phase 1: universe compresses — edges warp inward, white blooms ──
    # EASE_IN makes it start gentle and accelerate, matching the feeling
    # of falling toward a point of light.
    tween.set_parallel(true)
    tween.tween_method(
        func(v: float): _expansion_shader_mat.set_shader_parameter("distortion_strength", v),
        0.0, 1.5, 1.8
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tween.tween_method(
        func(v: float): _expansion_shader_mat.set_shader_parameter("white_amount", v),
        0.0, 1.0, 1.8
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    # Very gentle scale from cursor keeps the depth feeling without pushing
    # content off-screen — the warp effect does the heavy lifting now.
    tween.tween_property(self, "scale", Vector2(1.06, 1.06), 1.8) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

    # ── Peak white: invisible moment — fire the actual prestige reset ────
    tween.set_parallel(false)
    tween.tween_callback(func(): _do_prestige_reset())
    tween.tween_interval(1.5)

    # ── Phase 2: expansion — white recedes, edges warp back out ──────────
    # EASE_OUT makes it decelerate into stillness, like breath returning.
    tween.set_parallel(true)
    tween.tween_method(
        func(v: float): _expansion_shader_mat.set_shader_parameter("distortion_strength", v),
        1.5, 0.0, 1.8
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_method(
        func(v: float): _expansion_shader_mat.set_shader_parameter("white_amount", v),
        1.0, 0.0, 1.8
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "scale", Vector2.ONE, 1.8) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

    # ── Cleanup ──────────────────────────────────────────────────────────
    tween.set_parallel(false)
    tween.tween_callback(func():
        overlay.visible        = false
        scale                  = Vector2.ONE
        pivot_offset           = Vector2.ZERO
        _expansion_anim_active = false
    )


# ==================================================
# UI CONCEALMENT CLICKTHROUGH HELPERS
# ==================================================

func _hide_subtree(node: Node) -> void:
    if node is Control:
        _saved_mouse_filters[node.get_instance_id()] = node.mouse_filter
        node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for child in node.get_children():
        _hide_subtree(child)


func _show_subtree(node: Node) -> void:
    if node is Control:
        var id := node.get_instance_id()
        if _saved_mouse_filters.has(id):
            node.mouse_filter = _saved_mouse_filters[id]
    for child in node.get_children():
        _show_subtree(child)



# ==================================================
# SPARK EFFECT
# ==================================================
func _spawn_spark_effect() -> void:
    var btn = get_node_or_null("TopBandHBox/LeftStackVBox/ClickSelectPanelContainer/ClickSelectMargin/ClickSelectVBox/SummonSparkButton")
    if not btn: return
    var canvas_layer = get_parent()
    if not canvas_layer: return
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var global_pos: Vector2 = btn.get_global_position()
    var btn_size:   Vector2 = btn.get_size()
    var origin := Vector2(
        rng.randf_range(global_pos.x, global_pos.x + btn_size.x),
        rng.randf_range(global_pos.y, global_pos.y + btn_size.y))

    # Constellation puzzle hint: bias spark toward the screen-space position
    # of the lowest-funded unsolved puzzle constellation.
    var hint_dir := Vector2.ZERO
    if game_context and game_context.hint_bias_enabled:
        var cd := get_node_or_null("/root/ConstellationData")
        var starfield := get_node_or_null("../ColorRect")
        if cd and cd.has_method("get_puzzle_hint_direction") and starfield and starfield.has_method("get_effective_view_matrix"):
            var dir3: Vector3 = cd.get_puzzle_hint_direction()
            if dir3 != Vector3.ZERO:
                var eff_mat: Basis   = starfield.get_effective_view_matrix()
                var vp_size: Vector2 = get_viewport_rect().size
                var aspect:  float   = vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.0
                var local_ray: Vector3 = eff_mat.inverse() * dir3
                if local_ray.z > 0.001:
                    # Constellation is in front — project to screen position and
                    # aim toward it directly, even if it's outside the FOV edges.
                    var inv_2tan: float = 1.0 / (2.0 * tan(deg_to_rad(75.0 * 0.5)))
                    var screen_x: float = local_ray.x / local_ray.z * inv_2tan + 0.5
                    var screen_y: float = local_ray.y / local_ray.z * aspect * inv_2tan + 0.5
                    var target_px: Vector2 = Vector2(screen_x, screen_y) * vp_size
                    hint_dir = (target_px - origin).normalized()
                else:
                    # Constellation is behind the viewer — perspective projection
                    # breaks down here (divide by negative z inverts everything).
                    # Use the lateral components directly: local_ray.x tells us
                    # which way to turn horizontally, local_ray.y vertically.
                    # Screen y is inverted relative to world y, hence the negation.
                    var lateral := Vector2(local_ray.x, -local_ray.y)
                    if lateral.length_squared() > 0.0001:
                        hint_dir = lateral.normalized()
                    # If directly behind (lateral ≈ zero), no useful direction
                    # exists, so hint_dir stays Vector2.ZERO and sparks drift freely.

    var effect = SPARK_EFFECT.instantiate()
    canvas_layer.add_child(effect)
    effect.launch(origin, hint_dir)


# ==================================================
# RESOURCE ROWS
# ==================================================
func _on_row_clicked(resource_key: String) -> void:
    if not game_context: return
    game_context.toggle_lock(resource_key)


func _setup_resource_rows() -> void:
    var rows = get_tree().get_nodes_in_group("resource_rows")
    for row in rows:
        match row.name:
            "RowSparksLabelInstance":    row.set_resource_key("sparks_label")
            "RowUonitesLabelInstance":   row.set_resource_key("uonites_label")
            "RowFociLabelInstance":      row.set_resource_key("foci_label")
            "RowVolitionsLabelInstance": row.set_resource_key("volitions_label")
            "RowSparksValueInstance":    row.set_resource_key("sparks_value")
            "RowUonitesValueInstance":   row.set_resource_key("uonites_value")
            "RowFociValueInstance":      row.set_resource_key("foci_value")
            "RowVolitionsValueInstance": row.set_resource_key("volitions_value")
            "RowSolidMonadInstance":     row.set_resource_key("monad_solid")
            "RowLiquidMonadInstance":    row.set_resource_key("monad_liquid")
            "RowGasMonadInstance":       row.set_resource_key("monad_gas")
            "RowIotaInstance":           row.set_resource_key("iota")
            "RowParticleInstance":       row.set_resource_key("particle")
            "RowMoteInstance":           row.set_resource_key("mote")
            "RowGrainInstance":          row.set_resource_key("grain")
            "RowUonitesInstance":        row.set_resource_key("uonites_wheel")
            "RowFociInstance":           row.set_resource_key("foci_wheel")
            "RowVolitionsInstance":      row.set_resource_key("volitions_wheel")
            _:
                row.set_label(row.name)
                row.set_resource_key(row.name)

    var lockable = ["monad_solid", "monad_liquid", "monad_gas", "iota", "mote", "particle", "grain"]
    for row in get_tree().get_nodes_in_group("resource_rows"):
        if row.resource_key in lockable and not row.row_clicked.is_connected(_on_row_clicked):
            row.row_clicked.connect(_on_row_clicked)

func _cache_tooltip_buttons() -> void:
    for btn_name in ["MonadCompressButton", "TetradAssembleButton",
                     "ParticleCompressButton", "IotaAssembleButton",
                     "MoteCompressButton", "GrainAssembleButton", "CreateUoniteButton"]:
        var node = find_child(btn_name, true, false)
        if node:
            _tooltip_buttons[btn_name] = node
        else:
            push_warning("RootUI: tooltip button not found: " + btn_name)


func _update_button_tooltips() -> void:
    if _settings_popout and not _settings_popout.tooltips_enabled:
        for btn_name in _tooltip_buttons:
            var node: Control = _tooltip_buttons.get(btn_name)
            if node:
                node.tooltip_text = ""
        return
    var op_map: Dictionary = {
        "TetradAssembleButton":   "tetrad_assemble",
        "ParticleCompressButton": "particle_compress",
        "IotaAssembleButton":     "iota_assemble",
        "MoteCompressButton":     "mote_compress",
        "GrainAssembleButton":    "grain_assemble",
        "CreateUoniteButton":     "uonite_assemble",
    }
    var tc: Dictionary = game_context.totals_created
    var total_map: Dictionary = {
        "TetradAssembleButton":   _sum_totals(game_context.tetrad.keys()),
        "ParticleCompressButton": tc.get("particle", BigNum.zero()),
        "IotaAssembleButton":     tc.get("iota",     BigNum.zero()),
        "MoteCompressButton":     tc.get("mote",     BigNum.zero()),
        "GrainAssembleButton":    tc.get("grain",    BigNum.zero()),
        "CreateUoniteButton":     tc.get("uonite",   BigNum.zero()),
    }
    for btn_name in total_map:
        var node: Control = _tooltip_buttons.get(btn_name)
        if node:
            node.tooltip_text = "%s\nTotal created: %s" % [
                _fmt_recipe(op_map[btn_name]),
                _fmt(total_map[btn_name]),
            ]
    var monad_btn: Control = _tooltip_buttons.get("MonadCompressButton")
    if monad_btn:
        monad_btn.tooltip_text = "%s\nSolid:  %s\nLiquid: %s\nGas:    %s" % [
            _fmt_recipe("monad_compress"),
            _fmt(tc.get("monad_solid",  BigNum.zero())),
            _fmt(tc.get("monad_liquid", BigNum.zero())),
            _fmt(tc.get("monad_gas",    BigNum.zero())),
        ]
            
# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    if not game_context: return
    _time += delta
    game_context.update_watermarks()
    _update_counters()
    _update_tetrad_display()
    _update_bars(delta)
    _check_monad_upgrade_trigger()
    _run_simple_triggers()
    _check_totals_milestones()
    _check_star_in_view_trigger(delta)
    _tooltip_accum += delta
    if _tooltip_accum >= 1.0:
        _tooltip_accum = 0.0
        _update_button_tooltips()
    _autosave_accum += delta
    if _autosave_accum >= 60.0:
        _autosave_accum = 0.0
        if save_manager:
            save_manager.save_game()

# _check_firmament_threshold used to live here — folded into
# _simple_triggers, see _build_simple_triggers() (refactor-order item #10,
# 2026-07-26). The dead commented-out enqueue_dialogue(...) call it had
# was dropped, not carried into the table.


# ==================================================
# COUNTERS
# ==================================================

func _ever_created(key: String) -> bool:
    if not game_context:
        return false
    return not game_context.totals_created.get(key, BigNum.zero()).is_zero()


func _update_counters() -> void:
    var rows = get_tree().get_nodes_in_group("resource_rows")
    for row in rows:
        match row.resource_key:
            "sparks_label":    row.set_label("[b]Sparks[/b]")
            "uonites_label":   row.set_label("[b]Uonites[/b]")
            "foci_label":      row.set_label("[b]Foci[/b]")
            "volitions_label": row.set_label("[b]Volitions[/b]")
            "sparks_value": (func():
                row.set_label(_fmt(game_context.sparks))
                var summoned: BigNum = game_context.totals_created.get("sparks_summoned", BigNum.zero())
                if not summoned.is_zero():
                    row.set_tooltip("Total summoned: " + summoned.to_display_string())
                else:
                    row.set_tooltip("")
            ).call()
            "uonites_value":
                var u_assigned  = game_context.get_total_uonites_assigned()
                var u_available = game_context.uonite.sub(u_assigned)
                row.set_label(_fmt(u_available) + "/" + _fmt(game_context.uonite))
            "foci_value":
                var f_assigned  = game_context.get_total_foci_assigned()
                var f_available = max(0, game_context.archon_foci - f_assigned)
                row.set_label(str(f_available) + "/" + str(game_context.archon_foci))
            "volitions_value":
                var bvps: int = game_context.get_bonus_volitions_per_slot()
                if bvps <= 0 or game_context.volition_slots.is_empty():
                    var v_assigned  = game_context.get_total_volitions_assigned()
                    var v_available = max(0, game_context.volitions - v_assigned)
                    row.set_label(str(v_available) + "/" + str(game_context.volitions))
                else:
                    var parts: Array[String] = []
                    var slot_count: int = game_context.volition_slots.size()
                    var display_cap: int = mini(slot_count, 2)
                    for si in display_cap:
                        var slot = game_context.volition_slots[si]
                        var p_free: int = 1 if slot["category"] == "" else 0
                        var c_free: int = game_context.get_free_children_in_slot(si)
                        var pair: String = str(p_free) + "/" + str(c_free)
                        if slot["category"] != "":
                            pair = "[color=#FFD730]" + pair + "[/color]"
                        parts.append(pair)
                    if slot_count > display_cap:
                        parts.append("+%d" % (slot_count - display_cap))
                    row.set_label(" | ".join(parts))
            "sparks":
                var locked = game_context.is_locked("sparks")
                row.set_label("[color=%s]Sparks: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.sparks),
                    " 🔒" if locked else ""])
            "monad_solid":
                var locked   = game_context.is_locked("monad_solid")
                var created  = _ever_created("monad_solid")
                row.set_label("[color=%s]Solid: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.monad["solid"]),
                    " 🔒" if locked else ""])
            "monad_liquid":
                var locked   = game_context.is_locked("monad_liquid")
                var created  = _ever_created("monad_liquid")
                row.set_label("[color=%s]Liquid: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.monad["liquid"]),
                    " 🔒" if locked else ""])
            "monad_gas":
                var locked   = game_context.is_locked("monad_gas")
                var created  = _ever_created("monad_gas")
                row.set_label("[color=%s]Gas: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.monad["gas"]),
                    " 🔒" if locked else ""])
            "particle":
                var locked   = game_context.is_locked("particle")
                var created  = _ever_created("particle")
                row.set_label("[color=%s]Particle: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.particle),
                    " 🔒" if locked else ""])
            "iota":
                var locked   = game_context.is_locked("iota")
                var created  = _ever_created("iota")
                row.set_label("[color=%s]Iota: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.iota),
                    " 🔒" if locked else ""])
            "mote":
                var locked   = game_context.is_locked("mote")
                var created  = _ever_created("mote")
                row.set_label("[color=%s]Mote: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.mote),
                    " 🔒" if locked else ""])
            "grain":
                var locked   = game_context.is_locked("grain")
                var created  = _ever_created("grain")
                row.set_label("[color=%s]Grain: %s%s[/color]" % [
                    "#ffdd77" if locked else ("#ffffff" if created else "#444444"),
                    _fmt(game_context.grain),
                    " 🔒" if locked else ""])
        if _uonite_icosa and game_context.ui_unlocks.get("uonite_creation", false):
            var grain_target: int = game_context.motes_this_cycle
            if grain_target < _icosa_grain_display:
                _icosa_grain_display = grain_target
            elif grain_target > _icosa_grain_display:
                _icosa_grain_display += 1
            _uonite_icosa.current_grains = _icosa_grain_display


# ==================================================
# FORMATTING
# ==================================================
func _fmt(value) -> String:
    if value == null:
        return "0"
    if value is BigNum:
        return _format_scientific_one_decimal(value)
    if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
        if abs(float(value)) >= 1e6 or abs(float(value)) <= 1e-4:
            return "%.1e" % float(value)
        return str(int(float(value)))
    return str(value)


func _format_scientific_one_decimal(value) -> String:
    if not value is BigNum:
        return "%.1e" % float(value)
    var s: String = value.to_display_string().to_lower()
    if "e" not in s:
        return str(int(value.to_float()))
    var parts = s.split("e")
    if parts.size() != 2:
        return s
    var mantissa = snapped(float(parts[0]), 0.1)
    return "%.1fe%s" % [mantissa, parts[1]]


func _fmt_float(value: float) -> String:
    if value <= 0.0: return "0"
    return _fmt(BigNum.from_float(value))


# ==================================================
# TETRAD DISPLAY
# ==================================================
func _build_category_header(category_name: String, category_key: String) -> String:
    var locked = game_context.is_category_locked(category_key)
    var category_varieties := {
        "cat_fundament": ["adaemant", "aquae", "aethyr"],
        "cat_element":   ["earth", "water", "air"],
        "cat_symmetric": ["mud", "dust", "cloud"],
        "cat_medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
    }
    var any_created := false
    for v in category_varieties.get(category_key, []):
        if _tetrad_variety_triggered.get(v, false):
            any_created = true
            break
    var color: String
    if locked:
        color = "#ffdd77"
    elif any_created:
        color = "#aaaaaa"
    else:
        color = "#444444"
    return "[color=%s][i]%s[/i][/color]" % [color, category_name]


func _build_tetrad_line(keys: Array) -> String:
    var parts = []
    for key in keys:
        var locked   = game_context.is_locked(key)
        var created  = _tetrad_variety_triggered.get(key, false)
        var color: String
        if locked:
            color = "#ffdd77"
        elif created:
            color = "#ffffff"
        else:
            color = "#444444"
        var icon = " 🔒" if locked else ""
        parts.append("[color=%s]%s:[/color]\n[color=%s]%s%s[/color]" % [
            color, TETRAD_NAMES[key],
            color, _fmt(game_context.tetrad.get(key, BigNum.zero())), icon])
    return "\n".join(parts)


func _get_tetrad_tooltip(key: String) -> String:
    if key == "":
        return ""
    if key.begins_with("cat_"):
        return "Click to lock / unlock category"
    if not game_data:
        return ""
    var data = game_data.TETRADS.get(key, {})
    if data.is_empty():
        return ""
    var parts: Array = []
    if data.get("s", 0) > 0: parts.append("S%d" % data["s"])
    if data.get("l", 0) > 0: parts.append("L%d" % data["l"])
    if data.get("g", 0) > 0: parts.append("G%d" % data["g"])
    var composition: String = " / ".join(parts)
    if not game_context:
        return composition
    var total: BigNum = game_context.totals_created.get(key, BigNum.zero())
    if total.is_zero():
        return composition
    return "%s\nTotal: %s" % [composition, _fmt(total)]


func _totals_display_name(key: String) -> String:
    if key.begins_with("monad_"):
        return "Monad (%s)" % key.split("_")[1].capitalize()
    if game_data:
        var d = game_data.TETRADS.get(key, {}).get("display", "")
        if d != "": return d
    match key:
        "particle":         return "Particle"
        "iota":             return "Iota"
        "mote":             return "Mote"
        "grain":            return "Grain"
        "uonite":           return "Uonite"
        "monad_all":        return "All Monads"
        "tetrad_fundament": return "Fundament Tetrads"
        "tetrad_element":   return "Element Tetrads"
        "tetrad_symmetric": return "Symmetric Tetrads"
        "tetrad_medial":    return "Medial Tetrads"
        "tetrad_all":       return "All Tetrads"
    return key.capitalize()


func _update_tetrad_display() -> void:
    if not game_context:
        return
    if _left_tetrad_label and _left_tetrad_label is RichTextLabel:
        var txt  = _build_category_header("Fundaments", "cat_fundament") + "\n"
        txt     += _build_tetrad_line(["adaemant", "aquae", "aethyr"]) + "\n\n"
        txt     += _build_tetrad_line(["dirt", "sand"]) + "\n"
        _left_tetrad_label.bbcode_enabled = true
        _left_tetrad_label.bbcode_text    = txt
    if _middle_label and _middle_label is RichTextLabel:
        var txt  = _build_category_header("Elements", "cat_element") + "\n"
        txt     += _build_tetrad_line(["earth", "water", "air"]) + "\n"
        txt     += _build_category_header("Medials", "cat_medial") + "\n"
        txt     += _build_tetrad_line(["haze", "mist"]) + "\n"
        _middle_label.bbcode_enabled = true
        _middle_label.bbcode_text    = txt
    if _medials2_label and _medials2_label is RichTextLabel:
        var txt  = _build_category_header("Symmetrics", "cat_symmetric") + "\n"
        txt     += _build_tetrad_line(["mud", "dust", "cloud"]) + "\n\n"
        txt     += _build_tetrad_line(["ooze", "foam"]) + "\n"
        _medials2_label.visible        = true
        _medials2_label.bbcode_enabled = true
        _medials2_label.bbcode_text    = txt


# ==================================================
# BARS
# ==================================================
func _setup_bars() -> void:
    bars.clear()
    _bar_smoothed_rates.clear()
    var resources = ["sparks", "monad", "tetrad", "iota", "mote", "particle", "grain", "uonite"]
    for res in resources:
        var gen_bar = find_child(res.capitalize() + "GenBar", true, false)
        if gen_bar:
            var gen_lbl = _make_or_get_overlay_label(gen_bar, res.capitalize() + "GenLabel")
            bars[res] = {"gen_bar": gen_bar, "gen_lbl": gen_lbl}
            gen_bar.max_value = 100.0
            gen_bar.min_value = 0.0
            _bar_smoothed_rates[res] = 0.0
        else:
            push_warning("RootUI: Missing GenBar for " + res)


func _make_or_get_overlay_label(bar: ProgressBar, label_name: String) -> Label:
    var lbl = bar.get_node_or_null(label_name)
    if lbl:
        return lbl
    lbl = Label.new()
    lbl.name                 = label_name
    lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
    lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
    lbl.add_theme_color_override("font_color", BAR_LABEL_COLOR)
    lbl.add_theme_font_size_override("font_size", BAR_LABEL_FONT_SIZE)
    lbl.clip_text = true
    bar.add_child(lbl)
    return lbl


func _update_bars(delta: float) -> void:
    if not game_context or bars.is_empty():
        return

    for res in bars:
        var data    = bars[res]
        var gen_bar: ProgressBar = data["gen_bar"]
        var gen_lbl: Label       = data["gen_lbl"]

        var op = _res_to_op(res)

        var assign_f: float = 0.0
        if op != "":
            assign_f = game_context.get_operation_total_bignum(op).to_float()

        var prod_per_sec: float = 0.0
        if op != "" and game_context.rates.has(op):
            prod_per_sec = game_context.rates[op].to_float()

        var actual_drain: float = 0.0
        if production_manager:
            actual_drain = production_manager.get_resource_drain_per_second(res)

        var potential_drain: float = 0.0
        if production_manager:
            potential_drain = production_manager.get_potential_drain_per_second(res)

        var net_drain: float  = actual_drain - prod_per_sec
        var target_pct: float = 100.0
        var potential_net     = potential_drain - prod_per_sec
        if potential_net > 0.0 and assign_f > 0.0:
            var drain_per_worker = potential_net / assign_f
            var decrease_rate    = drain_per_worker / 10.0
            target_pct = max(0.0, gen_bar.value - decrease_rate * delta * 100.0)
        elif potential_net <= 0.0:
            target_pct = 100.0

        gen_bar.value = target_pct

        var base_color: Color = Color.WHITE
        if game_data:
            base_color = Color.from_string(
                game_data.RESOURCES.get(res, {}).get("color", "#ffffff"),
                Color.WHITE)

        if net_drain < -prod_per_sec * 0.05 and assign_f > 0.0:
            var flash       = sin(_time * BAR_FLASH_SPEED * TAU) * 0.5 + 0.5
            var flash_color = base_color.lerp(Color.WHITE, flash * 0.6)
            gen_bar.add_theme_stylebox_override("fill", _get_bar_fill_style(res, flash_color))
        else:
            gen_bar.add_theme_stylebox_override("fill", _get_bar_fill_style(res, base_color))

        var assign_str: String = "—" if res == "uonite" else \
            _fmt(game_context.get_operation_total_bignum(op)) if op != "" else "—"

        var need_str: String = "—"
        var need = potential_drain - prod_per_sec
        if need > 0.0:
            need_str = "-%d/s" % int(need)
        elif need < 0.0:
            need_str = "+%d/s" % int(-need)
        else:
            need_str = "0/s"
        gen_lbl.text = "%s    %s" % [assign_str, need_str]


func _get_bar_fill_style(res: String, color: Color) -> StyleBoxFlat:
    if not _bar_fill_styles.has(res):
        var s = StyleBoxFlat.new()
        s.corner_radius_top_left     = 2
        s.corner_radius_top_right    = 2
        s.corner_radius_bottom_left  = 2
        s.corner_radius_bottom_right = 2
        _bar_fill_styles[res] = s
    _bar_fill_styles[res].bg_color = color
    return _bar_fill_styles[res]


func _res_to_op(res: String) -> String:
    match res:
        "sparks":   return "sparks_summon"
        "monad":    return "monad_compress"
        "tetrad":   return "tetrad_assemble"
        "particle": return "particle_compress"
        "iota":     return "iota_assemble"
        "mote":     return "mote_compress"
        "grain":    return "grain_assemble"
    return ""


# ==================================================
# SAVE / LOAD
# ==================================================
func _load_on_start() -> void:
    if save_manager:
        save_manager.load_game()
    if archon_dialogue_manager:
        archon_dialogue_manager.start_intro()


func save_game() -> void:
    if save_manager and save_manager.has_method("save_game"):
        save_manager.save_game()


func load_game() -> void:
    if save_manager and save_manager.has_method("load_game"):
        save_manager.load_game()
        
        
func _on_reset_requested() -> void:
    if save_manager and save_manager.has_method("reset_save"):
        save_manager.reset_save()
