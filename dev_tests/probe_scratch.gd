extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# VERIFYING THE ZEBRATUTOR REMOVAL (2026-08-18). The A/B that justified it
# ran with the pass still present and toggled by a flag; this re-measures
# the shipped path with the pass and its instrumentation actually gone, to
# confirm the numbers hold and nothing else moved.
#
# Expected, from the A/B (20 puzzles/arm, 4 seeds x 5 constellations):
#     full closures     0 -> 1        closure median   29 -> 12
#     closure mean    246 -> 15       closure worst  2848 -> 54
#     clues/puzzle    258 -> 289      cells marked    688 -> 0
#     seq_unique 20/20 and contradictions 0 in BOTH arms; Forms 22 in both.
#
# Same 4 seeds as that A/B so the "disabled" column is directly comparable.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555]

	var clues: Array = []
	var pools: Array = []
	var sols: Array = []
	var seq_ok: int = 0
	var closures: int = 0
	var contradictions: int = 0
	var n: int = 0
	var forms: Dictionary = {}
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
			pools.append(g._unused_pool_size())
			for clue in g.chosen_form_clues:
				var fn: String = str(clue.get("form_name", "?"))
				forms[fn] = int(forms.get(fn, 0)) + 1
			if bool(result.get("seq_unique", false)):
				seq_ok += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1
				if bool(result.get("name_unique_closure", false)):
					closures += 1
				sols.append(g._solve_name_closure(result.get("seq_solutions", []) as Array, 5000).size())

	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	clues.sort()
	pools.sort()
	sols.sort()
	var csum: int = 0
	for c in clues:
		csum += int(c)
	var ssum: int = 0
	for s in sols:
		ssum += int(s)

	print("\n  puzzles: %d   (%.0fs)" % [n, elapsed])
	print("  seq_unique:      %d / %d      [expect 20/20]" % [seq_ok, n])
	print("  CONTRADICTIONS:  %d / %d      [MUST be 0]" % [contradictions, seq_ok])
	print("  full closures:   %d / %d      [expect 1]" % [closures, seq_ok])
	print("  clues/puzzle:    median=%d mean=%.0f   [expect ~306 / ~289]"
		% [int(clues[clues.size() / 2]), float(csum) / float(maxi(1, clues.size()))])
	print("  unused pool:     median=%d" % int(pools[pools.size() / 2]))
	if not sols.is_empty():
		print("  closure:         min=%d median=%d max=%d mean=%.0f   [expect 1 / 12 / 54 / 15]"
			% [int(sols[0]), int(sols[sols.size() / 2]), int(sols[sols.size() - 1]),
				float(ssum) / float(sols.size())])
		print("  distribution:    %s" % str(sols))
	print("  Forms firing:    %d of 23      [expect 22]" % forms.size())

	if contradictions > 0:
		print("\n  !! CONTRADICTIONS — unsound !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
