extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# DOES PRUNING COLLAPSE VOCABULARY, JUST BY A DIFFERENT MECHANISM? (2026-08-18)
#
# test_clue_has_hidden_content failed on its NON-VACUITY guards (0 Mutual
# Exclusion clues in ITS sample) after pruning landed — same failure SHAPE
# as this morning's negation-flood collapse, but the cause is structurally
# different and needs checking, not assuming: pruning keeps a clue only if
# removing it INCREASES the solution count, and non-feeding Forms (Mutual
# Exclusion, Count, Betweenness, Disjunction, Group Comparison, ...) never
# carry closure content by definition — so every one of their clues is a
# provably-safe removal candidate regardless of what else survives.
#
# Measuring the actual post-prune Form mix directly, standard 8x5 sample,
# rather than inferring health from one test's vacuity failure.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555, 77, 909090, 13, 24601]

	var form_dist: Dictionary = {}
	var puzzles: int = 0
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
			await g._generate_clues_forms_attempt()
			puzzles += 1
			for clue in g.chosen_form_clues:
				var fn: String = str(clue.get("form_name", "?"))
				form_dist[fn] = int(form_dist.get(fn, 0)) + 1

	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	var total_c: int = 0
	for k in form_dist.keys():
		total_c += int(form_dist[k])

	print("\n  puzzles: %d   (%.0fs)   total clues: %d\n" % [puzzles, elapsed, total_c])
	var names: Array = form_dist.keys()
	names.sort_custom(func(a, b): return int(form_dist[a]) > int(form_dist[b]))
	var top: String = ""
	var top_n: int = 0
	for f in names:
		var c: int = int(form_dist[f])
		if c > top_n:
			top_n = c
			top = f
		print("    %-32s %5d  (%.1f%%)" % [f, c, 100.0 * float(c) / float(maxi(1, total_c))])

	print("\n  Forms firing: %d of 23     dominant: %s at %.0f%%   [pre-fix collapse: 7/23, 88%%]"
		% [names.size(), top, 100.0 * float(top_n) / float(maxi(1, total_c))])
	print("  clues/puzzle: %.1f" % (float(total_c) / float(maxi(1, puzzles))))

	print("ALL PASS (%d failures)" % fails)
	finish()
