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
# nesting down to individual Monads.
#
# animate_motes (added 2026-09-11): a straight CPU port of archai_lattice.gd's
# sine-wave agitation, NOT a shader -- deliberately, per the user's own
# "test it out first, measure it" call, since a naive per-frame full-mesh
# rebuild across up to 20 SIMULTANEOUS Mote lattices (archai_lattice.gd only
# ever shows one) is a real risk of reproducing the exact per-frame hitch
# fixed earlier this session. One optimization is already folded in even at
# this "straight port" stage, since it costs nothing extra to get right:
# the expensive trig-heavy deform step runs ONCE per frame (on one cached
# lattice's worth of curve points), and its result is then just
# affine-transformed into each shown slot -- not re-deformed per slot,
# since the underlying wave math is identical for all of them. If this
# still hitches, the next step is the GPU vertex-shader version discussed
# but not built (bake wave params as vertex data once, animate on the GPU,
# zero per-frame CPU rebuild).

# preload, NOT a bare global `ArchaiLatticeGeometry.foo()` reference --
# confirmed directly (2026-09-06) that the bare class_name reference makes
# THIS script fail to compile (can_instantiate() == false, no visible error)
# whenever the project's global-script-class cache hasn't been refreshed
# since archai_lattice_geometry.gd was added, which a plain `--headless
# --script` run does NOT reliably do on its own. preload() sidesteps that
# cache entirely and always resolves. Deliberately reuses the class's own
# name so every existing ArchaiLatticeGeometry.foo() call site keeps
# working unchanged -- the SHADOWED_GLOBAL_IDENTIFIER warning this trips is
# the intended effect (shadow the flaky global lookup with a reliable
# local one), not a mistake.
@warning_ignore("shadowed_global_identifier")
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

# Same agitation-level convention as archai_lattice.gd (Spark 25%, Solid
# 50%, Liquid 75%, Gas 100% of full wave amplitude/speed).
const LEVEL_SPARK  := 0.25
const LEVEL_SOLID  := 0.50
const LEVEL_LIQUID := 0.75
const LEVEL_GAS    := 1.00

# Wave tuning -- same shape as archai_lattice.gd's defaults, but
# MOTE_WAVE_SEGMENTS is deliberately half its 32 default: this display can
# show up to 20 lattices at once (archai_lattice.gd only ever shows one),
# so per-lattice point count matters 20x as much here.
const MOTE_WAVE_AMPLITUDE  := 0.09
const MOTE_WAVES_PER_EDGE  := 2.5
const MOTE_WAVE_SPEED      := 0.9
const MOTE_WAVE_SEGMENTS   := 16

# The 20 icosahedron faces, one per possible shown Mote. Hoisted to a
# top-level const (was a local literal rebuilt every _generate_icosahedron()
# call) since animate_motes's per-frame path needs it too and it never
# actually varies. Plain int-literal sub-arrays, NOT PackedInt32Array(...)
# constructor calls -- confirmed directly that GDScript's const-folding
# rejects a const array whose elements are constructor calls (parse error
# 43, no message text), even though the identical PackedInt32Array(...)
# literals are fine as a local var inside a function.
const FACE_LIST := [
    [0,2,8],   [0,2,10],
    [0,4,6],   [0,4,8],
    [0,6,10],  [1,3,9],
    [1,3,11],  [1,4,6],
    [1,4,9],   [1,6,11],
    [2,5,7],   [2,5,8],
    [2,7,10],  [3,5,7],
    [3,5,9],   [3,7,11],
    [4,8,9],   [5,8,9],
    [6,10,11], [7,10,11],
]

