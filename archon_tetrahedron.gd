@tool
extends MeshInstance3D

@export var size: float = 0.67
@export var line_color: Color = Color(0.873, 0.662, 0.087, 1.0)

@export_range(0, 5) var ability_level: int = 3:
    set(value):
        ability_level = clamp(value, 0, 5)
        _rebuild_mesh()

# Visual Tuning
@export var inner_scale: float = 0.25:
    set(value):
        inner_scale = value
        _rebuild_mesh()

@export var inner_front_boost: float = 1.6:
    set(value):
        inner_front_boost = max(1.0, value)
        _rebuild_mesh()
        
@export_range(0.0, 1.0, 0.01) var eye_spacing: float = 1.0:
    set(value):
        eye_spacing = value
        _rebuild_mesh()

# Per-feature rotation (degrees). X=nod, Y=turn, Z=tilt.
@export_range(-45.0, 45.0, 0.5) var left_eye_x: float = 0.0:
    set(v):
        left_eye_x = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var left_eye_y: float = 0.0:
    set(v):
        left_eye_y = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var left_eye_z: float = 0.0:
    set(v):
        left_eye_z = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var right_eye_x: float = 0.0:
    set(v):
        right_eye_x = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var right_eye_y: float = 0.0:
    set(v):
        right_eye_y = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var right_eye_z: float = 0.0:
    set(v):
        right_eye_z = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var mouth_x: float = 0.0:
    set(v):
        mouth_x = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var mouth_y: float = 0.0:
    set(v):
        mouth_y = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var mouth_z: float = 0.0:
    set(v):
        mouth_z = v
        _rebuild_mesh()

# Outer face rotation (applied to the whole tetrahedron)
@export_range(-45.0, 45.0, 0.5) var face_x: float = 0.0:
    set(v):
        face_x = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var face_y: float = 0.0:
    set(v):
        face_y = v
        _rebuild_mesh()
@export_range(-45.0, 45.0, 0.5) var face_z: float = 0.0:
    set(v):
        face_z = v
        _rebuild_mesh()

# Movement
@export var mouse_tracking_strength: float = 1.0
@export var smooth_speed: float = 12.0
@export var max_yaw: float = 45.0
@export var max_pitch: float = 25.0

var _shiver_tween: Tween = null

func play_shiver() -> void:
    if _shiver_tween:
        _shiver_tween.kill()
    _shiver_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var steps: int = rng.randi_range(3, 5)
    var amp: float = rng.randf_range(4.0, 9.0)
    var start_y: float = rotation_degrees.y
    for i in steps:
        var shiver_dir: float = 1.0 if i % 2 == 0 else -1.0
        var offset: float = shiver_dir * amp * rng.randf_range(0.6, 1.0)
        var step_time: float = rng.randf_range(0.04, 0.09)
        _shiver_tween.tween_property(self, "rotation_degrees:y", start_y + offset, step_time)
    _shiver_tween.tween_property(self, "rotation_degrees:y", start_y, 0.08)
    
    
var _wiggle_tween: Tween = null

func play_wiggle_y() -> void:
    if _wiggle_tween:
        _wiggle_tween.kill()
    _wiggle_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var steps: int    = rng.randi_range(2, 4)
    var amp:   float  = rng.randf_range(6.0, 14.0)
    var start_x: float = rotation_degrees.x
    for i in steps:
        var wiggle_dir: float = 1.0 if i % 2 == 0 else -1.0
        var offset:     float = wiggle_dir * amp * rng.randf_range(0.5, 1.0)
        var step_time:  float = rng.randf_range(0.10, 0.18)
        _wiggle_tween.tween_property(self, "rotation_degrees:x", start_x + offset, step_time)
    _wiggle_tween.tween_property(self, "rotation_degrees:x", start_x, 0.12)    
   
 
var _tantrum_tween: Tween = null
var _tantrum_active: bool = false

func play_tantrum() -> void:
    if _tantrum_tween:
        _tantrum_tween.kill()
    if _shiver_tween:
        _shiver_tween.kill()

    var rng := RandomNumberGenerator.new()
    rng.randomize()

    var axis_index: int = rng.randi_range(0, 2)
    var axis_property: String = ["rotation_degrees:x", "rotation_degrees:y", "rotation_degrees:z"][axis_index]
    var current_angle: float = [rotation_degrees.x, rotation_degrees.y, rotation_degrees.z][axis_index]
    var spin_dir: float = 1.0 if rng.randi_range(0, 1) == 0 else -1.0
    var rotations: float = rng.randf_range(3.0, 4.0)
    var duration: float = rng.randf_range(1.2, 1.6)
    var target_angle: float = current_angle + (spin_dir * rotations * 360.0)

    _tantrum_active = true
    _tantrum_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
    _tantrum_tween.tween_property(self, axis_property, target_angle, duration)
    _tantrum_tween.tween_callback(func(): _tantrum_active = false)
    

