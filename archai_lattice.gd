@tool
extends MeshInstance3D
# ================= ARCHAI LATTICE v1.0.0 =================
# Wireframe viewer for the Sierpinski assembly model (design spec: see
# memory planned_archai_purity_tier_taxonomy, and the header block in
# firmament_ui.gd). PROTOTYPE — the model it draws is not settled design.
#
# Structure it builds, per tier:
#   Tetrad   (tier 1) = 4 Monads at tetrahedron corners + 1 Spark centroid.
#                       10 edges (6 Monad-Monad, 4 Spark spokes).
#   Particle (tier 2) = 4 Tetrads at the corners of a double-edge tetrahedron
#                       + 1 Spark in the octahedral gap, joined to the 6 shared
#                       Monads. Sub-units touch ONLY at those 6 points.
#   Iota     (tier 3) = same step again on 4 Particles.
#   Mote     (tier 4) = same step again on 4 Iotas.
#
# Expected counts (assert these if you ever refactor the recursion):
#   tier 1:   5 verts (  4 Monad,  1 Spark),  10 edges
#   tier 2:  15 verts ( 10 Monad,  5 Spark),  46 edges
#   tier 3:  55 verts ( 34 Monad, 21 Spark), 190 edges
#   tier 4: 215 verts (130 Monad, 85 Spark), 766 edges
#
# Edges are drawn as sinusoids, not straight lines. Agitation (amplitude AND
# wiggle count together) is set by the Monad the line EMERGES from, in 25%
# steps up from straight: Spark 25%, Solid 50%, Liquid 75%, Gas 100%. Each
# edge lerps from its own end's level to the far end's, so the two meet at
# equivalence exactly at the midpoint. Because the spatial frequency varies
# along the edge, phase is the integral of frequency, not frequency * t --
# otherwise the wave visibly tears where the rate changes.
#
# Monad types are assigned per unique lattice POSITION after welding, so the
# same-type-at-shared-vertices matching rule is satisfied by construction --
# every lattice this generates is a legal one.

# preload, not the bare global `ArchaiLatticeGeometry.foo()` class_name
# reference -- confirmed directly (2026-09-06) that the bare reference can
# fail to compile (can_instantiate() == false, no visible error) when the
# project's global-script-class cache hasn't been refreshed since that file
# was added, which a plain `--headless --script` run doesn't reliably force.
# preload() sidesteps that cache entirely and always resolves.
const ArchaiLatticeGeometry := preload("res://archai_lattice_geometry.gd")

const MONAD_TBD := -1
const KIND_SPARK := 0
const KIND_SOLID := 1
const KIND_LIQUID := 2
const KIND_GAS := 3

## Defaults to Iota (3), not Mote: Particle's own cavity is already at the
## terminal target size, so show_cavity_fill has nothing to add at tier 2 --
## the new cavity-fill connections only exist at Iota (6 pockets, 19 new
## verts) and Mote (36 pockets, 115 new verts). Mote's total (215 base +
## 115 fill = 330 verts) is too dense to read; Iota (55 + 19 = 74) still
## shows every new connection clearly.
@export_range(1, 4) var tier: int = 3: set = _set_tier
@export var lattice_seed: int = 1: set = _set_seed
@export var fit_radius: float = 1.0: set = _set_fit
@export var animate: bool = true
## Pauses the whole viewer -- spin AND the sine-wave deformation -- for a
## still, exact-geometry view. Independent of `animate`, which only ever
## gated the wave; nothing previously stopped the rotation on its own.
@export var rotating: bool = true
@export var spin_speed: float = 0.25
@export var log_summary: bool = true
## Draws every edge as a straight segment instead of the sinusoid -- for
## inspecting exact structure (vertex counts, which edges exist) rather
## than the illustrative agitation view. Independent of the wave settings
## below, which stay live underneath so switching back needs no rebuild.
@export var straight_lines: bool = false: set = _set_straight
## Adds the Mote/Iota cavity's Grain-track fill: the terminal
## "particle-octahedron" Spark pockets and the scaffold Monad vertices they
## connect to (each pocket's own defining vertex + the shared octahedron
## centre one level up -- its only two real neighbours, per the "particle
## cavities... in a Grain" thread in planned_uonite_vs_grain_prestige_tracks
## memory). Ignored below tier 3 -- Particle's cavity is already terminal,
## nothing to fill.
@export var show_cavity_fill: bool = false: set = _set_cavity_fill
## A tier's own PRE-EXISTING central Spark (built by _build_tier itself,
## degree 6 to its cavity's 6 vertices from the very first version of this
## file) has more real neighbours available: the midpoints of the cavity
## octahedron's own 12 edges land EXACTLY on Monads already in the base
## lattice -- verified 2026-09-02 at Iota (12/12 exact position matches,
## not approximate), where they turn out to be each corner Particle's own
## internal weld-points, carried through and offset when assembled into
## Iota. Does NOT touch _build_tier's own tested output -- purely additive,
## found fresh each rebuild by exact position match, same discipline as
## show_cavity_fill. Whether other tiers have the same count (or any) is
## NOT assumed -- deliberately scoped to "see what's real," not asserted.
@export var show_extra_centroid_edges: bool = false: set = _set_extra_centroid