@export var radius: float = 1.0
@export var rotation_speed: float = 0.8
@export var line_color: Color = Color(0.8, 0.6, 0.1, 1.0)
## Sine-wave agitation on the Mote-detail wireframe, ported from
## archai_lattice.gd. Off (the shipped default) falls back to the cheap
## static straight-line render (_build_mote_lines()). Measured directly
## (2026-09-11): _update_mote_deform() costs ~10ms/frame regardless of how
## many Motes are shown (1 through 20 all measured about the same) -- the
## bottleneck is the shared ~13,000-point sine-deform loop itself in
## GDScript's interpreted per-element loop, not the per-slot replication.
## That's ~60% of a 60fps frame's entire budget for this one step alone,
## before the mesh re-upload on top -- too expensive to ship on by default.
## Left in as an explicit opt-in toggle for testing/further work (a GPU
## vertex-shader version, discussed but not built, is the likely next step
## if this gets revisited).
@export var animate_motes: bool = false
## How many of the 20 Motes making up this Uonite have been assembled so
## far -- was named current_grains before the Assembly-narrative rework;
## renamed since it only ever counted Motes, never Grains.
@export var current_motes: int = 0: set = _set_motes

var time: float = 0.0
var verts: PackedVector3Array

var _mesh: ArrayMesh = null
var _outer_line_arrays: Array = []
var _mote_shown_count: int = 0

func _ready() -> void:
    _generate_icosahedron()

func _process(delta: float) -> void:
    time += delta
    rotation.y = time * rotation_speed
    if animate_motes and _mote_shown_count > 0:
        _rebuild_surfaces()

func _set_motes(value: int) -> void:
    current_motes = clamp(value, 0, 20)
    _generate_icosahedron()


## Rebuilds everything that depends on `radius`/`current_motes` -- the
## icosahedron's own vertex positions, the static outer-wireframe arrays,
## and (if any Motes are shown) the per-slot affine transforms + replicated
## color/index buffers. Does NOT touch animation time -- _process() drives
## that separately by calling _rebuild_surfaces() every frame while
## animate_motes is on, reusing everything cached here unchanged.
func _generate_icosahedron() -> void:
    if not is_inside_tree():
        return

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

    var all_vertices := verts.duplicate()
    all_vertices.append(Vector3.ZERO)

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

    _outer_line_arrays = []
    _outer_line_arrays.resize(Mesh.ARRAY_MAX)
    _outer_line_arrays[Mesh.ARRAY_VERTEX] = all_vertices
    _outer_line_arrays[Mesh.ARRAY_INDEX] = line_indices

    _mote_shown_count = mini(current_motes, 20)
    if _mote_shown_count > 0:
        _ensure_mote_lattice_cache()
        _rebuild_mote_slot_data(_mote_shown_count)

    _rebuild_surfaces()

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


## Assembles and uploads both surfaces from whatever's currently cached --
## the static outer wireframe (_outer_line_arrays, unchanged since the last
## _generate_icosahedron()) plus the Mote-detail surface, either the cheap
## static straight-line build (_build_mote_lines(), animate_motes off) or a
## freshly deformed animated one (_update_mote_deform(), animate_motes on).
## Reuses one persistent ArrayMesh (clear_surfaces() + re-add) rather than
## allocating a new one each call -- matches archai_lattice.gd's own
## _upload() pattern, and means materials (set once in
## _generate_icosahedron(), never here) stay attached across every
## per-frame animated rebuild.
func _rebuild_surfaces() -> void:
    if _mesh == null:
        _mesh = ArrayMesh.new()
        mesh = _mesh

    _mesh.clear_surfaces()
    _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, _outer_line_arrays)

    if _mote_shown_count > 0:
        var mote_arrays := []
        mote_arrays.resize(Mesh.ARRAY_MAX)
        if animate_motes:
            _update_mote_deform()
            mote_arrays[Mesh.ARRAY_VERTEX] = _mote_out_positions
            mote_arrays[Mesh.ARRAY_COLOR]  = _mote_out_colors
            mote_arrays[Mesh.ARRAY_INDEX]  = _mote_out_indices
        else:
            var mote_lines: Dictionary = _build_mote_lines(_mote_shown_count, FACE_LIST, Vector3.ZERO)
            mote_arrays[Mesh.ARRAY_VERTEX] = mote_lines["verts"]
            mote_arrays[Mesh.ARRAY_COLOR]  = mote_lines["colors"]
        _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, mote_arrays)


