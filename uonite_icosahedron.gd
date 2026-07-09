@tool
extends MeshInstance3D
# UONITE ICOSAHEDRON — Working wireframe + filled tetras

@export var radius: float = 1.0
@export var rotation_speed: float = 0.8
@export var line_color: Color = Color(0.8, 0.6, 0.1, 1.0)
@export var current_grains: int = 0: set = _set_grains

var time: float = 0.0
var verts: PackedVector3Array

func _ready() -> void:
    _generate_icosahedron()

func _process(delta: float) -> void:
    time += delta
    rotation.y = time * rotation_speed

func _set_grains(value: int) -> void:
    current_grains = clamp(value, 0, 20)
    _generate_icosahedron()
    
    
func _add_inner_face(fill: PackedVector3Array, 
        c: Vector3, a: Vector3, b: Vector3, opposite: Vector3) -> PackedVector3Array:
    # Wind center-a-b so normal faces away from `opposite`
    var normal = (a - c).cross(b - c)
    if normal.dot(opposite - c) > 0.0:
        fill.append(c); fill.append(b); fill.append(a)
    else:
        fill.append(c); fill.append(a); fill.append(b)
    return fill

func _generate_icosahedron() -> void:
    if not is_inside_tree():
        return

    var mesh_array := ArrayMesh.new()

    var PHI := (1.0 + sqrt(5.0)) / 2.0
    var s := radius / sqrt(1.0 + PHI * PHI)

    verts = PackedVector3Array([
        Vector3(0,  1,  PHI) * s, Vector3(0,  1, -PHI) * s,
        Vector3(0, -1,  PHI) * s, Vector3(0, -1, -PHI) * s,
        Vector3(1,  PHI, 0) * s,  Vector3(1, -PHI, 0) * s,
        Vector3(-1, PHI, 0) * s,  Vector3(-1, -PHI, 0) * s,
        Vector3(PHI, 0,  1) * s,  Vector3(PHI, 0, -1) * s,
        Vector3(-PHI, 0,  1) * s, Vector3(-PHI, 0, -1) * s
    ])

    # Rotate so one vertex is at the top
    var top_dir := verts[0].normalized()
    var angle := -atan2(top_dir.z, top_dir.y)
    var rotation_basis := Basis.from_euler(Vector3(angle, 0, 0))
    for i in verts.size():
        verts[i] = rotation_basis * verts[i]

    var center := Vector3.ZERO
    var all_vertices := verts.duplicate()
    all_vertices.append(center)

    # Wireframe
    var line_indices := PackedInt32Array()

    # Outer edges (simplified from your working version)
    var outer_edges := PackedInt32Array([
        0,2, 0,4, 0,6, 0,8, 0,10,
        1,3, 1,4, 1,6, 1,9, 1,11,
        2,5, 2,7, 2,8, 2,10,
        3,5, 3,7, 3,9, 3,11,
        4,6, 4,8, 4,9,
        5,7, 5,8, 5,9,
        6,10, 6,11,
        7,10, 7,11,
        8,9, 10,11
    ])
    line_indices.append_array(outer_edges)

    # Radial spokes
    for i in 12:
        line_indices.append(i)
        line_indices.append(12)

    var line_arrays := []
    line_arrays.resize(Mesh.ARRAY_MAX)
    line_arrays[Mesh.ARRAY_VERTEX] = all_vertices
    line_arrays[Mesh.ARRAY_INDEX] = line_indices
    mesh_array.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)

    # Filled tetras
    var fill_verts := PackedVector3Array()
    var num_to_show := mini(current_grains, 20)

    # Correct 20 faces
    var face_list := [
        PackedInt32Array([0,2,8]),  PackedInt32Array([0,2,10]),
        PackedInt32Array([0,4,6]),  PackedInt32Array([0,4,8]),
        PackedInt32Array([0,6,10]), PackedInt32Array([1,3,9]),
        PackedInt32Array([1,3,11]), PackedInt32Array([1,4,6]),
        PackedInt32Array([1,4,9]),  PackedInt32Array([1,6,11]),
        PackedInt32Array([2,5,7]),  PackedInt32Array([2,5,8]),
        PackedInt32Array([2,7,10]), PackedInt32Array([3,5,7]),
        PackedInt32Array([3,5,9]),  PackedInt32Array([3,7,11]),
        PackedInt32Array([4,8,9]),  PackedInt32Array([5,8,9]),
        PackedInt32Array([6,10,11]),PackedInt32Array([7,10,11]),
    ]

    for i in num_to_show:
        var f: PackedInt32Array = face_list[i]
        var v0: Vector3 = verts[f[0]]
        var v1: Vector3 = verts[f[1]]
        var v2: Vector3 = verts[f[2]]

        # Outer face — wind so normal points AWAY from center (outward)
        var face_center = (v0 + v1 + v2) / 3.0
        var normal = (v1 - v0).cross(v2 - v0)
        if normal.dot(face_center) < 0.0:
            fill_verts.append(v0); fill_verts.append(v2); fill_verts.append(v1)
        else:
            fill_verts.append(v0); fill_verts.append(v1); fill_verts.append(v2)

        # Inner faces — wind so normals point TOWARD center (inward faces of tetra)
        # Each inner face: center + two verts. Normal should face away from the opposite vert.
        fill_verts = _add_inner_face(fill_verts, center, v0, v1, v2)
        fill_verts = _add_inner_face(fill_verts, center, v1, v2, v0)
        fill_verts = _add_inner_face(fill_verts, center, v2, v0, v1)

    if not fill_verts.is_empty():
        var fill_arrays := []
        fill_arrays.resize(Mesh.ARRAY_MAX)
        fill_arrays[Mesh.ARRAY_VERTEX] = fill_verts
        mesh_array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fill_arrays)

    mesh = mesh_array

    # Materials
    var line_mat := StandardMaterial3D.new()
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    line_mat.albedo_color = line_color
    set_surface_override_material(0, line_mat)

    var fill_mat := ShaderMaterial.new()
    fill_mat.shader = preload("res://uonite_fill.gdshader")
    fill_mat.render_priority = 1
    # fill_mat.set_shader_parameter("purple_size", 1.0)
    # fill_mat.set_shader_parameter("green_size", 0.0)
    # fill_mat.set_shader_parameter("transition_width", 0.0)
    fill_mat.set_shader_parameter("purple_size", 0.28)
    fill_mat.set_shader_parameter("green_size", 0.27)
    fill_mat.set_shader_parameter("transition_width", 0.02)
    fill_mat.set_shader_parameter("sharpness", 3.0)

    if mesh.get_surface_count() > 1:
        set_surface_override_material(1, fill_mat)