@export_group("Wave")
## Peak sideways swing, as a fraction of each edge's own length.
@export var amplitude: float = 0.09: set = _set_amplitude
## Full sine cycles along an edge at 100% agitation.
@export var waves_per_edge: float = 2.5: set = _set_waves
@export var wave_speed: float = 0.9: set = _set_speed
@export_range(2, 128) var segments: int = 32: set = _set_segments

@export_group("Agitation")
@export_range(0.0, 1.0) var level_spark: float = 0.25: set = _set_l_spark
@export_range(0.0, 1.0) var level_solid: float = 0.50: set = _set_l_solid
@export_range(0.0, 1.0) var level_liquid: float = 0.75: set = _set_l_liquid
@export_range(0.0, 1.0) var level_gas: float = 1.00: set = _set_l_gas

@export_group("Colors")
@export var color_spark: Color = Color(1.00, 0.97, 0.80): set = _set_c_spark
@export var color_solid: Color = Color(0.80, 0.53, 0.40): set = _set_c_solid
@export var color_liquid: Color = Color(0.27, 0.55, 0.85): set = _set_c_liquid
@export var color_gas: Color = Color(0.63, 0.50, 0.85): set = _set_c_gas

# ---- lattice (node graph) ----
var _vert_pos: PackedVector3Array = PackedVector3Array()
var _vert_kind: PackedInt32Array = PackedInt32Array()
var _edges: Array = []

# ---- per-curve-point buffers, sized once per rebuild ----
var _c_base: PackedVector3Array = PackedVector3Array()
var _c_u: PackedVector3Array = PackedVector3Array()
var _c_v: PackedVector3Array = PackedVector3Array()
var _c_amp: PackedFloat32Array = PackedFloat32Array()
var _c_phase: PackedFloat32Array = PackedFloat32Array()
var _c_omega: PackedFloat32Array = PackedFloat32Array()
var _c_off: PackedFloat32Array = PackedFloat32Array()
var _c_col: PackedColorArray = PackedColorArray()
var _c_out: PackedVector3Array = PackedVector3Array()
var _c_idx: PackedInt32Array = PackedInt32Array()

var _time: float = 0.0
var _mesh: ArrayMesh = null


func _ready() -> void:
    _rebuild()


func _process(delta: float) -> void:
    if not rotating:
        return
    _time += delta
    rotation.y = _time * spin_speed
    if animate and not straight_lines and not _c_out.is_empty():
        _deform()
        _upload()


# ==================================================
# SETTERS
# ==================================================
func _set_tier(v: int) -> void:
    tier = clampi(v, 1, 4)
    _rebuild()

func _set_seed(v: int) -> void:
    lattice_seed = v
    _rebuild()

func _set_fit(v: float) -> void:
    fit_radius = maxf(v, 0.01)
    _rebuild()

func _set_amplitude(v: float) -> void:
    amplitude = v
    _rebuild()

func _set_waves(v: float) -> void:
    waves_per_edge = v
    _rebuild()

func _set_speed(v: float) -> void:
    wave_speed = v
    _rebuild()

