extends "res://dev_tests/test_base.gd"
# Guards the Sierpinski assembly recursion in archai_lattice.gd.
#
# The per-tier counts below are DERIVED DESIGN NUMBERS, not observations of
# whatever the code currently emits -- they come from the model itself:
#
#   verts(n) = 10 + 4*(verts(n-1) - 4) + 1     (4 outer tips + 6 shared
#   monads(n) = 10 + 4*(monads(n-1) - 4)        midpoints, 4 sub-copies with
#   sparks(n) = 4*sparks(n-1) + 1               their corners welded, 1 Spark)
#   edges(n) = 4*edges(n-1) + 6
#
# If a refactor changes these, the model changed -- do not "fix" the test to
# match new output without checking the geometry first.
#
# The welding check is the load-bearing one. Sub-units are only ever allowed
# to touch at the 6 edge midpoints; if corner identity welding regresses to
# float-position welding (or breaks outright), coincident-but-distinct
# vertices appear and the counts drift. Distance is checked directly so that
# failure is caught as itself rather than as a confusing count mismatch.
#
# WELD MULTIPLICITY (added 2026-09-02): traced by hand that no Monad in this
# recursion is ever the coalescence of more than 2 raw tier-1 Monad slots --
# every welding event merges exactly a pair, and once merged a vertex is
# never referenced by a higher tier's own welding (only a sub-unit's 4
# unmerged CORNER identities ever get reached for by the tier above it). A
# parallel recursive function below tracks "how many raw tier-1 Monad slots
# does each final vertex represent" using the SAME remap structure as
# _build_tier, independent of vertex positions, so this is checked directly
# rather than re-trusted from the hand trace.

var fails: int = 0

# tier -> [verts, monads, sparks, edges]
const EXPECT := {
	1: [5, 4, 1, 10],
	2: [15, 10, 5, 46],
	3: [55, 34, 21, 190],
	4: [215, 130, 85, 766],
}
const TIER_NAMES := {1: "Tetrad", 2: "Particle", 3: "Iota", 4: "Mote"}


func _bad(msg: String) -> void:
	fails += 1
	print("    FAIL: %s" % msg)


# ==================================================
# WELD MULTIPLICITY -- parallel to _build_tier's own remap logic, tracking
# accumulated raw-Monad-slot counts per final vertex instead of positions.
# ==================================================
func _mult_tetrad() -> Dictionary:
	# 4 raw Monad slots, each its own single unmerged identity, + 1 fresh Spark.
	return {
		"mult": [1, 1, 1, 1, 1],
		"is_monad": [true, true, true, true, false],
		"corners": [0, 1, 2, 3],
	}


func _mult_tier(t: int) -> Dictionary:
	if t <= 1:
		return _mult_tetrad()

	var sub := _mult_tier(t - 1)
	var sub_mult: Array = sub["mult"]
	var sub_is_monad: Array = sub["is_monad"]
	var sub_corners: Array = sub["corners"]

	var mult: Array = []
	var is_monad: Array = []

	var corner_idx: Array = []
	for i in range(4):
		corner_idx.append(mult.size())
		mult.append(0)
		is_monad.append(true)

	var mid_idx := {}
	for i in range(4):
		for j in range(i + 1, 4):
			mid_idx[Vector2i(i, j)] = mult.size()
			mult.append(0)
			is_monad.append(true)

	for ci in range(4):
		var remap := {}
		for j in range(4):
			var sc: int = sub_corners[j]
			if j == ci:
				remap[sc] = corner_idx[ci]
			else:
				remap[sc] = mid_idx[Vector2i(mini(ci, j), maxi(ci, j))]
		for vi in sub_mult.size():
			if remap.has(vi):
				var tgt: int = remap[vi]
				mult[tgt] += int(sub_mult[vi])
				continue
			mult.append(sub_mult[vi])
			is_monad.append(sub_is_monad[vi])

	mult.append(1)
	is_monad.append(false)

	return {"mult": mult, "is_monad": is_monad, "corners": corner_idx}


