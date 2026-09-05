extends "res://dev_tests/test_base.gd"
# Verifies the corrected octahedral cavity decomposition in archai_lattice.gd
# (6 octahedra + 8 tetrahedra sharing ONE shared centre, edge halved each
# level -- NOT the earlier vertex-truncation guess, which left an
# unaccounted cuboctahedron remainder) and answers the user's exact
# question: given real coordinates, how many connections does
#
#   near-external-face cavity Sparks -> 4 nearest Monads (normal tetrad range)
#   interior cavity Sparks           -> 4 nearest OTHER cavity Sparks
#
# actually produce for Iota (6 pockets) and Mote (36 pockets)?
#
# Near/far is NOT assumed -- it is measured. Each pocket's distance to the
# nearest real Monad vertex in the tier's own bare lattice is computed.
#
# Mote's 36 distances split cleanly: 30 pockets at 0.707, 6 at 1.225 -- a
# real, wide gap, not noise. Iota's 6 distances are ALL exactly 0.707 --
# tied, because a single octahedron's 6 vertices are symmetric under its own
# symmetry group, so there is no genuine near/far distinction to find
# WITHIN Iota's own data. Hunting for "the biggest gap" in tied numbers
# would manufacture a fake split (verified: it does, arbitrarily, off sort
# order). So the threshold is measured ONCE from Mote -- the only tier with
# a real gap -- and applied as a fixed distance to both tiers. Iota's 0.707
# matches Mote's near-face cluster exactly, so all 6 of Iota's pockets
# land near-face under this shared threshold, which is the geometrically
# honest answer: at Iota's cavity SIZE, every terminal pocket genuinely IS
# that close to the real Monad lattice.

var fails: int = 0


func _bad(msg: String) -> void:
	fails += 1
	print("    FAIL: %s" % msg)


func _nearest_k(from: Vector3, pool: Array, k: int, exclude_i: int = -1) -> Array:
	# pool: Array of Vector3. Returns indices of the k nearest (excluding
	# exclude_i, for self-exclusion when pool == the pocket list itself).
	var dists: Array = []
	for i in pool.size():
		if i == exclude_i:
			continue
		dists.append([((pool[i] as Vector3) - from).length(), i])
	dists.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in range(mini(k, dists.size())):
		out.append(int(dists[i][1]))
	return out


func _analyze(inst, tier: int, tier_name: String, threshold: float) -> void:
	print("  -- %s (tier %d) --" % [tier_name, tier])

	var lat: Dictionary = inst._build_tier(tier)
	var pos: Array = lat["pos"]
	var kind: Array = lat["kind"]
	var tbd: int = int(inst.MONAD_TBD)

	var monad_pos: Array = []
	for i in pos.size():
		if int(kind[i]) == tbd:
			monad_pos.append(pos[i])

	var pockets: Array = inst.cavity_pockets(tier)
	var expect: int = 6 if tier == 3 else (36 if tier == 4 else 1)
	if pockets.size() != expect:
		_bad("%s: got %d cavity pockets, expected %d" % [tier_name, pockets.size(), expect])
	for p in pockets:
		if absf(float(p["edge"]) - 1.0) > 0.01:
			_bad("%s: a terminal pocket has edge %f, expected 1.0" % [tier_name, p["edge"]])

	var pocket_pos: Array = []
	for p in pockets:
		pocket_pos.append(p["center"])

	# Distance from each pocket to its nearest real Monad.
	var nearest_monad_dist: Array = []
	for pp in pocket_pos:
		var best := INF
		for mp in monad_pos:
			best = minf(best, ((mp as Vector3) - (pp as Vector3)).length())
		nearest_monad_dist.append(best)

	var sorted_d: Array = nearest_monad_dist.duplicate()
	sorted_d.sort()
	print("    nearest-Monad distances (sorted): %s"
		% [sorted_d.map(func(d): return "%.3f" % d)])
	print("    using threshold %.3f (see Mote below for where this comes from)" % threshold)

	var near_idx: Array = []
	var far_idx: Array = []
	for i in pocket_pos.size():
		if nearest_monad_dist[i] <= threshold:
			near_idx.append(i)
		else:
			far_idx.append(i)
	print("    near-face pockets: %d,  interior pockets: %d" % [near_idx.size(), far_idx.size()])

	# Near-face: connect to 4 nearest Monads each.
	var near_edges := near_idx.size() * 4

	# Interior: connect to 4 nearest OTHER cavity pockets each, deduped as
	# an undirected graph (a pair counted once even if each nominates the
	# other).
	var far_pair_set := {}
	for i in far_idx:
		var nn: Array = _nearest_k(pocket_pos[i], pocket_pos, 4, i)
		for j in nn:
			var key := Vector2i(mini(i, j), maxi(i, j))
			far_pair_set[key] = true
	var far_edges := far_pair_set.size()

	print("    edges: near-face %d (= %d x 4)   interior %d (deduped undirected pairs)"
		% [near_edges, near_idx.size(), far_edges])
	print("    TOTAL new connections for one %s's cavity Sparks: %d"
		% [tier_name, near_edges + far_edges])


func _monad_positions(inst, tier: int) -> Array:
	var lat: Dictionary = inst._build_tier(tier)
	var pos: Array = lat["pos"]
	var kind: Array = lat["kind"]
	var tbd: int = int(inst.MONAD_TBD)
	var out: Array = []
	for i in pos.size():
		if int(kind[i]) == tbd:
			out.append(pos[i])
	return out


func _pocket_monad_distances(inst, tier: int, monad_pos: Array) -> Array:
	var pockets: Array = inst.cavity_pockets(tier)
	var out: Array = []
	for p in pockets:
		var pp: Vector3 = p["center"]
		var best := INF
		for mp in monad_pos:
			best = minf(best, ((mp as Vector3) - pp).length())
		out.append(best)
	return out


func run() -> void:
	var ls := load("res://archai_lattice.gd")
	if ls == null or not ls.can_instantiate():
		_bad("archai_lattice.gd does not compile")
		print("FAILURES (%d failures)" % fails)
		finish()
		return

	var inst = ls.new()

	# Sanity check: Particle's cavity is already terminal, 1 pocket.
	var p_pockets: Array = inst.cavity_pockets(2)
	if p_pockets.size() != 1:
		_bad("Particle cavity: got %d pockets, expected 1 (already terminal)" % p_pockets.size())

	# Derive the threshold from Mote alone -- the only tier with a real gap.
	var mote_monads: Array = _monad_positions(inst, 4)
	var mote_dists: Array = _pocket_monad_distances(inst, 4, mote_monads)
	var sorted_md: Array = mote_dists.duplicate()
	sorted_md.sort()
	var split_at := -1
	var biggest_gap := -1.0
	for i in range(sorted_md.size() - 1):
		var gap: float = float(sorted_md[i + 1]) - float(sorted_md[i])
		if gap > biggest_gap:
			biggest_gap = gap
			split_at = i
	var threshold: float = (float(sorted_md[split_at]) + float(sorted_md[split_at + 1])) * 0.5
	print("  Mote gap check: largest gap %.3f, between rank %d (%.3f) and %d (%.3f) -> threshold %.3f"
		% [biggest_gap, split_at, sorted_md[split_at], split_at + 1, sorted_md[split_at + 1], threshold])
	if biggest_gap < 0.1:
		_bad("Mote's distances have no real gap (%.3f) -- threshold is not meaningful" % biggest_gap)

	_analyze(inst, 3, "Iota", threshold)
	_analyze(inst, 4, "Mote", threshold)

	inst.free()

	if fails == 0:
		print("ALL PASS (%d failures)" % fails)
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
