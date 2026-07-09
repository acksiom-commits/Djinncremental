@tool
extends Node3D


# ========== ARCHON FACE CONTROLLER SCRIPT ===============


@export var mouse_tracking_strength: float = 1.0
@export var smooth_speed: float = 12.0
@export var max_yaw: float = 45.0
@export var max_pitch: float = 25.0
@export var invert_yaw: bool = false

var current_basis: Basis

func _ready() -> void:
    current_basis = basis

func _process(delta: float) -> void:
    if Engine.is_editor_hint() or mouse_tracking_strength <= 0:
        return
        
    var cam = get_viewport().get_camera_3d()
    if not cam: return
    
    var mouse_pos = get_viewport().get_mouse_position()
    var ray_dir = cam.project_ray_normal(mouse_pos)
    
    # Projecting a point 10 units away to find the look-at target
    var target_global = cam.global_position + ray_dir * 10.0
    var local_target = to_local(target_global).normalized()
    
    # Simple math: Mesh is now 0-centered
    var yaw = rad_to_deg(atan2(local_target.x, -local_target.z))
    var pitch = rad_to_deg(asin(local_target.y))
    
    if invert_yaw: yaw = -yaw
    
    # Clamp and smooth
    yaw = clamp(yaw, -max_yaw, max_yaw)
    pitch = clamp(pitch, -max_pitch, max_pitch)
    
    var target_basis = Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
    current_basis = current_basis.slerp(target_basis, smooth_speed * delta)
    basis = current_basis