func _check_weld_multiplicity(inst, tier: int, tier_name: String, expect_monads: int) -> void:
	var m := _mult_tier(tier)
	var mult: Array = m["mult"]
	var is_monad: Array = m["is_monad"]

	var monad_count := 0
	var max_mult := 0
	var raw_sum := 0
	var spark_bad := 0
	for i in mult.size():
		if bool(is_monad[i]):
			monad_count += 1
			max_mult = maxi(max_mult, int(mult[i]))
			raw_sum += int(mult[i])
		else:
			if int(mult[i]) != 1:
				spark_bad += 1

	# Cross-check against the real build: this parallel accounting must land
	# on the same Monad count _build_tier itself produces, or it isn't
	# actually tracking the same recursion.
	if monad_count != expect_monads:
		_bad("%s: weld-multiplicity accounting found %d Monads, real build has %d"
			% [tier_name, monad_count, expect_monads])

	# Independent arithmetic check: total raw Monad-slots produced before any
	# welding is exactly 4 per sub-unit, recursively -- 4^tier.
	var expect_raw: int = 1
	for _i in range(tier):
		expect_raw *= 4
	if raw_sum != expect_raw:
		_bad("%s: raw Monad-slot sum %d, expected 4^%d = %d" % [tier_name, raw_sum, tier, expect_raw])

	if spark_bad > 0:
		_bad("%s: %d Spark vertices have multiplicity != 1 -- Sparks should never be welded"
			% [tier_name, spark_bad])

	var expect_max: int = 1 if tier <= 1 else 2
	if max_mult != expect_max:
		_bad("%s: max weld multiplicity %d, expected %d" % [tier_name, max_mult, expect_max])
	else:
		print("    weld multiplicity: max %d among %d Monads (raw slots %d = 4^%d) -- OK"
			% [max_mult, monad_count, raw_sum, tier])


# ==================================================
# STELLA OCTANGULA WELD EXPANSION (added 2026-09-02)
# ==================================================
# A Monad is 5 Sparks: 4 at a tetrahedron's corners + 1 centroid (established
# for the neurology count). A weld point (multiplicity 2) is NOT one such
# tetrahedron -- it's two, inverted relative to each other and rotated 120
# degrees off vertex alignment (the two tetrahedra's own 3-fold symmetry, so
# this is their unique maximally-offset relative orientation), centroids
# coincident but still separate nodes. This is the stella octangula / compound
# of two tetrahedra -- equivalently, two tetrahedra formed from a cube's 8
# vertices by alternating parity.
#
# Verified directly from coordinates below (not assumed): each vertex of one
# tetrahedron is tied for NEAREST with exactly 3 of the other's 4 vertices
# (skipping only its antipode, the cube's long diagonal) -- 4 x 3 = 12 cross
# edges, matching the user's own count.
#
# A weld point's full internal structure: 2 tetrahedra x 10 edges each (6
# mutual among the 4 corner Sparks + 4 spokes to that tetrahedron's OWN
# centroid) + 12 cross edges = 10 nodes, 32 edges. A single-thread
# (multiplicity 1) Monad stays 5 nodes, 10 edges, same as before.
func _stella_cross_edge_count() -> int:
	# Two tetrahedra as alternating vertices of a cube, edge 2 -- the
	# standard stella octangula construction.
	var a := [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
	var b := [Vector3(-1, -1, -1), Vector3(-1, 1, 1), Vector3(1, -1, 1), Vector3(1, 1, -1)]
	var count := 0
	for va in a:
		var dists: Array = []
		for vb in b:
			dists.append((va as Vector3).distance_to(vb as Vector3))
		var near: float = dists.min()
		var tied := 0
		for d in dists:
			if absf(float(d) - near) < 0.0001:
				tied += 1
		if tied != 3:
			_bad("stella cross-edges: a vertex tied with %d nearest, expected 3" % tied)
		count += tied
	return count


func _mult_counts(tier: int) -> Dictionary:
	var m := _mult_tier(tier)
	var mult: Array = m["mult"]
	var is_monad: Array = m["is_monad"]
	var c1 := 0
	var c2 := 0
	for i in mult.size():
		if bool(is_monad[i]):
			if int(mult[i]) == 1:
				c1 += 1
			elif int(mult[i]) == 2:
				c2 += 1
	return {"mult1": c1, "mult2": c2}


## tier -> [expanded nodes, expanded edges], hand-derived from the mult1/mult2
## split (4/0, 4/6, 4/30, 4/126 for tiers 1-4) and the 5/10 vs 10/32
## per-Monad node/edge costs above, then cross-checked against the formula
## the test computes independently below.
const STELLA_EXPECT := {
	1: [21, 50],
	2: [85, 278],
	3: [341, 1190],
	4: [1365, 4838],
}


func _check_stella_expansion(tier: int, tier_name: String, hub_sparks: int, orig_edges: int) -> void:
	var counts := _mult_counts(tier)
	var c1: int = counts["mult1"]
	var c2: int = counts["mult2"]

	var nodes: int = c1 * 5 + c2 * 10 + hub_sparks
	var edges: int = c1 * 10 + c2 * 32 + orig_edges

	print("    stella expansion: %d single-thread Monads (5 nodes each) + %d weld Monads (10 nodes each) -> %d nodes, %d edges"
		% [c1, c2, nodes, edges])

	var exp: Array = STELLA_EXPECT[tier]
	if nodes != int(exp[0]):
		_bad("%s: stella-expanded nodes %d, expected %d" % [tier_name, nodes, exp[0]])
	if edges != int(exp[1]):
		_bad("%s: stella-expanded edges %d, expected %d" % [tier_name, edges, exp[1]])


# ==================================================
# N-WAY UONITE COALESCENCE (added 2026-09-02)
# ==================================================
# Extends the stella-octangula (2-way) cross-connection rule to the Uonite's
# real coalescence multiplicities: 5-way at each of its 12 outer icosahedron
# vertices, 20-way at its shared center (both confirmed directly from
# uonite_icosahedron.gd's actual cell construction -- every one of the 20
# {center, v0, v1, v2} cells references the SAME index 12 for its apex).
#
# 5-way is well-defined with NO free parameter: 5 Monad-tetrahedra sharing a
# centroid, related by the genuine 72-degree rotational symmetry that exists
# at an icosahedron vertex. Rotating the whole group of 5 together changes
# nothing about their relative geometry, so the cross-edge count has no
# hidden knob -- confirmed uniform (4 per pair) across all 10 pairs.
#
# 20-way is NOT fully determined: each of the 20 tetrahedra's roll about its
# own outward axis (real geometry, one of the 20 true face-normal
# directions) is an independent, unforced choice -- there is no reverse-
# engineered "squish" pinning it down (deliberately not attempted; see
# planned_uonite_vs_grain_prestige_tracks memory). Tested 778/781/778/994
# across four alternate rolls against the documented convention's 847 --
# real spread, not noise. The test below locks in the DOCUMENTED convention
# (REF_TETRA[0] as the outward-pointing vertex, aligned via the shortest
# rotation to each face normal) as a regression guard for THAT convention,
# not a claim that 847 is the unique right answer.
const REF_TETRA := [
	Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)
]