func _ready() -> void:
    _rebuild_mesh()
    
    var line_mat := StandardMaterial3D.new()
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    line_mat.vertex_color_use_as_albedo = true
    set_surface_override_material(0, line_mat)

func _process(delta: float) -> void:
    if Engine.is_editor_hint() or mouse_tracking_strength <= 0:
        return
    if _tantrum_active:
        return
    
    var cam := get_viewport().get_camera_3d()
    if not cam: return
    
    var mouse_pos := get_viewport().get_mouse_position()
    var ray_origin := cam.project_ray_origin(mouse_pos)
    var ray_dir := cam.project_ray_normal(mouse_pos)
    var target_global_pos := ray_origin + (ray_dir * 10.0)
    
    var target_basis := global_transform.looking_at(target_global_pos, Vector3.UP).basis.orthonormalized()
    var current_basis := global_transform.basis.orthonormalized()
    
    global_transform.basis = current_basis.slerp(target_basis, smooth_speed * delta)
    
    var euler := global_transform.basis.get_euler()
    euler.x = clamp(euler.x, -max_pitch * PI/180.0, max_pitch * PI/180.0)
    euler.y = clamp(euler.y, -max_yaw * PI/180.0, max_yaw * PI/180.0)
    euler.z = 0.0
    
    global_transform.basis = Basis.from_euler(euler)

# ─────────────────────────────────────────────────────────────────────────────
# Mesh Construction
# ─────────────────────────────────────────────────────────────────────────────

func _rebuild_mesh() -> void:
    if not is_inside_tree(): return
    
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_LINES)
    
    var geo := _calculate_geometry()
    var v0: Vector3 = geo.v0
    var v1: Vector3 = geo.v1
    var v2: Vector3 = geo.v2
    var v3: Vector3 = geo.v3
    if face_x != 0.0 or face_y != 0.0 or face_z != 0.0:
        var centroid := (v0 + v1 + v2 + v3) / 4.0
        var rot := Basis.from_euler(Vector3(
            deg_to_rad(face_x),
            deg_to_rad(face_y),
            deg_to_rad(face_z)))
        v0 = centroid + rot * (v0 - centroid)
        v1 = centroid + rot * (v1 - centroid)
        v2 = centroid + rot * (v2 - centroid)
        v3 = centroid + rot * (v3 - centroid)
    # Outer large tetrahedron (darker gold)
    _add_tetra_edges(st, v0, v1, v2, v3, geo.front_z, geo.r, false)
    
    # Inner features
    if ability_level >= 1:
        _add_inner_tetra(st, geo)
    
    if ability_level >= 2:
        _add_eyes(st, geo)
    
    mesh = st.commit()

func _calculate_geometry() -> Dictionary:
    var h: float = sqrt(6.0) / 3.0 * size
    var r: float = size / sqrt(3.0)
    var front_z: float = -r / 3.0
    
    return {
        "h": h,
        "r": r,
        "front_z": front_z,
        "v0": Vector3(0, -h/2.0, front_z),
        "v1": Vector3(0, 0, 2.0 * r / 3.0),
        "v2": Vector3(r * sqrt(3.0)/2.0, h/2.0, front_z),
        "v3": Vector3(-r * sqrt(3.0)/2.0, h/2.0, front_z),
        "s_factor": inner_scale,
        "recess": 0.01
    }

func _add_inner_tetra(st: SurfaceTool, geo: Dictionary) -> void:
    var g_factor: float = (1.0 - 2.0 * geo.s_factor) / 3.0
    var i_h: float = geo.h * geo.s_factor
    var i_r: float = geo.r * geo.s_factor

    var m_y: float = geo.v0.y + (geo.h * g_factor)
    var b0 := Vector3(0, m_y, geo.front_z + geo.recess)
    var b1 := b0 + Vector3(0, i_h/3.0, i_r)
    var b2 := b0 + Vector3(i_r * sqrt(3.0)/2.0, i_h, 0)
    var b3 := b0 + Vector3(-i_r * sqrt(3.0)/2.0, i_h, 0)

    if mouth_x != 0.0 or mouth_y != 0.0 or mouth_z != 0.0:
        var centroid := (b0 + b1 + b2 + b3) / 4.0
        var rot := Basis.from_euler(Vector3(
            deg_to_rad(mouth_x),
            deg_to_rad(mouth_y),
            deg_to_rad(mouth_z)
        ))
        b0 = centroid + rot * (b0 - centroid)
        b1 = centroid + rot * (b1 - centroid)
        b2 = centroid + rot * (b2 - centroid)
        b3 = centroid + rot * (b3 - centroid)

    _add_tetra_edges(st, b0, b1, b2, b3, b0.z, i_r, true)

