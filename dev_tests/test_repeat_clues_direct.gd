extends "res://dev_tests/test_base.gd"
# Easy states repeat firings only directly (2026-10-19, author: working out the
# repeat clues was the main time sink on Beginner-Easy).
#
#   direct:   "The second firing of Helios is on note 14."
#             "<X> fires on note 7."   (a star that fires once)
#   indirect: "The second firing of the star that plays G4 is immediately
#             after the third firing of Volkaim."   (any relation, window,
#             span or range that involves a repeat firing)
#
# Read off each shipped clue's facts. With the setting off the same puzzles
# carry indirect repeat clues, so the check can fail.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const CASES := [[1, 11], [2, 11], [2, 37], [4, 41], [4, 59]]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner(cid: int, seed: int, direct: int):
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
	g.repeat_direct_override = direct
	await g.generate_clues_forms()
	return g


## "direct", "indirect", or "" when the clue says nothing about repeat firings.
func _repeat_kind(cl: Dictionary) -> String:
	var k: String = ""
	for f in cl.get("disclosures", []):
		var fd: Dictionary = f
		match str(fd.get("kind", "")):
			"firing_relation":
				if str(fd["pick_a"].get("kind", "")) != "first" or str(fd["pick_b"].get("kind", "")) != "first":
					return "indirect"
			"firing_position":
				var sel: Dictionary = fd.get("sel", {})
				var exact: bool = int(fd.get("lo", -1)) == int(fd.get("hi", -2)) and str(sel.get("kind", "")) == "nth"
				var only_note: bool = str(sel.get("kind", "")) == "count" and int(sel.get("lo", -1)) == int(sel.get("hi", -2))
				if exact or only_note:
					k = "direct"
				else:
					return "indirect"
	return k


func run() -> void:
	var easy_default: bool = bool((PuzzleScript.DIFFICULTY_PROFILES["easy"] as Dictionary).get("repeat_clues_direct", false))
	var on_gates: int = 0
	var on_direct: int = 0
	var on_indirect: Array = []
	var off_indirect: int = 0
	for case in CASES:
		var g_on = await _beginner(int(case[0]), int(case[1]), -1)   # Easy's own setting
		if g_on.gate_passed:
			on_gates += 1
		for cl in g_on.chosen_form_clues:
			match _repeat_kind(cl):
				"direct":
					on_direct += 1
				"indirect":
					on_indirect.append(str(cl["text"]))
		var g_off = await _beginner(int(case[0]), int(case[1]), 0)
		for cl2 in g_off.chosen_form_clues:
			if _repeat_kind(cl2) == "indirect":
				off_indirect += 1
	for t in on_indirect:
		print("    indirect on Easy: ", t)
	ok(easy_default, "Easy has repeat_clues_direct on")
	ok(on_gates == CASES.size(), "every Easy puzzle has one answer (%d of %d)" % [on_gates, CASES.size()])
	ok(off_indirect > 0, "with the setting off the same puzzles carry indirect repeat clues, so this can fail (%d)" % off_indirect)
	ok(on_direct > 0, "Easy puzzles state repeat firings directly (%d clues)" % on_direct)
	ok(on_indirect.is_empty(), "no Easy puzzle ships an indirect repeat clue (%d)" % on_indirect.size())
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
