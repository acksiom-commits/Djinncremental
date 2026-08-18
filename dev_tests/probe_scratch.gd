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
# ── CORRECTION, 2026-08-18: the tenth-slice "size-3 offset" was a bad
# comparison, not a real effect ────────────────────────────────────────────
#
# The tenth slice (MUTEX_PITCH_SCARCITY_WEIGHT) was reported as showing a
# possible offsetting regression: size-3 pitch-group untouched rate
# "21% -> 24%". That 21% was WRONG — it was the NINTH slice's own number
# (the RETRACTED MUTEX_AXIS_WEIGHTS state, a different committed history
# entirely), not the tenth slice's actual starting point.
#
# Verified directly: ran the EXACT committed e483b0b file (eighth slice,
# def_star-biased, immediately before any Mutex changes) against the same
# 8 seeds x 5 constellations. TRUE baseline for size-3: 46/168 = 27%, not
# 21%. Cross-checked via a neutral-weight (1.0) control on the tenth-
# slice code path first — bit-for-bit identical to the e483b0b run (same
# 39/48/46/7/5/9 across every bucket), confirming w *= 1.0 really is a
# mathematical no-op and the comparison is sound.
#
# CORRECTED comparison, same 8 x 5 both runs:
#     size-3 untouched:  27% (true baseline) -> 24% (actual fix) — a REAL
#         IMPROVEMENT, not an offset. The "offset" never existed.
# Combined with singleton-pitch's already-reported 33%->29%, the tenth
# slice helped BOTH buckets, with no found regression anywhere. No further
# action needed — the memory note flagging this as worth checking is now
# resolved as a false alarm, not a live issue.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   tenth slice (Mutex id_cat fix, current committed state): 24% untouched
#     overall, singleton-pitch 29% (was 33%), size-3 24% (TRUE baseline
#     was 27%, not the previously-reported 21%)
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
#     that found the WRONG PATHWAY was targeted, not just ineffective.
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
