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
# ── RETRACTED, 2026-08-18: Distance Existential pitch-scarcity fixes ─────
#
# Built and reverted, same day — the non-feeding-Forms lead's THIRD Form,
# and (unlike Mutex) neither sub-attempt moved the actual target metric,
# despite both working correctly on their OWN terms.
#
# ATTEMPT 1 — deprioritize_pitch on the SUBJECT's id_cat draw (via
# _sample_identity_axis_cell), reusing the proven-effective Mutex pattern
# exactly. RESULT: flat. singleton-pitch untouched 29% -> 30% (one star's
# worth of noise, not a regression, but no gain either).
#
# WHY IT DIDN'T FULLY WORK: Distance Existential has a SECOND consumption
# pathway the id_cat fix cannot reach. `target` (the OTHER end of the
# hop-distance clue) is chosen by pure distance-reachability with no
# weighted pick anywhere — its scarcity risk comes from
# _group_noun_phrase(prop_cat, target, false), which checks target's OWN
# _group_size and collapses from an indefinite phrase ("a star that plays
# G4") to a DEFINITE, uniquely-identifying one ("the star that plays G4")
# whenever that size is 1 — exactly as scarce a disclosure as an id_cat
# pick, gated on which raw value target happens to have, not on any
# category choice.
#
# ATTEMPT 2 — bias prop_cat itself toward COLOR (never singleton,
# confirmed repeatedly this session — colour group sizes are always 3-5),
# away from PITCH, targeting this second mechanism directly. RESULT:
# Distance Existential's OWN singleton-pitch disclosures dropped further
# (35 -> 25, confirming the mechanism diagnosis was correct) — but EVERY
# SINGLE closure-coverage bucket came back BYTE-FOR-BYTE IDENTICAL to
# attempt 1's numbers (36/120, 64/224, 31/168, 8/32, 8/40, 7/48 — all six,
# not just one). Distance Existential is non-feeding, so its own count
# only matters INDIRECTLY (freeing cells for feeding Forms) — and unlike
# Mutex, where that indirection measurably worked, here the freed capacity
# does not appear to reach any feeding Form at all. Cause not diagnosed
# further (would need tracing generation-order effects, a separate,
# bigger investigation from "fix the next Form").
#
# Both mechanism diagnoses were CORRECT (each Form's own numbers moved
# exactly as predicted); NEITHER translated into the metric this lead
# exists to move. 0/40 contradictions throughout both attempts — nothing
# unsound, purely ineffective for the stated goal.
#
# REVERTED CLEANLY via `git checkout -- constellation_logic_puzzle.gd`
# rather than six manual reversals (the change touched two shared,
# widely-used helpers plus a renamed constant) — zero diff against
# f657e1a confirmed before re-running the suite.
#
# If revisited: do NOT re-apply id_cat/prop_cat fixes to Distance
# Existential without FIRST tracing why Mutex's freed cells got absorbed
# and this Form's did not — the missing piece is generation ORDER/TIMING,
# not another category-weighting lever.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   tenth slice (Mutex id_cat fix, current standing committed state): 24%
#     untouched, singleton-pitch 29%, size-3 24% — the actual baseline.
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
#     Scheduling Group Order first made singleton-pitch coverage WORSE —
#     reverted rather than kept "because it seemed like it should help."
#   * A CORRECT MECHANISM DIAGNOSIS DOES NOT GUARANTEE THE METRIC MOVES.
#     Both Distance Existential fixes reduced the Form's OWN scarce-cell
#     consumption exactly as predicted, and STILL produced zero change on
#     every closure-coverage bucket — the mechanism inside the Form was
#     right; whether the freed resource reaches a feeding Form downstream
#     is a SEPARATE question this investigation didn't answer.
#   * A "BEFORE" NUMBER FROM A DIFFERENT COMMIT IS NOT YOUR BASELINE.
#     Comparing the tenth slice against the ninth slice's own (retracted)
#     measurement, rather than the actual prior committed state, invented
#     a regression that never existed. Verified by re-running the exact
#     committed pre-fix file directly, not by re-deriving the number from
#     memory or from a differently-configured run.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
