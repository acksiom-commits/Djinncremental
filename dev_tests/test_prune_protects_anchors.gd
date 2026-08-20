extends "res://dev_tests/test_base.gd"
# Pruning must never remove an opening anchor.
#
# _prune_redundant_clues (10579ce) drops any clue whose removal does not
# raise the surviving solution count. Opening anchors are exactly the
# clues that look most redundant by that measure — they are the most
# direct, highest-information Forms, built FIRST while True cells are
# still unconsumed, so by the time the rest of the clue set exists their
# content is usually derivable from it. They are kept anyway, because they
# shape a specific opening foothold for difficulty tuning
# (_build_opening_anchors): removing them silently changes the intended
# opening, which is a design decision, not an optimisation.
#
# Protection is by INDEX (protected_count, captured right after the anchor
# pass), so this test checks by TEXT identity instead — an off-by-one in
# the index bound would still pass an index-based check.
#
# WHY THIS TEST EXISTS: the protection shipped with a probe reporting
# "anchor losses: 0", which proved nothing. `difficulty` defaults to
# "hard", whose opening_anchors is [] — so protected_count was 0 and no
# anchor was ever at risk in any measurement taken. The zero was the
# vacuous kind. "easy" is currently the ONLY profile with anchors, so this
# test forces it and asserts a non-zero anchor count BEFORE asserting none
# were lost.
#
# Two puzzles is enough: anchors run ~5 per puzzle, so the non-vacuity
# floor is comfortably cleared, and each puzzle costs ~25s here (Forms
# generation, then pruning's several hundred solver calls).

const SEED := 11
const CONSTELLATIONS := [0, 2]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var total_anchors: int = 0
	var lost: int = 0
	var lost_examples: Array = []
	var closures: int = 0
	var seq_ok: int = 0
	var contradictions: int = 0
	var puzzles: int = 0

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		var g = load("res://constellation_logic_puzzle.gd").new()
		var sq: Array = []
		for i in range(scn):
			sq.append(i)
		g.setup(scn, cdef["line_pairs"], sq, SEED, cid, cdef.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		g.difficulty = "easy"

		g._build_record_array()
		g._build_matrix()
		var seq_facts: Array[Dictionary] = []
		var name_revealed: Array[bool] = []
		for _s in scn:
			name_revealed.append(false)
		var tier_counts: Dictionary = {1: 0, 2: 0, 3: 0}
		var form_counts: Dictionary = {}

		g._build_opening_anchors(seq_facts, name_revealed, tier_counts, form_counts)
		var anchor_texts: Array = []
		for c in g.chosen_form_clues:
			anchor_texts.append(str(c.get("text", "")))
		var protected_n: int = g.chosen_form_clues.size()
		total_anchors += protected_n

		var max_stall: int = maxi(400, g._unused_pool_size() * 2)
		var stall: int = 0
		while g._unused_pool_size() > 0 and stall < max_stall:
			var committed: bool = false
			for tier in g._tiers_by_underrepresentation(tier_counts):
				var tf: Array = g._forms_in_tier(int(tier), form_counts)
				if tf.is_empty():
					continue
				g._shuffle_array(tf)
				var ta: int = 0
				var built: bool = false
				while ta < int(g.TIER_OPPORTUNISTIC_ATTEMPTS) and not built:
					ta += 1
					built = g._try_build_and_commit(int(tf[ta % tf.size()]),
						seq_facts, name_revealed, tier_counts, form_counts)
				if built:
					committed = true
					break
			if committed:
				stall = 0
			else:
				stall += 1

		seq_facts = await g._prune_redundant_clues(name_revealed, protected_n)
		puzzles += 1

		var surviving: Dictionary = {}
		for c2 in g.chosen_form_clues:
			surviving[str(c2.get("text", ""))] = true
		for at in anchor_texts:
			if not surviving.has(at):
				lost += 1
				if lost_examples.size() < 5:
					lost_examples.append("c%d: %s" % [cid, str(at)])

		var ss: Array = g._solve(seq_facts, 2)
		if ss.size() == 1:
			seq_ok += 1
			var ns: Array = g._solve_name_closure(ss, 5)
			if ns.size() == 0:
				contradictions += 1
			if ns.size() == 1:
				closures += 1

	print("  puzzles: %d (difficulty = \"easy\")" % puzzles)
	print("  anchors built: %d,  lost to pruning: %d" % [total_anchors, lost])
	for e in lost_examples:
		print("    LOST: %s" % str(e))
	print("  seq_unique: %d/%d,  closures: %d/%d,  contradictions: %d"
		% [seq_ok, puzzles, closures, seq_ok, contradictions])

	# Non-vacuity FIRST: a 0 in the check below means nothing unless
	# anchors actually existed to be protected.
	ok(total_anchors > 0,
		"anchors were actually built (%d) — otherwise the next check is vacuous" % total_anchors)
	ok(lost == 0, "pruning removed no anchor (%d lost)" % lost)
	ok(contradictions == 0,
		"pruning left no contradictory puzzle on the easy profile (%d)" % contradictions)

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
