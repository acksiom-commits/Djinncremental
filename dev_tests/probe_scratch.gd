extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends: a permanently red
# suite is one whose red stops meaning anything, which would quietly defeat
# test_matrix_up_lint.gd. Open findings go in that file's KNOWN_UNTRIAGED,
# never in a standing failure here. Keep `fails` even while idle, or the
# runner scores this module "unscored" and the summary stops reading
# ALL MODULES PASS.
#
# IDLE. Deliberately asserts nothing.
#
# Last investigation (2026-08-16): is "which positions are indistinguishable"
# a CONSTELLATION property (hardcodable per constellation) or a PER-PUZZLE
# one? ANSWER: per-puzzle. Over 12 pitch seeds, refining on topology + pitch
# with colour excluded, Archon gave 7 distinct at-risk sets and Bellows 5;
# the three fully connected constellations gave none at all.
#
# Two structural facts it produced, both now in test_position_separability's
# header: the Archon is FOUR components (a 6-cycle plus three triangles,
# every star degree 2), and a pitch tie inside a triangle is ALWAYS an
# interchangeable pair while a pitch tie in the 6-cycle almost never is —
# in a triangle the neighbour multiset is the same set either way, so it can
# never break the tie. Over 400 seeds the three triangles collided 74/70/60
# times: statistically even, so a small-sample lopsided reading is noise.
#
# Three process notes from the 2026-08-14 run, each of which cost a wrong
# conclusion:
#   * PRINT THE DATA, NOT THE SUMMARY. "0 hop-distance differences" was true
#     and the inference from it was wrong — the raw vectors showed 12 of 15
#     entries were -1 (unreachable), not a symmetry.
#   * VARY EVERY INPUT THE REAL SYSTEM VARIES. A "3 of 5" figure came from
#     holding the pitch assignment fixed without noticing; the honest number
#     was ~8%. Say which inputs were held fixed, or vary them.
#   * READ THE WHOLE FUNCTION. "Pitch is authored, not seeded" was asserted
#     after reading three branches of get_note_assignment() and stopping
#     before the Fisher-Yates shuffle at its tail.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
