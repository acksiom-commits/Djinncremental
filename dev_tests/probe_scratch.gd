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
# ── RETRACTED, 2026-08-17: Group Order scheduling priority ───────────────
#
# Built and reverted, same session. Gave Group Order (9) an unconditional
# priority pass — one guaranteed attempt before the main loop, ahead of
# non-feeding Forms competing for the same scarce singleton-pitch cells.
# The existing opening_anchors mechanism was rejected as the vehicle
# FIRST (difficulty-gated, empty for "hard" — every measurement this
# whole investigation has run against, so it would never have shown up).
#
# MEASURED, matched-seed A/B (same 8 seeds x 5 constellations both runs):
#     overall untouched:        25% -> 26%   (roughly flat, maybe noise)
#     singleton-pitch untouched: 32% -> 37%  (WORSE — the targeted metric)
#     Group Order clue volume:  ~38 -> 73    (priority pass worked AS
#                                              SCHEDULING — just didn't help)
# Still 0/40 contradictions throughout — nothing unsound, purely a
# coverage regression on the exact thing this was meant to fix.
#
# HYPOTHESIS, not yet verified: Group Order's SUBJECT draw is NAME-biased
# (fifth slice), but its `def_star` draw (`g: _sample_identity_axis_cell
# (group_cat, chain, -1)`) is NOT — pure bookkeeping, never produces a
# name_group fact. Running Group Order FIRST may just mean that unbiased
# draw claims a scarce singleton-pitch cell for BOOKKEEPING before
# Equality Pair (far higher volume, already NAME-biased, and actually
# capable of turning that same cell into a useful fact) reaches it in the
# main loop — winning Group Order more turns while making each turn worse
# for the shared resource.
#
# REVERTED CLEANLY: constellation_logic_puzzle.gd has zero diff against
# the last commit. If this is revisited, the def_star draw is the first
# thing to bias (or skip when it would land on a scarce cell) — do NOT
# just re-add scheduling priority alone, it was already tried and made
# the target metric worse.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   sixth slice (+ NAME bias, current committed state): 25% untouched,
#     singleton-pitch 32% vs 25% average — the actual STANDING baseline.
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
#   * A NEW LEVER CAN MOVE THE METRIC IT TARGETS IN THE WRONG DIRECTION.
#     Scheduling Group Order first was a reasonable hypothesis and a
#     clean, matched-seed measurement showed it made singleton-pitch
#     coverage WORSE, not better — reverted rather than kept "because it
#     seemed like it should help."

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