func _add_eyes(st: SurfaceTool, geo: Dictionary) -> void:
    var g_factor: float = (1.0 - 2.0 * geo.s_factor) / 3.0
    var i_h: float = geo.h * geo.s_factor
    var i_r: float = geo.r * geo.s_factor

    var e_y_top: float = geo.v2.y - (geo.h * g_factor)
    var e_y_bot: float = e_y_top - i_h
    var total_w: float = geo.v2.x - geo.v3.x
    var i_w: float = total_w * geo.s_factor
    var i_g: float = (total_w - 2.0 * i_w) / 3.0
    var center_gap: float = i_g * eye_spacing
    var side_margin: float = (total_w - 2.0 * i_w - center_gap) / 2.0

    var eye_positions := [geo.v3.x + side_margin, geo.v3.x + side_margin + i_w + center_gap]
    var eye_rotations := [
        Vector3(deg_to_rad(left_eye_x),  deg_to_rad(left_eye_y),  deg_to_rad(left_eye_z)),
        Vector3(deg_to_rad(right_eye_x), deg_to_rad(right_eye_y), deg_to_rad(right_eye_z)),
    ]

    for i in range(2):
        var ex: float = eye_positions[i]
        var s3 := Vector3(ex,           e_y_top,                   geo.front_z + geo.recess)
        var s2 := Vector3(ex + i_w,     e_y_top,                   geo.front_z + geo.recess)
        var s0 := Vector3(ex + i_w/2.0, e_y_bot,                   geo.front_z + geo.recess)
        var s1 := Vector3(ex + i_w/2.0, (e_y_top + e_y_bot)/2.0,  geo.front_z + geo.recess + i_r)

        var rot_euler: Vector3 = eye_rotations[i]
        if rot_euler != Vector3.ZERO:
            var centroid := (s0 + s1 + s2 + s3) / 4.0
            var rot := Basis.from_euler(rot_euler)
            s0 = centroid + rot * (s0 - centroid)
            s1 = centroid + rot * (s1 - centroid)
            s2 = centroid + rot * (s2 - centroid)
            s3 = centroid + rot * (s3 - centroid)

        _add_tetra_edges(st, s0, s1, s2, s3, s3.z, i_r, true)

# ─────────────────────────────────────────────────────────────────────────────
# Drawing Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _add_tetra_edges(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, 
                     fz: float, td: float, is_inner: bool = false) -> void:
    var pairs := [[a, b], [a, c], [a, d], [b, c], [b, d], [c, d]]
    for pair in pairs:
        for v in pair:
            st.set_color(_get_dimmed_color(v, fz, td, is_inner))
            st.add_vertex(v)

func _get_dimmed_color(pos: Vector3, l_fz: float, l_td: float, is_inner: bool = false) -> Color:
    var depth_t: float = (pos.z - l_fz) / l_td
    var brightness: float = 1.0
    
    # 95% dimming (your current preference)
    if depth_t > 0.25:
        var dim_factor: float = (depth_t - 0.25) / 0.75
        brightness = 1.0 - (dim_factor * 0.95)
    
    # Boost inner front edges
    if is_inner:
        brightness *= inner_front_boost
    
    return Color(line_color.r * brightness, line_color.g * brightness, line_color.b * brightness, line_color.a)


# ─────────────────────────────────────────────────────────────────────────────
# Expression API
# ─────────────────────────────────────────────────────────────────────────────

# Expression data: each entry is { property: target_value, ... }
# All unlisted properties are implicitly 0.0 (neutral).
const EXPRESSIONS: Dictionary = {
    "spock_right": {
        "left_eye_z": 18.0,    # positive = CCW tilt as seen by viewer on Kaleb's right eye
        "left_eye_x": -6.0,    # slight forward nod for depth read
    },
}

var _expr_tween: Tween = null