## Cache for the tier-4 (Mote) lattice + its resolved S/L/G typing + the
## reference-tetrahedron basis inverse -- all invariant (they depend on
## nothing but MOTE_TYPE_SEED and the fixed recursion), so computed ONCE per
## instance rather than re-derived on every rebuild. Populated lazily by
## _ensure_mote_lattice_cache(). Was recomputed from scratch on every
## _generate_icosahedron() call, including the full build_tier(4) recursion
## -- fine on an actual Mote-count change, wasteful (and, combined with
## root_ui.gd previously reassigning current_motes unconditionally every
## frame, a measurable per-frame cost) when nothing about the lattice itself
## ever changes between calls.
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
    # edge length 8, not 1 (its recursion scales big_edge = 2^(tier-1)
    # internally) -- using edge 1 here silently scaled the whole mapped
    # lattice 8x too large (caught by direct verification, not assumed).
    # tetra_corners always puts its first corner at the origin (documented
    # invariant), relied on below rather than re-derived.
    var ref_corners: Array = ArchaiLatticeGeometry.tetra_corners(pow(2.0, 3.0))
    _mote_cache_ref_basis_inv = Basis(ref_corners[1], ref_corners[2], ref_corners[3]).inverse()

    _mote_cache_ready = true


## Stamps a fitted copy of the cached tier-4 (Mote) lattice into each of
## `count` face slots by an exact affine map from the lattice's own
## reference tetrahedron onto that face's real (v0, v1, v2, center)
## tetrahedron. That target tetrahedron is NOT regular (the 3
## center-to-vertex edges are the icosahedron's circumradius, the 3 face
## edges are its edge length -- different in general), so the map carries
## some shear/non-uniform scale; the nested structure still reads clearly
## since the map is exact at all 4 corners, not an approximation. Only this
## per-face transform actually needs to redo work per call -- it depends on
## `verts`, which can change (radius/rotation setup), unlike the cached
## lattice itself. STATIC (animate_motes off) path only -- see
## _update_mote_deform() for the animated equivalent.
## Returns {"verts": PackedVector3Array, "colors": PackedColorArray} rather
## than mutating parameters -- Packed*Array args are copy-on-write value
## types in GDScript, not references like Array/Dictionary, so writing
## through a parameter would only ever mutate a local copy.
func _build_mote_lines(count: int, face_list: Array, center: Vector3) -> Dictionary:
    _ensure_mote_lattice_cache()

    var out_verts := PackedVector3Array()
    var out_colors := PackedColorArray()

    for i in count:
        var f: Array = face_list[i]
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


# ==================================================
# ANIMATED MODE (animate_motes) -- ported from archai_lattice.gd
# ==================================================
# The straight-line static path above rebuilds a fresh set of transformed
# points on every ACTUAL Mote-count change (cheap, infrequent). Animated
# mode needs a wiggling wave visible ALONG each edge, which needs each edge
# subdivided into MOTE_WAVE_SEGMENTS+1 points -- and it has to redo that
# every FRAME, for up to 20 simultaneous lattices, so the split below
# matters: everything that does NOT depend on animation time (the
# subdivided curve buffers -- base position, tangent basis, amplitude,
# phase, angular speed, per-edge random offset) is built ONCE, lazily, by
# _ensure_mote_curve_data(); only the actual per-frame sine evaluation
# (_update_mote_deform()) and the cheap per-slot affine transform re-run
# every frame.

func _level_of(k: int) -> float:
    match k:
        KIND_SPARK:  return LEVEL_SPARK
        KIND_SOLID:  return LEVEL_SOLID
        KIND_LIQUID: return LEVEL_LIQUID
        _:           return LEVEL_GAS


