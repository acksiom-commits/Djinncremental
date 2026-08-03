extends VBoxContainer

# ================= FIRMAMENT UI v1.2.0 =================
# v1.2.0: Scene tree restructured to mirror RootUI top-level skeleton.
#         SolidMaterialsPanel / LiquidMaterialsPanel / GasMaterialsPanel
#         moved from flat children of FirmTopBandHBox into:
#           FirmBarsPanelContainer → FirmBarsMargin → FirmBarsVBox
#         find_child() calls below use recursive=true so no path changes needed.
#         FirmAllocationVBox / FirmMidBandHBox / FirmBottomBandHBox stubs added.
# v1.1.0: Fixed AgesPopout wiring — unlock_age called for primordial
#         and firmament, set_active_age called once for firmament,
#         reveal() called to make tab visible.
# v1.0.0: Initial Firmament age controller.
# All game state lives in autoloads -- no data is lost on scene change.

var game_context:            Node = null
var production_manager:      Node = null
var save_manager:            Node = null
var game_data:               Node = null
var archon_dialogue_manager: Node = null

var _ages_popout:      Node = null
var _journal_popout: Node = null
var _settings_popout:  Node = null

var _panel_nodes:      Dictionary = {}
const REVEAL_DURATION: float = 1.5


func _ready() -> void:
    game_context            = get_node_or_null("/root/GameContext")
    production_manager      = get_node_or_null("/root/ProductionManager")
    save_manager            = get_node_or_null("/root/SaveManager")
    game_data               = get_node_or_null("/root/GameData")
    archon_dialogue_manager = get_node_or_null("/root/ArchonDialogueManager")

    _ages_popout      = find_child("AgesPopout",            true, false)
    _journal_popout = find_child("DialogueJournalPopout", true, false)

    if _ages_popout:
        _ages_popout.unlock_age("primordial")
        _ages_popout.unlock_age("firmament")
        _ages_popout.set_active_age("firmament")
        _ages_popout.reveal()
        _ages_popout.age_selected.connect(_on_age_selected)

    if _journal_popout and archon_dialogue_manager:
        archon_dialogue_manager.sequence_complete.connect(
            _journal_popout.append_sequence)
        archon_dialogue_manager.notification_shown.connect(
            _journal_popout.append_notification)

    _settings_popout = find_child("SettingsPopout", true, false)
    if _settings_popout:
        _settings_popout.save_requested.connect(save_game)
        _settings_popout.load_requested.connect(load_game)
        _settings_popout.reset_requested.connect(_on_reset_requested)
        # A direct get_tree().quit() call bypasses NOTIFICATION_WM_CLOSE_
        # REQUEST entirely (that only fires for an OS-level close request —
        # see save_manager.gd's own handler for that path), so this button
        # needs its own explicit save first. Mirrors root_ui.gd's identical
        # quit_requested handler.
        _settings_popout.quit_requested.connect(func(): save_game(); get_tree().quit())

    if archon_dialogue_manager:
        archon_dialogue_manager.ui_reveal_requested.connect(_reveal_panel)

    _setup_panel_nodes()
    _hide_all_panels()

    if archon_dialogue_manager:
        archon_dialogue_manager.enqueue_dialogue([
            "The Primordial Stage is behind us.",
			"The Firmament awaits your shaping."
        ])


func _setup_panel_nodes() -> void:
    # find_child(name, owned=true, recursive=true) searches the full subtree,
    # so the materials panels are found correctly inside their new FirmBarsVBox home.
    _panel_nodes = {
        # ── Centre-column material panels (now nested in FirmBarsPanelContainer)
        "materials_solid":   find_child("SolidMaterialsPanel",  true, false),
        "materials_liquid":  find_child("LiquidMaterialsPanel", true, false),
        "materials_gas":     find_child("GasMaterialsPanel",    true, false),
        # ── Structural stub zones — included so _hide_all_panels tolerates null gracefully
        # and unlock keys can reference them when content is populated later.
        "allocation_zone":   find_child("FirmAllocationVBox",   true, false),
        "mid_band":          find_child("FirmMidBandHBox",       true, false),
    }


func _hide_all_panels() -> void:
    for key in _panel_nodes:
        var node = _panel_nodes[key]
        if node:
            node.modulate.a   = 0.0
            node.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
    var tween = create_tween()
    tween.tween_property(node, "modulate:a", 1.0, REVEAL_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_age_selected(key: String) -> void:
    match key:
        "primordial":
            _transition_to_age("res://RootUI.tscn")
        "world":
            _transition_to_age("res://WorldUI.tscn")
        "civilization":
            _transition_to_age("res://CivilizationUI.tscn")


func _transition_to_age(scene_path: String) -> void:
    if save_manager:
        save_manager.save_game()
    var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tween.tween_property(get_tree().current_scene, "modulate:a", 0.0, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(scene_path))


func save_game() -> void:
    if save_manager and save_manager.has_method("save_game"):
        save_manager.save_game()


func load_game() -> void:
    if save_manager and save_manager.has_method("load_game"):
        save_manager.load_game()


func _on_reset_requested() -> void:
    if save_manager and save_manager.has_method("reset_save"):
        save_manager.reset_save()
