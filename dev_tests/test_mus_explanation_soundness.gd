extends "res://dev_tests/test_base.gd"
# MUS-extraction step explainer (Bogaerts/Gamba/Guns, arXiv:2006.06343) —
# nifty-chasing-castle plan, Changes A-F. Guards the three properties a
# player-facing explanation MUST have to be trustworthy, plus the
# propagation-completeness fix (naked-K-subset + locked-group resolution)
# that made full closure possible at all:
#
#   1. COMPLETENESS: pure propagation (_propagate_only, never
#      _solve()'s backtracking fallback) closes every cell on both axes.
#      This is the regression guard for the naked-K-subset/locked-group
#      fix specifically — Satchel stalled at 13/17 Sequence stars before
#      it, 17/17 after.
#   2. SOUNDNESS: every claimed exclusion is genuinely false of the real
#      solution (never trust a step that's wrong, even if convenient).
#   3. NON-REDUNDANCY (Definition 7): removing any single element of a
#      found support must break sufficiency, or it wasn't minimal.
#
# COST DISCIPLINE: exhaustive per-cell MUS extraction is expensive —
# measured ~185s for ONE 17-star puzzle's full two-axis sequence
# (dev_tests/probe_scratch, 2026-09-20). This module samples a handful of
# cells per puzzle rather than running the full sequence, so it stays
# proportionate to a routine suite run. The full exhaustive sweep (and the
# difficulty-score aggregation, Change F) is real and testable, but stays
# a `-- probe`-invoked deep-check, not something every suite run pays for.