var _mote_curve_ready: bool = false
var _mote_points_per_lattice: int = 0
var _mote_c_base:  PackedVector3Array = PackedVector3Array()
var _mote_c_u:     PackedVector3Array = PackedVector3Array()
var _mote_c_v:     PackedVector3Array = PackedVector3Array()
var _mote_c_amp:   PackedFloat32Array = PackedFloat32Array()
var _mote_c_phase: PackedFloat32Array = PackedFloat32Array()
var _mote_c_omega: PackedFloat32Array = PackedFloat32Array()
var _mote_c_off:   PackedFloat32Array = PackedFloat32Array()
var _mote_c_col:   PackedColorArray   = PackedColorArray()
var _mote_c_idx:   PackedInt32Array   = PackedInt32Array()
var _mote_c_deformed: PackedVector3Array = PackedVector3Array()

## Builds the ONE-lattice-worth subdivided curve buffers, in the SAME
## reference/local space _mote_cache_pos already lives in (i.e. BEFORE any
## per-slot affine transform) -- every shown slot reuses this exact same
## data, only differing in which transform gets applied to the deformed
## result afterward. Lazily built once; MOTE_TYPE_SEED-seeded per-edge
## random phase offset, same as archai_lattice.gd's own lattice_seed-keyed
## offset.
func _ensure_mote_curve_data() -> void:
    if _mote_curve_ready:
        return
    _ensure_mote_lattice_cache()

    var n_edges := _mote_cache_edges.size()
    var per := MOTE_WAVE_SEGMENTS + 1
    var total := n_edges * per
    _mote_points_per_lattice = total

    _mote_c_base.resize(total)
    _mote_c_u.resize(total)
    _mote_c_v.resize(total)
    _mote_c_amp.resize(total)
    _mote_c_phase.resize(total)
    _mote_c_omega.resize(total)
    _mote_c_off.resize(total)
    _mote_c_col.resize(total)
    _mote_c_idx.resize(n_edges * MOTE_WAVE_SEGMENTS * 2)
    _mote_c_deformed.resize(total)

    var rng := RandomNumberGenerator.new()
    rng.seed = MOTE_TYPE_SEED * 7919 + 13

    var w := 0
    var ii := 0
    for ei in n_edges:
        var e: Vector2i = _mote_cache_edges[ei]
        var pa: Vector3 = _mote_cache_pos[e.x]
        var pb: Vector3 = _mote_cache_pos[e.y]
        var la: float = _level_of(_mote_cache_kind[e.x])
        var lb: float = _level_of(_mote_cache_kind[e.y])
        var ca: Color = _kind_color(_mote_cache_kind[e.x])
        var cb: Color = _kind_color(_mote_cache_kind[e.y])

        var span: Vector3 = pb - pa
        var elen: float = span.length()
        var dir: Vector3 = span / maxf(elen, 0.00001)

        var ref := Vector3.UP
        if absf(dir.dot(ref)) > 0.9:
            ref = Vector3.RIGHT
        var u: Vector3 = dir.cross(ref).normalized()
        var v: Vector3 = dir.cross(u).normalized()
        var off: float = rng.randf() * TAU

        for k in range(per):
            var t := float(k) / float(MOTE_WAVE_SEGMENTS)
            var lev := lerpf(la, lb, t)
            _mote_c_base[w] = pa + span * t
            _mote_c_u[w] = u
            _mote_c_v[w] = v
            # sin(PI*t) pins the wave to zero at both endpoints so
            # subdivided edges still meet their real shared vertices.
            _mote_c_amp[w] = MOTE_WAVE_AMPLITUDE * elen * lev * sin(PI * t)
            # Integral of a linearly-varying frequency, NOT frequency * t --
            # same reasoning as archai_lattice.gd's _build_curves().
            _mote_c_phase[w] = TAU * MOTE_WAVES_PER_EDGE * (la * t + (lb - la) * t * t * 0.5)
            _mote_c_omega[w] = TAU * MOTE_WAVE_SPEED * lev
            _mote_c_off[w] = off
            _mote_c_col[w] = ca.lerp(cb, t)
            w += 1

        var base_i := ei * per
        for k in range(MOTE_WAVE_SEGMENTS):
            _mote_c_idx[ii] = base_i + k
            ii += 1
            _mote_c_idx[ii] = base_i + k + 1
            ii += 1

    _mote_curve_ready = true