func play_expression(expr_name: String, hold_duration: float = 1.2) -> void:
    if not EXPRESSIONS.has(expr_name):
        push_warning("ArchonTetrahedron: unknown expression '%s'" % expr_name)
        return

    if _expr_tween:
        _expr_tween.kill()

    const MOVE_IN:  float = 0.18
    const MOVE_OUT: float = 0.28

    var targets: Dictionary = EXPRESSIONS[expr_name]

    _expr_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

    # ── Phase 1: animate to expression pose ──
    for prop in targets:
        _expr_tween.parallel().tween_property(self, prop, targets[prop], MOVE_IN)

    # ── Phase 2: hold ──
    _expr_tween.tween_interval(hold_duration)

    # ── Phase 3: return to neutral — must use tween_property, not parallel(),
    #    so each return step is sequenced AFTER the interval completes ──
    var first := true
    for prop in targets:
        if first:
            _expr_tween.tween_property(self, prop, 0.0, MOVE_OUT)
            first = false
        else:
            _expr_tween.parallel().tween_property(self, prop, 0.0, MOVE_OUT)


func reset_to_neutral(duration: float = 0.5) -> void:
    if _expr_tween:
        _expr_tween.kill()
    
    var props := ["left_eye_x",  "left_eye_y",  "left_eye_z",
                  "right_eye_x", "right_eye_y", "right_eye_z",
                  "mouth_x",     "mouth_y",     "mouth_z",
                  "face_x",      "face_y",      "face_z"]

    var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    for prop in props:
        t.parallel().tween_property(self, prop, 0.0, duration)


func placeh_express() -> void:
    if _expr_tween:
        _expr_tween.kill()
    # Disable mouse tracking for duration of expression
    var saved_tracking := mouse_tracking_strength
    mouse_tracking_strength = 0.0
    global_transform.basis = Basis.IDENTITY
    const MOVE_IN:  float = 0.18
    const MOVE_OUT: float = 0.28
    _expr_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    # ── EDIT VALUES BELOW (0.0 = neutral) ──
    # Eyes: X=nod, Y=turn, Z=tilt
    _expr_tween.parallel().tween_property(self, "left_eye_x",   15.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "left_eye_y",   20.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "left_eye_z",   0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_x",  15.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_y",  20.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_z", 0.0, MOVE_IN)
    # Mouth: X=nod, Y=turn, Z=tilt
    _expr_tween.parallel().tween_property(self, "mouth_x",    10.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "mouth_y",      15.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "mouth_z",      0.0, MOVE_IN)
    # Face: X=nod, Y=turn, Z=tilt
    _expr_tween.parallel().tween_property(self, "face_x",      10.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "face_y",      15.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "face_z",      0.0, MOVE_IN)
    # ── EDIT VALUES ABOVE ──
    _expr_tween.tween_interval(3.0)
    var first := true
    for prop in ["left_eye_x", "left_eye_y", "left_eye_z", "right_eye_x", "right_eye_y", "right_eye_z", "mouth_x", "mouth_y", "mouth_z", "face_x", "face_y", "face_z"]:
        if first:
            _expr_tween.tween_property(self, prop, 0.0, MOVE_OUT)
            first = false
        else:
            _expr_tween.parallel().tween_property(self, prop, 0.0, MOVE_OUT)
    _expr_tween.finished.connect(func():
        mouse_tracking_strength = saved_tracking
    , CONNECT_ONE_SHOT)


func glare_express() -> void:
    if _expr_tween:
        _expr_tween.kill()
    var saved_tracking := mouse_tracking_strength
    mouse_tracking_strength = 0.0
    global_transform.basis = Basis.IDENTITY
    const MOVE_IN:  float = 0.18
    const MOVE_OUT: float = 0.28
    _expr_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _expr_tween.parallel().tween_property(self, "left_eye_x",   0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "left_eye_y",   0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "left_eye_z",  -16.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_x",  0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_y",  0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "right_eye_z", 16.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "mouth_x",    -35.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "mouth_y",      0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "mouth_z",      0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "face_x",      0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "face_y",      0.0, MOVE_IN)
    _expr_tween.parallel().tween_property(self, "face_z",      0.0, MOVE_IN)
    _expr_tween.tween_interval(3.0)
    var first := true
    for prop in ["left_eye_x", "left_eye_y", "left_eye_z", "right_eye_x", "right_eye_y", "right_eye_z", "mouth_x", "mouth_y", "mouth_z", "face_x", "face_y", "face_z"]:
        if first:
            _expr_tween.tween_property(self, prop, 0.0, MOVE_OUT)
            first = false
        else:
            _expr_tween.parallel().tween_property(self, prop, 0.0, MOVE_OUT)
    _expr_tween.finished.connect(func():
        mouse_tracking_strength = saved_tracking
    , CONNECT_ONE_SHOT)
