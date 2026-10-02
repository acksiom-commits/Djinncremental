extends "res://dev_tests/test_base.gd"
# Mutual Exclusion (Form 13)'s axis-based "...all have different pitches"
# branch, reported live 2026-10-01: "Helios, Oraides, and Pyrios all have
# different pitches" reads as a non-clue under Beginner mode (easy_layout,
# where the melody-repeat mechanic makes every star's pitch globally
# unique by construction, per planned_repeat_count_axis_design.md).
#
# Traced to the root cause: _mutex_axis_groups(axis) filters Colour/Pitch
# to ONLY stars whose raw value is globally one-of-a-kind
# (_category_uniquely_labels), then groups by raw value -- but any star
# that survives that filter is, by the filter's own definition, the ONLY
# star with that value, so every group it can ever build has exactly ONE
# member. There is no input for which this function can produce a 2+
# member Colour/Pitch group. That means the axis-based "these differ"
# claim has ALWAYS been tautological for Colour/Pitch, in Expert mode
# too -- just rare there (~19% of stars qualify) and so easy to never
# notice, versus Beginner mode where 100% qualify and Mutex is also a
# forced opening-anchor clue (near-guaranteed to surface it).
#
# Fix: _mutex_pick_viable_axis now rejects Colour/Pitch as a candidate
# axis unless at least one of its groups has 2+ members
# (_mutex_axis_has_real_group). Since that's structurally never true
# today, this suppresses Colour/Pitch from the axis-based branch
# entirely (Name/Sequence, which have their own, different, already-
# correct degeneracy check -- cross_cells==0 -- are untouched).
#
# What must hold:
#  - _mutex_axis_has_real_group, in isolation: true for a real group,
#    false for all-singleton input, false for empty input.
#  - _mutex_pick_viable_axis never returns Colour or Pitch as the axis,
#    against a realistic HARD-mode matrix with genuine colour/pitch
#    sharing (proving this was ALWAYS broken, not just under Beginner
#    mode) -- and Name/Sequence remain viable and get picked.
#  - Same result under a Beginner-mode-shaped (easy_layout) matrix where
#    every pitch is additionally unique by construction.
#  - A real end-to-end generated Beginner-mode puzzle (The Archon, easy)
#    never ships a Mutual Exclusion clue whose axis is Pitch or Colour.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _puzzle(n: int, colors: Array, pitches: Array):
	var g = PuzzleScript.new()
	g.star_count = n
	# Array[int] properties silently abort on an untyped literal assignment
	# through this dynamic reference (known project gotcha) -- build typed
	# locals first.
	var typed_colors: Array[int] = []
	for c in colors:
		typed_colors.append(int(c))
	g.star_colors = typed_colors
	var typed_pitches: Array[int] = []
	for p in pitches:
		typed_pitches.append(int(p))
	g.star_pitch_index = typed_pitches
	return g