func _rotated_tetra(basis: Basis) -> Array:
	var out: Array = []
	for v in REF_TETRA:
		out.append(basis * (v as Vector3))
	return out


func _n_way_cross_edges(groups: Array) -> int:
	var total := 0
	for i in range(groups.size()):
		for j in range(i + 1, groups.size()):
			var a: Array = groups[i]
			var b: Array = groups[j]
			for va in a:
				var dists: Array = []
				for vb in b:
					dists.append((va as Vector3).distance_to(vb as Vector3))
				var near: float = dists.min()
				for d in dists:
					if absf(float(d) - near) < 0.0001:
						total += 1
	return total


func _check_n_way_coalescence() -> void:
	# 5-way: 72-degree rotations about a shared axis. No free parameter.
	var groups5: Array = []
	for k in range(5):
		groups5.append(_rotated_tetra(Basis(Vector3.UP, deg_to_rad(72.0 * k))))
	var cross5 := _n_way_cross_edges(groups5)
	print("  5-way coalescence (12 outer icosahedron vertices, each): %d cross-edges" % cross5)
	if cross5 != 40:
		_bad("5-way cross-edges %d, expected 40" % cross5)

	# 20-way: real icosahedron face-normal directions, documented roll
	# convention (see comment block above).
	var PHI := (1.0 + sqrt(5.0)) / 2.0
	var s := 1.0 / sqrt(1.0 + PHI * PHI)
	var iverts := [
		Vector3(0, 1, PHI) * s, Vector3(0, 1, -PHI) * s,
		Vector3(0, -1, PHI) * s, Vector3(0, -1, -PHI) * s,
		Vector3(1, PHI, 0) * s, Vector3(1, -PHI, 0) * s,
		Vector3(-1, PHI, 0) * s, Vector3(-1, -PHI, 0) * s,
		Vector3(PHI, 0, 1) * s, Vector3(PHI, 0, -1) * s,
		Vector3(-PHI, 0, 1) * s, Vector3(-PHI, 0, -1) * s,
	]
	var face_list := [
		[0, 2, 8], [0, 2, 10], [0, 4, 6], [0, 4, 8], [0, 6, 10],
		[1, 3, 9], [1, 3, 11], [1, 4, 6], [1, 4, 9], [1, 6, 11],
		[2, 5, 7], [2, 5, 8], [2, 7, 10], [3, 5, 7], [3, 5, 9],
		[3, 7, 11], [4, 8, 9], [5, 8, 9], [6, 10, 11], [7, 10, 11],
	]
	var groups20: Array = []
	for f in face_list:
		var v0: Vector3 = iverts[f[0]]
		var v1: Vector3 = iverts[f[1]]
		var v2: Vector3 = iverts[f[2]]
		var outward: Vector3 = ((v0 + v1 + v2) / 3.0).normalized()
		var ref_dir: Vector3 = (REF_TETRA[0] as Vector3).normalized()
		var rot_axis: Vector3 = ref_dir.cross(outward)
		var basis: Basis
		if rot_axis.length() < 0.0001:
			basis = Basis.IDENTITY if ref_dir.dot(outward) > 0 else Basis(Vector3.RIGHT, PI)
		else:
			basis = Basis(rot_axis.normalized(), ref_dir.angle_to(outward))
		groups20.append(_rotated_tetra(basis))
	var cross20 := _n_way_cross_edges(groups20)
	print("  20-way coalescence (Uonite center): %d cross-edges (roll-convention-dependent, NOT a unique geometric fact -- see comment above)"
		% cross20)
	if cross20 != 847:
		_bad("20-way cross-edges %d, expected 847 under the documented roll convention" % cross20)

	var new_edges: int = 12 * cross5 + cross20
	print("  new edges from coalescence: 12 x %d (outer) + %d (center) = %d" % [cross5, cross20, new_edges])


