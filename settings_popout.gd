extends Control
# ================= settings POPOUT v1.1.0 =================
# v1.1.0: BgLockToggle and ConstellationToggle wired.

const TAB_WIDTH:   float = 22.0
const PANEL_WIDTH: float = 160.0
const ANIM_TIME:   float = 0.22

signal save_requested
signal load_requested
signal reset_requested
signal quit_requested
signal ui_minimal_requested(minimal: bool)

var tooltips_enabled: bool = true

var _is_open: bool  = false
var _tween:   Tween = null

var _starfield: Node = null
var _overlay:   Node = null

@onready var _tab_btn           : Button             = $SettingsTabButton
@onready var _panel             : PanelContainer     = $SettingsPanel
@onready var _save_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/SaveButton
@onready var _load_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/LoadButton
@onready var _reset_btn         : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/ResetButton
@onready var _reset_confirm     : ConfirmationDialog = $ResetConfirmDialog
@onready var _quit_btn          : Button             = $SettingsPanel/SettingsMargin/SettingsVBox/QuitButton
@onready var _tooltips_tog      : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/TooltipsToggle
@onready var _bg_lock_tog       : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/BgLockToggle
@onready var _constellation_tog : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/ConstellationToggle
@onready var _ui_minimal_tog    : CheckButton        = $SettingsPanel/SettingsMargin/SettingsVBox/UiMinimalToggle

func _ready() -> void:
    _starfield = get_node_or_null("/root/Node2D/CanvasLayer/ColorRect")
    _overlay   = get_node_or_null("/root/Node2D/CanvasLayer/ConstellationOverlay")

    _tab_btn.pressed.connect(_on_tab_pressed)
    _save_btn.pressed.connect(func(): save_requested.emit(); _close())
    _load_btn.pressed.connect(func(): load_requested.emit(); _close())
    _reset_btn.pressed.connect(_on_reset_btn_pressed)
    _reset_confirm.confirmed.connect(func(): reset_requested.emit())
    _quit_btn.pressed.connect(func(): quit_requested.emit())

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
    _style_dialog_button(_reset_confirm.get_ok_button())
    _style_dialog_button(_reset_confirm.get_cancel_button())
    

func _on_reset_btn_pressed() -> void:
    _reset_confirm.popup_centered()


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
        if _reset_confirm.visible:
            return
        if not _panel.get_global_rect().has_point(event.global_position) \
        and not _tab_btn.get_global_rect().has_point(event.global_position):
            _close()
            get_viewport().set_input_as_handled()
            
            
func _style_dialog_button(btn: Button) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color                   = Color(0.12, 0.09, 0.22, 0.95)
    style.border_color               = Color(0.4, 0.28, 0.62, 0.9)
    style.border_width_left          = 1
    style.border_width_right         = 1
    style.border_width_top           = 1
    style.border_width_bottom        = 1
    style.corner_radius_top_left     = 4
    style.corner_radius_top_right    = 4
    style.corner_radius_bottom_left  = 4
    style.corner_radius_bottom_right = 4
    style.content_margin_left        = 16
    style.content_margin_right       = 16
    style.content_margin_top         = 8
    style.content_margin_bottom      = 8
    btn.add_theme_stylebox_override("normal", style)

    var hover := style.duplicate()
    hover.bg_color = Color(0.18, 0.13, 0.30, 0.96)
    hover.border_color = Color(0.55, 0.38, 0.80, 1.0)
    btn.add_theme_stylebox_override("hover", hover)

    var pressed := style.duplicate()
    pressed.bg_color = Color(0.25, 0.18, 0.42, 1.0)
    pressed.border_color = Color(0.65, 0.45, 0.90, 1.0)
    btn.add_theme_stylebox_override("pressed", pressed)

    btn.add_theme_color_override("font_color", Color(0.82, 0.82, 0.95, 1.0))
    btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