func _set_segments(v: int) -> void:
    segments = clampi(v, 2, 128)
    _rebuild()

func _set_l_spark(v: float) -> void:
    level_spark = v
    _rebuild()

func _set_l_solid(v: float) -> void:
    level_solid = v
    _rebuild()

func _set_l_liquid(v: float) -> void:
    level_liquid = v
    _rebuild()

func _set_l_gas(v: float) -> void:
    level_gas = v
    _rebuild()

func _set_c_spark(v: Color) -> void:
    color_spark = v
    _rebuild()

func _set_c_solid(v: Color) -> void:
    color_solid = v
    _rebuild()

func _set_c_liquid(v: Color) -> void:
    color_liquid = v
    _rebuild()

func _set_c_gas(v: Color) -> void:
    color_gas = v
    _rebuild()

func _set_straight(v: bool) -> void:
    straight_lines = v
    _rebuild()

func _set_cavity_fill(v: bool) -> void:
    show_cavity_fill = v
    _rebuild()

func _set_extra_centroid(v: bool) -> void:
    show_extra_centroid_edges = v
    _rebuild()


# ==================================================
# LATTICE CONSTRUCTION
# ==================================================
# _tetra_corners/_build_tetrad/_build_tier used to live here -- moved to
# ArchaiLatticeGeometry (2026-09-06) so uonite_icosahedron.gd's always-on
# Uonite display can build the identical Mote/Iota/Particle/Tetrad structure
# without a second, driftable copy of this recursion. Behavior is byte-for-
# byte identical; only the call sites below changed.


# ==================================================
# CAVITY DECOMPOSITION
# ==================================================
# A tier's octahedral gap (edge = big_edge/2, vertices = the 6 shared-Monad
# midpoints above) is NOT simply "6 corner octahedra + 8 face tetrahedra
# sitting independently at the original vertices" -- that construction
# leaves a cuboctahedron-shaped remainder unaccounted for (verified against
# the closed-form cuboctahedron volume 5*sqrt(2)/3 * a^3, which a naive
# vertex-truncation undercounts by exactly the cuboctahedron's own volume).
#
# The identity that actually holds, exact to the fraction, verified by hand
# against both the whole-octahedron volume formula and by re-deriving the
# cuboctahedron's own volume two independent ways:
#
#   octahedron(edge 2E) = 6 octahedra(edge E) + 8 tetrahedra(edge E)
#
# where ALL 14 pieces share ONE common point: the big octahedron's centre.
# Each small octahedron runs from that shared centre out to one of the big
# octahedron's 6 original vertices (its other 4 vertices are the midpoints
# of the 4 edges between that vertex and its 4 non-antipodal neighbours).
# Each small tetrahedron cones the centre to one of the 8 triangular faces
# (one vertex picked from each of the big octahedron's 3 antipodal pairs).
#
## Distance between the two nearest of 6 octahedron vertices -- the EDGE
## length. (The other distance that appears, sqrt(2) times longer, is the
## antipodal diagonal, not an edge.)
func _octa_edge_length(verts: Array) -> float:
    var m := INF
    for i in range(6):
        for j in range(i + 1, 6):
            m = minf(m, (verts[i] as Vector3).distance_to(verts[j]))
    return m


## The unique vertex farthest from verts[vi] -- its antipode across the
## octahedron's centre.
func _octa_antipode(verts: Array, vi: int) -> int:
    var best := -1
    var best_d := -1.0
    for wi in range(6):
        if wi == vi:
            continue
        var d: float = (verts[vi] as Vector3).distance_to(verts[wi])
        if d > best_d:
            best_d = d
            best = wi
    return best


