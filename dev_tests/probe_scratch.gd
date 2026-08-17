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
# ── Phase 2, fourth slice, 2026-08-16: Equality Pair (form_id 12) ────────
#
# Wired via a NEW helper, _name_same_axis_facts, but it emits a PLAIN
# "name_group" fact — reuses the existing kind and closure-side code
# unchanged. Key realization that shaped this: Equality Pair's "known"
# (non-NAME) side is a concrete generator-known star index the WHOLE WAY
# THROUGH, regardless of whether its id_cat is Sequence or Pitch — unlike
# the EXISTING Sequence-anchored name_group branch, whose group_key is an
# abstract RANK needing rank_to_star resolution INSIDE the closure. This
# one computes its raw axis value at EMISSION time, so no new closure
# code was needed at all, only a new emission function.
#
# Deliberately scoped to the ONE-SIDE-NAME case only (~44% of draws,
# reuses everything). The BOTH-SIDES-NAME case (~11%) needs real mutual
# arc-consistency propagation ("once domain(A) collapses to one group,
# narrow domain(B) to the same group") that neither value_in_set nor
# value_out_set can express, and _solve()'s existing propagation passes
# are order-shaped, not equivalence-class-shaped — deferred as separate
# work, not silently dropped.
#
# Measured, 20 puzzles / 316 names — the biggest single jump so far:
#     exact Sequence pin:                     5 (2%)    — unchanged
#     colour/pitch group OR order fact only: 172 (54%)  — up from 126 (40%)
#     NO closure-usable constraint at all:   139 (44%)  — down from 185 (59%)
# 121 Form-12 clues fired across 20 puzzles — Equality Pair is one of the
# two historically-dominant Forms by clue volume, so the size of this
# jump was expected once wired. Still 0/20 contradictions across all FOUR
# slices now (engine remains sound); still 0/20 full closures — 44%
# untouched is real progress but still short of complete.
#
# NEXT: the both-sides-NAME propagation pass is now the single highest-
# leverage remaining item (Equality Pair alone leaves ~11% of ITS OWN
# draws on the table for exactly this reason) — bigger lift than any fact-
# kind addition so far, genuinely new solver machinery, not a quick add.
#
# ── Superseded numbers, kept for the process trail (all 0/20 closures,
# 0/20 contradictions throughout) ─────────────────────────────────────────
#   third slice  (+ Group Order):     126/316 (40%) covered, 185 (59%) not
#   second slice (+ Form 23):         118/316 (37%) covered, 193 (61%) not
#   first slice  (Exact Id + Neg only): 0 group facts reaching the closure
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
