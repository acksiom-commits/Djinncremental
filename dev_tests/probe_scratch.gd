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
# ── RETRACTED, 2026-08-17: MUTEX_AXIS_WEIGHTS retune ──────────────────────
#
# Built and reverted, same session — the non-feeding-Forms lead's first
# attempt. Cut PITCH's axis weight 0.45 -> 0.15 (freed weight to NAME/
# SEQUENCE), reasoning: axis=Pitch forces EVERY Mutex participant to have
# singleton pitch (_mutex_axis_groups filters non-unique members out
# entirely), and Mutex was measured the single largest non-feeding
# consumer of that resource (36 genuine disclosures).
#
# MEASURED, matched-seed (same 8 x 5 both runs):
#     overall untouched:        24% -> 24%   (flat — null result)
#     singleton-pitch untouched: 33% -> 33%  (EXACTLY flat: 39/120 both
#                                              times, not just close)
#     Mutex clue volume:        higher -> 52 (dropped, as intended)
#     Mutex genuine disclosures: 36    -> 60 (WENT UP — the opposite of
#                                              the goal, despite volume
#                                              dropping)
#
# WHY: the fix only addressed ONE of Mutex's two singleton-pitch
# consumption pathways. axis=Pitch (cut 45%->15%) genuinely shrank. But
# axis=Name/Sequence now fires 80% of the time (up from 50%), and WITHIN
# those clues, each of 3-5 participants gets an id_cat via a SEPARATE
# weighted pick (_mutex_legal_id_cats / MUTEX_REPEAT_CATEGORY_WEIGHT) —
# PITCH stays fully eligible there whenever that specific participant
# happens to have singleton pitch, entirely independent of axis. More
# Name/Sequence-axis clues meant more chances down THIS path, and it grew
# more than the axis path shrank. Net: the ORIGINAL FORM SELECTED (Mutex)
# was right; the SPECIFIC MECHANISM targeted within it was incomplete.
#
# REVERTED CLEANLY: constellation_logic_puzzle.gd has zero diff against
# the last commit. If revisited, the id_cat-level pick inside
# _mutex_legal_id_cats/_mutex_weighted_pick_remove is the ACTUAL dominant
# pathway — fixing axis weight alone will not work, confirmed by
# measurement, not theory.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   eighth slice (def_star bias, current committed state): 24% untouched,
#     singleton-pitch 33% vs overall average — the actual STANDING baseline.
#   RETRACTED (Group Order priority): 26% untouched, singleton-pitch 37%.
#
# ── Earlier process notes, each of which cost a wrong conclusion ─────────
#   * PRINT THE DATA, NOT THE SUMMARY. "0 hop-distance differences" was true
#     and the inference from it was wrong — the raw vectors showed 12 of 15
#     entries were -1 (unreachable), not a symmetry.
#   * VARY EVERY INPUT THE REAL SYSTEM VARIES. A "3 of 5" figure came from
#     holding the pitch assignment fixed without noticing; the honest number
#     was ~8%. Say which inputs were held fixed, or vary them.
#   * READ THE WHOLE FUNCTION. "Pitch is authored, not seeded" was asserted
#     after reading three branches of get_note_assignment() and stopping
#     before the Fisher-Yates shuffle at its tail.
#   * MEASURE THE RIGHT FACT KIND, NOT A NEARBY ONE. "301 of 316 pinned"
#     came from counting ordinal_exact — plausible-looking, unrelated to
#     what was being asked, and not even read by the code under test.
#   * A NEW LEVER CAN MOVE THE METRIC IT TARGETS IN THE WRONG DIRECTION.
#     Scheduling Group Order first was a reasonable hypothesis and a
#     clean, matched-seed measurement showed it made singleton-pitch
#     coverage WORSE, not better — reverted rather than kept "because it
#     seemed like it should help."
#   * A SUSPICIOUSLY EXACT NULL RESULT DESERVES A SECOND MEASUREMENT, NOT
#     A SHRUG. Singleton-pitch landed at literally 39/120 both before and
#     after the axis-weight retune — that exactness, not just the flatness,
#     is what triggered a follow-up (per-Form disclosure counts), which
#     found the mechanism was wrong even though the AGGREGATE number
#     looked identical.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
