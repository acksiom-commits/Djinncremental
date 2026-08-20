extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# DEPLOY PREP + FOURTEENTH SLICE (2026-08-18). Two changes measured
# together:
#
#   1. _prune_redundant_clues now YIELDS every PRUNE_YIELD_INTERVAL
#      candidates. It was ~2.7s of fully synchronous solving per puzzle on
#      the LIVE path (generate_clues_forms -> _generate_clues_forms_attempt),
#      i.e. a full-stop freeze — the exact bug the YIELD_INTERVAL note
#      above the main loop records as already fixed once. Under the
#      headless runner _host is null, so nothing suspends and results must
#      be IDENTICAL to 10579ce; this run is what proves that.
#
#   2. Pairwise Order wired into the closure via Group Order's existing
#      _name_order_vs_group_facts (no new fact kind). Gated on
#      axis == SEQUENCE, since the validator compares sequence ranks.
#
# The REFRAME this slice tests: with closure already at 20/20, more Form
# wiring no longer buys solvability — it buys VOCABULARY. Pruning drops a
# clue whenever removing it doesn't raise the solution count, so
# NON-FEEDING Forms are always provably-safe removals and get cut first.
# Post-prune shares bear that out exactly: every WIRED Form sits at
# 3-10%, every UNWIRED one under 1%. If wiring Pairwise Order lifts it out
# of the 0.1% floor, the hypothesis holds and the remaining Forms are
# worth batching.
#
# BASELINE is 10579ce (pruning landed), standard 8x5:
#     clues/puzzle 39.5     Forms firing 20/23    dominant 34%
#     Pairwise Order 2 of 1581 clues (0.1%)
# and on the 4-seed prune sample: seq_unique 20/20, closures 20/20,
# contradictions 0, anchor losses 0.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555, 77, 909090, 13, 24601]

	var form_dist: Dictionary = {}
	var puzzles: int = 0
	var seq_ok: int = 0
	var closures: int = 0
	var contradictions: int = 0
	var clues: Array = []
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
			puzzles += 1
			clues.append(g.chosen_form_clues.size())
			for clue in g.chosen_form_clues:
				var fn: String = str(clue.get("form_name", "?"))
				form_dist[fn] = int(form_dist.get(fn, 0)) + 1
			if bool(result.get("seq_unique", false)):
				seq_ok += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1
				if bool(result.get("name_unique_closure", false)):
					closures += 1

	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	clues.sort()
	var total_c: int = 0
	for k in form_dist.keys():
		total_c += int(form_dist[k])

	print("\n  puzzles: %d   (%.0fs)   total clues: %d" % [puzzles, elapsed, total_c])
	print("  seq_unique:     %d / %d      [baseline 40/40]" % [seq_ok, puzzles])
	print("  CONTRADICTIONS: %d / %d      [MUST be 0]" % [contradictions, seq_ok])
	print("  full closures:  %d / %d      [baseline 40/40 — must NOT regress]" % [closures, seq_ok])
	print("  clues/puzzle:   median=%d mean=%.1f   [baseline 39.5 mean]\n"
		% [int(clues[clues.size() / 2]), float(total_c) / float(maxi(1, puzzles))])

	var names: Array = form_dist.keys()
	names.sort_custom(func(a, b): return int(form_dist[a]) > int(form_dist[b]))
	var top_n: int = 0
	for f in names:
		var c: int = int(form_dist[f])
		if c > top_n:
			top_n = c
		var flag: String = ""
		if str(f) == "Pairwise Order":
			flag = "   <-- WIRED THIS SLICE (was 2 / 0.1%)"
		print("    %-32s %5d  (%.1f%%)%s" % [f, c, 100.0 * float(c) / float(maxi(1, total_c)), flag])

	print("\n  Forms firing: %d of 23     dominant %.0f%%   [baseline 20/23, 34%%]"
		% [names.size(), 100.0 * float(top_n) / float(maxi(1, total_c))])

	if contradictions > 0:
		print("\n  !! CONTRADICTIONS — the Pairwise Order reading is unsound, revert !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
