extends "res://dev_tests/test_base.gd"
# PRUNING REMEMBERS WHAT IT PROVED NEEDED (_try_prune_clue_at, 2026-10-15).
#
# Pruning only removes clues, and "this clue is needed" stays true for every
# smaller set, so the recheck and safety-net passes skip clues an earlier pass
# already proved needed. That must be a pure speed-up: the same puzzles, clue
# for clue, as with every clue re-proved (prune_memo_enabled = false). Measured
# when built on 12 Beginner puzzles: identical 12 of 12, 245 s -> 113 s, the
# slowest 67.5 s -> 37.5 s.
#
# Checked here on fast puzzles (the slow ones take a minute each), and the
# skip has to actually happen, or "identical" proves nothing.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _gen(cid: int, seed: int, memo: bool) -> Array:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.prune_memo_enabled = memo
	g.setup(int(def["star_count"]), def["line_pairs"], eng.get_correct_star_sequence(cid), seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	await g.generate_clues_forms()
	var texts: Array = []
	for cl in g.chosen_form_clues:
		texts.append(str(cl["text"]))
	return [texts, g.note_owner_solves, g.gate_passed]


func run() -> void:
	var identical: int = 0
	var fewer: int = 0
	var cases: Array = [[4, 11], [4, 23], [2, 23], [5, 11]]
	for pair in cases:
		var off: Array = await _gen(int(pair[0]), int(pair[1]), false)
		var on: Array = await _gen(int(pair[0]), int(pair[1]), true)
		var same: bool = off[0] == on[0] and bool(on[2]) and bool(off[2])
		if same:
			identical += 1
		if int(on[1]) < int(off[1]):
			fewer += 1
		print("    c%d s%d: %d clues; proof runs %d with every clue re-proved, %d remembering" % [
			int(pair[0]), int(pair[1]), (on[0] as Array).size(), int(off[1]), int(on[1])])
	ok(identical == cases.size(), "remembering needed clues ships the same puzzles, clue for clue (%d of %d)" % [identical, cases.size()])
	ok(fewer == cases.size(), "and it actually skips proofs on every one (%d of %d)" % [fewer, cases.size()])

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
