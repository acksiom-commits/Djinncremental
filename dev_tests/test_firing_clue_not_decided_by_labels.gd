extends "res://dev_tests/test_base.gd"
# No Firing clue may speak only of firings its own labels already print
# (reported 2026-10-16, author: "possibly the most useless thing I've seen
# generated yet"):
#
#   "The only firing of the star that fires 8th note is not immediately
#    before the first firing of the star that first fires on note 5."
#
# A Sequence label names a star by its first note, so that star's first (or
# only) firing IS that note. Both sides known means note 8 vs note 5: true
# before the player reads a word. The same held for the Adjacency version
# ("...the star that fires 1st note is immediately before the first firing of
# the star that first fires on note 2") and for a Firing Position window
# count about a once-firing star named by its note.
#
# Read off the shipped clues' facts: a firing_relation whose two sides both
# carry a label note (label_refs a and b) and both pick the first firing, or a
# firing_position "count" about a star named by its note (label_refs s).

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const CIDS := [0, 1, 2, 3, 4, 5]
const SEEDS := [11, 23, 37]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner(cid: int, seed: int):
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
	return g


func run() -> void:
	var rel_seen: int = 0
	var pos_seen: int = 0
	var decided: Array = []
	var puzzles: int = 0
	for cid in CIDS:
		for seed in SEEDS:
			var g = _beginner(cid, seed)
			await g.generate_clues_forms()
			if not g.gate_passed:
				continue
			puzzles += 1
			for cl in g.chosen_form_clues:
				for f in (cl as Dictionary).get("disclosures", []):
					var fd: Dictionary = f
					var refs: Dictionary = fd.get("label_refs", {})
					match str(fd.get("kind", "")):
						"firing_relation":
							rel_seen += 1
							if refs.has("a") and refs.has("b") and str(fd["pick_a"].get("kind", "")) == "first" \
									and str(fd["pick_b"].get("kind", "")) == "first":
								decided.append("c%d s%d: %s" % [cid, seed, str(cl["text"])])
						"firing_position":
							pos_seen += 1
							if refs.has("s") and str(fd["sel"].get("kind", "")) == "count":
								decided.append("c%d s%d: %s" % [cid, seed, str(cl["text"])])
	for t in decided:
		print("    decided by its labels: ", t)
	ok(puzzles >= 15, "Beginner puzzles generated (%d of %d)" % [puzzles, CIDS.size() * SEEDS.size()])
	ok(rel_seen >= 20, "enough Firing Relation facts shipped to judge (%d)" % rel_seen)
	ok(pos_seen >= 10, "enough Firing Position facts shipped to judge (%d)" % pos_seen)
	ok(decided.is_empty(), "no shipped Firing clue is decided by its labels alone (%d)" % decided.size())
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
