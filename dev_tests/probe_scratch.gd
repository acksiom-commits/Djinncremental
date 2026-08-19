extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# PHASE 2 TWELFTH SLICE (2026-08-18): distance_hop wired into
# _solve_name_closure(). Chosen after a READ-ONLY diagnostic (not a guess):
# 123 of 318 distance facts carry ref_cat==NAME, they reach 118 distinct
# names of which 42 are currently unconstrained (32% of the 131-name gap),
# and only 4 of 123 constrain nothing. Expected LOOSE though — median 8 of
# ~15.8 positions survive per fact, only 3 of 123 pin outright — so the
# real hope is INTERSECTION: 76 of those 118 names already carry a
# constraint, and a second independent one can collapse them.
#
# BASELINE is commit 6c9004a (the eleventh slice), same seeds:
#     exact pin        136  (21.5%)
#     group/order      293  (46.4%)
#     same-group        72  (11.4%)
#     UNTOUCHED        131  (20.7%)
#     contradictions   0 / 38
#     full closures    0 / 38
#     TRUE solutions   144 / 732 / 2312 / 2880, then 5000-cap x34
#
# Distance is a NARROWING, not a membership/pin kind, so it does NOT move
# a name between the coverage buckets above — a name whose only constraint
# is a hop still counts as "untouched" in that classification, which reads
# the same five name_* kinds it always has. The number that matters for
# this slice is therefore the TRUE SOLUTION COUNT, not the buckets.
#
# CONTRADICTIONS is still the load-bearing check: 0/N across all twelve
# slices is what proves the closure sound rather than merely under-fed. A
# nonzero count means the distance reading (especially the negated one) is
# WRONG and must be reverted regardless of what the counts did.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555, 77, 909090, 13, 24601]

	var puzzles: int = 0
	var contradictions: int = 0
	var closures_attempted: int = 0
	var full_closures: int = 0
	var solution_counts: Array = []

	for cid in [0, 1, 2, 3, 4]:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in seeds:
			var g = load("res://constellation_logic_puzzle.gd").new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid,
				cdef.get("name_theme", {}), cd.get_note_assignment(cid),
				cd.get_note_freqs(cid), null)
			var result: Dictionary = await g._generate_clues_forms_attempt()
			puzzles += 1

			if bool(result.get("seq_unique", false)):
				closures_attempted += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1
				if bool(result.get("name_unique_closure", false)):
					full_closures += 1
				var seq_sols: Array = result.get("seq_solutions", []) as Array
				solution_counts.append(g._solve_name_closure(seq_sols, 5000).size())

	print("\n  puzzles: %d" % puzzles)
	print("  CONTRADICTIONS: %d / %d   [MUST be 0 — 0/N across all 12 slices]"
		% [contradictions, closures_attempted])
	print("  FULL CLOSURES:  %d / %d   [0/N for all 11 prior slices]"
		% [full_closures, closures_attempted])

	if not solution_counts.is_empty():
		var sorted_counts: Array = solution_counts.duplicate()
		sorted_counts.sort()
		var sum: int = 0
		for v in sorted_counts:
			sum += int(v)
		print("\n  TRUE surviving name-solutions (cap 5000):")
		print("    min=%d  median=%d  max=%d  mean=%.1f"
			% [int(sorted_counts[0]), int(sorted_counts[sorted_counts.size() / 2]),
				int(sorted_counts[sorted_counts.size() - 1]),
				float(sum) / float(sorted_counts.size())])
		print("    BASELINE (6c9004a): min=144  median=5000  max=5000  mean=4633.4")
		var capped: int = 0
		var near: int = 0
		for v2 in sorted_counts:
			if int(v2) >= 5000:
				capped += 1
			if int(v2) <= 4:
				near += 1
		print("    still cap-limited: %d / %d   [baseline 34 / 38]" % [capped, sorted_counts.size()])
		print("    within 4 of closing: %d / %d   [baseline 0 / 38]" % [near, sorted_counts.size()])
		print("    full distribution: %s" % str(sorted_counts))

	if contradictions > 0:
		print("  !! CONTRADICTIONS — the distance reading is unsound, revert !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
