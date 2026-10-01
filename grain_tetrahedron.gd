@tool
extends MeshInstance3D
# GRAIN TETRAHEDRON — outer wireframe + per-Mote wireframe detail
#
# The Grain-branch counterpart of uonite_icosahedron.gd (2026-10-01), built
# the same way: a wireframe host solid whose faces reveal progressively as
# Motes are assembled, each revealed face stamped with a real wireframe
# copy of ArchaiLatticeGeometry's tier-4 (Mote) lattice. The host solid is
# a tetrahedron (4 faces) rather than an icosahedron (20), matching
# grain_assemble's own recipe cost of GRAIN_MOTES_PER_UNIT = 4 mote_grains
# per Grain (game_context.gd) -- one face per Mote, exactly as the
# icosahedron's 20 faces match Uonite's 20-mote_uonite cost.
#
# Deliberately a SEPARATE file from uonite_icosahedron.gd rather than a
# shared base class -- this project's own convention for parallel Will/Form
# branch logic is parallel, independently-named implementations (see
# production_manager.gd's _assemble_iota_grains_* vs the Uonite-branch
# equivalents), not a shared abstraction layered over a single working,
# already-shipped display.

@warning_ignore("shadowed_global_identifier")
const ArchaiLatticeGeometry := preload("res://archai_lattice_geometry.gd")

const KIND_SPARK := ArchaiLatticeGeometry.KIND_SPARK
const KIND_SOLID  := 1
const KIND_LIQUID := 2
const KIND_GAS    := 3

# Same default palette as uonite_icosahedron.gd / archai_lattice.gd, so
# every lattice display in the game reads as the same visual language.
const COLOR_SPARK  := Color(1.00, 0.97, 0.80)
const COLOR_SOLID  := Color(0.80, 0.53, 0.40)
const COLOR_LIQUID := Color(0.27, 0.55, 0.85)
const COLOR_GAS    := Color(0.63, 0.50, 0.85)

## Fixed seed: the revealed Motes all show the same S/L/G typing rather
## than reshuffling on every rebuild, which would otherwise flicker the
## whole display's coloring every time the count ticks.
const MOTE_TYPE_SEED := 1

## How many of this tetrahedron's 4 faces are actually drawn -- a
## grain_assemble costs exactly GRAIN_MOTES_PER_UNIT (4) mote_grains, one
## face per Mote, same "one face per Mote" convention as the icosahedron.
const MAX_MOTES := 4

@export var radius: float = 1.0
@export var rotation_speed: float = 0.8
@export var line_color: Color = Color(0.8, 0.6, 0.1, 1.0)
## How many of the 4 Motes making up this Grain have been assembled so far.
@export var current_motes: int = 0: set = _set_motes

var time: float = 0.0
var verts: PackedVector3Array

# ==================================================
# COMPLETION DIM -- same technique as uonite_icosahedron.gd's
# play_completion_dim(): a brief dim-to-black-and-back played when a Grain
# completes, multiplying into the materials' own colors per frame rather
# than rebuilding mesh geometry.
const DIM_OUT_DURATION: float = 0.25
const DIM_IN_DURATION:  float = 0.35
var _dim: float = 1.0
var _dim_tween: Tween = null
var _line_mat: StandardMaterial3D = null
var _mote_mat: StandardMaterial3D = null

func _ready() -> void:
    _generate_tetrahedron()

func _process(delta: float) -> void:
    time += delta
    rotation.y = time * rotation_speed
    if _line_mat:
        _line_mat.albedo_color = Color(line_color.r * _dim, line_color.g * _dim, line_color.b * _dim, line_color.a)
    if _mote_mat:
        _mote_mat.albedo_color = Color(_dim, _dim, _dim, 1.0)