var _mote_slot_v0: Array = []
var _mote_slot_m:  Array = []
var _mote_out_positions: PackedVector3Array = PackedVector3Array()
var _mote_out_colors:    PackedColorArray   = PackedColorArray()
var _mote_out_indices:   PackedInt32Array   = PackedInt32Array()

## Rebuilds the per-shown-slot affine transforms (v0, m) plus the
## replicated color/index buffers -- everything the animated path needs
## that depends only on `verts` (the icosahedron's own current vertex
## positions) and `shown_count` (from current_motes), NOT on animation
## time. Called once per _generate_icosahedron() (a Mote-count change),
## never per-frame -- _update_mote_deform() reuses all of this every frame
## unchanged, recomputing only the actual wave positions.
func _rebuild_mote_slot_data(shown_count: int) -> void:
    _ensure_mote_curve_data()

    _mote_slot_v0.resize(shown_count)
    _mote_slot_m.resize(shown_count)

    var ppl := _mote_points_per_lattice
    var idx_per_lattice := _mote_c_idx.size()
    _mote_out_positions.resize(shown_count * ppl)
    _mote_out_colors.resize(shown_count * ppl)
    _mote_out_indices.resize(shown_count * idx_per_lattice)

    for i in shown_count:
        var f: Array = FACE_LIST[i]
        var v0: Vector3 = verts[f[0]]
        var v1: Vector3 = verts[f[1]]
        var v2: Vector3 = verts[f[2]]
        var target_basis := Basis(v1 - v0, v2 - v0, Vector3.ZERO - v0)
        _mote_slot_v0[i] = v0
        _mote_slot_m[i] = target_basis * _mote_cache_ref_basis_inv

        var col_base := i * ppl
        for p in ppl:
            _mote_out_colors[col_base + p] = _mote_c_col[p]

        var idx_out_base := i * idx_per_lattice
        var idx_offset := i * ppl
        for k in idx_per_lattice:
            _mote_out_indices[idx_out_base + k] = _mote_c_idx[k] + idx_offset


## Per-frame: deforms the ONE cached lattice's curve points (the expensive,
## trig-heavy step) exactly ONCE, then stamps that SAME deformed result
## through each shown slot's own cached affine transform -- the wave math
## is identical for every slot (only the final placement differs), so
## re-deforming per slot would be pure waste. Fills _mote_out_positions,
## which _rebuild_surfaces() uploads directly.
func _update_mote_deform() -> void:
    for i in _mote_c_base.size():
        var a := _mote_c_amp[i]
        var ph := _mote_c_phase[i]
        var om := _mote_c_omega[i]
        var o := _mote_c_off[i]
        var s1 := sin(ph + om * time + o)
        var s2 := sin(ph * 0.7 + om * 0.7 * time + o * 1.7 + 1.3)
        _mote_c_deformed[i] = _mote_c_base[i] + _mote_c_u[i] * (a * s1) + _mote_c_v[i] * (a * 0.55 * s2)

    var ppl := _mote_points_per_lattice
    for slot in _mote_shown_count:
        var v0: Vector3 = _mote_slot_v0[slot]
        var m: Basis = _mote_slot_m[slot]
        var base := slot * ppl
        for p in ppl:
            _mote_out_positions[base + p] = v0 + m * _mote_c_deformed[p]
