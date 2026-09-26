extends "res://dev_tests/test_base.gd"
# The MUS step explainer's free-step search (2026-09-26 fix).
#
# It used to take 585 s on a 15-star puzzle (Sequence alone), 327 s of it in
# the free-step shrink, because every trial ran _propagate_only, which resolves
# locked groups by re-running itself per permutation. The free-step check now
# uses _alldiff_eliminate -- the human-style eliminations (single candidate,
# hidden single, naked pairs/triples) -- and a step takes the free route only
# when it is CHEAPER than the clue-based one.
#
# What must hold, and why each case exists:
#  - The eliminator is SOUND: it never removes a cell that is true in the real
#    solution, and never contradicts a sound board. Tested against ground truth
#    on random partial boards, both axes.
#  - It is deliberately WEAKER than the full solver: whenever it says a cell is
#    forced, _propagate_only agrees. The reverse is allowed to fail (that is
#    what makes it fast and followable), so the check is a subset, not equality.
#    Both directions are counted so a silent "0 of 0" cannot pass.
#  - Every step the explainer emits is VALID: its stated support really forces
#    its cell, none explains a TRUE cell away, and the number of steps equals
#    the number of cells the clues eliminate.
#  - It stays FAST: the slow path took minutes; a generous bound catches a
#    regression to it without being flaky on a slow machine.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

const TIME_BOUND_SECONDS: float = 120.0

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## The FULL, unbudgeted solver's verdict. The explainer's own checks carry a
## resolution budget (weaker, still sound); the comparisons here must not.
func _seq_forced_full(g, facts: Array, s: int, r: int) -> bool:
	var typed: Array[Dictionary] = []
	for f in facts:
		typed.append(f)
	var prop: Dictionary = g._propagate_only(typed)
	return bool(prop["consistent"]) and not bool(prop["possible"][s][r])


func _name_forced_full(g, facts: Array, seq_solutions: Array, s: int, p: int) -> bool:
	var pseudo: Array = []
	for f in facts:
		pseudo.append({"disclosures": [f]})
	var prop: Dictionary = g._name_propagate_only(seq_solutions, pseudo)
	return bool(prop["consistent"]) and not bool(prop["possible"][s][p])


