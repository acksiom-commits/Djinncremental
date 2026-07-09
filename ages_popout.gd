extends Control
# ================= AGES POPOUT v1.1.0 =================

const TAB_WIDTH:   float = 22.0
const PANEL_WIDTH: float = 175.0
const ANIM_TIME:   float = 0.22

const COLOR_LOCKED:   Color = Color("#444455")
const COLOR_UNLOCKED: Color = Color("#aaddff")
const COLOR_ACTIVE:   Color = Color("#ffdd55")

const AGE_KEYS: Array[String] = ["primordial", "firmament", "world", "civilization"]

signal age_selected(key: String)

var _is_open:    bool   = false
var _tween:      Tween  = null
var _active_age: String = ""
var _unlocked: Dictionary = {
    "primordial":   true,
    "firmament":    false,
    "world":        false,
    "civilization": false,
}

@onready var _tab_btn : Button         = $AgesTabButton
@onready var _panel   : PanelContainer = $AgesPanel

@onready var _prim_btn  : Button = $AgesPanel/AgesMargin/AgesVBox/PrimordialButton
@onready var _prim_name : Label  = $AgesPanel/AgesMargin/AgesVBox/PrimordialButton/BtnVBox/NameLabel

@onready var _firm_btn  : Button = $AgesPanel/AgesMargin/AgesVBox/FirmamentButton
@onready var _firm_name : Label  = $AgesPanel/AgesMargin/AgesVBox/FirmamentButton/BtnVBox/NameLabel

@onready var _world_btn  : Button = $AgesPanel/AgesMargin/AgesVBox/WorldButton
@onready var _world_name : Label  = $AgesPanel/AgesMargin/AgesVBox/WorldButton/BtnVBox/NameLabel

@onready var _civ_btn  : Button = $AgesPanel/AgesMargin/AgesVBox/CivilizationButton
@onready var _civ_name : Label  = $AgesPanel/AgesMargin/AgesVBox/CivilizationButton/BtnVBox/NameLabel


func _ready() -> void:
    _tab_btn.pressed.connect(_on_tab_pressed)
    _prim_btn.pressed.connect(func(): _on_age_pressed("primordial"))
    _firm_btn.pressed.connect(func(): _on_age_pressed("firmament"))
    _world_btn.pressed.connect(func(): _on_age_pressed("world"))
    _civ_btn.pressed.connect(func():  _on_age_pressed("civilization"))
    _panel.visible = true
    _panel.top_level = true
    call_deferred("_init_panel_position")
    get_viewport().size_changed.connect(_init_panel_position)
    # === AGES LOCK: remove both comment markers below to activate the gate ===
    #if ConstellationData.unlocked.size() < 8:
    #    modulate.a = 0.0
    #    ConstellationData.constellation_unlocked.connect(_on_constellation_unlocked)
    _refresh_all()
    

func _init_panel_position() -> void:
    _panel.global_position = Vector2(
        _tab_btn.global_position.x - PANEL_WIDTH,
        _tab_btn.global_position.y
    )


# ==========================================================================
# PUBLIC API
# ==========================================================================

func unlock_age(key: String) -> void:
    if key in _unlocked:
        _unlocked[key] = true
        _refresh_all()


func set_active_age(key: String) -> void:
    _active_age = key
    _refresh_all()


func reveal() -> void:
    var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    t.tween_property(self, "modulate:a", 1.0, 1.5)
    
    
func _on_constellation_unlocked(_id: int) -> void:
    if ConstellationData.unlocked.size() >= 8:
        reveal()
        ConstellationData.constellation_unlocked.disconnect(_on_constellation_unlocked)


# ==========================================================================
# SLIDE TOGGLE
# ==========================================================================
func _on_tab_pressed() -> void:
    if _is_open:
        _close()
        return
    _is_open = true
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    var tab_x: float = _tab_btn.global_position.x
    _tween.tween_property(_tab_btn, "position:x", PANEL_WIDTH, ANIM_TIME)
    _tween.parallel().tween_property(_panel, "global_position:x", tab_x, ANIM_TIME)
        
        
func _close() -> void:
    if not _is_open:
        return
    _is_open = false
    if _tween:
        _tween.kill()
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    var closed_x: float = global_position.x - PANEL_WIDTH
    _tween.tween_property(_tab_btn, "position:x", 0.0, ANIM_TIME)
    _tween.parallel().tween_property(_panel, "global_position:x", closed_x, ANIM_TIME)


func _input(event: InputEvent) -> void:
    if not _is_open:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _panel.get_global_rect().has_point(event.global_position):
            return
        if _tab_btn.get_global_rect().has_point(event.global_position):
            return
        _close()
        get_viewport().set_input_as_handled()


# ==========================================================================
# AGE BUTTON PRESS
# ==========================================================================
func _on_age_pressed(key: String) -> void:
    if not _unlocked.get(key, false):
        return
    if key == _active_age:
        return
    set_active_age(key)
    age_selected.emit(key)


# ==========================================================================
# VISUAL REFRESH
# active age button is hidden entirely — you are already there
# ==========================================================================
func _refresh_all() -> void:
    _refresh_one(_prim_btn,  _prim_name,  "primordial")
    _refresh_one(_firm_btn,  _firm_name,  "firmament")
    _refresh_one(_world_btn, _world_name, "world")
    _refresh_one(_civ_btn,   _civ_name,   "civilization")
    # Resize panel to fit visible buttons
    await get_tree().process_frame
    var content_height: float = _panel.get_combined_minimum_size().y
    _panel.size.y = content_height
    _tab_btn.size.y = content_height


func _refresh_one(btn: Button, name_l: Label, key: String) -> void:
    var is_active:   bool = (_active_age == key)
    var is_unlocked: bool = _unlocked.get(key, false)

    btn.visible  = not is_active
    btn.disabled = not is_unlocked

    name_l.add_theme_color_override("font_color",
        COLOR_UNLOCKED if is_unlocked else
        COLOR_LOCKED)

    btn.modulate = (
        Color(1.00, 1.00, 1.00, 1.00) if is_unlocked else
        Color(0.55, 0.55, 0.65, 0.65)
    )
