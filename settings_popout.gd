extends Control
# ================= settings POPOUT v1.2.0 =================
# v1.1.0: BgLockToggle and ConstellationToggle wired.
# v1.2.0: Save slots (SlotRow) and the Autosave toggle. Save/Load/Reset act
#         on the SELECTED slot, which starts each opening on the slot being
#         played; every signal below carries that slot number.

const TAB_WIDTH:   float = 22.0
const PANEL_WIDTH: float = 160.0
const ANIM_TIME:   float = 0.22

const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

signal save_requested(slot: int)
signal load_requested(slot: int)
signal reset_requested(slot: int)
## The selected slot is empty and the player confirmed starting fresh there.
signal new_game_requested(slot: int)
signal quit_requested
signal ui_minimal_requested(minimal: bool)

var tooltips_enabled: bool = true

var _is_open: bool  = false
var _tween:   Tween = null

var _starfield:    Node = null
var _overlay:      Node = null
var _save_manager: Node = null

var _selected_slot: int = 1
# What SlotConfirmDialog's OK runs — one dialog serves both the overwrite
# and the new-game confirmations.
var _slot_confirm_action: Callable = Callable()

@onready var _tab_btn           : Button             = $SettingsTabButton
@onready var _panel             : PanelContainer     = $SettingsPanel
# One button per SaveManager.SLOT_COUNT slot; add a SlotNButton to SlotRow
# alongside raising that constant.
@onready var _slot_btns         : Array[Button]      = [
    $SettingsPanel/SettingsMargin/SettingsVBox/SlotRow/Slot1Button,
    $SettingsPanel/SettingsMargin/SettingsVBox/SlotRow/Slot2Button,
    $SettingsPanel/SettingsMargin/SettingsVBox/SlotRow/Slot3Button,
]
@onready var _slot_status       : Label              = $SettingsPanel/SettingsMargin/SettingsVBox/SlotStatusLabel
@onready var _slot_confirm      : ConfirmationDialog = $SlotConfirmDialog
@onready var _save_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/SaveButton
@onready var _load_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/LoadButton
@onready var _reset_btn         : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/ResetButton
@onready var _reset_confirm     : ConfirmationDialog = $ResetConfirmDialog
@onready var _quit_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/QuitButton
@onready var _autosave_tog      : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/AutosaveToggle
@onready var _tooltips_tog      : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/TooltipsToggle
@onready var _bg_lock_tog       : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/BgLockToggle
@onready var _constellation_tog : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/ConstellationToggle
@onready var _ui_minimal_tog    : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/UiMinimalToggle

func _ready() -> void:
    _starfield    = get_node_or_null("/root/Node2D/CanvasLayer/ColorRect")
    _overlay      = get_node_or_null("/root/Node2D/CanvasLayer/ConstellationOverlay")
    _save_manager = get_node_or_null("/root/SaveManager")

    _tab_btn.pressed.connect(_on_tab_pressed)
    for i in _slot_btns.size():
        var slot: int = i + 1
        _slot_btns[i].pressed.connect(func(): _select_slot(slot))
    _save_btn.pressed.connect(_on_save_btn_pressed)
    _load_btn.pressed.connect(_on_load_btn_pressed)
    _reset_btn.pressed.connect(_on_reset_btn_pressed)
    _reset_confirm.confirmed.connect(_on_reset_confirmed)
    _slot_confirm.confirmed.connect(_on_slot_confirmed)
    _quit_btn.pressed.connect(func(): quit_requested.emit())

    _autosave_tog.set_pressed_no_signal(_save_manager.autosave_enabled if _save_manager else true)
    _autosave_tog.toggled.connect(_on_autosave_toggled)
    if _save_manager and _save_manager.has_signal("slot_load_failed"):
        _save_manager.slot_load_failed.connect(_on_slot_load_failed)

    _bg_lock_tog.toggled.connect(_on_bg_lock_toggled)
    _constellation_tog.toggled.connect(_on_constellation_toggled)
    _tooltips_tog.toggled.connect(_on_tooltips_toggled)

    _ui_minimal_tog.toggled.connect(_on_ui_minimal_toggled)
    _ui_minimal_tog.button_pressed = false

    _bg_lock_tog.button_pressed       = false
    _constellation_tog.button_pressed = true

    # Panel starts hidden to the right of the tab
    _panel.visible = true
    _panel.position = Vector2(22.0, 0.0)
    _tab_btn.position = Vector2(0.0, 0.0)

    _reset_confirm.get_ok_button().text = "Yes, Reset"
    _reset_confirm.get_cancel_button().text = "Keep Playing"
    _reset_confirm.get_ok_button().theme_type_variation     = "DialogConfirmButton"
    _reset_confirm.get_cancel_button().theme_type_variation = "DialogConfirmButton"
    _slot_confirm.get_cancel_button().text = "Cancel"
    _slot_confirm.get_ok_button().theme_type_variation     = "DialogConfirmButton"
    _slot_confirm.get_cancel_button().theme_type_variation = "DialogConfirmButton"
    _slot_confirm.min_size = Vector2i(340, 0)

    _selected_slot = _active_slot()
    _refresh_slot_ui()


func _active_slot() -> int:
    return _save_manager.active_slot if _save_manager else 1


func _slot_has_save(slot: int) -> bool:
    return _save_manager.slot_has_save(slot) if _save_manager else false


func _select_slot(slot: int) -> void:
    _selected_slot = slot
    _refresh_slot_ui()


