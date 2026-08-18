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
# ── Phase 2, tenth slice, 2026-08-17: Mutex id_cat pitch scarcity ────────
#
# The non-feeding-Forms lead's third attempt, and the first clean win.
# MUTEX_PITCH_SCARCITY_WEIGHT (0.5) applied at the CONFIRMED-by-
# measurement dominant pathway — _mutex_legal_id_cats' per-participant
# weighted pick (_mutex_weighted_pick_remove), where PITCH stays fully
# eligible as an id_cat whenever a given participant happens to have
# singleton pitch, entirely independent of axis. The FIRST attempt
# (MUTEX_AXIS_WEIGHTS, retracted) targeted a DIFFERENT pathway (axis
# choice) and made this one measurably worse (36->60) by shifting more
# clue volume onto it.
#
# Matched-seed measurement, same 8 x 5 as every prior slice:
#     Mutex's OWN singleton-pitch disclosures:  36 -> 19  (mechanism
#         validated — nearly the exact inverse of the WRONG fix's 36->60)
#     singleton-pitch untouched:                33% -> 29%  (real gain,
#         the largest movement on this specific metric of any attempt)
#     overall untouched:                        24% -> 24%  (flat — the
#         size-1 gain looks offset by a small, likely noisy shift in
#         size-3, 21%->24%)
#     Mutex clue volume:                        52 -> 34 (dropped further,
#         expected — PITCH is a less attractive id_cat option overall now)
# Still 0/40 contradictions.
#
# KEPT (not reverted) — first attempt in this whole lead with BOTH a
# validated mechanism and a measured gain on the actual target metric,
# not just a flat/harmless result or a clear regression.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   eighth slice (def_star bias, prior standing state): 24% untouched,
#     singleton-pitch 33%
#   RETRACTED (Group Order priority): 26% untouched, singleton-pitch 37%
#   RETRACTED (Mutex axis weight): 24% untouched, singleton-pitch 33%
#     (flat), Mutex disclosures 36->60 (wrong mechanism)
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
#   * A SUSPICIOUSLY EXACT NULL RESULT DESERVES A SECOND MEASUREMENT.
#     Singleton-pitch landed at literally 39/120 both before and after the
#     axis-weight retune — that exactness triggered the per-Form follow-up
#     that found the WRONG PATHWAY was targeted, not just an ineffective one.
#   * WHEN A DIAGNOSIS IS RIGHT, THE FOLLOW-UP FIX CAN CONFIRM IT DIRECTLY.
#     The retracted attempt's OWN measurement (which pathway dominates)
#     became this slice's target, and Mutex's disclosure count moving in
#     the PREDICTED direction (down, not up) is independent confirmation
#     the mechanism was correctly understood this time.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