## Recurses an octahedron (given by its 6 vertices) down to terminal
## "particle-octahedron" pockets at `target_edge`. Each returned entry is
## one terminal pocket: its centre (where the pocket's own Spark sits) and
## edge (should equal target_edge, kept for sanity-checking).
func _octa_terminal_pockets(verts: Array, target_edge: float) -> Array:
    var edge := _octa_edge_length(verts)
    if edge <= target_edge + 0.0001:
        var terminal_centre := Vector3.ZERO
        for v in verts:
            terminal_centre += v
        return [{"center": terminal_centre / 6.0, "edge": edge}]

    var pockets: Array = []
    var centre := Vector3.ZERO
    for v in verts:
        centre += v
    centre /= 6.0

    for vi in range(6):
        var v: Vector3 = verts[vi]
        var anti := _octa_antipode(verts, vi)
        var child: Array = [v, centre]
        for wi in range(6):
            if wi != vi and wi != anti:
                child.append((v + (verts[wi] as Vector3)) * 0.5)
        pockets.append_array(_octa_terminal_pockets(child, target_edge))
    return pockets


## The 6 vertices of a tier's OWN outermost octahedral cavity (not any
## nested corner-unit's smaller one) -- same construction `_build_tier`
## uses internally for `mid_idx`, exposed standalone so cavity analysis
## doesn't need to re-run the whole recursive lattice build.
func _cavity_verts(for_tier: int) -> Array:
    var big_edge: float = pow(2.0, float(for_tier - 1))
    var corners := ArchaiLatticeGeometry.tetra_corners(big_edge)
    var verts: Array = []
    for i in range(4):
        for j in range(i + 1, 4):
            verts.append((corners[i] + corners[j]) * 0.5)
    return verts


## Terminal "particle-octahedron" (edge-1) Spark pockets for a tier's own
## cavity: 6 for Iota (one recursion level), 36 for Mote (two levels).
## Particle's cavity (edge 1) is already the target -- returns 1 pocket at
## its own centroid, matching the single mandatory rivet Spark.
func cavity_pockets(for_tier: int) -> Array:
    return _octa_terminal_pockets(_cavity_verts(for_tier), 1.0)


# ==================================================
# GRAIN-TRACK CAVITY FILL (added 2026-09-02)
# ==================================================
# Scope, deliberately: the terminal pocket Sparks and the Monad scaffold
# they connect through (each pocket's own defining vertex + the shared
# octahedron centre one level up -- ITS ONLY TWO REAL NEIGHBOURS). Does NOT
# draw the 8/48 face-tetrahedra Particle/Tetrad positions' own internal
# structure -- that would need each one's own full recursive sub-lattice
# (a Particle's central Spark is degree 6 to ITS OWN cavity, not degree 4
# to this scaffold), out of scope for this pass and not what was asked.
#
# Expected new-vertex counts (verify if this recursion is ever touched):
#   Iota cavity (1 decompose level):  13 scaffold Monads +  6 pockets = 19
#   Mote cavity (2 decompose levels): 91 scaffold Monads + 36 pockets = 127
# Edges: 2 per pocket (to its "v" and its "centre"), so 12 / 72 respectively.

## Partitions an octahedron's 6 vertices into its 3 antipodal pairs (each
## vertex ties for nearest with all others except its own antipode, so
## every vertex has exactly one). Returns 3 Vector2i(i, j) index-pairs into
## `verts`. Order among the 3 pairs and within each pair is whatever
## `_octa_antipode` returns first -- callers that need the 8 tetrahedra
## combinations don't care which pair is "first", only that all 8 binary
## choices get enumerated once each.
func _octa_antipodal_pairs(verts: Array) -> Array:
    var pairs: Array = []
    var used := {}
    for i in range(6):
        if used.has(i):
            continue
        var anti: int = _octa_antipode(verts, i)
        used[i] = true
        used[anti] = true
        pairs.append(Vector2i(i, anti))
    return pairs


