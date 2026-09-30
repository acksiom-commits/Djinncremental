extends "res://dev_tests/test_base.gd"
# Category.REPEAT — step 2 of the Repeat Count axis build order (see
# planned_repeat_count_axis_design.md). This module covers ONLY the matrix
# ENCODING: repeat_count made bijective-with-star via sub-rank, exactly like
# Category.COLOR/Category.PITCH already are. Category.REPEAT is deliberately
# NOT in BIJECTIVE_CATEGORIES yet and _characteristic_label has no branch for
# it -- so nothing here exercises live clue generation drawing on this axis;
# that is a later step, once Form 12 is wired in.
#
# What must hold, and why each case exists:
#  - _cat_star_to_value[REPEAT] must be a TRUE PERMUTATION of 0..star_count-1
#    -- every star individually addressable in the matrix, even though most
#    stars legitimately share the same raw repeat_count value (measured:
#    Archon easy is 6/3/1 across three values). A collision here would mean
#    two stars silently alias to the same matrix cell.
#  - _cat_value_to_star[REPEAT] must be the EXACT inverse -- round-tripping
#    every star through star->value->star must return the original star.
#  - Sorting stars by their assigned value_index must group equal
#    repeat_count values into contiguous blocks, in ascending repeat_count
#    order -- this is _rank_by_raw_and_subrank's own contract (sort by raw
#    value, sub-rank only breaks ties), and every Form that will eventually
#    read this axis depends on it holding.
#  - Within one repeat_count group, _repeat_count_sub_rank must itself be a
#    clean 0..(group_size-1) permutation -- no duplicate sub-rank letters
#    for two stars that share a raw value.
#  - Category.REPEAT must NOT be in BIJECTIVE_CATEGORIES yet, and a real
#    generated puzzle's clue text must contain no bare "?" -- the exact
#    silent-breakage failure mode the Category enum's own POSITION comment
#    warns a premature activation would cause.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _build_archon_easy(seed: int, cd, gc) -> PuzzleScript:
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(def["star_count"])
	var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
	overlay_engine.set_constellation(0, cd, gc)
	var sq: Array = overlay_engine.get_correct_star_sequence(0)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(scn, def["line_pairs"], sq, seed, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	return g


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[0] = "easy"

	print("=== the REPEAT bijection is a true permutation, correctly inverted ===")
	for seed in [1, 2, 3, 42, 999]:
		var g = _build_archon_easy(seed, cd, gc)
		await g.generate_clues_forms()
		var s2v: Array = g._cat_star_to_value[PuzzleScript.Category.REPEAT]
		var v2s: Array = g._cat_value_to_star[PuzzleScript.Category.REPEAT]
		ok(s2v.size() == 10 and v2s.size() == 10, "seed %d: both directions sized to star_count (got %d, %d)" % [seed, s2v.size(), v2s.size()])
		var seen: Dictionary = {}
		var dupes: int = 0
		for v in s2v:
			if seen.has(v):
				dupes += 1
			seen[v] = true
		ok(dupes == 0 and seen.size() == 10, "seed %d: every value_index 0..9 assigned to exactly one star (got %d dupes, %d distinct)" % [seed, dupes, seen.size()])
		var roundtrip_ok: bool = true
		for star in 10:
			if int(v2s[int(s2v[star])]) != star:
				roundtrip_ok = false
		ok(roundtrip_ok, "seed %d: value_to_star correctly inverts star_to_value for every star" % seed)

		print("\n=== seed %d: sorting by value_index groups equal repeat_count together ===" % seed)
		var order: Array = []
		for star in 10:
			order.append(star)
		order.sort_custom(func(a, b): return int(s2v[a]) < int(s2v[b]))
		var prev_count: int = -999
		var grouping_ok: bool = true
		var non_decreasing: bool = true
		for star in order:
			var rc: int = int(g.repeat_count[star])
			if rc < prev_count:
				non_decreasing = false
			prev_count = rc
		ok(non_decreasing, "seed %d: repeat_count is non-decreasing along the value_index order (ties broken by sub-rank only)" % seed)

		print("\n=== seed %d: sub-rank is a clean permutation WITHIN each repeat_count group ===" % seed)
		var groups: Dictionary = {}
		for star in 10:
			var rc2: int = int(g.repeat_count[star])
			if not groups.has(rc2):
				groups[rc2] = []
			(groups[rc2] as Array).append(int(g._repeat_count_sub_rank[star]))
		var subrank_ok: bool = true
		for rc3 in groups:
			var subranks: Array = groups[rc3]
			subranks.sort()
			for i in subranks.size():
				if int(subranks[i]) != i:
					subrank_ok = false
		ok(subrank_ok, "seed %d: each repeat_count group's sub-ranks are exactly 0..(group_size-1), no gaps or dupes" % seed)

	print("\n=== REPEAT is not yet live -- matrix encoding only ===")
	ok(not (PuzzleScript.Category.REPEAT in PuzzleScript.BIJECTIVE_CATEGORIES),
		"Category.REPEAT is deliberately NOT in BIJECTIVE_CATEGORIES yet")

	print("\n=== a real generated puzzle still ships clean clue text (no broken '?' from the new slot) ===")
	var g2 = _build_archon_easy(11, cd, gc)
	await g2.generate_clues_forms()
	ok(g2.gate_passed and not g2.chosen_form_clues.is_empty(),
		"a real puzzle still ships (gate_passed=%s, %d clues)" % [g2.gate_passed, g2.chosen_form_clues.size()])
	var bad_clues: int = 0
	for c in g2.chosen_form_clues:
		var text: String = str((c as Dictionary).get("text", ""))
		if text.strip_edges() == "?" or text.contains(" ? ") or text.ends_with(" ?") or text == "":
			bad_clues += 1
			print("    suspicious clue text: '%s'" % text)
	ok(bad_clues == 0, "no clue's text degenerated to a bare '?' (got %d)" % bad_clues)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
