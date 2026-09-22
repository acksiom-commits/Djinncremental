extends "res://dev_tests/test_base.gd"
# Anchor-redundancy bug (user-reported 2026-09-21, The Archon): "Heleai is
# among the last 3" (an opening-anchor Range clue) shipped alongside
# "Heleai is the star that fires 15th note" (another opening-anchor Exact
# Identity clue, same star, rank inside the range's own window) -- the
# range added zero information once the exact rank was known.
#
# Root cause: opening anchors sit before protected_clue_count so the main
# _prune_redundant_clues() pass never tests them -- correct for THAT
# pass (an anchor drawn early can't know a LATER anchor will subsume it),
# but nothing ever gave anchors a second look once the full clue set
# was final. Confirmed via a broad sweep (7 constellations x 40 seeds)
# that ~60 superficially-similar range/exact pairs are almost always
# NOT actually redundant -- the range clue's exclusions are usually still
# load-bearing for closing some OTHER star's name, even though the named
# star's OWN rank looks pinned twice. So the fix can't be "delete any
# range whose window contains a same-star exact value"; it has to be
# "give anchors the exact same rigorous removability test the main pass
# already uses (Sequence uniqueness + name closure + no-unbind), just
# applied to the anchor prefix too" -- see _recheck_anchors_for_redundancy.
#
# This test can't rely on a natural seed (a targeted sweep found no
# second reproducible case within a reasonable search), so it verifies
# the FIX MECHANISM directly: generate a real, validly-unique puzzle,
# inject a synthetic Range clue that is redundant BY CONSTRUCTION (its
# window is built to fully contain an already-known exact rank, and it
# touches no Name node, so it can't affect name_revealed either) as if it
# were one of the anchors, and confirm _recheck_anchors_for_redundancy
# removes it. A second case confirms the reverse: a Range clue asserting
# information NOT already covered by any exact fact is correctly kept.

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
	var cdef: Dictionary = cd.get_constellation_def(0)  # The Archon
	var scn: int = int(cdef["star_count"])

	var g = P.new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	g.setup(scn, cdef["line_pairs"], sq, 5, 0, cdef.get("name_theme", {}),
		cd.get_note_assignment(0), cd.get_note_freqs(0), null)
	await g.generate_clues_forms()
	ok(not g.chosen_form_clues.is_empty(), "puzzle generated at least one clue")

	# Find any star with a known exact rank among the real, shipped clues.
	var exact_star: int = -1
	var exact_rank: int = -1
	for c in g.chosen_form_clues:
		for f in (c.get("disclosures", []) as Array):
			var fd: Dictionary = f
			if str(fd.get("kind", "")) == "ordinal_exact":
				exact_star = int(fd["s"])
				exact_rank = int(fd["r"])
				break
		if exact_star >= 0:
			break
	ok(exact_star >= 0, "found a star with a known exact rank to build the synthetic case against")

	# --- Case 1: a Range clue redundant BY CONSTRUCTION -------------------
	var lo: int = maxi(0, exact_rank - 1)
	var hi: int = mini(scn - 1, exact_rank + 1)
	var redundant_text: String = "TEST_REDUNDANT: star %d is among ranks [%d,%d]." % [exact_star, lo, hi]
	g.chosen_form_clues.append({
		"form_id": 8, "form_name": "Range", "text": redundant_text,
		"characteristics": [], "chars": [], "cells": [], "search_terms": [],
		"disclosures": [{"kind": "ordinal_range", "s": exact_star, "lo": lo, "hi": hi}],
	})

	var name_revealed: Array = []
	for _n in scn:
		name_revealed.append(false)
	g._recompute_name_revealed(name_revealed)

	g._recheck_anchors_for_redundancy([redundant_text], name_revealed)

	var still_present_1: bool = false
	for c in g.chosen_form_clues:
		if str(c.get("text", "")) == redundant_text:
			still_present_1 = true
	ok(not still_present_1,
		"a Range clue redundant by construction (window fully covers an already-known exact rank) gets removed")

	# --- Case 2: a Range clue that is NOT covered by any known exact fact,
	# on a star with NO exact-rank disclosure anywhere -- must be kept. ---
	var covered_stars: Dictionary = {}
	for c in g.chosen_form_clues:
		for f in (c.get("disclosures", []) as Array):
			var fd: Dictionary = f
			if str(fd.get("kind", "")) == "ordinal_exact":
				covered_stars[int(fd["s"])] = true
	var uncovered_star: int = -1
	for s in scn:
		if not covered_stars.has(s):
			uncovered_star = s
			break

	if uncovered_star < 0:
		print("  (skipped case 2: every star already has an exact-rank disclosure in this puzzle -- nothing uncovered to test against)")
	else:
		var necessary_text: String = "TEST_NECESSARY: star %d is among ranks [0,0]." % uncovered_star
		g.chosen_form_clues.append({
			"form_id": 8, "form_name": "Range", "text": necessary_text,
			"characteristics": [], "chars": [], "cells": [], "search_terms": [],
			"disclosures": [{"kind": "ordinal_range", "s": uncovered_star, "lo": 0, "hi": 0}],
		})
		# Pin the puzzle to have this new fact be the ONLY thing that
		# determines this star's rank is exactly 0 -- since nothing else
		# discloses this star's rank at all (that's how uncovered_star was
		# picked), removing it should either break Sequence uniqueness
		# outright or at minimum not be silently accepted as safe.
		var name_revealed2: Array = []
		for _n in scn:
			name_revealed2.append(false)
		g._recompute_name_revealed(name_revealed2)
		g._recheck_anchors_for_redundancy([necessary_text], name_revealed2)
		var still_present_2: bool = false
		for c in g.chosen_form_clues:
			if str(c.get("text", "")) == necessary_text:
				still_present_2 = true
		ok(still_present_2,
			"a Range clue asserting genuinely new information (no other clue discloses this star's rank at all) is correctly kept")

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