## Recurses one octahedron's cavity fill. `verts`/`idx` are its 6 boundary
## points as (position, index) pairs -- idx entries are REAL indices, either
## already in the outer lattice (first call) or newly allocated by a parent
## call (recursion). Appends to `new_pos`/`new_kind`/`new_edges` in place;
## new indices continue on from `base_index` (== outer_pos.size() at the
## first call). Never welds by float position -- every shared point (a
## level's own centre, a midpoint two sibling children both touch) is
## passed down explicitly by index, the same identity discipline
## `_build_tier` itself relies on.
##
## `tetra_out`, if not null, ALSO collects the 8 corner-tetrahedra sibling
## to this level's 6 sub-octahedra -- the other half of the "octahedron
## edge 2E = 6 octahedra edge E + 8 tetrahedra edge E" identity, previously
## left undrawn (see header comment). Each entry is {"idx": [centre_i, a, b,
## c]} where a/b/c are one pick from each of the 3 antipodal pairs (all 8
## combinations), all 4 indices real and shared with whatever else in this
## same recursion pass touches them -- the centre is the SAME centre_i the
## sub-octahedra branch uses, and a/b/c are the SAME idx[] entries passed
## into this call, never independently reallocated. Collected once per
## recursion level (Iota: 1 level -> 8 total; Mote: top level -> 8 at
## Particle scale + 6 further levels -> 48 at Tetrad scale), matching
## planned_archai_purity_tier_taxonomy.md's "8 Tetrad (all 8 pieces of the
## single decomposition pass)" / "48 Tetrad (Level-2, 6 octahedra x 8 each)".
func _cavity_fill_recurse(verts: Array, idx: Array, target_edge: float,
        new_pos: Array, new_kind: Array, new_edges: Array, base_index: int,
        tetra_out: Array = []) -> void:
    var edge: float = _octa_edge_length(verts)
    var centre := Vector3.ZERO
    for v in verts:
        centre += v
    centre /= 6.0

    if edge <= target_edge + 0.0001:
        # Terminal pocket: 1 Spark, degree 2 -- to this recursion's own "v"
        # (idx[0]) and "centre" (idx[1], already allocated one level up).
        var spark_i: int = base_index + new_pos.size()
        new_pos.append(centre)
        new_kind.append(KIND_SPARK)
        new_edges.append(Vector2i(spark_i, int(idx[0])))
        new_edges.append(Vector2i(spark_i, int(idx[1])))
        return

    var centre_i: int = base_index + new_pos.size()
    new_pos.append(centre)
    new_kind.append(MONAD_TBD)

    # Always computed (cheap: 8 small lookups) even when the caller passed
    # the default throwaway array and doesn't want it -- simpler than a
    # meaningful opt-out, and build_cavity_fill()'s existing behavior/output
    # is unaffected either way since this only ever appends to `tetra_out`.
    var pairs: Array = _octa_antipodal_pairs(verts)
    for a_bit in range(2):
        for b_bit in range(2):
            for c_bit in range(2):
                var a: int = int((pairs[0] as Vector2i)[a_bit])
                var b: int = int((pairs[1] as Vector2i)[b_bit])
                var c: int = int((pairs[2] as Vector2i)[c_bit])
                # edge*0.5: these tetrahedra are half this level's own edge
                # length -- Iota's one level and Mote's deepest (2nd) level
                # both land at edge 1 (Tetrad scale, target_edge); Mote's
                # shallower (1st/top) level lands at edge 2 (Particle scale)
                # instead -- tag it so callers can tell the two apart rather
                # than assuming every entry is Tetrad-scale.
                tetra_out.append({"idx": [centre_i, int(idx[a]), int(idx[b]), int(idx[c])], "edge": edge * 0.5})

    # 6 children, each recursing toward one of the 6 boundary points. Their
    # midpoints are shared PAIRWISE (child vi's midpoint toward wi is the
    # same point as child wi's midpoint toward vi) -- allocate once, reuse.
    # Midpoint positions are cheap and deterministic to recompute, so look
    # up only the INDEX by identity; never round-trip a position through
    # new_pos by offset arithmetic.
    var mid_idx := {}
    for vi in range(6):
        var v: Vector3 = verts[vi]
        var anti: int = _octa_antipode(verts, vi)
        var child_verts: Array = [v, centre]
        var child_idx: Array = [idx[vi], centre_i]
        for wi in range(6):
            if wi == vi or wi == anti:
                continue
            var key := Vector2i(mini(vi, wi), maxi(vi, wi))
            var mp: Vector3 = (v + (verts[wi] as Vector3)) * 0.5
            var mi: int
            if mid_idx.has(key):
                mi = mid_idx[key]
            else:
                mi = base_index + new_pos.size()
                new_pos.append(mp)
                new_kind.append(MONAD_TBD)
                mid_idx[key] = mi
            child_verts.append(mp)
            child_idx.append(mi)
        _cavity_fill_recurse(child_verts, child_idx, target_edge, new_pos, new_kind, new_edges, base_index, tetra_out)


