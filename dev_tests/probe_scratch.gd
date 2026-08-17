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
# ── Phase 2 of the position-axis migration, first slice, 2026-08-16 ──────
#
# Built _solve_name_closure(): a possible[name_star][candidate_position]
# grid, same shape _solve() already uses for Sequence, fed by NEW value_fact
# kinds "name_group"/"name_group_neg" (descriptor-anchored, mirroring
# distance_hop's ref_cat/target_cat idiom rather than storing a resolved
# position list) emitted ONLY from characteristics that were ACTUALLY
# rendered via _characteristic_label() in a clue's own text line — never
# from grid_updates/chars, which include touched-but-unrendered bookkeeping
# (confirmed via Pairwise Order's axis_a/axis_b and Equality Pair's
# axis_a/axis_b, neither ever passed to _characteristic_label).
#
# Wired to exactly two Forms so far: Exact Identity and Single Negation —
# the only two whose relation (same star / different star) is unambiguous
# at the cell level. Measured, NOT assumed: both are structurally UNABLE to
# carry a Colour fact, because every clue drawn from
# _sample_grid_cell_maybe_chained requires _category_uniquely_labels on
# BOTH sides, and Colour's group size is never 1 (measured earlier: only
# 3/4/5). So this slice can only ever produce Sequence-anchored (always
# singleton) or Pitch-anchored (singleton only ~19% of stars) facts.
#
# Result over 20 puzzles, all 5 constellations:
#     name_unique_closure   0 of 20   (fully expected, not a bug)
#     under-constrained (>1 solutions)   20 of 20
#     CONTRADICTIONS (0 solutions)        0 of 20
# The 0/0 split is the important number: the closure never contradicts the
# true assignment, so the ENGINE is sound — it is starved of facts, not
# broken. name_unique_closure is a non-gating field on
# _generate_clues_forms_attempt's return dict; the LIVE gate (name_unique,
# the old mention-coverage flag) is untouched.
#
# NEXT: the 177/971 colour-naming clues measured in the Phase 0 probe come
# from a DIFFERENT code path — group-phrase Forms (Mutual Exclusion / Count
# / Group Comparison) that describe a colour GROUP directly rather than
# rendering one star's identity — not yet mapped. That's where the real
# coverage gain is; wiring more identity-anchored Forms won't reach it.
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
#   * The Archon is FOUR components — a 6-cycle plus three triangles, every
#     star degree 2. A pitch tie inside a triangle is ALWAYS an
#     interchangeable pair; one in the 6-cycle almost never is.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
