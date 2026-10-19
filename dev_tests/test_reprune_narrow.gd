extends "res://dev_tests/test_base.gd"
# The narrow second pruning pass (2026-10-18, author's choice over a full one).
#
# Easy adds "<Name> is the star that first fires on note T" clues after
# pruning. A clue that speaks only of first firings the player then knows (by a
# note label, or by a name such a clue pins) is decided before it is read:
#   "The first firing of the star that first fires on note 10 is exactly 4
#    notes before the first firing of Aetherios."  (reported, next to)
#   "Aetherios is the star that first fires on note 14."
# The narrow pass removes those and nothing else. The full pass (every clue
# the set no longer needs) measured 21.1 -> 17.4 clues but cut names tied by
# hints from 82% to 61%; narrow 21.1 -> 20.7 with hint reach unchanged.
#
# Same seed, pass off vs on: the pass runs after every other draw, so the two
# puzzles are identical up to it.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
# Puzzles where the measurement saw the pass remove something (cheap to build).
const CASES := [[2, 11], [2, 59], [4, 11], [4, 41]]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner(cid: int, seed: int, mode: String):
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
	g.setup(int(def["star_count"]), def["line_pairs"], eng.get_correct_star_sequence(cid), seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g.reprune_mode = mode
	await g.generate_clues_forms()
	return g


func _texts(g) -> Array:
	var out: Array = []
	for c in g.chosen_form_clues:
		out.append(str(c["text"]))
	return out


func run() -> void:
	var removed_total: int = 0
	var decided_before: int = 0
	var bad_removals: Array = []
	var added: Array = []
	var pins_lost: Array = []
	var gates: int = 0
	for case in CASES:
		var cid: int = int(case[0])
		var seed: int = int(case[1])
		var off = await _beginner(cid, seed, "off")
		var on = await _beginner(cid, seed, "narrow")
		if off.gate_passed and on.gate_passed:
			gates += 1
		var pinned: Dictionary = off._names_pinned_to_first_notes()
		var on_texts: Array = _texts(on)
		var off_texts: Array = _texts(off)
		for c in off.chosen_form_clues:
			var t: String = str(c["text"])
			var decided: bool = not off._is_redundancy_exempt_form(int(c.get("form_id", -1))) \
				and off._clue_decided_by_known_first_notes(c, pinned)
			if decided:
				decided_before += 1
			if not on_texts.has(t):
				removed_total += 1
				print("    c%d s%d removed: %s" % [cid, seed, t])
				if not decided:
					bad_removals.append(t)
			if t.contains("is the star that first fires on note") and not on_texts.has(t):
				pins_lost.append(t)
		for t2 in on_texts:
			if not off_texts.has(t2):
				added.append(t2)
	ok(gates == CASES.size(), "every puzzle has one answer with the pass off and on (%d of %d)" % [gates, CASES.size()])
	ok(decided_before > 0, "the puzzles without the pass carry decided clues, so the check can fail (%d)" % decided_before)
	ok(removed_total > 0, "the pass removed something (%d clues)" % removed_total)
	ok(bad_removals.is_empty(), "every clue it removed is decided by known first notes (%d not)" % bad_removals.size())
	ok(added.is_empty(), "it adds nothing (%d)" % added.size())
	ok(pins_lost.is_empty(), "every \"first fires on note\" clue stays (%d lost)" % pins_lost.size())
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
