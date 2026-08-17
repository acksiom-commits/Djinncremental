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
# ── Phase 2, fifth slice, 2026-08-16: same-group propagation ─────────────
#
# Built _propagate_same_group(): domain-level reachability pruning for
# Equality Pair's both-sides-NAME case, deferred since the fourth slice.
# name_star_a's and name_star_b's positions must share the same raw `cat`
# value with NO group_key known (unlike name_group) — not expressible as
# a per-row value_in_set/value_out_set restriction. Removes a candidate
# position from one row only when unreachable by ANY value in the other
# row's domain, repeated to a fixpoint (transitive chains across multiple
# pairs fall out for free, no extra logic).
#
# SOUND but NOT COMPLETE by construction — never teaches _solve()'s own
# backtracking about the constraint. Argued safe in the code's own header
# comment: every fact fed to _solve() is validated against ground truth
# first, so the TRUE assignment is always among whatever _solve() finds;
# if it finds exactly one, that one IS truth, full stop. The only failure
# direction is UNDER-claiming uniqueness, never over-claiming it — safe
# for a rejection gate. MEASURED, not just argued: 0/20 contradictions,
# confirming the argument held rather than assuming it did.
#
# Measured, 20 puzzles / 316 names:
#     exact Sequence pin:                     5 (2%)   — unchanged
#     colour/pitch group OR order fact only: 172 (54%)  — unchanged
#     same-group pairing only (no group_key): 21 (7%)   — NEW bucket
#     NO closure-usable constraint at all:   118 (37%)  — down from 139 (44%)
# 17 name_same_group facts fired across 20 puzzles. Still 0/20
# contradictions across all FIVE slices now; still 0/20 full closures.
#
# NEXT: 37% still untouched. The both-sides-NAME propagation was the
# recorded highest-leverage item and it's done — no single obvious next
# lever remains; candidates are raising Form 23/9's selection frequency,
# revisiting Dual Negation/Mutual Exclusion for player-facing variety
# (not closure coverage, per the earlier finding), or auditing which
# SPECIFIC names stay untouched across seeds to see if it's concentrated
# (a structural gap) or diffuse (needs broader coverage across the board).
#
# ── Superseded numbers, kept for the process trail (all 0/20 closures,
# 0/20 contradictions throughout) ─────────────────────────────────────────
#   fourth slice (+ Equality Pair, one-side only): 172/316 (54%) covered,
#     139 (44%) untouched
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