## A tier's own pre-existing central Spark (always the LAST entry in
## `_build_tier`'s own `pos`, by that function's own convention) may have
## real neighbours beyond the 6 cavity vertices it's already wired to: the
## midpoints of the cavity octahedron's own 12 edges, IF they happen to
## coincide exactly with a Monad already present in `outer_pos`. Matched by
## exact position -- both sides are deterministic from the same
## construction, not independent measurements. Returns only the matches
## actually found; no count is assumed or hard-coded per tier.
func extra_centroid_edges(outer_pos: Array, for_tier: int) -> Array:
    var edges: Array = []
    var spark_i: int = outer_pos.size() - 1

    var cav: Array = _cavity_verts(for_tier)
    var mids: Array = []
    for i in range(6):
        var anti: int = _octa_antipode(cav, i)
        for j in range(6):
            if j <= i or j == anti:
                continue
            mids.append(((cav[i] as Vector3) + (cav[j] as Vector3)) * 0.5)

    for m in mids:
        for i in outer_pos.size():
            if i == spark_i:
                continue
            if (outer_pos[i] as Vector3).is_equal_approx(m as Vector3):
                edges.append(Vector2i(spark_i, i))
                break

    return edges


## Builds the Grain-track cavity fill for a tier's own outermost cavity,
## given the already-built outer lattice's own `pos` array (so the 6 real
## cavity-boundary Monads are matched to their real indices, never
## duplicated). Matches by exact position equality -- safe here because
## both sides compute the identical deterministic formula from the same
## input, not independent measurements that could drift.
##
## Two levels deep (Mote), DIFFERENT Level-1 children's own Level-2
## midpoints can land on the exact same physical point by the octahedron's
## own symmetry -- each child's `mid_idx` in `_cavity_fill_recurse` is
## scoped locally to that child, with no visibility across siblings, so
## such a coincidence allocates two distinct indices for one real point.
## Compacted below by position identity, same as the dedup any other
## cross-branch weld in this file relies on -- never left as two
## coincident-but-distinct vertices.
##
## Return dict adds a "tetrahedra" key alongside the original pos/kind/
## edges: the 8-per-level corner-tetrahedra positions (see
## _cavity_fill_recurse's tetra_out doc), each {"idx": [centre, a, b, c]},
## indices already remapped through the same compaction pass as everything
## else here so they're valid against the returned "pos" array. These are
## POSITIONS ONLY -- no Spark/Monad vertex is placed there and no edges are
## generated for them; they exist so callers (e.g. production-side weld-
## compatibility checks) can read the real shared-vertex structure among
## the 8/48 Tetrad-scale positions without re-deriving the geometry.
func build_cavity_fill(outer_pos: Array, for_tier: int) -> Dictionary:
    var new_pos: Array = []
    var new_kind: Array = []
    var new_edges: Array = []
    var tetra_out: Array = []
    if for_tier < 3:
        return {"pos": new_pos, "kind": new_kind, "edges": new_edges, "tetrahedra": tetra_out}

    var base_index: int = outer_pos.size()
    var cav_verts: Array = _cavity_verts(for_tier)
    var boundary_idx: Array = []
    for cv in cav_verts:
        var found := -1
        for i in outer_pos.size():
            if (outer_pos[i] as Vector3).is_equal_approx(cv as Vector3):
                found = i
                break
        boundary_idx.append(found)

    _cavity_fill_recurse(cav_verts, boundary_idx, 1.0, new_pos, new_kind, new_edges, base_index, tetra_out)

    # Compact by position identity: any two new_pos entries at the exact
    # same point are the same real vertex, allocated twice.
    var canonical_i := {}   # quantized-position key -> compacted new_pos index
    var idx_remap := {}      # original base_index+i -> compacted base_index+i
    var comp_pos: Array = []
    var comp_kind: Array = []
    for i in new_pos.size():
        var key: Vector3 = (new_pos[i] as Vector3).snapped(Vector3.ONE * 0.00001)
        if canonical_i.has(key):
            idx_remap[base_index + i] = base_index + int(canonical_i[key])
        else:
            var ci: int = comp_pos.size()
            canonical_i[key] = ci
            comp_pos.append(new_pos[i])
            comp_kind.append(new_kind[i])
            idx_remap[base_index + i] = base_index + ci

    var comp_edges: Array = []
    for e in new_edges:
        var a: int = (e as Vector2i).x
        var b: int = (e as Vector2i).y
        comp_edges.append(Vector2i(
            int(idx_remap.get(a, a)),
            int(idx_remap.get(b, b))))

    var comp_tetra: Array = []
    for t in tetra_out:
        var raw_idx: Array = (t as Dictionary)["idx"]
        var remapped: Array = []
        for v in raw_idx:
            remapped.append(int(idx_remap.get(int(v), int(v))))
        comp_tetra.append({"idx": remapped, "edge": float((t as Dictionary)["edge"])})

    return {"pos": comp_pos, "kind": comp_kind, "edges": comp_edges, "tetrahedra": comp_tetra}


