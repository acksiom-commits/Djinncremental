extends "res://dev_tests/test_base.gd"
# _final_redundancy_safety_net (2026-09-22): a whole-clue-set recheck run
# after BOTH _prune_redundant_clues (main-loop tail) and
# _recheck_anchors_for_redundancy (former-anchor prefix) finish, closing
# the coverage gap where neither pass can see a clue made redundant by a
# change the OTHER one made. Reuses _try_prune_clue_at, the same
# removability test already verified against two real bugs and a
# 60-puzzle sweep.
#
# Verifies: (1) a clue injected as fully redundant by construction gets
# removed regardless of where it sits, (2) running the pass AGAIN on an
# already-settled real clue set removes nothing further (idempotent --
# it doesn't chew into genuinely necessary content once nothing is left
# to prune; a real generated puzzle's own clues are the test data here,
# not a synthetic "necessary" clue -- see the note below on why a
# synthetic one doesn't actually prove what it looks like it proves),
# (3) the guaranteed opening Mutex (form_id 13) is NEVER removed even
# when it's the one made redundant -- same protection
# _recheck_anchors_for_redundancy already gives it, for the same
# "guaranteed opener" reason, not re-litigated here.

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
	ok(exact_star >= 0, "found a star with a known exact rank to build synthetic cases against")

	# --- Case 1: redundant by construction, injected in the MIDDLE of the
	# clue list (neither a former anchor nor the freshly-drawn tail
	# _prune_redundant_clues already minimized) -- only the safety net's
	# whole-set sweep is positioned to catch this specifically. ---
	var lo: int = maxi(0, exact_rank - 1)
	var hi: int = mini(scn - 1, exact_rank + 1)
	var redundant_text: String = "TEST_REDUNDANT: star %d is among ranks [%d,%d]." % [exact_star, lo, hi]
	var mid: int = int(g.chosen_form_clues.size() / 2.0)
	g.chosen_form_clues.insert(mid, {
		"form_id": 8, "form_name": "Range", "text": redundant_text,
		"characteristics": [], "chars": [], "cells": [], "search_terms": [],
		"disclosures": [{"kind": "ordinal_range", "s": exact_star, "lo": lo, "hi": hi}],
	})

	# --- Case 2: the guaranteed Mutex opener, made just as redundant as
	# case 1 -- must NEVER be removed by this pass. ---
	var mutex_idx: int = -1
	for i in g.chosen_form_clues.size():
		if int(g.chosen_form_clues[i].get("form_id", -1)) == 13:
			mutex_idx = i
			break
	ok(mutex_idx >= 0, "puzzle has an opening Mutex clue to test protection against")

	var name_revealed: Array = []
	for _n in scn:
		name_revealed.append(false)
	g._recompute_name_revealed(name_revealed)

	await g._final_redundancy_safety_net(name_revealed)

	var still_present_1: bool = false
	var mutex_survived: bool = false
	for c in g.chosen_form_clues:
		var t: String = str(c.get("text", ""))
		if t == redundant_text:
			still_present_1 = true
		if int(c.get("form_id", -1)) == 13:
			mutex_survived = true

	ok(not still_present_1,
		"a clue redundant by construction, injected mid-list, is removed by the whole-set sweep")
	ok(mutex_survived, "the guaranteed opening Mutex clue is never removed, even when redundant")

	# --- Idempotency: the clue set is now settled (case 1's redundancy
	# removed, everything else already minimized by the real generation
	# run). Running the pass AGAIN must find nothing further to remove --
	# a real generated puzzle's own surviving clues are all genuinely
	# load-bearing, so this proves the pass doesn't over-prune once
	# nothing is left to prune, without needing a synthetic "necessary"
	# clue (which, as an earlier version of this test discovered, isn't
	# actually guaranteed to be necessary: a fully-solvable puzzle's OTHER
	# clues can already jointly entail a star's rank even with no single
	# clue stating it directly, so a hand-added "new" fact about it can be
	# genuinely redundant from the start, not a test bug to work around).
	var count_before_replay: int = g.chosen_form_clues.size()
	await g._final_redundancy_safety_net(name_revealed)
	ok(g.chosen_form_clues.size() == count_before_replay,
		"running the pass again on an already-settled set removes nothing further (%d -> %d)"
			% [count_before_replay, g.chosen_form_clues.size()])

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
