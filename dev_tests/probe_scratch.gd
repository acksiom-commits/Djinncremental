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
# ── Phase 0 of the position-axis migration, ANSWERED 2026-08-16 ──────────
#
# Question: can a POSITION x NAME closure be built on the EXISTING matrix,
# deferring the Colour/Pitch cardinality drop (Phase 3)? ANSWER: YES.
#
# Measured over 20 puzzles / 971 clues, all five constellations:
#     clues naming a COLOUR                 177
#     clues naming a PITCH                  277
#     clues carrying a sub-rank letter        0
# The two nonzero rows are the non-vacuity check: zero leaks would also be
# what "no colour clue was ever generated" looks like.
#
# The stronger result came from the follow-up, over 15 puzzles / 237 stars:
#     colour group sizes seen    3, 4, 5      — NEVER 1
#     pitch  group sizes seen    1..6         — 45 stars in singleton groups
#
# _category_uniquely_labels() requires group size <= 1, so COLOUR CAN NEVER
# BE AN IDENTITY LABEL AT ALL, yet 339 COLOR chars appear in clues. Both
# facts hold because `chars` records MENTIONS, not rendered identities:
# colour reaches the player only as a SET constraint ("Theryis is among the
# blue ones"), which is exactly the semantics a player-space closure needs.
# Pitch differs legitimately — a note played by exactly one star IS a
# checkable identity once the player has listened.
#
# So the shipped clue set is ALREADY expressed in the player's value space.
# The sub-rank fiction lives entirely inside _matrix as clue-SELECTION
# bookkeeping and never escapes it. Phase 3 is cleanup, not a prerequisite.
#
# Consequence for Phase 2, still unverified: the closure looks like a NEW
# CONSUMER of `chars` rather than a re-encoding — translate each char to
# the position SET it constrains (colour -> its group, pitch -> its group,
# name/sequence -> singleton) instead of the single star it is stored
# against. If that holds for all 21 Form builders, the `cells` re-encoding
# and the CACHE_VERSION bump both drop out of the plan. Negation,
# betweenness, count and distance Forms are the ones to check: their
# constraint is not carried by the two chars alone.
#
# ── Process notes from earlier runs, each of which cost a wrong call ─────
#   * PRINT THE DATA, NOT THE SUMMARY. "0 hop-distance differences" was true
#     and the inference from it was wrong — the raw vectors showed 12 of 15
#     entries were -1 (unreachable), not a symmetry.
#   * VARY EVERY INPUT THE REAL SYSTEM VARIES. A "3 of 5" figure came from
#     holding the pitch assignment fixed without noticing; the honest number
#     was ~8%. Say which inputs were held fixed, or vary them.
#   * READ THE WHOLE FUNCTION. "Pitch is authored, not seeded" was asserted
#     after reading three branches of get_note_assignment() and stopping
#     before the Fisher-Yates shuffle at its tail.
#   * The Archon is FOUR components — a 6-cycle plus three triangles, every
#     star degree 2. A pitch tie inside a triangle is ALWAYS an
#     interchangeable pair; one in the 6-cycle almost never is.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