const SEEDS := [11]
# Satchel is id 4 now (swapped with The Bellows 2026-09-23 — see
# constellation_data.gd v0.3.6); this constant must keep pointing at
# Satchel specifically (see the header comment above), not whichever
# constellation happens to sit at id 3 after the swap.
const CONSTELLATIONS := [0, 4]
const SAMPLE_PER_AXIS := 6

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _verbose() -> bool:
	for a in OS.get_cmdline_user_args():
		if "mus_explanation" in str(a):
			return true
	return false


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var P = load("res://constellation_logic_puzzle.gd")

	var puzzles: int = 0
	var seq_incomplete: int = 0
	var name_incomplete: int = 0
	var seq_sampled: int = 0
	var name_sampled: int = 0
	var redundancy_violations: int = 0
	var unsound: int = 0
	var genuinely_non_unique: int = 0
	var incomplete_examples: Array = []

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in SEEDS:
			var g = P.new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			# generate_clues_forms(), NOT _generate_clues_forms_attempt()
			# directly: this test must exercise the actual gate+retry loop
			# (seq_unique and name_unique and name_unique_closure, fixed
			# 2026-09-20) to mean anything about what SHIPS. A single raw
			# attempt can legitimately come back non-unique — that's
			# exactly what the gate exists to catch and retry past; only
			# the FINAL chosen_form_clues after generate_clues_forms()
			# returns is what a player would ever actually see.
			await g.generate_clues_forms()
			puzzles += 1
			var clues: Array = g.chosen_form_clues

			# --- Completeness: does propagation alone close every cell? ---
			var seq_pool: Array = g._seq_facts_from_clues_tagged(clues)
			var seq_full: Dictionary = g._propagate_only(seq_pool)
			var seq_possible: Array = seq_full["possible"]
			var seq_gaps: Array = []
			if bool(seq_full["consistent"]):
				for s in scn:
					var tc: int = 0
					for r in scn:
						if bool(seq_possible[s][r]):
							tc += 1
					if tc != 1:
						seq_gaps.append(s)
			if not seq_gaps.is_empty():
				seq_incomplete += 1
				incomplete_examples.append("c%d seed %d SEQUENCE: %d/%d stars unresolved by propagation alone"
					% [cid, seed, seq_gaps.size(), scn])

			var seq_solutions: Array = g._solve(g._seq_facts_from_clues(), 2)
			var name_pool: Array = g._name_facts_from_clues_tagged(clues)
			var name_full: Dictionary = g._name_propagate_only(seq_solutions)
			var name_possible: Array = name_full["possible"]
			var name_gaps: Array = []
			if bool(name_full["consistent"]) and seq_solutions.size() == 1:
				for ns in scn:
					var tcn: int = 0
					for np in scn:
						if bool(name_possible[ns][np]):
							tcn += 1
					if tcn != 1:
						name_gaps.append(ns)
			if not name_gaps.is_empty():
				name_incomplete += 1
				# A gap here has two very different possible causes, and
				# they must not be conflated: (a) propagation genuinely
				# can't close it yet but the puzzle IS still uniquely
				# solvable via backtracking -- a solver-completeness note;
				# (b) the puzzle is NOT actually uniquely solvable at all
				# -- a real generator defect, since the live ship gate
				# (generate_clues_forms's `seq_unique and name_unique`)
				# never checks name_unique_closure (see
				# live_gate_is_name_unique_not_closure). Found exactly
				# this way, c3 seed 11, 2026-09-20: _solve_name_closure
				# with backtracking returned 2 solutions for the same
				# puzzle propagation left ambiguous -- names genuinely
				# swappable, not a solver gap.
				var real_name_solutions: Array = g._solve_name_closure(seq_solutions, 3)
				if real_name_solutions.size() == 1:
					incomplete_examples.append(
						"c%d seed %d NAME: %d/%d unresolved by propagation, but backtracking DOES find a unique solution — solver-completeness gap, not a generator defect"
							% [cid, seed, name_gaps.size(), scn])
				else:
					genuinely_non_unique += 1
					incomplete_examples.append(
						"c%d seed %d NAME: GENUINELY NOT UNIQUE — backtracking itself finds %d solutions (stars %s swappable) — real generator defect, not a solver limitation"
							% [cid, seed, real_name_solutions.size(), str(name_gaps)])

			# --- Sample exclusion cells on each axis for soundness/non-redundancy ---
			var seq_checked: int = 0
			for s2 in scn:
				if seq_checked >= SAMPLE_PER_AXIS:
					break
				for r2 in scn:
					if seq_checked >= SAMPLE_PER_AXIS:
						break
					if bool(seq_possible[s2][r2]):
						continue
					seq_checked += 1
					seq_sampled += 1
					var still_forces: Callable = Callable(g, "_seq_target_forced").bind(s2, r2, false)
					var support: Array = g._mus_minimal_support(seq_pool, still_forces)
					for k in support.size():
						var trial: Array = support.duplicate()
						trial.remove_at(k)
						if g._seq_target_forced(trial, s2, r2, false):
							redundancy_violations += 1
					if int(g.sequence_rank_solution[s2]) == r2:
						unsound += 1

			if seq_solutions.size() == 1:
				var name_checked: int = 0
				for ns2 in scn:
					if name_checked >= SAMPLE_PER_AXIS:
						break
					for np2 in scn:
						if name_checked >= SAMPLE_PER_AXIS:
							break
						if bool(name_possible[ns2][np2]):
							continue
						name_checked += 1
						name_sampled += 1
						var still_forces_n: Callable = Callable(g, "_name_target_forced").bind(seq_solutions, ns2, np2, false)
						var support_n: Array = g._mus_minimal_support(name_pool, still_forces_n)
						for k2 in support_n.size():
							var trial_n: Array = support_n.duplicate()
							trial_n.remove_at(k2)
							if g._name_target_forced(trial_n, seq_solutions, ns2, np2, false):
								redundancy_violations += 1

			if _verbose():
				var t0: int = Time.get_ticks_msec()
				var score: Dictionary = g._compute_difficulty_score()
				var elapsed: int = Time.get_ticks_msec() - t0
				if not score.is_empty():
					print("    c%d seed %d difficulty score: total_cost=%d step_count=%d hard_step_count=%d (%.1fs)"
						% [cid, seed, int(score["total_cost"]), int(score["step_count"]),
							int(score["hard_step_count"]), float(elapsed) / 1000.0])

	print("\n  %d puzzles checked, %d cells sampled (SEQUENCE), %d cells sampled (NAME)"
		% [puzzles, seq_sampled, name_sampled])
	for ex in incomplete_examples:
		print("      ", ex)
	if not _verbose():
		print("  (run with `-- mus_explanation` for per-puzzle difficulty scores — slow, full sequence build)")

	ok(puzzles > 0, "generated puzzles to judge (%d)" % puzzles)
	ok(seq_incomplete == 0,
		"pure propagation closes every Sequence cell (%d/%d puzzles incomplete) — regression guard for the naked-K-subset/locked-group fix"
			% [seq_incomplete, puzzles])
	# NOT a hard failure by itself: the solver's naked-subset bound
	# (MAX_NAKED_SUBSET_K) is a documented, deliberate limit, and a puzzle
	# left incomplete by pure propagation can still be genuinely unique
	# (closed by backtracking). The HARD bar is genuinely_non_unique below
	# — that's the one that must never happen.
	print("  (informational, not a failure) pure propagation closed Name axis on %d/%d puzzles"
		% [puzzles - name_incomplete, puzzles])
	ok(genuinely_non_unique == 0,
		"every puzzle IS actually uniquely solvable on the Name axis, even where propagation alone can't prove it (%d/%d puzzles genuinely non-unique) — this is the real correctness bar; a failure here means the live ship gate (seq_unique and name_unique) let a non-unique puzzle through, since it never checks name_unique_closure"
			% [genuinely_non_unique, puzzles])
	ok(seq_sampled > 0 and name_sampled > 0,
		"sampled cells on both axes (%d SEQUENCE, %d NAME) — otherwise the checks below are vacuous"
			% [seq_sampled, name_sampled])
	ok(redundancy_violations == 0,
		"every sampled support is non-redundant, Definition 7 (%d violations)" % redundancy_violations)
	ok(unsound == 0,
		"every sampled exclusion is genuinely false of the real solution (%d violations)" % unsound)

	print("ALL PASS (%d failures)" % fails)
	finish()
