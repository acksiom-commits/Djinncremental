extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# PHASE 2 THIRTEENTH SLICE (2026-08-18): Dual Negation wired into
# _solve_name_closure(). Picked by a fresh post-fix survey (cost structure
# changed completely today — cascade + zebratutor pass both removed):
# 2922 clues, 87% naming a star (2553), zero feeding, by a huge margin the
# largest unwired source. "Neither X nor Y is V" split into two
# independent _name_group_facts calls, reusing Single Negation's exact
# proven shape — no new fact kind, no new validator.
#
# BASELINE is commit 87a1abe (zebratutor removed, cascade already gone),
# same 4-seed sample used for that A/B:
#     seq_unique 20/20   contradictions 0   full closures 1/20
#     closure: min=1 median=12 max=54 mean=15
#     clues/puzzle: median=306 mean=289
#     distribution: [1,2,3,3,4,5,6,8,10,11,12,12,14,16,16,23,24,28,44,54]
#
# CONTRADICTIONS is still the check that overrides everything else — the
# reused _name_group_facts machinery has been sound for 13 slices, but a
# nonzero count here would mean the (id1,false_val)/(id2,false_val)
# splitting is wrong regardless of what the counts show.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555]

	var clues: Array = []
	var sols: Array = []
	var seq_ok: int = 0
	var closures: int = 0
	var contradictions: int = 0
	var n: int = 0
	var t0: int = Time.get_ticks_msec()

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
			n += 1
			clues.append(g.chosen_form_clues.size())
			if bool(result.get("seq_unique", false)):
				seq_ok += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1
				if bool(result.get("name_unique_closure", false)):
					closures += 1
				sols.append(g._solve_name_closure(result.get("seq_solutions", []) as Array, 5000).size())

	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	clues.sort()
	sols.sort()
	var csum: int = 0
	for c in clues:
		csum += int(c)
	var ssum: int = 0
	for s in sols:
		ssum += int(s)

	print("\n  puzzles: %d   (%.0fs)" % [n, elapsed])
	print("  seq_unique:      %d / %d      [baseline 20/20]" % [seq_ok, n])
	print("  CONTRADICTIONS:  %d / %d      [MUST be 0]" % [contradictions, seq_ok])
	print("  full closures:   %d / %d      [baseline 1/20]" % [closures, seq_ok])
	print("  clues/puzzle:    median=%d mean=%.0f   [baseline 306 / 289]"
		% [int(clues[clues.size() / 2]), float(csum) / float(maxi(1, clues.size()))])
	if not sols.is_empty():
		print("  closure:         min=%d median=%d max=%d mean=%.0f   [baseline 1 / 12 / 54 / 15]"
			% [int(sols[0]), int(sols[sols.size() / 2]), int(sols[sols.size() - 1]),
				float(ssum) / float(sols.size())])
		print("  distribution:    %s" % str(sols))

	if contradictions > 0:
		print("\n  !! CONTRADICTIONS — unsound, revert !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