func run() -> void:
	print("=== _mutex_axis_has_real_group, in isolation ===")
	var g0 = _puzzle(1, [0], [0])
	ok(g0._mutex_axis_has_real_group([[0], [1], [2]]) == false,
		"all-singleton groups -> false")
	ok(g0._mutex_axis_has_real_group([[0, 1], [2]]) == true,
		"one real (2-member) group among singletons -> true")
	ok(g0._mutex_axis_has_real_group([]) == false,
		"no groups at all -> false")

	print("\n=== _mutex_pick_viable_axis never returns Colour/Pitch: HARD-mode-shaped matrix ===")
	# 10 stars, colours with GENUINE sharing (groups of 3/3/2/2), pitches
	# with genuine sharing too (groups of 4/3/2/1) -- the ordinary,
	# already-live Expert-mode shape. Star 9 has a truly unique pitch (the
	# ~19%-ish case); nothing else does.
	var g1 = _puzzle(10,
		[0, 0, 0, 1, 1, 1, 2, 2, 3, 3],
		[0, 0, 0, 0, 1, 1, 1, 2, 2, 3])
	var hard_axes_seen: Dictionary = {}
	for i in 500:
		var pick: Dictionary = g1._mutex_pick_viable_axis(3)
		if not pick.is_empty():
			hard_axes_seen[int(pick["axis"])] = true
	ok(not hard_axes_seen.has(PuzzleScript.Category.PITCH),
		"Pitch never drawn as the axis across 500 picks (seen: %s)" % str(hard_axes_seen.keys()))
	ok(not hard_axes_seen.has(PuzzleScript.Category.COLOR),
		"Colour never drawn as the axis across 500 picks (seen: %s)" % str(hard_axes_seen.keys()))
	ok(hard_axes_seen.has(PuzzleScript.Category.NAME) and hard_axes_seen.has(PuzzleScript.Category.SEQUENCE),
		"Name and Sequence are both still viable and get picked (seen: %s)" % str(hard_axes_seen.keys()))

	print("\n=== _mutex_pick_viable_axis never returns Colour/Pitch: BEGINNER-mode-shaped matrix ===")
	# Same 10 stars, colours still genuinely shared (colour grouping is
	# independent of the melody-repeat mechanic), but EVERY pitch unique --
	# the Beginner-mode shape the live report hit.
	var g2 = _puzzle(10,
		[0, 0, 0, 1, 1, 1, 2, 2, 3, 3],
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	var easy_axes_seen: Dictionary = {}
	for i in 500:
		var pick2: Dictionary = g2._mutex_pick_viable_axis(3)
		if not pick2.is_empty():
			easy_axes_seen[int(pick2["axis"])] = true
	ok(not easy_axes_seen.has(PuzzleScript.Category.PITCH),
		"Pitch never drawn as the axis across 500 picks, fully-bijective case (seen: %s)" % str(easy_axes_seen.keys()))
	ok(not easy_axes_seen.has(PuzzleScript.Category.COLOR),
		"Colour never drawn as the axis across 500 picks (seen: %s)" % str(easy_axes_seen.keys()))
	ok(easy_axes_seen.has(PuzzleScript.Category.NAME) and easy_axes_seen.has(PuzzleScript.Category.SEQUENCE),
		"Name and Sequence remain viable and get picked (seen: %s)" % str(easy_axes_seen.keys()))

	print("\n=== direct draws against a real Beginner-mode matrix, frozen (never committed) ===")
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[0] = "easy"
	cd.player_seed = 11
	var def: Dictionary = cd.get_constellation_def(0)
	var scn: int = int(def["star_count"])
	var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
	overlay_engine.set_constellation(0, cd, gc)
	var sq: Array = overlay_engine.get_correct_star_sequence(0)

	var g3 = PuzzleScript.new()
	g3.difficulty = "easy"
	g3.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	g3._build_record_array()
	g3._build_matrix()

	# "values_all_different" is ONLY ever emitted by the axis==Colour/Pitch
	# branch (the Name/Sequence branch's own comment: "nothing beyond
	# 'different stars' to disclose") -- so the fix working correctly means
	# this fact kind should now appear ZERO times, by design. The
	# denominator has to be "did Form 13 produce anything at all" instead,
	# or this check would be asking the fix to fail in order to prove
	# itself non-vacuous.
	var total_mutex_draws: int = 0
	var bad_axis_clues: int = 0
	for i in 500:
		var clue: Dictionary = g3._build_form_mutual_exclusion({})
		if clue.is_empty():
			continue
		total_mutex_draws += 1
		for vf in (clue.get("value_facts", []) as Array):
			var fd: Dictionary = vf
			if str(fd.get("kind", "")) == "values_all_different":
				var cat: int = int(fd.get("cat", -1))
				if cat == PuzzleScript.Category.PITCH or cat == PuzzleScript.Category.COLOR:
					bad_axis_clues += 1
					print("    BAD: %s" % str(clue.get("text", "")))
	ok(total_mutex_draws > 0, "Form 13 actually produced a clue at least once across 500 direct calls on a real Beginner-mode matrix (%d) -- otherwise this check is vacuous" % total_mutex_draws)
	ok(bad_axis_clues == 0, "zero of %d real draws assert Colour/Pitch distinctness (found %d)" % [total_mutex_draws, bad_axis_clues])

	print("\n=== a real end-to-end generated Beginner-mode puzzle still ships cleanly ===")
	for seed in [11, 12, 13]:
		var g = PuzzleScript.new()
		g.difficulty = "easy"
		g.setup(scn, def["line_pairs"], sq, seed, 0, def.get("name_theme", {}),
			cd.get_note_assignment(0), cd.get_note_freqs(0), null)
		await g.generate_clues_forms()
		ok(g.gate_passed, "seed %d: the puzzle still passes the ship gate" % seed)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