## Grain-track cavity fill (added 2026-09-02): terminal pocket Sparks +
## their scaffold Monads, each pocket wired to its only two real neighbours
## (own vertex + shared centre one level up). Iota: one decompose level,
## 13 scaffold + 6 pockets = 19 new verts, 12 new edges (2 per pocket).
## Mote: two levels -- hand-derived 91 scaffold + 36 pockets = 127, but
## DIFFERENT Level-1 children's own Level-2 midpoints can coincide at the
## same real point (octahedron symmetry, invisible to the by-hand count
## since each child's own dedup never sees its siblings' allocations) --
## build_cavity_fill() compacts those by position identity, landing on the
## CODE-VERIFIED 115, not 127. Do not revert to 127 without re-deriving why.
const CAVITY_FILL_EXPECT := {
	3: [19, 12, 6],   # [new verts, new edges, terminal pockets]
	4: [115, 72, 36],
}

## Tetrad-SCALE (edge 1) cavity-tetrahedra count per tier -- the "tetrad"
## input of iota_assemble_grains/mote_assemble_grains. Iota's single
## decomposition level lands directly at edge 1 (8 total). Mote's TOP level
## (edge 4->2) also produces 8 tetrahedra, but at Particle scale (edge 2) --
## not counted here; only its 6 deeper (edge 2->1) branches, 8 each, are
## Tetrad-scale (48 total).
const CAVITY_TETRA_EXPECT := {
	3: 8,
	4: 48,
}


func _check_cavity_fill(inst, tier: int, tier_name: String, outer_pos: Array) -> void:
	if not CAVITY_FILL_EXPECT.has(tier):
		return
	var exp: Array = CAVITY_FILL_EXPECT[tier]

	var fill: Dictionary = inst.build_cavity_fill(outer_pos, tier)
	var fp: Array = fill["pos"]
	var fk: Array = fill["kind"]
	var fe: Array = fill["edges"]

	if fp.size() != int(exp[0]):
		_bad("%s cavity fill: %d new verts, expected %d" % [tier_name, fp.size(), exp[0]])
	if fe.size() != int(exp[1]):
		_bad("%s cavity fill: %d new edges, expected %d" % [tier_name, fe.size(), exp[1]])

	var spark_count := 0
	for k in fk:
		if int(k) == int(inst.KIND_SPARK):
			spark_count += 1
	if spark_count != int(exp[2]):
		_bad("%s cavity fill: %d terminal Spark pockets, expected %d" % [tier_name, spark_count, exp[2]])

	# Every terminal pocket must be degree exactly 2 -- its own vertex and
	# the shared centre one level up, its only two real neighbours.
	var base: int = outer_pos.size()
	var degree := {}
	for e in fe:
		var a: int = (e as Vector2i).x
		var b: int = (e as Vector2i).y
		degree[a] = int(degree.get(a, 0)) + 1
		degree[b] = int(degree.get(b, 0)) + 1
	var bad_degree := 0
	for i in fp.size():
		if int(fk[i]) == int(inst.KIND_SPARK):
			var d: int = int(degree.get(base + i, 0))
			if d != 2:
				bad_degree += 1
	if bad_degree > 0:
		_bad("%s cavity fill: %d terminal pockets have degree != 2" % [tier_name, bad_degree])

	# No cavity-fill vertex may coincide with a distinct outer-lattice or
	# sibling cavity-fill vertex -- same welding-integrity check as the
	# main recursion, applied to the new geometry.
	var all_new: Array = fp
	var min_sep := 1e20
	for i in range(all_new.size()):
		for j in range(i + 1, all_new.size()):
			var d: float = ((all_new[i] as Vector3) - (all_new[j] as Vector3)).length()
			if d < min_sep:
				min_sep = d
	if min_sep < 0.0001:
		_bad("%s cavity fill: coincident distinct new vertices (min sep %f)" % [tier_name, min_sep])

	print("    cavity fill: %d new verts (%d Spark pockets), %d new edges, all pockets degree 2 -- OK"
		% [fp.size(), spark_count, fe.size()])


