extends "res://dev_tests/test_base.gd"
# "Easy" redefined (2026-09-28, per user direction) to mean a genuinely smaller,
# separately-authored star layout, not just a different clue mix over the same
# stars. The Archon (id 0) is the first constellation with one: 15 stars -> 10
# (its own distinct-note count), reusing the Djinn's vessel_layouts pattern
# (get_constellation_def resolves onto the SAME top-level keys every consumer
# already reads) with GameContext.get_constellation_difficulty() as the
# selector instead of chosen_vessel.
#
# What must hold, and why each case exists:
#  - NO GameContext at all must leave the constellation COMPLETELY UNCHANGED
#    (15 stars). This is a real bug this session caught in its own first draft:
#    defaulting to "easy" when there is nothing to ask would have silently
#    swapped constellation 0 to 10 stars under every dev_tests probe and test
#    module that builds a bare ConstellationData.new() with no GameContext --
#    which is most of them, including several written before this feature
#    existed.
#  - A REAL GameContext with no override defaults to "easy" (GameContext's own
#    documented default) -> the reduced layout, matching "redefine easy
#    itself" rather than an opt-in third tier.
#  - Explicit "hard" and explicit "easy" both resolve correctly and
#    independently.
#  - The easy layout's own shape: exactly 10 stars, 12 edges, every position on
#    the unit sphere, matching what was authored.
#  - get_note_assignment(0) under easy gives a full 0..9 permutation with NO
#    repeats, across several seeds -- the entire point of the reduction.
#  - A REAL end-to-end generation succeeds at the reduced size, and hard mode
#    is unaffected by the feature existing at all.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()

	print("=== no GameContext: constellation 0 is completely unaffected ===")
	ok(cd._game_context == null, "sanity: a bare ConstellationData has no GameContext (matches every other test/probe)")
	var untouched: Dictionary = cd.get_constellation_def(0)
	ok(int(untouched["star_count"]) == 15, "star_count is still 15 with nothing to ask about difficulty (got %d)" % int(untouched["star_count"]))
	ok((untouched["fixed_star_positions"] as Array).size() == 15, "still 15 authored positions")

	print("\n=== with a real GameContext ===")
	cd._game_context = gc
	ok(gc.get_constellation_difficulty(0) == "easy", "GameContext defaults constellation 0 to easy (its own documented default)")
	var default_def: Dictionary = cd.get_constellation_def(0)
	ok(int(default_def["star_count"]) == 10, "so with no override at all, the reduced layout is what a real player sees by default (got %d)" % int(default_def["star_count"]))

	gc.constellation_difficulty[0] = "hard"
	var hard_def: Dictionary = cd.get_constellation_def(0)
	ok(int(hard_def["star_count"]) == 15 and (hard_def["fixed_star_positions"] as Array).size() == 15,
		"explicit hard: unchanged, 15 stars (got %d)" % int(hard_def["star_count"]))

	gc.constellation_difficulty[0] = "easy"
	var easy_def: Dictionary = cd.get_constellation_def(0)
	var positions: Array = easy_def["fixed_star_positions"]
	var line_pairs: Array = easy_def["line_pairs"]
	ok(int(easy_def["star_count"]) == 10, "explicit easy: 10 stars (got %d)" % int(easy_def["star_count"]))
	ok(positions.size() == 10, "10 authored positions (got %d)" % positions.size())
	ok(line_pairs.size() == 24, "12 edges, 24 flat entries (got %d)" % line_pairs.size())
	var off_sphere: int = 0
	for p in positions:
		var v: Array = p
		var mag: float = float(v[0]) * float(v[0]) + float(v[1]) * float(v[1]) + float(v[2]) * float(v[2])
		if absf(mag - 1.0) > 0.01:
			off_sphere += 1
	ok(off_sphere == 0, "every easy-layout star sits on the unit sphere (%d off)" % off_sphere)

	print("\n=== the whole point: no shared notes ===")
	var trials: int = 0
	var bad_trials: int = 0
	for seed in [1, 2, 3, 42, 999, 123456]:
		gc.constellation_difficulty.clear()
		cd.player_seed = seed
		var notes: Array = cd.get_note_assignment(0)
		var freqs: Array = cd.get_note_freqs(0)
		trials += 1
		var distinct: Dictionary = {}
		for n in notes:
			distinct[int(n)] = true
		if notes.size() != 10 or distinct.size() != 10 or freqs.size() != 10:
			bad_trials += 1
			print("    seed %d: size=%d distinct=%d freqs=%d -- %s" % [seed, notes.size(), distinct.size(), freqs.size(), str(notes)])
	ok(trials == 6, "sanity: judged 6 seeds")
	ok(bad_trials == 0, "every seed gives exactly 10 distinct notes for 10 stars, never a repeat (%d bad of %d)" % [bad_trials, trials])

	print("\n=== a real end-to-end generation at the reduced size ===")
	gc.constellation_difficulty[0] = "easy"
	cd.player_seed = 11
	var gen_def: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(gen_def["star_count"])
	var g = PuzzleScript.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.difficulty = "easy"
	g.setup(scn, gen_def["line_pairs"], sq, 11, 0, gen_def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g.generate_clues_forms()
	ok(g.star_count == 10, "the generator actually ran at 10 stars (got %d)" % g.star_count)
	ok(g.gate_passed and not g.chosen_form_clues.is_empty(),
		"a real easy-mode puzzle ships (gate_passed=%s, %d clues)" % [g.gate_passed, g.chosen_form_clues.size()])

	print("\n=== hard mode is unaffected by the feature existing ===")
	gc.constellation_difficulty[0] = "hard"
	var hard_gen_def: Dictionary = cd.get_constellation_def(0)
	var g2 = PuzzleScript.new()
	var sq2: Array = []
	for i in range(15):
		sq2.append(i)
	g2.setup(15, hard_gen_def["line_pairs"], sq2, 11, 0, hard_gen_def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g2.generate_clues_forms()
	ok(g2.star_count == 15, "hard mode still runs at the original 15 stars (got %d)" % g2.star_count)
	ok(g2.gate_passed and not g2.chosen_form_clues.is_empty(),
		"and still ships a real puzzle (gate_passed=%s, %d clues)" % [g2.gate_passed, g2.chosen_form_clues.size()])

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