func _pool_of_false_cells(truth: Array, n: int) -> Array:
	var falses: Array = []
	for s in n:
		for r in n:
			if int(truth[s]) != r:
				falses.append([s, r])
	return falses


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var cdef: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(cdef["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 31337, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g._generate_clues_forms_attempt()
	var seq_solutions: Array = g._solve(g._seq_facts_from_clues(), 2)
	ok(seq_solutions.size() == 1, "the fixture puzzle is uniquely solvable on Sequence")
	var name_sols: Array = g._solve_name_closure(seq_solutions)
	ok(name_sols.size() == 1, "and on Name")

	print("\n=== the eliminator: sound, and never stronger than the full solver ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var truths: Dictionary = {"sequence": g.sequence_rank_solution, "name": name_sols[0]}
	for axis in truths:
		var truth: Array = truths[axis]
		var falses: Array = _pool_of_false_cells(truth, scn)
		var boards: int = 0
		var unsound: int = 0
		var contradicted: int = 0
		var new_only: int = 0      # eliminator says forced, full solver does not: must be 0
		var both: int = 0
		var solver_only: int = 0   # full solver forced, eliminator did not: allowed (weaker)
		for trial in 40:
			var k: int = [20, 60, 120, 180][trial % 4]
			var pool: Array = falses.duplicate()
			var subset: Array = []
			while subset.size() < mini(k, pool.size()):
				subset.append(pool.pop_at(rng.randi() % pool.size()))
			var grid: Array = g._init_possibility_grid()
			for c in subset:
				grid[int(c[0])][int(c[1])] = false
			boards += 1
			if not g._alldiff_eliminate(grid):
				contradicted += 1
				continue
			for s in scn:
				if not bool(grid[s][int(truth[s])]):
					unsound += 1   # removed the TRUE cell
			# Compare with the full solver on the same board, cell by cell.
			var facts: Array = []
			for c2 in subset:
				if axis == "sequence":
					facts.append({"kind": "ordinal_neg", "s": int(c2[0]), "r": int(c2[1])})
				else:
					facts.append({"kind": "name_group_neg", "name_star": int(c2[0]),
						"cat": PuzzleScript.Category.SEQUENCE, "group_key": int(c2[1])})
			for probe in 10:
				var s2: int = rng.randi() % scn
				var r2: int = rng.randi() % scn
				var mine: bool = not bool(grid[s2][r2])
				var full: bool
				if axis == "sequence":
					full = _seq_forced_full(g, facts, s2, r2)
				else:
					full = _name_forced_full(g, facts, seq_solutions, s2, r2)
				if mine and not full:
					new_only += 1
				elif mine and full:
					both += 1
				elif full and not mine:
					solver_only += 1
		print("    %s: %d boards; eliminator+solver agree on %d cells, solver alone %d, eliminator alone %d" % [axis, boards, both, solver_only, new_only])
		ok(contradicted == 0, "%s: never contradicts a sound board (%d)" % [axis, contradicted])
		ok(unsound == 0, "%s: never removes a cell that is true in the solution (%d)" % [axis, unsound])
		ok(new_only == 0, "%s: never claims a cell is forced when the full solver does not (%d)" % [axis, new_only])
		ok(both > 30, "%s: enough forced cells were compared to mean something (%d)" % [axis, both])

	print("\n=== the explainer end to end ===")
	var t0: int = Time.get_ticks_msec()
	var seq_res: Dictionary = g._mus_build_sequence_seq(g.chosen_form_clues)
	var name_res: Dictionary = g._mus_build_sequence_name(g.chosen_form_clues, seq_solutions)
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	print("    Sequence + Name explained in %.1fs" % secs)
	ok(secs < TIME_BOUND_SECONDS, "fast (%.1fs < %.0fs; the slow path took ~700s)" % [secs, TIME_BOUND_SECONDS])
	ok(bool(seq_res["consistent"]) and bool(name_res["consistent"]), "both axes explain consistently")

	var seq_steps: Array = seq_res["sequence"]
	var full_grid: Array = g._propagate_only(g._seq_facts_from_clues_tagged(g.chosen_form_clues))["possible"]
	var eliminated_cells: int = 0
	for s in scn:
		for r in scn:
			if not bool(full_grid[s][r]):
				eliminated_cells += 1
	ok(seq_steps.size() == eliminated_cells, "Sequence: one step per cell the clues eliminate (%d of %d)" % [seq_steps.size(), eliminated_cells])
	var seq_bad: int = 0
	var seq_true_cell: int = 0
	var seq_free: int = 0
	for st in seq_steps:
		if int(g.sequence_rank_solution[int(st["star"])]) == int(st["rank"]):
			seq_true_cell += 1
		if (st["s"] as Array).is_empty():
			seq_free += 1
			if not g._seq_target_forced_via_mask(st["e"], int(st["star"]), int(st["rank"]), false):
				seq_bad += 1
		elif not _seq_forced_full(g, st["s"], int(st["star"]), int(st["rank"])):
			seq_bad += 1
	print("    Sequence: %d steps, %d via free elimination" % [seq_steps.size(), seq_free])
	ok(seq_true_cell == 0, "Sequence: no step explains a TRUE cell away (%d)" % seq_true_cell)
	ok(seq_bad == 0, "Sequence: every step's stated support really forces its cell (%d invalid)" % seq_bad)
	ok(seq_free > 0, "Sequence: some steps did take the free route, so that path was exercised (%d)" % seq_free)

	var name_steps: Array = name_res["sequence"]
	var name_bad: int = 0
	var name_true_cell: int = 0
	var name_free: int = 0
	for st2 in name_steps:
		if int(name_sols[0][int(st2["name_star"])]) == int(st2["position"]):
			name_true_cell += 1
		if (st2["s"] as Array).is_empty():
			name_free += 1
			if not g._name_target_forced_via_mask(st2["e"], int(st2["name_star"]), int(st2["position"]), false):
				name_bad += 1
		elif not _name_forced_full(g, st2["s"], seq_solutions, int(st2["name_star"]), int(st2["position"])):
			name_bad += 1
	print("    Name: %d steps, %d via free elimination" % [name_steps.size(), name_free])
	ok(name_true_cell == 0, "Name: no step explains a TRUE cell away (%d)" % name_true_cell)
	ok(name_bad == 0, "Name: every step's stated support really forces its cell (%d invalid)" % name_bad)
	ok(name_steps.size() > 0, "Name: there were steps to judge (%d)" % name_steps.size())

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