## Called externally (root_ui.gd, on a detected Grain completion) -- dims
## the whole display to black and back up. Safe to call while a previous
## dim is still running: kills and restarts from wherever the tween
## currently is, rather than queuing or fighting over _dim.
func play_completion_dim() -> void:
    if _dim_tween:
        _dim_tween.kill()
    _dim_tween = create_tween()
    _dim_tween.tween_property(self, "_dim", 0.0, DIM_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    _dim_tween.tween_property(self, "_dim", 1.0, DIM_IN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_motes(value: int) -> void:
    current_motes = clamp(value, 0, MAX_MOTES)
    _generate_tetrahedron()


func _generate_tetrahedron() -> void:
    if not is_inside_tree():
        return

    var mesh_array := ArrayMesh.new()

    # A regular tetrahedron's circumradius is edge * sqrt(6)/4 -- solve for
    # the edge length that gives the requested circumradius (`radius`,
    # same meaning as the icosahedron's own export), then center the
    # corners on the origin (tetra_corners() itself puts its first corner
    # AT the origin, not centered, which is right for the Mote-lattice
    # reference frame it also builds below but wrong for a display that
    # needs to rotate in place).
    var edge: float = radius / (sqrt(6.0) / 4.0)
    var raw_corners: Array = ArchaiLatticeGeometry.tetra_corners(edge)
    var centroid := Vector3.ZERO
    for c in raw_corners:
        centroid += c as Vector3
    centroid /= 4.0

    verts = PackedVector3Array()
    for c in raw_corners:
        verts.append((c as Vector3) - centroid)

    # Rotate so one vertex points straight up, same convention as
    # uonite_icosahedron.gd's own top-alignment.
    var top_dir := verts[0].normalized()
    var angle := -atan2(top_dir.z, top_dir.y)
    var rotation_basis := Basis.from_euler(Vector3(angle, 0, 0))
    for i in verts.size():
        verts[i] = rotation_basis * verts[i]

    var center := Vector3.ZERO
    var all_vertices := verts.duplicate()
    all_vertices.append(center)

    # Wireframe: every vertex pair is an edge (a tetrahedron is fully
    # connected), plus a radial spoke from each vertex to the center --
    # same "outer edges + spokes" shape as the icosahedron's wireframe.
    var line_indices := PackedInt32Array([
        0,1, 0,2, 0,3, 1,2, 1,3, 2,3,
    ])
    for i in 4:
        line_indices.append(i)
        line_indices.append(4)

    var line_arrays := []
    line_arrays.resize(Mesh.ARRAY_MAX)
    line_arrays[Mesh.ARRAY_VERTEX] = all_vertices
    line_arrays[Mesh.ARRAY_INDEX] = line_indices
    mesh_array.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)

    # Per-Mote wireframe detail
    var num_to_show := mini(current_motes, MAX_MOTES)

    var face_list := [
        PackedInt32Array([0,1,2]), PackedInt32Array([0,1,3]),
        PackedInt32Array([0,2,3]), PackedInt32Array([1,2,3]),
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

    # Materials -- cached and reused (not recreated each rebuild) so
    # play_completion_dim()'s per-frame _dim multiply in _process() keeps
    # affecting whatever's actually applied, across every Mote-count change.
    if _line_mat == null:
        _line_mat = StandardMaterial3D.new()
        _line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    set_surface_override_material(0, _line_mat)

    if mesh.get_surface_count() > 1:
        if _mote_mat == null:
            _mote_mat = StandardMaterial3D.new()
            _mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            _mote_mat.vertex_color_use_as_albedo = true
        set_surface_override_material(1, _mote_mat)


## Cache for the tier-4 (Mote) lattice + its resolved S/L/G typing + the
## reference-tetrahedron basis inverse -- all invariant, computed once per
## instance. Identical in spirit to uonite_icosahedron.gd's own cache; see
## that file's comment for why this matters (avoids rebuilding the full
## build_tier(4) recursion on every Mote-count tick).
var _mote_cache_ready: bool = false
var _mote_cache_pos: Array = []
var _mote_cache_edges: Array = []
var _mote_cache_kind: PackedInt32Array = PackedInt32Array()
var _mote_cache_ref_basis_inv: Basis = Basis()

func _ensure_mote_lattice_cache() -> void:
    if _mote_cache_ready:
        return

    var base: Dictionary = ArchaiLatticeGeometry.build_tier(4)
    _mote_cache_pos = base["pos"]
    var base_kind: Array = base["kind"]
    _mote_cache_edges = base["edges"]

    _mote_cache_kind.resize(base_kind.size())
    var rng := RandomNumberGenerator.new()
    rng.seed = MOTE_TYPE_SEED
    for i in base_kind.size():
        if int(base_kind[i]) == KIND_SPARK:
            _mote_cache_kind[i] = KIND_SPARK
        else:
            _mote_cache_kind[i] = KIND_SOLID + rng.randi_range(0, 2)

    # build_tier(4)'s OWN outer corners sit at tetra_corners(pow(2.0, 3)) --
    # edge length 8, not 1 -- see uonite_icosahedron.gd's identical comment
    # for the direct verification behind this.
    var ref_corners: Array = ArchaiLatticeGeometry.tetra_corners(pow(2.0, 3.0))
    _mote_cache_ref_basis_inv = Basis(ref_corners[1], ref_corners[2], ref_corners[3]).inverse()

    _mote_cache_ready = true


## Stamps a fitted copy of the cached tier-4 (Mote) lattice into each of
## `count` face slots -- identical technique to
## uonite_icosahedron.gd's _build_mote_lines(), see that file's comment for
## the full derivation (exact affine map from the lattice's own reference
## tetrahedron onto each face's real (v0, v1, v2, center) tetrahedron).
func _build_mote_lines(count: int, face_list: Array, center: Vector3) -> Dictionary:
    _ensure_mote_lattice_cache()

    var out_verts := PackedVector3Array()
    var out_colors := PackedColorArray()

    for i in count:
        var f: PackedInt32Array = face_list[i]
        var v0: Vector3 = verts[f[0]]
        var v1: Vector3 = verts[f[1]]
        var v2: Vector3 = verts[f[2]]

        var target_basis := Basis(v1 - v0, v2 - v0, center - v0)
        var m: Basis = target_basis * _mote_cache_ref_basis_inv

        for e in _mote_cache_edges:
            var a: int = (e as Vector2i).x
            var b: int = (e as Vector2i).y
            var pa: Vector3 = v0 + m * (_mote_cache_pos[a] as Vector3)
            var pb: Vector3 = v0 + m * (_mote_cache_pos[b] as Vector3)
            out_verts.append(pa)
            out_colors.append(_kind_color(_mote_cache_kind[a]))
            out_verts.append(pb)
            out_colors.append(_kind_color(_mote_cache_kind[b]))

    return {"verts": out_verts, "colors": out_colors}


func _kind_color(k: int) -> Color:
    match k:
        KIND_SPARK:  return COLOR_SPARK
        KIND_SOLID:  return COLOR_SOLID
        KIND_LIQUID: return COLOR_LIQUID
        _:           return COLOR_GAS
