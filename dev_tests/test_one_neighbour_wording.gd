extends "res://dev_tests/test_base.gd"
# Extreme (Form 11) and Count (Form 10) on a subject with exactly ONE connected
# star (user-reported 2026-10-21). Both Forms used to print the plural for it:
# "Aetheriai is the earliest to fire among its connected stars." /
# "Exactly 0 of Oreai's connected stars fire before it." With one neighbour
# either Form is a single before/after comparison, now worded
# "X (first) fires before/after its only connected star( first fires)."
#
# Constellations 0, 2, 5 and 6 have no one-neighbour stars, so this draws on
# 1 (beginner, repeating melody -- exercises the "first fires" verbs), 3 and 4
# (hard). Prints how many one-neighbour clues it judged, and fails if none.
#
# What must hold:
#  - every one-neighbour clue uses the singular sentence, never "connected stars"
#  - its verb says "first fires" exactly when the subject repeats, and the
#    " first fires" tail appears exactly when the neighbour repeats
#  - the claim is true: "before" iff the subject first fires before its neighbour
#  - no subject with 2+ connected stars gets the singular sentence

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

# Label non-greedy: a greedy one swallows "first" and leaves the verb "fires".
const RE_ONE := "^(.+?) (first fires|fires) (before|after) its only connected star( first fires)?\\.$"

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner_puzzle(cid: int, seed: int):
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g._build_record_array()
	g._build_matrix()
	return g


func _hard_puzzle(cid: int, seed: int):
	var cd = load("res://constellation_data.gd").new()   # no GameContext -> hard mode
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var sq: Array = []
	for i in range(int(def["star_count"])):
		sq.append(i)
	var g = PuzzleScript.new()
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	g._build_record_array()
	g._build_matrix()
	return g


func _rep(g, star: int) -> bool:
	return int(g.repeat_count[star]) > 0


func run() -> void:
	var re_one := RegEx.create_from_string(RE_ONE)
	var puzzles: Array = [
		["c1 beginner", _beginner_puzzle(1, 11)],
		["c3 hard", _hard_puzzle(3, 11)],
		["c4 hard", _hard_puzzle(4, 11)],
	]
	var singles: int = 0
	var singles_repeat: int = 0   # one-neighbour clues where either side repeats
	var multis: int = 0
	var wrong: int = 0
	var leaked: int = 0
	for entry in puzzles:
		var label: String = entry[0]
		var g = entry[1]
		var local_singles: int = 0
		for builder in ["_build_form_extreme", "_build_form_count"]:
			for i in 300:
				var c: Dictionary = g.call(builder, {})
				if c.is_empty():
					continue
				var text: String = str(c["text"])
				var subject: int = int((c["chars"] as Array)[0]["star"])
				var nbrs: Array = g.proximity[subject]
				if nbrs.size() != 1:
					multis += 1
					if text.contains("its only connected star"):
						leaked += 1
						print("    singular on %d neighbours: %s" % [nbrs.size(), text])
					continue
				singles += 1
				local_singles += 1
				var nbr: int = int(nbrs[0])
				if _rep(g, subject) or _rep(g, nbr):
					singles_repeat += 1
				var m = re_one.search(text)
				var before: bool = g._order_value(PuzzleScript.Category.SEQUENCE, subject) \
					< g._order_value(PuzzleScript.Category.SEQUENCE, nbr)
				if m == null \
						or (m.get_string(2) == "first fires") != _rep(g, subject) \
						or (m.get_string(4) != "") != _rep(g, nbr) \
						or (m.get_string(3) == "before") != before:
					wrong += 1
					print("    wrong (%s): %s" % [label, text])
		print("  %s: %d one-neighbour clues drawn" % [label, local_singles])

	ok(singles > 0, "drew one-neighbour Extreme/Count clues (%d, plus %d with 2+ neighbours)" % [singles, multis])
	ok(singles_repeat > 0, "some of them involve a repeating star, so the 'first fires' verbs are exercised (%d)" % singles_repeat)
	ok(wrong == 0, "one-neighbour clues use the singular sentence with the right verbs and a true claim (%d wrong of %d)" % [wrong, singles])
	ok(leaked == 0, "no subject with 2+ connected stars gets the singular sentence (%d of %d)" % [leaked, multis])

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
