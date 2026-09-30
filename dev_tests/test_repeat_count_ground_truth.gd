extends "res://dev_tests/test_base.gd"
# Ground truth for the new "Repeat Count" clue axis (2026-09-28/29, per user
# direction -- see planned_repeat_count_axis_design.md). This module covers
# ONLY the raw numbers computed in constellation_logic_puzzle.gd's setup():
# repeat_count[star] = how many EXTRA times that star's note fires in the
# melody beyond its first occurrence. Nothing here builds a clue Form yet --
# that is a later step in the design doc's build order.
#
# What must hold, and why each case exists:
#  - Archon's own melody (puzzle_sequence: [8,7,6,5,4,3,2,1,0,1,2,1,0,4,9])
#    has a KNOWN, hand-countable repeat distribution: pitches 0,2,4 each
#    fire twice (1 repeat), pitch 1 fires three times (2 repeats), the rest
#    fire once (0 repeats) -- sorted values [0,0,0,0,0,0,1,1,1,2]. Easy mode
#    is a clean 1:1 star<->pitch assignment, so this distribution must show
#    up on repeat_count regardless of which star ends up holding which
#    pitch (the shuffle changes WHICH star has which count, never the
#    multiset of counts itself) -- checked across several seeds.
#  - A star that never fires anywhere must read -1 (an authoring gap
#    sentinel), never 0 (which legitimately means "fires once, no repeat")
#    -- these are different facts and must not collide.
#  - _repeat_count_is_degenerate() must correctly tell apart a real,
#    varied distribution (Archon easy: false) from a genuinely constant one
#    (hand-built fixture: true) -- this is the guard the Form-building step
#    will depend on to skip the axis entirely where it carries no signal.
#  - repeat_count round-trips through to_cache_dict()/from_cache_dict()
#    like every other optional field added this session.

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
	cd._game_context = gc
	gc.constellation_difficulty[0] = "easy"

	print("=== Archon easy mode: known repeat distribution, across seeds ===")
	var expected_sorted: Array = [0, 0, 0, 0, 0, 0, 1, 1, 1, 2]
	for seed in [1, 2, 3, 42, 999]:
		cd.player_seed = seed
		var def: Dictionary = cd.get_constellation_def(0)
		var scn: int = int(def["star_count"])
		# The REAL melody-derived sequence, not an identity placeholder --
		# repeat_count is meaningless without the actual repeat structure.
		var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
		overlay_engine.set_constellation(0, cd, gc)
		var sq: Array = overlay_engine.get_correct_star_sequence(0)
		var g = PuzzleScript.new()
		g.difficulty = "easy"
		g.setup(scn, def["line_pairs"], sq, seed, 0, def.get("name_theme", {}),
			cd.get_note_assignment(0), cd.get_note_freqs(0), null)
		ok(g.repeat_count.size() == 10, "seed %d: repeat_count sized to star_count (got %d)" % [seed, g.repeat_count.size()])
		var sorted_counts: Array = g.repeat_count.duplicate()
		sorted_counts.sort()
		ok(sorted_counts == expected_sorted,
			"seed %d: sorted repeat_count matches Archon's hand-counted melody distribution (got %s)" % [seed, str(sorted_counts)])
		ok(not g._repeat_count_is_degenerate(), "seed %d: a real varied distribution is NOT flagged degenerate" % seed)
		var never_fires: int = 0
		for v in g.repeat_count:
			if v < 0:
				never_fires += 1
		ok(never_fires == 0, "seed %d: every one of Archon's 10 easy-mode stars fires at least once (got %d never-fires)" % [seed, never_fires])

	print("\n=== a star that never fires reads -1, not 0 ===")
	var g2 = PuzzleScript.new()
	# 3 "stars" but a melody that only ever plays stars 0 and 1 -- star 2
	# never fires, an authoring gap.
	g2.setup(3, [0, 1, 1, 2, 2, 0], [0, 1, 0, 1], 11, 0, {}, [0, 1, 2], [440.0, 493.88, 523.25], null)
	ok(g2.repeat_count.size() == 3, "sanity: 3 stars (got %d)" % g2.repeat_count.size())
	ok(int(g2.repeat_count[2]) == -1, "star 2, which never fires in the melody, reads -1 (got %d)" % int(g2.repeat_count[2]))
	ok(int(g2.repeat_count[0]) == 1, "star 0 fires twice (positions 0,2) -> 1 repeat (got %d)" % int(g2.repeat_count[0]))
	ok(int(g2.repeat_count[1]) == 1, "star 1 fires twice (positions 1,3) -> 1 repeat (got %d)" % int(g2.repeat_count[1]))

	print("\n=== degeneracy check on a genuinely constant distribution ===")
	var g3 = PuzzleScript.new()
	# Typed locals, not literals assigned via a dynamic ref -- this project's
	# own documented gotcha: an untyped Array literal assigned straight into
	# a typed Array[int] property can silently abort the whole script.
	var all_zero: Array[int] = [0, 0, 0, 0]
	g3.repeat_count = all_zero
	ok(g3._repeat_count_is_degenerate(), "all-zero repeat_count IS degenerate")
	var all_never: Array[int] = [-1, -1, -1]
	g3.repeat_count = all_never
	ok(g3._repeat_count_is_degenerate(), "all-never-fires (all -1) IS degenerate too -- no melody data is not a signal")
	var empty_counts: Array[int] = []
	g3.repeat_count = empty_counts
	ok(g3._repeat_count_is_degenerate(), "an empty repeat_count (no setup run) is treated as degenerate, not crashed on")

	print("\n=== save/load round-trip ===")
	cd.player_seed = 11
	var def4: Dictionary = cd.get_constellation_def(0)
	var scn4: int = int(def4["star_count"])
	var overlay_engine4 = load("res://click_sequence_puzzle_engine.gd").new()
	overlay_engine4.set_constellation(0, cd, gc)
	var sq4: Array = overlay_engine4.get_correct_star_sequence(0)
	var g4 = PuzzleScript.new()
	g4.difficulty = "easy"
	g4.setup(scn4, def4["line_pairs"], sq4, 11, 0, def4.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	# validate_cache_dict requires generation_complete=true (a real solved
	# puzzle), not just a bare setup() -- run the actual generator.
	await g4.generate_clues_forms()
	var cached: Dictionary = g4.to_cache_dict()
	ok((cached.get("repeat_count", []) as Array).size() == 10, "to_cache_dict includes repeat_count (got %d entries)" % (cached.get("repeat_count", []) as Array).size())
	var g5 = PuzzleScript.new()
	ok(g5.from_cache_dict(cached), "from_cache_dict accepts the round-tripped cache")
	ok(g5.repeat_count == g4.repeat_count, "repeat_count survives the round-trip unchanged (got %s vs %s)" % [str(g5.repeat_count), str(g4.repeat_count)])

	print("\n=== an old-style cache with no repeat_count field loads safely ===")
	var old_cache: Dictionary = g4.to_cache_dict()
	old_cache.erase("repeat_count")
	var g6 = PuzzleScript.new()
	ok(g6.from_cache_dict(old_cache), "from_cache_dict still accepts a cache missing the new field")
	ok(g6.repeat_count.is_empty(), "repeat_count defaults to empty, not a crash, when the field is absent (got %s)" % str(g6.repeat_count))

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
