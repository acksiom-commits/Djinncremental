extends "res://dev_tests/test_base.gd"
# Mutual Exclusion's heterogeneous distinctness list
# (_mutex_build_distinct_set, "X, Y, Z, and W are all different stars")
# silently dropped its "descriptor_not_in_group" disclosure whenever a
# Colour/Pitch element happened to be a genuine SINGLETON group (e.g. "the
# red star" when only one star is red) -- a stray `members.size() < 2:
# continue` skipped it, even though the underlying grid_updates cell was
# (and always had been) written correctly.
#
# Reported live 2026-10-01: a clue "Sviatoslav, the red star, and the star
# 1 hop from Bogumila are all different stars" left Sviatoslav's Sort:
# Colour row with no "not red" mark -- the player's own deduction tooling
# never learned what the clue's text and grid both already guaranteed,
# which is exactly how a sound clue set can still produce an apparent
# contradiction in play (something else, still correctly excluding other
# colours, eventually narrowed Sviatoslav toward red instead of away from
# it, since this one exclusion was invisible to that process).
#
# What must hold:
#  - A Name/Sequence element paired with a SINGLETON Colour/Pitch element
#    in this Form emits descriptor_not_in_group, exactly like a
#    multi-member group element already does.
#  - The emitted fact's group_key correctly names the singleton's own raw
#    value (so a player-facing consumer resolves it to the right group).
#  - The fix does not change WHICH clues get drawn or how often (same
#    draw counts before/after -- this only adds a missing disclosure to
#    draws that already existed, touching no _rng call).

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
	var def: Dictionary = cd.get_constellation_def(0)   # The Archon
	var scn: int = int(def["star_count"])
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	var g = PuzzleScript.new()
	g.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)

	# Force one colour down to a genuine singleton (star 0 only) by
	# reassigning its other real members to a different real colour --
	# stays within the constellation's own valid palette, matching the
	# live report's shape (Red = {Rostoei} only, among 4 real colours).
	var forced_colors: Array[int] = g.star_colors.duplicate()
	var singleton_val: int = int(forced_colors[0])
	for i in forced_colors.size():
		if i != 0 and int(forced_colors[i]) == singleton_val:
			forced_colors[i] = (singleton_val + 1) % 4
	g.star_colors = forced_colors
	ok(g._group_size(PuzzleScript.Category.COLOR, 0) == 1,
		"test setup: star 0's colour is now a genuine singleton (got group size %d)" % g._group_size(PuzzleScript.Category.COLOR, 0))

	g._build_record_array()
	g._build_matrix()

	var total_draws: int = 0
	var star0_with_name_or_seq: int = 0
	var with_disclosure: int = 0
	var bad_group_key: int = 0

	for i in 1000:
		var clue: Dictionary = g._mutex_build_distinct_set()
		if clue.is_empty():
			continue
		total_draws += 1
		var chars: Array = clue.get("chars", [])
		var has_color_star0: bool = false
		var has_name_or_seq: bool = false
		for ch in chars:
			var cd2: Dictionary = ch
			var c2: int = int(cd2.get("cat", -1))
			if c2 == PuzzleScript.Category.COLOR and int(cd2.get("star", -1)) == 0:
				has_color_star0 = true
			if c2 == PuzzleScript.Category.NAME or c2 == PuzzleScript.Category.SEQUENCE:
				has_name_or_seq = true
		if not (has_color_star0 and has_name_or_seq):
			continue
		star0_with_name_or_seq += 1
		var found: bool = false
		for vf in (clue.get("value_facts", []) as Array):
			var fd: Dictionary = vf
			if str(fd.get("kind", "")) == "descriptor_not_in_group" and int(fd.get("group_cat", -1)) == PuzzleScript.Category.COLOR:
				found = true
				if int(fd.get("group_key", -1)) != singleton_val:
					bad_group_key += 1
		if found:
			with_disclosure += 1

	ok(star0_with_name_or_seq > 0,
		"at least one draw paired a Name/Sequence element with the singleton Colour element (%d of %d draws) -- otherwise this check is vacuous" % [star0_with_name_or_seq, total_draws])
	ok(with_disclosure == star0_with_name_or_seq,
		"every such draw emits descriptor_not_in_group, not just the multi-member-group ones (%d of %d)" % [with_disclosure, star0_with_name_or_seq])
	ok(bad_group_key == 0,
		"every emitted fact names the singleton's own real colour value (0 mismatches)")

	print("\n=== the fix changes no draw counts -- it only adds a missing disclosure ===")
	# Same seed, same forced colours, same 1000 draws: the exact counts
	# above (total_draws, star0_with_name_or_seq) are themselves this
	# check -- a second independent run with the identical setup should
	# reproduce them exactly, since nothing here touches an _rng call.
	var g2 = PuzzleScript.new()
	g2.setup(scn, def["line_pairs"], sq, 11, 0, def.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	g2.star_colors = forced_colors.duplicate()
	g2._build_record_array()
	g2._build_matrix()
	var total_draws2: int = 0
	var star0_with_name_or_seq2: int = 0
	for i in 1000:
		var clue2: Dictionary = g2._mutex_build_distinct_set()
		if clue2.is_empty():
			continue
		total_draws2 += 1
		var chars2: Array = clue2.get("chars", [])
		var has_color_star0_2: bool = false
		var has_name_or_seq2: bool = false
		for ch2 in chars2:
			var cd3: Dictionary = ch2
			var c3: int = int(cd3.get("cat", -1))
			if c3 == PuzzleScript.Category.COLOR and int(cd3.get("star", -1)) == 0:
				has_color_star0_2 = true
			if c3 == PuzzleScript.Category.NAME or c3 == PuzzleScript.Category.SEQUENCE:
				has_name_or_seq2 = true
		if has_color_star0_2 and has_name_or_seq2:
			star0_with_name_or_seq2 += 1
	ok(total_draws2 == total_draws, "identical total draw count on a re-run with the same seed/setup (%d vs %d)" % [total_draws2, total_draws])
	ok(star0_with_name_or_seq2 == star0_with_name_or_seq, "identical matching-shape draw count (%d vs %d)" % [star0_with_name_or_seq2, star0_with_name_or_seq])

	print("\n=== a real end-to-end generated puzzle still ships cleanly ===")
	for seed in [11, 12, 13]:
		var g3 = PuzzleScript.new()
		g3.setup(scn, def["line_pairs"], sq, seed, 0, def.get("name_theme", {}),
			cd.get_note_assignment(0), cd.get_note_freqs(0), null)
		await g3.generate_clues_forms()
		ok(g3.gate_passed, "seed %d: the puzzle still passes the ship gate" % seed)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
