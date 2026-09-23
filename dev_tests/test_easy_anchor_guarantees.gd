extends "res://dev_tests/test_base.gd"
# "easy" profile's opening-anchor guarantees, per user direction
# 2026-09-22: reduce difficulty further by guaranteeing more direct
# clues early, rather than by capping the total clue count.
#
#   - clues[0]: Mutual Exclusion, EXACTLY 4 categories.
#   - clues[1]: Mutual Exclusion, EXACTLY 3 categories.
#   - Then a guaranteed pair of Sequence-axis and a guaranteed pair of
#     Pitch-axis Betweenness ("[x] fires before [y], which fires before
#     [z]" / the Pitch equivalent) chain clues -- 2 of each, always.
#
# The chain-pair guarantee needed its own mechanism
# (_betweenness_two_disjoint_triples in constellation_logic_puzzle.gd):
# an early version drew the two same-axis clues independently, and the
# SECOND draw could be starved by whichever stars the first happened to
# take -- measured, only ~38% of puzzles got the full 2-and-2 even at a
# 20-try retry budget. It also needed exempting from the existing
# redundancy safety net (_is_redundancy_exempt_form) the same way the
# opening Mutex already is: even when both triples build correctly and
# distinctly, the safety net can legitimately (and correctly, by its own
# rigorous test) find one of them redundant once the REST of the puzzle
# is assembled -- true in isolation, but it silently broke the "2 each"
# guarantee this mechanism exists to provide.

const SEEDS := [5, 11, 20, 33]
const CONSTELLATIONS := [0, 1, 2, 3]

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var P = load("res://constellation_logic_puzzle.gd")
	const Category = preload("res://constellation_logic_puzzle.gd").Category

	for cid in CONSTELLATIONS:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or not (cdef.get("line_pairs") is Array) \
				or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in SEEDS:
			var g = P.new()
			g.difficulty = "easy"
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid, cdef.get("name_theme", {}),
				cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
			await g._generate_clues_forms_attempt()
			var clues: Array = g.chosen_form_clues
			var tag := "c%d seed %-3d" % [cid, seed]

			if clues.size() < 2:
				ok(false, "%s: fewer than 2 clues shipped at all" % tag)
				continue

			var m0: Dictionary = clues[0]
			var m1: Dictionary = clues[1]
			ok(int(m0.get("form_id", -1)) == 13 and int(m1.get("form_id", -1)) == 13,
				"%s: clues[0..1] are both Mutual Exclusion" % tag)

			var stars0: Dictionary = {}
			for ch in (m0.get("chars", []) as Array):
				stars0[int((ch as Dictionary).get("star", -1))] = true
			ok(stars0.size() == 4, "%s: clues[0] names exactly 4 categories (got %d)" % [tag, stars0.size()])

			var stars1: Dictionary = {}
			for ch in (m1.get("chars", []) as Array):
				stars1[int((ch as Dictionary).get("star", -1))] = true
			ok(stars1.size() == 3, "%s: clues[1] names exactly 3 categories (got %d)" % [tag, stars1.size()])

			# The chain pair sits in the CONTIGUOUS run of form_id==17
			# clues right after the two Mutex anchors -- capped at 4 so a
			# later, unrelated main-loop Betweenness draw can't be
			# mistaken for part of the guarantee.
			var seq_chains: int = 0
			var pitch_chains: int = 0
			var i: int = 2
			while i < clues.size() and i < 6 and int((clues[i] as Dictionary).get("form_id", -1)) == 17:
				var chars: Array = (clues[i] as Dictionary).get("chars", [])
				var axis_cat: int = int((chars[3] as Dictionary).get("cat", -1)) if chars.size() >= 4 else -1
				if axis_cat == Category.SEQUENCE:
					seq_chains += 1
				elif axis_cat == Category.PITCH:
					pitch_chains += 1
				i += 1
			ok(seq_chains == 2, "%s: exactly 2 surviving Sequence-axis chain clues (got %d)" % [tag, seq_chains])
			ok(pitch_chains == 2, "%s: exactly 2 surviving Pitch-axis chain clues (got %d)" % [tag, pitch_chains])

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