## The 8 tetrahedra sibling to each level's 6 sub-octahedra (see
## archai_lattice.gd's _cavity_fill_recurse tetra_out doc) form a 3-cube
## adjacency graph: each pair shares that level's own centre plus however
## many of the 3 antipodal-pair picks they agree on. Verifies the
## well-known 3-cube pair-distance distribution (12 pairs differ in 1
## coordinate -> share 3 vertices, a full face; 12 differ in 2 -> share 2;
## 4 differ in 3, the opposite corners -> share only the centre) holds for
## real, per group of 8 (grouped by shared centre index). Iota has exactly
## 1 such group (all Tetrad-scale); Mote has 7: 1 at Particle scale (edge 2,
## the top-level 8, NOT what the recipe's "tetrad" cost means) + 6 at
## Tetrad scale (edge 1, one per Level-1 branch, the 48 that is).
func _check_cavity_tetrahedra(inst, tier: int, tier_name: String, outer_pos: Array) -> void:
	if not CAVITY_TETRA_EXPECT.has(tier):
		return
	var fill: Dictionary = inst.build_cavity_fill(outer_pos, tier)
	if not fill.has("tetrahedra"):
		_bad("%s: build_cavity_fill has no 'tetrahedra' key" % tier_name)
		return
	var tetras: Array = fill["tetrahedra"]

	var groups: Dictionary = {}   # centre index -> Array of tetra dicts
	for t in tetras:
		var centre: int = int((t as Dictionary)["idx"][0])
		if not groups.has(centre):
			groups[centre] = []
		(groups[centre] as Array).append(t)

	var tetrad_scale_count := 0
	for centre in groups:
		var group: Array = groups[centre]
		if group.size() != 8:
			_bad("%s: cavity-tetrahedra group at centre %d has %d members, expected 8"
				% [tier_name, centre, group.size()])
			continue

		var share3 := 0
		var share2 := 0
		var share1 := 0
		for i in range(8):
			for j in range(i + 1, 8):
				var a: Array = (group[i] as Dictionary)["idx"]
				var b: Array = (group[j] as Dictionary)["idx"]
				var shared := 0
				for v in a:
					if b.has(v):
						shared += 1
				match shared:
					3: share3 += 1
					2: share2 += 1
					1: share1 += 1
					_:
						_bad("%s: cavity-tetrahedra pair shares %d vertices, expected 1/2/3"
							% [tier_name, shared])
		if share3 != 12 or share2 != 12 or share1 != 4:
			_bad("%s: cavity-tetrahedra group at centre %d has share-distribution %d/%d/%d, expected 12/12/4 (face/edge/opposite-corner)"
				% [tier_name, centre, share3, share2, share1])

		var g_edge: float = float((group[0] as Dictionary)["edge"])
		if absf(g_edge - 1.0) < 0.0001:
			tetrad_scale_count += group.size()

	var expected: int = int(CAVITY_TETRA_EXPECT[tier])
	if tetrad_scale_count != expected:
		_bad("%s: %d Tetrad-scale cavity tetrahedra, expected %d"
			% [tier_name, tetrad_scale_count, expected])

	print("    cavity tetrahedra: %d groups of 8 (%d total, %d Tetrad-scale) -- share-distribution 12/12/4 OK"
		% [groups.size(), tetras.size(), tetrad_scale_count])


## A tier's own pre-existing central Spark may have real neighbours beyond
## its base-6: the cavity octahedron's 12 edge-midpoints, IF they happen to
## exactly coincide with a Monad already in the base lattice. Confirmed at
## Iota (all 12 are exact matches -- a corner Particle's own internal
## weld-points, carried through and offset when assembled into Iota).
## Particle is asserted at 0: its corners are raw Tetrads with no internal
## sub-structure of their own for a midpoint to coincide with. Tetrad and
## Mote are printed, NOT asserted -- Tetrad has no octahedral cavity at all
## (this check isn't meaningful there), and Mote's count was deliberately
## deferred by the user ("not yet, I want to see how things shake out at
## the iota level first"). Do not add an assertion for either without
## checking first.
func _check_extra_centroid_edges(inst, tier: int, tier_name: String, outer_pos: Array) -> void:
	var edges: Array = inst.extra_centroid_edges(outer_pos, tier)
	print("    extra centroid edges: %d real matches found" % edges.size())

	if tier == 2:
		if edges.size() != 0:
			_bad("%s: %d extra centroid edges, expected 0 (raw Tetrad corners, no sub-structure)"
				% [tier_name, edges.size()])
		return
	if tier == 3:
		if edges.size() != 12:
			_bad("%s: %d extra centroid edges, expected 12" % [tier_name, edges.size()])
		# Every match must be a genuinely distinct Monad, not the same one
		# twice, and not the central Spark's OWN existing 6 cavity edges.
		var spark_i: int = outer_pos.size() - 1
		var targets := {}
		for e in edges:
			var a: int = (e as Vector2i).x
			var b: int = (e as Vector2i).y
			if a != spark_i and b != spark_i:
				_bad("%s: extra centroid edge %s does not touch the central Spark" % [tier_name, e])
			var other: int = b if a == spark_i else a
			if targets.has(other):
				_bad("%s: extra centroid edge duplicated toward vertex %d" % [tier_name, other])
			targets[other] = true
		if targets.size() != 12:
			_bad("%s: extra centroid edges reach %d distinct vertices, expected 12"
				% [tier_name, targets.size()])
		return
	# tier == 4 (Mote): observe only, no assertion yet.