func _rebuild() -> void:
    if not is_inside_tree():
        return

    var lat := ArchaiLatticeGeometry.build_tier(tier)
    var pos: Array = lat["pos"]
    var kind: Array = lat["kind"]
    _edges = lat["edges"]

    var extra_count := 0
    if show_extra_centroid_edges:
        # MUST run on the base lattice's own pos, before any cavity-fill
        # append below -- extra_centroid_edges() finds the tier's central
        # Spark as pos.size()-1, which is only correct before anything else
        # gets appended to pos.
        var extra: Array = extra_centroid_edges(pos, tier)
        extra_count = extra.size()
        _edges.append_array(extra)

    var fill_count := 0
    if show_cavity_fill:
        var fill := build_cavity_fill(pos, tier)
        var fill_pos: Array = fill["pos"]
        var fill_kind: Array = fill["kind"]
        fill_count = fill_pos.size()
        pos.append_array(fill_pos)
        kind.append_array(fill_kind)
        _edges.append_array(fill["edges"])

    # Assign a Monad type per unique position. Shared vertices are already a
    # single entry here, so both sides of every contact agree automatically.
    var rng := RandomNumberGenerator.new()
    rng.seed = lattice_seed
    var monads := 0
    for i in kind.size():
        if kind[i] == MONAD_TBD:
            kind[i] = KIND_SOLID + rng.randi_range(0, 2)
            monads += 1

    # Centre and normalise so every tier frames the same in the viewport.
    var centre := Vector3.ZERO
    for p in pos:
        centre += p
    centre /= float(pos.size())
    var max_r := 0.0
    for p in pos:
        max_r = maxf(max_r, (p as Vector3 - centre).length())
    var s: float = fit_radius / maxf(max_r, 0.0001)

    _vert_pos.resize(pos.size())
    _vert_kind.resize(kind.size())
    for i in pos.size():
        _vert_pos[i] = ((pos[i] as Vector3) - centre) * s
        _vert_kind[i] = kind[i]

    if straight_lines:
        _upload_straight()
    else:
        _build_curves()
        _deform()
        _upload()

    if log_summary:
        var names := ["Tetrad", "Particle", "Iota", "Mote"]
        var fill_note := "  (+%d cavity-fill)" % fill_count if show_cavity_fill else ""
        var extra_note := "  (+%d extra centroid edges)" % extra_count if show_extra_centroid_edges else ""
        print("[ArchaiLattice] %s (tier %d): %d verts (%d Monad, %d Spark), %d edges%s%s"
            % [names[tier - 1], tier, _vert_pos.size(), monads,
               _vert_pos.size() - monads, _edges.size(), fill_note, extra_note])


# ==================================================
# CURVE BUFFERS
# ==================================================
func _level_of(k: int) -> float:
    match k:
        KIND_SPARK: return level_spark
        KIND_SOLID: return level_solid
        KIND_LIQUID: return level_liquid
        _: return level_gas


func _color_of(k: int) -> Color:
    match k:
        KIND_SPARK: return color_spark
        KIND_SOLID: return color_solid
        KIND_LIQUID: return color_liquid
        _: return color_gas


