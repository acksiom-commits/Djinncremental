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
# ── Fresh measurement pass, 2026-08-17, after the sixth slice ────────────
#
# Repeated the original audit's exact shape (8 seeds x 5 constellations,
# 632 names) on the current code. Reproduced the sixth slice's headline
# numbers exactly (3 pinned, 379 group/order, 92 same-group, 158
# untouched = 25%), then re-ran the degree/colour-size/pitch-size/
# per-position breakdowns that were last measured pre-bias.
#
# STILL DIFFUSE: 0 of 632 positions untouched in every seed; the whole
# per-position distribution just shifted toward fewer misses rather than
# concentrating anywhere. Degree and colour group size stayed flat and
# uncorrelated (the degree-3 outlier from the original audit reverted to
# normal, confirming it was noise as flagged then).
#
# PITCH SIZE — the bias helped, but did not fully close the gap it
# targeted:
#     size 1 (singleton): 48% untouched pre-bias -> 32% post-bias
#     overall average:     33% pre-bias          -> 25% post-bias
# The GAP between singleton-pitch and the overall average narrowed (15pts
# -> 7pts) but did not close. Same mechanism, still live: the bias only
# raises NAME's odds WITHIN the five closure-feeding Forms — it does
# nothing about Mutual Exclusion / Distance Existential / Dual Negation
# still competing for the same scarce singleton-pitch cell from outside
# the closure-feeding set.
#
# CONCLUSION: real, smaller residual lead (reduce competition from the
# non-feeding side, a genuinely different change than strengthening the
# feeding side further), but shrinking returns (15pt gap -> 7pt) alongside
# everything else reading flat/diffuse suggests this is near the point of
# diminishing value for TARGETED structural leads. Further gains likely
# look like broad volume (more Forms wired) rather than another mechanism
# this specific.
#
# ── Prior numbers, kept for the process trail (all 0/N closures, 0/N
# contradictions throughout) ──────────────────────────────────────────────
#   sixth slice  (+ NAME bias):              158/632 (25%) untouched
#   audit baseline (pre-bias):               211/632 (33%) untouched
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
#   * "chars" INCLUDES BOOKKEEPING, NOT JUST DISCLOSURE. A first pass at
#     the singleton-pitch mechanism scanned chars for {cat:PITCH} and got
#     188 "mentions" from a Form whose id_cat can never BE pitch by
#     construction — those were touched-but-never-rendered axis_a/axis_b
#     nodes. search_terms (rendered-only) gave the real number.
#   * AN UNEXPLAINED METRIC SHIFT NEEDS A CONTROL, NOT A SHRUG OR A PANIC.
#     seq_unique dropping to 38/40 was neither dismissed nor treated as a
#     blocking bug on sight — a neutral-weight re-run isolated whether the
#     BIAS or the CODE PATH caused it before deciding anything.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
