# carousel.gd - Robust reposition-based seamless loop
extends Control

var panels: Array[Panel] = []
var current_offset: float = 0.0

# Panel count for the seamless reposition-based loop — create_panels()'s
# range, _process()'s reposition loop, and its two off-screen wrap offsets
# all need this in sync, or the loop stops being seamless.
const PANEL_COUNT: int = 18

@export var panel_width: float = 120.0
@export var panel_height: float = 160.0
@export var panel_spacing: float = 26.0
@export var drag_speed_multiplier: float = 0.28
@export var inertia_damping: float = 0.75

var is_dragging: bool = false
var last_mouse_x: float = 0.0
var velocity: float = 0.0
var is_snapping: bool = false

func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    custom_minimum_size = Vector2(1200, 200)
    
    create_panels()
    current_offset = -280


func create_panels() -> void:
    for i in PANEL_COUNT:
        var panel = Panel.new()
        panel.custom_minimum_size = Vector2(panel_width, panel_height)
        panel.size = Vector2(panel_width, panel_height)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        
        var style = StyleBoxFlat.new()
        style.bg_color = Color(0.0, 0.0, 0.0, 0.12)
        style.border_width_left = 5
        style.border_width_right = 5
        style.border_width_top = 5
        style.border_width_bottom = 5
        style.corner_radius_top_left = 10
        style.corner_radius_top_right = 10
        style.corner_radius_bottom_left = 10
        style.corner_radius_bottom_right = 10
        
        var cat = int(i / 6)
        var base_col: Color = Color(0.95, 0.22, 0.22) if cat == 0 else \
                             Color(0.25, 0.6, 1.0) if cat == 1 else Color(1.0, 0.9, 0.2)
        
        style.border_color = base_col
        panel.add_theme_stylebox_override("panel", style)
        add_child(panel)
        panels.append(panel)


func _process(delta: float) -> void:
    if size.x < 100:
        return
    
    if not is_dragging:
        if is_snapping:
            var target = get_nearest_center_offset()
            current_offset = lerp(current_offset, target, 8.0 * delta)
            if abs(current_offset - target) < 5.0:
                current_offset = target
                is_snapping = false
        else:
            velocity *= inertia_damping
            current_offset += velocity * delta * 45
    
    var segment = panel_width + panel_spacing
    
    # Reposition panels for seamless loop
    for i in PANEL_COUNT:
        var x = current_offset + i * segment
        panels[i].position.x = x
        panels[i].position.y = (size.y - panel_height) / 2.0

        # Reposition panels that go off-screen to the other side
        if x < -panel_width * 2:
            panels[i].position.x += segment * PANEL_COUNT
        elif x > size.x + panel_width:
            panels[i].position.x -= segment * PANEL_COUNT


func get_nearest_center_offset() -> float:
    var segment = panel_width + panel_spacing
    var nearest = round(-current_offset / segment)
    return -nearest * segment


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_dragging = true
            is_snapping = false
            velocity = 0
            last_mouse_x = get_local_mouse_position().x
        else:
            is_dragging = false
            is_snapping = true
            
    elif event is InputEventMouseMotion and is_dragging:
        var dx = get_local_mouse_position().x - last_mouse_x
        current_offset += dx * drag_speed_multiplier
        velocity = dx * 3.0
        last_mouse_x = get_local_mouse_position().x