func _build_curves() -> void:
    var n_edges := _edges.size()
    var per := segments + 1
    var total := n_edges * per

    _c_base.resize(total)
    _c_u.resize(total)
    _c_v.resize(total)
    _c_amp.resize(total)
    _c_phase.resize(total)
    _c_omega.resize(total)
    _c_off.resize(total)
    _c_col.resize(total)
    _c_out.resize(total)
    _c_idx.resize(n_edges * segments * 2)

    var rng := RandomNumberGenerator.new()
    rng.seed = lattice_seed * 7919 + 13

    var w := 0
    var ii := 0
    for ei in n_edges:
        var e: Vector2i = _edges[ei]
        var pa := _vert_pos[e.x]
        var pb := _vert_pos[e.y]
        var la := _level_of(_vert_kind[e.x])
        var lb := _level_of(_vert_kind[e.y])
        var ca := _color_of(_vert_kind[e.x])
        var cb := _color_of(_vert_kind[e.y])

        var span := pb - pa
        var elen := span.length()
        var dir := span / maxf(elen, 0.00001)

        # Any stable perpendicular pair. Two components at different rates keep
        # the line from reading as a flat drawn-on-paper sine.
        var ref := Vector3.UP
        if absf(dir.dot(ref)) > 0.9:
            ref = Vector3.RIGHT
        var u := dir.cross(ref).normalized()
        var v := dir.cross(u).normalized()
        var off := rng.randf() * TAU

        for k in range(per):
            var t := float(k) / float(segments)
            var lev := lerpf(la, lb, t)
            _c_base[w] = pa + span * t
            _c_u[w] = u
            _c_v[w] = v
            # sin(PI*t) pins the wave to zero at both nodes so edges still meet.
            _c_amp[w] = amplitude * elen * lev * sin(PI * t)
            # Integral of a linearly-varying frequency, NOT frequency * t.
            _c_phase[w] = TAU * waves_per_edge * (la * t + (lb - la) * t * t * 0.5)
            _c_omega[w] = TAU * wave_speed * lev
            _c_off[w] = off
            _c_col[w] = ca.lerp(cb, t)
            w += 1

        var base_i := ei * per
        for k in range(segments):
            _c_idx[ii] = base_i + k
            ii += 1
            _c_idx[ii] = base_i + k + 1
            ii += 1


func _deform() -> void:
    for i in _c_base.size():
        var a := _c_amp[i]
        var ph := _c_phase[i]
        var om := _c_omega[i]
        var o := _c_off[i]
        var s1 := sin(ph + om * _time + o)
        var s2 := sin(ph * 0.7 + om * 0.7 * _time + o * 1.7 + 1.3)
        _c_out[i] = _c_base[i] + _c_u[i] * (a * s1) + _c_v[i] * (a * 0.55 * s2)


func _upload() -> void:
    if _mesh == null:
        _mesh = ArrayMesh.new()
        mesh = _mesh
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.vertex_color_use_as_albedo = true
        material_override = mat

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = _c_out
    arrays[Mesh.ARRAY_COLOR] = _c_col
    arrays[Mesh.ARRAY_INDEX] = _c_idx

    _mesh.clear_surfaces()
    _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


## Straight-segment path: one line per edge, direct vertex-to-vertex, no
## curve buffers at all. For inspecting exact structure (which edges exist,
## how many vertices) rather than the illustrative agitation view.
func _upload_straight() -> void:
    if _mesh == null:
        _mesh = ArrayMesh.new()
        mesh = _mesh
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.vertex_color_use_as_albedo = true
        material_override = mat

    var verts := PackedVector3Array()
    var cols := PackedColorArray()
    verts.resize(_edges.size() * 2)
    cols.resize(_edges.size() * 2)
    var w := 0
    for e in _edges:
        var a: int = (e as Vector2i).x
        var b: int = (e as Vector2i).y
        verts[w] = _vert_pos[a]
        cols[w] = _color_of(_vert_kind[a])
        w += 1
        verts[w] = _vert_pos[b]
        cols[w] = _color_of(_vert_kind[b])
        w += 1

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_COLOR] = cols

    _mesh.clear_surfaces()
    _mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