## Confirms the extra-centroid-edges finding at Iota isn't specific to a
## standalone Iota -- each of Mote's 4 corner-Iotas, embedded via nothing
## but a translation (_build_tier's own offset = corners[ci] * 0.5, no
## scaling; the whole recursion is purely affine), carries the SAME 12
## real-Monad matches for its own central Spark. Checked directly rather
## than assumed from the affine argument alone -- verified 2026-09-02, all
## 4 corners exactly 12/12. This is DISTINCT from Mote's own top-level
## central Spark's 12 (checked separately above, tier==4 in
## _check_extra_centroid_edges) -- a full Mote carries both: 4x12=48 from
## its embedded Iotas plus 12 from its own Spark = 60 total, not 48 alone.
func _check_embedded_corner_extra_edges(inst) -> void:
	var mote_lat: Dictionary = inst._build_tier(4)
	var mote_pos: Array = mote_lat["pos"]

	var iota_lat: Dictionary = inst._build_tier(3)
	var iota_pos: Array = iota_lat["pos"]
	var iota_spark_local: Vector3 = iota_pos[iota_pos.size() - 1]
	var iota_cav_local: Array = inst._cavity_verts(3)

	var mote_corners: Array = inst._tetra_corners(pow(2.0, 3.0))

	for ci in range(4):
		var offset: Vector3 = (mote_corners[ci] as Vector3) * 0.5
		var embedded_spark: Vector3 = iota_spark_local + offset

		var spark_idx := -1
		for i in mote_pos.size():
			if (mote_pos[i] as Vector3).is_equal_approx(embedded_spark):
				spark_idx = i
				break
		if spark_idx == -1:
			_bad("embedded corner-Iota %d: own central Spark not found in Mote's lattice" % ci)
			continue

		var matches := 0
		for i in range(6):
			var anti: int = inst._octa_antipode(iota_cav_local, i)
			for j in range(6):
				if j <= i or j == anti:
					continue
				var m: Vector3 = ((iota_cav_local[i] as Vector3) + (iota_cav_local[j] as Vector3)) * 0.5 + offset
				var found := false
				for k in mote_pos.size():
					if (mote_pos[k] as Vector3).is_equal_approx(m):
						found = true
						break
				if found:
					matches += 1

		if matches != 12:
			_bad("embedded corner-Iota %d: %d/12 extra-centroid matches, expected 12" % [ci, matches])

	if fails == 0:
		print("  embedded corner-Iotas: all 4 confirmed 12/12 extra-centroid matches -- OK")


