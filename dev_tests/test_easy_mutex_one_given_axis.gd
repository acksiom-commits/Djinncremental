extends "res://dev_tests/test_base.gd"
# Beginner-Easy Mutual Exclusion uses Colour or Pitch, never both (author,
# 2026-10-30). After Listen every star shows both, so a clue setting a Colour
# element against a Pitch element tells the player nothing. Name, Sequence
# and Hop stay; a clue may use neither of the two.
#
#  - Direct draws on real Beginner boards: no Easy clue carries both, in either
#    variant of the Form. The same draws under the Hard profile DO carry both,
#    so the check can see what it is looking for.
#  - Both Colour-bearing and Pitch-bearing clues are drawn, and Hop still is.
#  - The 4-element opener's shape is Name, Sequence, Hop and one of the two.
#  - End to end, on the two smallest boards, where a 4-element clue is hardest
#    to fit: the puzzle ships, opens with a 4-element then a 3-element Mutual
#    Exclusion, and nothing shipped carries both.

const P = preload("res://constellation_logic_puzzle.gd")

const DRAWS := 300

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _cats(clue: Dictionary) -> Array:
	var out: Array = []
	for ch in (clue.get("chars", []) as Array):
		out.append(int((ch as Dictionary).get("cat", -1)))
	return out


func _board(cd, gc, cid: int) -> Dictionary:
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	return {"def": def, "scn": int(def["star_count"]), "sq": eng.get_correct_star_sequence(cid)}


func _puzzle(cd, cid: int, b: Dictionary, profile: String, seed: int):
	var g = P.new()
	g.difficulty = profile
	var def: Dictionary = b["def"]
	g.setup(int(b["scn"]), def["line_pairs"], b["sq"], seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	return g


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	cd.player_seed = 11
	const COL: int = P.Category.COLOR
	const PIT: int = P.Category.PITCH
	const HOP: int = P.Category.DISTANCE

	var tally: Dictionary = {}
	for profile in ["easy", "hard"]:
		tally[profile] = {"drawn": 0, "both": 0, "col": 0, "pit": 0, "hop": 0}
	for cid in range(6):
		gc.constellation_difficulty[cid] = "easy"
		var b: Dictionary = _board(cd, gc, cid)
		for profile in ["easy", "hard"]:
			var g = _puzzle(cd, cid, b, profile, 11)
			g._build_record_array()
			g._build_matrix()
			var t: Dictionary = tally[profile]
			for i in DRAWS:
				var clue: Dictionary = g._build_form_mutual_exclusion({})
				if clue.is_empty():
					continue
				var cats: Array = _cats(clue)
				t["drawn"] = int(t["drawn"]) + 1
				if cats.has(COL) and cats.has(PIT):
					t["both"] = int(t["both"]) + 1
					if profile == "easy":
						print("    BAD: %s" % str(clue.get("text", "")))
				if cats.has(COL):
					t["col"] = int(t["col"]) + 1
				if cats.has(PIT):
					t["pit"] = int(t["pit"]) + 1
				if cats.has(HOP):
					t["hop"] = int(t["hop"]) + 1
	print("  easy %s" % str(tally["easy"]))
	print("  hard %s" % str(tally["hard"]))
	var te: Dictionary = tally["easy"]
	ok(int(te["drawn"]) > 0, "Easy drew %d clues on 6 Beginner boards" % int(te["drawn"]))
	ok(int(te["both"]) == 0, "none carries both Colour and Pitch (%d of %d)" % [int(te["both"]), int(te["drawn"])])
	ok(int(tally["hard"]["both"]) > 0, "control: the Hard profile's draws do carry both (%d of %d)"
		% [int(tally["hard"]["both"]), int(tally["hard"]["drawn"])])
	ok(int(te["col"]) > 0 and int(te["pit"]) > 0, "both kinds appear (%d Colour, %d Pitch)" % [int(te["col"]), int(te["pit"])])
	ok(int(te["hop"]) > 0, "Hop stays (%d clues)" % int(te["hop"]))

	print("\n=== the 4-element opener's shape ===")
	var four: int = 0
	var wrong: Array = []
	for cid2 in range(6):
		var b2: Dictionary = _board(cd, gc, cid2)
		var g2 = _puzzle(cd, cid2, b2, "easy", 11)
		g2._build_record_array()
		g2._build_matrix()
		g2._mutex_min_elements = 4
		g2._mutex_max_elements = 4
		g2._mutex_require_distinct_set = true
		for i2 in DRAWS:
			var clue2: Dictionary = g2._build_form_mutual_exclusion({})
			if clue2.is_empty():
				continue
			four += 1
			var c2: Array = _cats(clue2)
			if c2.size() != 4 or not (c2.has(P.Category.NAME) and c2.has(P.Category.SEQUENCE) and c2.has(HOP) \
					and (c2.has(COL) != c2.has(PIT))):
				wrong.append(str(clue2.get("text", "")))
	ok(four > 0, "4-element draws found on these boards (%d)" % four)
	ok(wrong.is_empty(), "every one is Name, Sequence, Hop and exactly one of Colour/Pitch (%d of %d wrong: %s)"
		% [wrong.size(), four, str(wrong.slice(0, 2))])

	print("\n=== end to end, the two smallest boards ===")
	for cid3 in [4, 1]:
		var b3: Dictionary = _board(cd, gc, cid3)
		var g3 = _puzzle(cd, cid3, b3, "easy", 11)
		await g3.generate_clues_forms()
		ok(bool(g3.gate_passed), "c%d: the puzzle passes the ship gate" % cid3)
		var clues: Array = g3.chosen_form_clues
		ok(clues.size() >= 2 and int(clues[0].get("form_id", -1)) == 13 and int(clues[1].get("form_id", -1)) == 13,
			"c%d: opens with two Mutual Exclusions" % cid3)
		ok(_cats(clues[0]).size() == 4 and _cats(clues[1]).size() == 3,
			"c%d: of 4 and then 3 elements (%d, %d)" % [cid3, _cats(clues[0]).size(), _cats(clues[1]).size()])
		var bad: int = 0
		var judged: int = 0
		for c3 in clues:
			if int((c3 as Dictionary).get("form_id", -1)) != 13:
				continue
			judged += 1
			if _cats(c3).has(COL) and _cats(c3).has(PIT):
				bad += 1
		ok(bad == 0, "c%d: no shipped Mutual Exclusion carries both (%d judged)" % [cid3, judged])

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
