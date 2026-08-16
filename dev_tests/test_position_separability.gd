extends "res://dev_tests/test_base.gd"
# Every map POSITION must be distinguishable from every other by what the
# player can observe: visible colour, audible pitch, and hop distance.
#
# If two are not, every clue predicate over observables answers the same for
# both, swapping them gives a second consistent solution, and the puzzle has
# no unique answer. In play that is indistinguishable from a propagation
# bug — the player stalls and cannot tell why.
#
# Measured before the fix, varying BOTH the pitch assignment and the colour
# assignment: Archon 2 of 24, Bellows 1 of 24, and zero for the three fully
# connected constellations. It concentrates where topology is weak.
#
# _separate_indistinguishable_positions() reshuffles colour until the
# observables separate everything. Colour is the only lever — topology is
# authored art and the pitch list is the musical theme — and it suffices:
# the largest class pitch and topology leave unseparated is 3 (Bellows,
# {0,1,2}), against 4 colours.
#
# The at-risk set is NOT a constellation constant: it moves with the pitch
# seed, which reset_note_assignment() rerolls on every new puzzle. Measured
# over 12 pitch seeds with colour excluded — Archon produced 7 distinct
# at-risk sets ({10,11}, {9,11}, {9,10}, {7,8}, {3,4}, {6,7}, none) and
# Bellows 5. So there is no per-constellation table of "the bad pair" to
# author instead of this check; an earlier reading that suggested otherwise
# came from holding the pitch seed fixed.
#
# The check here is deliberately INDEPENDENT of that implementation: it
# recomputes refinement from the authored line_pairs and the finished
# star_colors / pitch data, rather than calling the generator's own
# predicate. A test that asks the code whether the code is right proves
# nothing.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## Refinement classes over observable labels, computed here from scratch.
func _classes(scn: int, adj: Dictionary, labels: Array) -> Array:
	var lab: Array = labels.duplicate()
	for _round in scn:
		var sig: Array = []
		for s in scn:
			var neigh: Array = []
			for n in (adj[int(s)] as Array):
				neigh.append(str(lab[int(n)]))
			neigh.sort()
			sig.append("%s|%s" % [str(lab[int(s)]), ",".join(neigh)])
		var seen: Dictionary = {}
		var nxt: Array = []
		for s2 in scn:
			var k: String = str(sig[int(s2)])
			if not seen.has(k):
				seen[k] = str(seen.size())
			nxt.append(str(seen[k]))
		if str(nxt) == str(lab):
			break
		lab = nxt
	var groups: Dictionary = {}
	for s3 in scn:
		var k2: String = str(lab[int(s3)])
		if not groups.has(k2):
			groups[k2] = []
		(groups[k2] as Array).append(int(s3))
	var out: Array = []
	for g in groups:
		out.append(groups[g])
	return out


func run() -> void:
	var checked: int = 0
	var violations: int = 0
	var reshuffles: int = 0
	var failed_search: int = 0

	for cid in [0, 1, 2, 3, 4]:
		var cd = load("res://constellation_data.gd").new()
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		var lp: Array = cdef["line_pairs"]
		var adj: Dictionary = {}
		for s in scn:
			adj[int(s)] = []
		for i in range(0, lp.size() - 1, 2):
			(adj[int(lp[i])] as Array).append(int(lp[i + 1]))
			(adj[int(lp[i + 1])] as Array).append(int(lp[i]))

		var per_c: int = 0
		# Both variables the real game moves: the pitch assignment (reshuffled
		# by reset_note_assignment on every new puzzle) and the colour draw.
		for pitch_seed in [1, 2, 3, 4, 5, 6]:
			cd.note_assignment_seed_overrides[str(cid)] = pitch_seed
			var note_assign: Array = cd.get_note_assignment(cid)
			for colour_seed in [11, 4242, 31337, 55555]:
				var g = load("res://constellation_logic_puzzle.gd").new()
				var sq: Array = []
				for i2 in range(scn):
					sq.append(i2)
				g.setup(scn, cdef["line_pairs"], sq, colour_seed, cid,
					cdef.get("name_theme", {}), note_assign,
					cd.get_note_freqs(cid), null)
				checked += 1
				reshuffles += int(g._color_reshuffles_used)
				if bool(g._color_separation_failed):
					failed_search += 1

				var labels: Array = []
				for s2 in scn:
					labels.append("%d/%f" % [int(g.star_colors[s2]), g._freq_for_star(int(s2))])
				for c in _classes(scn, adj, labels):
					if (c as Array).size() > 1:
						violations += 1
						per_c += 1
						if per_c <= 2:
							print("    c%d pitch %d colour %d: interchangeable %s"
								% [cid, pitch_seed, colour_seed, str(c)])
						break
		print("  c%d %-13s %d of 24 still under-determined"
			% [cid, str(cdef.get("name", "?")), per_c])

	print("\n  puzzles checked: %d, colour reshuffles used in total: %d" % [checked, reshuffles])
	# Non-vacuity: "0 violations" is also what checking nothing reports.
	ok(checked >= 100, "checked a meaningful number of puzzles (%d)" % checked)
	ok(violations == 0,
		"every position is separable by colour + pitch + topology (%d violations)" % violations)
	ok(failed_search == 0,
		"the colour search never ran out of attempts (%d gave up)" % failed_search)
	# The filter must be DOING something on the constellations that need it,
	# or this passes because the problem stopped occurring for another reason.
	ok(reshuffles > 0,
		"the filter actually reshuffled at least once (%d) — otherwise this "
			% reshuffles + "test would pass even with the filter removed")

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
