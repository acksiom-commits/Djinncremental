extends VBoxContainer

# ============= MID-GAME MECHANICS FOUNDATION (design spec, not yet built) =============
# Archai: a new Particle categorization, sorted on two axes: Tetrad Variety and Purity Tier.
# Permanence: a Particle qualifies for Permanence (can survive an Expansion reset) iff at
#             least one of its compressed 5 tetrads is a Fundament Tetrad.
# Primal Archai: Particles whose compressed 5 tetrads are ALL Fundament tetrads.
# Purity Tiers (Primal Archai only, by split of the 5 Fundament tetrads across Varieties):
#   Tier 1 (highest): 5 of one Variety            (5)
#   Tier 2:           4 of one Variety + 1 other   (4-1)
#   Tier 3:           3 of one Variety + 2 other   (3-2)
#   Tier 4:           3 of one Variety + 1 of each of the others (3-1-1)
#   Tier 5 (lowest):  less than 3 of any single Variety (e.g. 2-2-1, 2-1-1-1, 1-1-1-1-1)
# Phlogiston/Quintessence: an Expansion reset destroys non-Permanent ("early-stage")
#             materials that don't survive it; that destruction harvests Phlogiston
#             (existing RESOURCES entry) as a byproduct. Quintessence is Phlogiston's
#             processed/refined form -- fuel source for Runes, and an ingredient in
#             Enchanted materials. Phlogiston's own further uses are TBD.
# See memory: planned_archai_purity_tier_taxonomy
# ================= FIRMAMENT UI v1.3.0 =================
# v1.3.0: Wired save_manager's game_loaded/save_load_failed signals, which
#         were never connected here (unlike root_ui.gd) — clicking Load
#         while already in Firmament left panel visibility stale and gave
#         no feedback on a corrupt save. Added _apply_unlock_visibility()/
#         _restore_subtree_input() (mirrors root_ui.gd) to resync the
#         materials/allocation panels to the loaded save's ui_unlocks, an
#         offline-progress notification pass, and the same corrupt-save
#         AcceptDialog as root_ui.gd. Root_ui.gd's other _on_game_loaded
#         logic (puzzle-cache bootstrap, Archon poke-minigame lockdown
#         restore, click-vol label, dialogue-trigger-flag resync) is all
#         gated on Primordial-only nodes/systems that don't exist here.
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

    if save_manager:
        save_manager.game_loaded.connect(_on_game_loaded)
        if save_manager.has_signal("save_load_failed"):
            save_manager.save_load_failed.connect(_on_save_load_failed)

    if archon_dialogue_manager:
        archon_dialogue_manager.ui_reveal_requested.connect(_reveal_panel)

    _setup_panel_nodes()
    _hide_all_panels()
    _apply_unlock_visibility()

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


func _apply_unlock_visibility() -> void:
    if not game_context:
        return
    for key in _panel_nodes:
        var node = _panel_nodes[key]
        if not node:
            continue
        if game_context.ui_unlocks.get(key, false):
            node.modulate.a   = 1.0
            node.mouse_filter = Control.MOUSE_FILTER_STOP
            _restore_subtree_input(node)
        else:
            node.modulate.a   = 0.0
            node.mouse_filter = Control.MOUSE_FILTER_IGNORE


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


func _on_save_load_failed() -> void:
    # Mirrors root_ui.gd's identical handler — save corruption is a global
    # SaveManager condition, not tied to which age scene is currently active,
    # so a player who clicks Load while in Firmament needs the same recovery
    # info (saving is already paused by SaveManager; this just surfaces it).
    var save_dir: String = ProjectSettings.globalize_path("user://")
    var dlg := AcceptDialog.new()
    dlg.title = "Save could not be read"
    dlg.dialog_text = ("Your save file and its backup could not be read, so the game "
        + "could not load your progress.\n\n"
        + "To protect them, saving has been paused — your files have NOT been "
        + "deleted or overwritten. You can find them here:\n\n"
        + save_dir + "\n\n"
        + "Back them up if you'd like to attempt recovery. To start over instead, "
        + "use Reset in the Settings menu.")
    dlg.dialog_autowrap = true
    dlg.min_size = Vector2i(460, 0)
    add_child(dlg)
    dlg.popup_centered()
    dlg.confirmed.connect(dlg.queue_free)
    dlg.canceled.connect(dlg.queue_free)


func _on_game_loaded(offline_seconds: float) -> void:
    # Resync panel visibility to the just-loaded save's ui_unlocks — without
    # this, clicking Load while already in Firmament leaves the materials
    # panels showing whatever the CURRENT session had revealed, which may no
    # longer match the state the player just loaded. Firmament has no
    # dialogue-trigger flags or puzzle cache of its own (those live in
    # root_ui.gd, gated on Primordial-only nodes like ConstellationOverlay
    # and the Archon poke minigame), so this is the whole resync it needs.
    _apply_unlock_visibility()
    if offline_seconds < 30.0 or not production_manager:
        return
    var results: Dictionary = production_manager.apply_offline_progress(offline_seconds)
    if results.is_empty():
        return
    var minutes := int(results.get("time_simulated", 0)) / 60.0
    var lines   := ["Away for ~%d min. Offline gains:" % minutes]
    for key in ["sparks", "monad", "tetrad", "particle", "iota_uonite", "mote_uonite", "grain"]:
        if results.has(key):
            lines.append("  +%s %s" % [results[key], key.capitalize()])
    if archon_dialogue_manager:
        archon_dialogue_manager.enqueue_notification("\n".join(lines))
        archon_dialogue_manager.try_show_next_notification()


func save_game() -> void:
    if save_manager and save_manager.has_method("save_game"):
        save_manager.save_game()


func load_game() -> void:
    if save_manager and save_manager.has_method("load_game"):
        save_manager.load_game()


func _on_reset_requested() -> void:
    if save_manager and save_manager.has_method("reset_save"):
        save_manager.reset_save()