func run() -> void:
	var ls := load("res://archai_lattice.gd")
	if ls == null or not ls.can_instantiate():
		_bad("archai_lattice.gd does not compile (can_instantiate() == false)")
		print("FAILURES (%d failures)" % fails)
		finish()
		return

	var inst = ls.new()
	var tbd: int = int(ls.MONAD_TBD)
	var spark: int = int(ls.KIND_SPARK)

	var cross := _stella_cross_edge_count()
	if cross != 12:
		_bad("stella octangula cross-edges: got %d, expected 12" % cross)
	else:
		print("  stella octangula cross-edges: 12 -- OK (each vertex ties for nearest with 3 of the other tetrahedron's 4)")

	_check_n_way_coalescence()

	for tier in [1, 2, 3, 4]:
		var lat: Dictionary = inst._build_tier(tier)
		var pos: Array = lat["pos"]
		var kind: Array = lat["kind"]
		var edges: Array = lat["edges"]

		var monads: int = 0
		var sparks: int = 0
		for k in kind:
			if int(k) == tbd:
				monads += 1
			elif int(k) == spark:
				sparks += 1

		var exp: Array = EXPECT[tier]
		var got := [pos.size(), monads, sparks, edges.size()]
		print("  tier %d %-9s verts=%-4d monad=%-4d spark=%-3d edges=%-4d"
			% [tier, TIER_NAMES[tier], got[0], got[1], got[2], got[3]])

		if int(got[0]) != int(exp[0]):
			_bad("tier %d verts %d, expected %d" % [tier, got[0], exp[0]])
		if int(got[1]) != int(exp[1]):
			_bad("tier %d monads %d, expected %d" % [tier, got[1], exp[1]])
		if int(got[2]) != int(exp[2]):
			_bad("tier %d sparks %d, expected %d" % [tier, got[2], exp[2]])
		if int(got[3]) != int(exp[3]):
			_bad("tier %d edges %d, expected %d" % [tier, got[3], exp[3]])
		if kind.size() != pos.size():
			_bad("tier %d kind/pos length mismatch (%d vs %d)"
				% [tier, kind.size(), pos.size()])

		# No two DISTINCT vertices may occupy the same point. Sub-units touch
		# only at shared midpoints, and those are one vertex by construction.
		var min_sep: float = 1e20
		for i in range(pos.size()):
			for j in range(i + 1, pos.size()):
				var d: float = ((pos[i] as Vector3) - (pos[j] as Vector3)).length()
				if d < min_sep:
					min_sep = d
		if min_sep < 0.0001:
			_bad("tier %d has coincident distinct vertices (min separation %f) "
				% [tier, min_sep] + "-- corner welding is broken")

		# Edges must be in range, non-degenerate, and unique.
		var seen := {}
		var dupes: int = 0
		var degenerate: int = 0
		var out_of_range: int = 0
		for e in edges:
			var a: int = int((e as Vector2i).x)
			var b: int = int((e as Vector2i).y)
			if a < 0 or b < 0 or a >= pos.size() or b >= pos.size():
				out_of_range += 1
				continue
			if a == b:
				degenerate += 1
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(key):
				dupes += 1
			else:
				seen[key] = true
		if out_of_range > 0:
			_bad("tier %d has %d edge endpoints out of range" % [tier, out_of_range])
		if degenerate > 0:
			_bad("tier %d has %d self-loop edges" % [tier, degenerate])
		if dupes > 0:
			_bad("tier %d has %d duplicate edges" % [tier, dupes])

		# Degree of the LAST vertex: the Spark added by this assembly step.
		# 4 spokes inside a bare Tetrad, 6 into the octahedral gap above it.
		var last: int = pos.size() - 1
		var deg: int = 0
		for e in edges:
			if int((e as Vector2i).x) == last or int((e as Vector2i).y) == last:
				deg += 1
		var want_deg: int = 4 if tier == 1 else 6
		if deg != want_deg:
			_bad("tier %d central Spark has degree %d, expected %d"
				% [tier, deg, want_deg])

		_check_weld_multiplicity(inst, tier, TIER_NAMES[tier], int(exp[1]))
		_check_stella_expansion(tier, TIER_NAMES[tier], int(exp[2]), int(exp[3]))
		_check_cavity_fill(inst, tier, TIER_NAMES[tier], pos)
		_check_cavity_tetrahedra(inst, tier, TIER_NAMES[tier], pos)
		_check_extra_centroid_edges(inst, tier, TIER_NAMES[tier], pos)

	# Geometry spot-check: a Particle's 10 Monads must sit at the 4 corners
	# and 6 edge midpoints of its edge-2 tetrahedron, so exactly 4 of them are
	# a full edge-length (2.0) from the centroid-most distant pair... simpler
	# and stronger: every Monad-Monad edge in a Tetrad has length 1.
	var t1: Dictionary = inst._build_tier(1)
	var p1: Array = t1["pos"]
	for e in t1["edges"]:
		var a: int = int((e as Vector2i).x)
		var b: int = int((e as Vector2i).y)
		if int(t1["kind"][a]) == tbd and int(t1["kind"][b]) == tbd:
			var l: float = ((p1[a] as Vector3) - (p1[b] as Vector3)).length()
			if absf(l - 1.0) > 0.0001:
				_bad("Tetrad Monad-Monad edge length %f, expected 1.0" % l)

	_check_embedded_corner_extra_edges(inst)

	inst.free()

	# ---- Scene wiring (v2.0.0: open-button + LatticePanel overlay) -------
	# The geometry being right is not the same as anything being ON SCREEN.
	# ArchaiLatticeViewer.tscn is now just a Button (archai_lattice_panel.gd)
	# that looks up LatticePanel.tscn by name and calls open() -- mirrors
	# constellation_panel.gd's StudyButton / ConstellationStudyOverlay
	# pattern exactly, so the two scenes are tested both independently and
	# wired together, the same way a real click would exercise them.
	var button_scene := load("res://ArchaiLatticeViewer.tscn")
	var panel_scene := load("res://LatticePanel.tscn")
	if button_scene == null or not button_scene.can_instantiate():
		_bad("ArchaiLatticeViewer.tscn missing or will not instantiate")
	elif panel_scene == null or not panel_scene.can_instantiate():
		_bad("LatticePanel.tscn missing or will not instantiate")
	else:
		var button = button_scene.instantiate()
		var panel = panel_scene.instantiate()
		# Both live under the same scene, same as RootUI/FirmamentUI's own
		# CanvasLayer -- find_child("LatticePanel") needs a shared ancestor.
		root.add_child(button)
		root.add_child(panel)
		await process_frame
		await process_frame

		var mi = panel.get_node_or_null(
			"CenterContainer/PanelContainer/OuterMargin/OuterVBox/ViewportContainer/LatticeViewport/ArchaiLattice")
		if mi == null:
			_bad("LatticePanel.tscn has no .../ViewportContainer/LatticeViewport/ArchaiLattice")
		elif mi.mesh == null:
			_bad("lattice built no mesh after _ready()")
		elif int(mi.mesh.get_surface_count()) < 1:
			_bad("lattice mesh has 0 surfaces")
		else:
			var ab: AABB = mi.mesh.get_aabb()
			var big: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
			print("  panel mesh: %d surface(s), aabb size %.3f"
				% [mi.mesh.get_surface_count(), big])
			if big < 0.001:
				_bad("lattice mesh AABB is degenerate (%f) -- nothing to draw" % big)

		var vp = panel.get_node_or_null(
			"CenterContainer/PanelContainer/OuterMargin/OuterVBox/ViewportContainer/LatticeViewport")
		if vp == null or mi == null:
			_bad("cannot reach panel sub-nodes to test open/close")
		elif not panel.has_method("open"):
			_bad("LatticePanel script exposes no open()")
		else:
			# Starts closed -- the overlay must not intrude until the button
			# is pressed. Mesh is still built above (child _ready() runs
			# before parent), so opening later shows a finished lattice.
			if bool(panel.visible):
				_bad("fresh panel is visible; should start closed")
			if bool(mi.is_processing()):
				_bad("fresh panel is processing; should start idle")
			if int(vp.render_target_update_mode) != int(SubViewport.UPDATE_DISABLED):
				_bad("fresh panel viewport should start UPDATE_DISABLED (mode %d)"
					% int(vp.render_target_update_mode))

			# The button's own press handler is what real play exercises --
			# call it directly rather than open() on the panel, so a broken
			# find_child lookup (e.g. wrong node name) is caught here rather
			# than only when a player actually clicks it.
			button._on_pressed()
			if not bool(panel.visible):
				_bad("button press: panel did not open")
			if int(vp.render_target_update_mode) != int(SubViewport.UPDATE_ALWAYS):
				_bad("button press: viewport did not resume updating")
			if not bool(mi.is_processing()):
				_bad("button press: lattice did not resume processing")

			panel._on_close()
			if bool(panel.visible):
				_bad("close: panel still visible")
			if int(vp.render_target_update_mode) != int(SubViewport.UPDATE_DISABLED):
				_bad("close: viewport still updating (mode %d)" % int(vp.render_target_update_mode))
			if bool(mi.is_processing()):
				_bad("close: lattice still processing each frame")
			if fails == 0:
				print("  open/close: button press opens + resumes render/process, close stops both")

		button.queue_free()
		panel.queue_free()
		await process_frame

	# Both UI scenes are hand-edited to instance the viewer. Parse them (do
	# NOT instantiate -- they pull in autoloads) so a malformed edit is caught
	# here rather than as a blank screen.
	for ui in ["res://RootUI.tscn", "res://FirmamentUI.tscn"]:
		var packed := load(ui)
		if packed == null or not packed.can_instantiate():
			_bad("%s failed to load -- scene file may be malformed" % ui)
		else:
			var st: SceneState = (packed as PackedScene).get_state()
			var found_button := false
			var found_panel := false
			for i in range(st.get_node_count()):
				var n := str(st.get_node_name(i))
				if n == "ArchaiLatticeViewer":
					found_button = true
				elif n == "LatticePanel":
					found_panel = true
			if not found_button:
				_bad("%s parses but does not instance ArchaiLatticeViewer" % ui)
			elif not found_panel:
				_bad("%s parses but does not instance LatticePanel" % ui)
			else:
				print("  %s OK, button + panel both instanced" % ui)

	if fails == 0:
		print("ALL PASS (%d failures)" % fails)
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
