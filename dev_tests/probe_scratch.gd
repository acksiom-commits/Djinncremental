extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# RE-MEASURING EVERYTHING AFTER THE CASCADE FIX (2026-08-18).
#
# _apply_grid_cell_result no longer marks a True cell's whole row and
# column Used. That cascade was a ground-truth fact ("bijection gives one
# True per row/column") driving a claim about what the PLAYER can derive —
# the tier error, in the generator, where the matrix-up lint does not
# scan. It has been in since 3497453 (2026-07-24), so EVERY measurement
# taken since was characterising the bug's blast radius rather than the
# system.
#
# Conclusions that were derived against the broken cascade and are now
# suspect — this run exists to re-test them:
#
#   "clue budget is ~2.5 x star_count (~44)"        <- cascade cost 29 cells/clue
#   "generation dead-ends, no Form can emit"        <- pool exhausted by cascade
#   "the Form set cannot express uniqueness"        <- measured under that dead-end
#   "COLOR:PITCH is 74% unreachable"                <- 2608 of its cells were CASCADE marks
#   "_unused_pool_size()==0 is never reached"       <- reached how, now?
#   "full closures 0/38"                            <- the headline
#   "multi-element clues cost 58 cells each"        <- 2 cascading cells; now ~2
#
# Baseline for every line below is commit 8e13f83, the parent of this
# change, same seeds, same probe shape.

var fails: int = 0

const COLOR_CAT: int = 2
const PITCH_CAT: int = 3


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555, 77, 909090, 13, 24601]

	var puzzles: int = 0
	var seq_unique_count: int = 0
	var contradictions: int = 0
	var full_closures: int = 0
	var clue_counts: Array = []
	var solution_counts: Array = []
	var pool_left: Array = []
	var pool_zero: int = 0
	var cp_used: int = 0
	var cp_total: int = 0
	var form_dist: Dictionary = {}
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
			clue_counts.append(g.chosen_form_clues.size())

			var pool: int = g._unused_pool_size()
			pool_left.append(pool)
			if pool == 0:
				pool_zero += 1

			var rows: Array = g._matrix[g._pair_key(COLOR_CAT, PITCH_CAT)]
			for row in rows:
				for cell in row:
					cp_total += 1
					if bool(cell["used"]):
						cp_used += 1

			for clue in g.chosen_form_clues:
				var fn: String = str(clue.get("form_name", "?"))
				form_dist[fn] = int(form_dist.get(fn, 0)) + 1

			if bool(result.get("seq_unique", false)):
				seq_unique_count += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1
				if bool(result.get("name_unique_closure", false)):
					full_closures += 1
				var seq_sols: Array = result.get("seq_solutions", []) as Array
				solution_counts.append(g._solve_name_closure(seq_sols, 5000).size())

	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	clue_counts.sort()
	pool_left.sort()
	var csum: int = 0
	for c in clue_counts:
		csum += int(c)

	print("\n  puzzles: %d   (%.0fs, %.1fs each)" % [puzzles, elapsed, elapsed / float(maxi(1, puzzles))])

	print("\n  === gates ===")
	print("    seq_unique:      %d / %d        [8e13f83: 38 / 40]" % [seq_unique_count, puzzles])
	print("    CONTRADICTIONS:  %d / %d        [MUST be 0]" % [contradictions, seq_unique_count])
	print("    FULL CLOSURES:   %d / %d        [8e13f83: 0 / 38]" % [full_closures, seq_unique_count])

	print("\n  === the clue budget (was ~2.5x star_count) ===")
	print("    clues/puzzle: min=%d median=%d max=%d mean=%.0f   [8e13f83: ~44]"
		% [int(clue_counts[0]), int(clue_counts[clue_counts.size() / 2]),
			int(clue_counts[clue_counts.size() - 1]), float(csum) / float(maxi(1, clue_counts.size()))])
	print("    unused pool left: min=%d median=%d max=%d   [8e13f83: 90-304]"
		% [int(pool_left[0]), int(pool_left[pool_left.size() / 2]), int(pool_left[pool_left.size() - 1])])
	print("    reached pool==0:  %d / %d   [8e13f83: 0 / 40]" % [pool_zero, puzzles])
	print("    COLOR:PITCH used: %.1f%%   [8e13f83: 25.8%% — of which nearly all was CASCADE]"
		% [100.0 * float(cp_used) / float(maxi(1, cp_total))])

	if not solution_counts.is_empty():
		solution_counts.sort()
		var ssum: int = 0
		var capped: int = 0
		var near: int = 0
		for v in solution_counts:
			ssum += int(v)
			if int(v) >= 5000:
				capped += 1
			if int(v) <= 4:
				near += 1
		print("\n  === closure distance ===")
		print("    min=%d median=%d max=%d mean=%.0f   [8e13f83: min=144 median=5000 mean=4633]"
			% [int(solution_counts[0]), int(solution_counts[solution_counts.size() / 2]),
				int(solution_counts[solution_counts.size() - 1]),
				float(ssum) / float(solution_counts.size())])
		print("    cap-limited: %d / %d   [8e13f83: 34 / 38]" % [capped, solution_counts.size()])
		print("    within 4:    %d / %d   [8e13f83: 0 / 38]" % [near, solution_counts.size()])
		print("    distribution: %s" % str(solution_counts))

	print("\n  === vocabulary (the thing the negation workaround destroyed) ===")
	var fnames: Array = form_dist.keys()
	fnames.sort_custom(func(a, b): return int(form_dist[a]) > int(form_dist[b]))
	var total_c: int = 0
	for f in fnames:
		total_c += int(form_dist[f])
	for f in fnames:
		print("    %-32s %5d  (%.1f%%)" % [f, int(form_dist[f]), 100.0 * float(form_dist[f]) / float(maxi(1, total_c))])
	print("    Forms firing: %d of 23" % fnames.size())

	if contradictions > 0:
		print("\n  !! CONTRADICTIONS — unsound !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