# Save/Load/Reset relabel to say exactly what they'll do to the selected
# slot, so the three buttons never need a separate "which slot" readout.
func _refresh_slot_ui() -> void:
    var active: int = _active_slot()
    var has_save: bool = _slot_has_save(_selected_slot)
    var paused: bool = _save_manager.saving_paused() if _save_manager else false
    for i in _slot_btns.size():
        var slot: int = i + 1
        _slot_btns[i].set_pressed_no_signal(slot == _selected_slot)
        _slot_btns[i].tooltip_text = "Slot %d%s" % [slot, " (current game)" if slot == active else ""]

    var status: String
    if not has_save:
        status = "Restart to begin" if (paused and _selected_slot == active) else "Empty"
    else:
        var saved_unix: int = _save_manager.slot_saved_unix(_selected_slot)
        status = _format_saved_time(saved_unix) if saved_unix > 0 else "Saved"
        if _selected_slot != active:
            status = "Saved " + status
        elif paused:
            status = "Saving paused"
    if _selected_slot == active:
        status = "Playing · " + status
    _slot_status.text = status

    _save_btn.text = "Save Game" if _selected_slot == active else "Save to Slot %d" % _selected_slot
    if not has_save:
        _load_btn.text = "New Game"
    else:
        _load_btn.text = "Load Game" if _selected_slot == active else "Load Slot %d" % _selected_slot
    _reset_btn.disabled = not has_save


func _format_saved_time(unix_utc: int) -> String:
    var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
    var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_utc + bias_minutes * 60)
    return "%02d:%02d %s %d" % [dt.hour, dt.minute, MONTHS[clampi(int(dt.month) - 1, 0, 11)], dt.day]


func _on_save_btn_pressed() -> void:
    var slot: int = _selected_slot
    if slot != _active_slot() and _slot_has_save(slot):
        _confirm_slot_action(
            "Overwrite Slot %d with your current game?\nThe game saved there will be lost." % slot,
            "Overwrite", func(): save_requested.emit(slot); _close())
        return
    save_requested.emit(slot)
    _close()


func _on_load_btn_pressed() -> void:
    var slot: int = _selected_slot
    if _slot_has_save(slot):
        load_requested.emit(slot)
        _close()
        return
    var active: int = _active_slot()
    var text: String = "Start a new game in Slot %d?\n\n" % slot
    if slot != active:
        if _save_manager and _save_manager.autosave_enabled:
            text += "Your current game is saved to Slot %d first. " % active
        else:
            text += "Your current game in Slot %d keeps its last save. " % active
    text += "Saving then pauses — restart the game to begin."
    _confirm_slot_action(text, "New Game",
        func(): new_game_requested.emit(slot); _refresh_slot_ui())


func _confirm_slot_action(text: String, ok_text: String, action: Callable) -> void:
    _slot_confirm_action = action
    _slot_confirm.dialog_text = text
    _slot_confirm.get_ok_button().text = ok_text
    _slot_confirm.popup_centered()


func _on_slot_confirmed() -> void:
    if _slot_confirm_action.is_valid():
        _slot_confirm_action.call()
    _slot_confirm_action = Callable()


func _on_reset_btn_pressed() -> void:
    if _selected_slot == _active_slot():
        _reset_confirm.dialog_text = "Delete Slot %d's save and restart?\nThis cannot be undone." % _selected_slot
    else:
        _reset_confirm.dialog_text = "Delete the game saved in Slot %d?\nThis cannot be undone." % _selected_slot
    _reset_confirm.popup_centered()


func _on_reset_confirmed() -> void:
    reset_requested.emit(_selected_slot)
    _refresh_slot_ui()


func _on_slot_load_failed(slot: int) -> void:
    var dlg := AcceptDialog.new()
    dlg.title = "Save could not be read"
    dlg.dialog_text = ("Slot %d's save file and its backup could not be read.\n\n" % slot
        + "Your current game is unchanged and still saving to Slot %d." % _active_slot())
    dlg.dialog_autowrap = true
    dlg.min_size = Vector2i(380, 0)
    add_child(dlg)
    dlg.popup_centered()
    dlg.confirmed.connect(dlg.queue_free)
    dlg.canceled.connect(dlg.queue_free)


func _on_autosave_toggled(pressed: bool) -> void:
    if _save_manager and _save_manager.has_method("set_autosave_enabled"):
        _save_manager.set_autosave_enabled(pressed)


func _on_bg_lock_toggled(pressed: bool) -> void:
    if _starfield and _starfield.has_method("set_rotation_locked"):
        _starfield.set_rotation_locked(pressed)


func _on_constellation_toggled(pressed: bool) -> void:
    if _overlay and _overlay.has_method("set_constellations_visible"):
        _overlay.set_constellations_visible(pressed)
    if _starfield and _starfield.has_method("set_constellations_visible"):
        _starfield.set_constellations_visible(pressed)
        

func _on_tooltips_toggled(enabled: bool) -> void:
    tooltips_enabled = enabled


func _on_ui_minimal_toggled(pressed: bool) -> void:
    ui_minimal_requested.emit(pressed)


func _on_tab_pressed() -> void:
    if _is_open:
        _close()
        return
    _is_open = true
    # Re-read on every opening: autosaves and age transitions write files
    # (and change timestamps) while the panel is shut.
    _selected_slot = _active_slot()
    _refresh_slot_ui()
    _tween = SlidePanelToggle.run(_tab_btn, "position:x", -182.0,
        _panel, "position:x", -160.0, ANIM_TIME, _tween)


func _close() -> void:
    if not _is_open:
        return
    _is_open = false
    _tween = SlidePanelToggle.run(_tab_btn, "position:x", 0.0,
        _panel, "position:x", 22.0, ANIM_TIME, _tween)
    
    
func _input(event: InputEvent) -> void:
    if not _is_open:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _reset_confirm.visible or _slot_confirm.visible:
            return
        if not _panel.get_global_rect().has_point(event.global_position) \
        and not _tab_btn.get_global_rect().has_point(event.global_position):
            _close()
            get_viewport().set_input_as_handled()
