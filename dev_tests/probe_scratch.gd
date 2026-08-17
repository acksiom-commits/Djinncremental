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
# ── Phase 2, third slice, 2026-08-16: Group Order (form_id 9) ────────────
#
# Wired via two NEW fact kinds — name_precedes_group / name_follows_group —
# a rank RANGE restriction, genuinely different from name_group's set-
# membership shape, so it got its own kind rather than being forced into
# the existing one. Closure resolves it via the ALREADY-established seq_sol
# (not pitch_rank_solution directly, even though they're equal whenever
# seq_unique holds — kept consistent with how the Sequence-anchored branch
# already resolves positions).
#
# Measured, 20 puzzles / 316 names:
#     exact Sequence pin:                     5 (2%)   — unchanged
#     colour/pitch group OR order fact only: 126 (40%)  — up from 118 (37%)
#     NO closure-usable constraint at all:   185 (59%)  — down from 193 (61%)
# Only 19 Form-9 clues fired across 20 puzzles (vs Form 23's 231) — Group
# Order is tier 3 (Systemic), generated far less often by design, so a
# small gain here was expected, not a sign anything's wrong. Still 0/20
# contradictions (engine sound, third slice running), still 0/20 full
# closures (well short of the ~59% coverage gap remaining).
#
# NEXT: 59% of names still get nothing. Two untested levers — raise Form
# 23/9's selection frequency (FORM_TIER/tier_ratio), or find another
# colour-capable source among the Forms mapped as "structurally blind"
# (worth re-checking whether that conclusion still holds given group_
# noun_phrase-style bypasses weren't considered for all of them).
#
# ── Phase 2, second slice, 2026-08-16 (superseded numbers) — Form 23 wired
# alone: 118/316 (37%) group-only, 193/316 (61%) untouched, 0/20 closures,
# 0/20 contradictions. A diagnostic mistake was caught and fixed here: a
# first pass counted "ordinal_exact" (Sequence-rank bookkeeping, unrelated
# to NAME, not read by the closure) instead of the actual consumed kinds.
#
# ── Phase 2, first slice, 2026-08-16 (superseded numbers) — Exact Identity
# + Single Negation only: name_unique_closure 0/20, under-constrained
# 20/20, contradictions 0/20.
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
