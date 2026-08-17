extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# IDLE. Deliberately asserts nothing.
#
# ── Audit, 2026-08-17: which names stay untouched by the NAME closure ────
#
# 8 seeds x 5 constellations, 632 names, 211 untouched (33%). Question:
# CONCENTRATED (same structural positions every seed — a real gap) or
# DIFFUSE (roughly uniform — needs more volume/breadth, not a fix)?
#
# ANSWER: diffuse. No position was untouched in EVERY seed (0 of 632 at
# 8/8); the distribution peaks in the middle (2-4 misses out of 8 for most
# positions), tapering at both ends — the signature of randomness, not a
# structural blind spot.
#
#     untouched in 0 of 8 seeds: 3 positions      6 of 8: 1 position
#     untouched in 1 of 8 seeds: 12 positions      never 7 or 8 of 8
#     ...peaks at 2-4 of 8 (23/19/15 positions)
#
# By attribute:
#     DEGREE:        flat, 32-44%, no correlation (the 44% outlier sits
#                     on only 48 samples — noise).
#     COLOUR size:    flat, 32-34% regardless of group size 3/4/5 — does
#                     NOT predict coverage at all.
#     PITCH size:     the one real spread — singleton (48% untouched) vs
#                     size-2 (26%). Plausible mechanism: a singleton-pitch
#                     star is the ONLY candidate for a pitch-anchored
#                     identity cell, so it's likelier to get consumed
#                     early by a CLOSURE-IRRELEVANT Form (Pairwise Order,
#                     Exact Offset, Pseudo-True-Pair) via the matrix's
#                     "used"-cell tracking, leaving nothing for Form
#                     23/Group Order/Equality Pair later. Real but modest
#                     (120 samples), not the dominant story.
#
# CONCLUSION: the gap is the expected consequence of two compounding
# facts, not a bug hiding in one property — only 5 of ~21 Forms feed the
# closure at all, and none of the generation is EXHAUSTIVE (nothing
# guarantees every name gets at least one closure-usable disclosure; it's
# draws against a random pool with "used"-cell exhaustion, not a
# coverage-complete scheduler). NEXT lever is volume/breadth (wire more
# Forms, bias selection frequency), not a targeted structural fix — except
# possibly the singleton-pitch starvation angle, worth a closer look on
# its own if pursued.
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

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
