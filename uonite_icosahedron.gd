@tool
extends MeshInstance3D
# UONITE ICOSAHEDRON — outer wireframe + per-Mote wireframe detail
#
# A Uonite is 20 Motes (see planned_uonite_vs_grain_prestige_tracks memory);
# each of the icosahedron's 20 faces stands for one of those Motes, revealed
# as it's actually assembled. Each revealed face used to fill with a flat,
# solid three-color tetrahedron (a placeholder from before the Assembly
# narrative existed); now it shows the real thing instead -- a wireframe
# copy of ArchaiLatticeGeometry's tier-4 (Mote) lattice, fitted into that
# face's tetrahedral slot, showing the actual Mote/Iota/Particle/Tetrad
# nesting down to individual Monads. Straight lines only for now (no
# sine-wave agitation, no per-frame rebuild) -- see archai_lattice.gd for
# that mode if/when this display grows into it.

# preload, NOT a bare global `ArchaiLatticeGeometry.foo()` reference --
# confirmed directly (2026-09-06) that the bare class_name reference makes
# THIS script fail to compile (can_instantiate() == false, no visible error)
# whenever the project's global-script-class cache hasn't been refreshed
# since archai_lattice_geometry.gd was added, which a plain `--headless
# --script` run does NOT reliably do on its own. preload() sidesteps that
# cache entirely and always resolves.
const ArchaiLatticeGeometry := preload("res://archai_lattice_geometry.gd")

const KIND_SPARK := ArchaiLatticeGeometry.KIND_SPARK
const KIND_SOLID  := 1
const KIND_LIQUID := 2
const KIND_GAS    := 3

# Same default palette as archai_lattice.gd, so the always-on Uonite display
# and the study-overlay viewer read as the same visual language.
const COLOR_SPARK  := Color(1.00, 0.97, 0.80)
const COLOR_SOLID  := Color(0.80, 0.53, 0.40)
const COLOR_LIQUID := Color(0.27, 0.55, 0.85)
const COLOR_GAS    := Color(0.63, 0.50, 0.85)

## Fixed seed: the 20 revealed Motes all show the same S/L/G typing rather
## than reshuffling on every rebuild (each _set_motes call), which would
## otherwise flicker the whole display's coloring every time the count ticks.
const MOTE_TYPE_SEED := 1

@export var radius: float = 1.0
@export var rotation_speed: float = 0.8
@export var line_color: Color = Color(0.8, 0.6, 0.1, 1.0)
## How many of the 20 Motes making up this Uonite have been assembled so
## far -- was named current_grains before the Assembly-narrative rework;
## renamed since it only ever counted Motes, never Grains.
@export var current_motes: int = 0: set = _set_motes

var time: float = 0.0
var verts: PackedVector3Array

func _ready() -> void:
    _generate_icosahedron()

func _process(delta: float) -> void:
    time += delta
    rotation.y = time * rotation_speed

func _set_motes(value: int) -> void:
    current_motes = clamp(value, 0, 20)
    _generate_icosahedron()


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

    # Per-Mote wireframe detail
    var num_to_show := mini(current_motes, 20)

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

    if num_to_show > 0:
        var mote_lines: Dictionary = _build_mote_lines(num_to_show, face_list, center)
        var mote_verts: PackedVector3Array = mote_lines["verts"]
        var mote_colors: PackedColorArray = mote_lines["colors"]
        if not mote_verts.is_empty():
            var mote_arrays := []
            mote_arrays.resize(Mesh.ARRAY_MAX)
            mote_arrays[Mesh.ARRAY_VERTEX] = mote_verts
            mote_arrays[Mesh.ARRAY_COLOR]  = mote_colors
            mesh_array.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, mote_arrays)

    mesh = mesh_array

    # Materials
    var line_mat := StandardMaterial3D.new()
    line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    line_mat.albedo_color = line_color
    set_surface_override_material(0, line_mat)

    if mesh.get_surface_count() > 1:
        var mote_mat := StandardMaterial3D.new()
        mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mote_mat.vertex_color_use_as_albedo = true
        set_surface_override_material(1, mote_mat)


## Builds one full tier-4 (Mote) lattice from ArchaiLatticeGeometry, assigns
## S/L/G types once (stable across rebuilds via MOTE_TYPE_SEED), then stamps
## a fitted copy of it into each of `count` face slots by an exact affine
## map from the lattice's own reference tetrahedron onto that face's real
## (v0, v1, v2, center) tetrahedron. That target tetrahedron is NOT regular
## (the 3 center-to-vertex edges are the icosahedron's circumradius, the 3
## face edges are its edge length -- different in general), so the map
## carries some shear/non-uniform scale; the nested structure still reads
## clearly since the map is exact at all 4 corners, not an approximation.
## Returns {"verts": PackedVector3Array, "colors": PackedColorArray} rather
## than mutating parameters -- Packed*Array args are copy-on-write value
## types in GDScript, not references like Array/Dictionary, so writing
## through a parameter would only ever mutate a local copy.
func _build_mote_lines(count: int, face_list: Array, center: Vector3) -> Dictionary:
    var out_verts := PackedVector3Array()
    var out_colors := PackedColorArray()

    var base: Dictionary = ArchaiLatticeGeometry.build_tier(4)
    var base_pos: Array = base["pos"]
    var base_kind: Array = base["kind"]
    var base_edges: Array = base["edges"]

    var resolved_kind := PackedInt32Array()
    resolved_kind.resize(base_kind.size())
    var rng := RandomNumberGenerator.new()
    rng.seed = MOTE_TYPE_SEED
    for i in base_kind.size():
        if int(base_kind[i]) == KIND_SPARK:
            resolved_kind[i] = KIND_SPARK
        else:
            resolved_kind[i] = KIND_SOLID + rng.randi_range(0, 2)

    # build_tier(4)'s OWN outer corners sit at tetra_corners(pow(2.0, 3)) --
    # edge length 8, not 1 (its recursion scales big_edge = 2^(tier-1)
    # internally) -- using edge 1 here silently scaled the whole mapped
    # lattice 8x too large (caught by direct verification, not assumed).
    # tetra_corners always puts its first corner at the origin (documented
    # invariant), relied on below rather than re-derived.
    var ref_corners: Array = ArchaiLatticeGeometry.tetra_corners(pow(2.0, 3.0))
    var r1: Vector3 = ref_corners[1]
    var r2: Vector3 = ref_corners[2]
    var r3: Vector3 = ref_corners[3]
    var ref_basis_inv: Basis = Basis(r1, r2, r3).inverse()

    for i in count:
        var f: PackedInt32Array = face_list[i]
        var v0: Vector3 = verts[f[0]]
        var v1: Vector3 = verts[f[1]]
        var v2: Vector3 = verts[f[2]]

        var target_basis := Basis(v1 - v0, v2 - v0, center - v0)
        var m: Basis = target_basis * ref_basis_inv

        for e in base_edges:
            var a: int = (e as Vector2i).x
            var b: int = (e as Vector2i).y
            var pa: Vector3 = v0 + m * (base_pos[a] as Vector3)
            var pb: Vector3 = v0 + m * (base_pos[b] as Vector3)
            out_verts.append(pa)
            out_colors.append(_kind_color(resolved_kind[a]))
            out_verts.append(pb)
            out_colors.append(_kind_color(resolved_kind[b]))

    return {"verts": out_verts, "colors": out_colors}


func _kind_color(k: int) -> Color:
    match k:
        KIND_SPARK:  return COLOR_SPARK
        KIND_SOLID:  return COLOR_SOLID
        KIND_LIQUID: return COLOR_LIQUID
        _:           return COLOR_GAS
