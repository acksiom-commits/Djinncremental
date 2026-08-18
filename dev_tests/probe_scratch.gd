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
# ── Phase 2, eighth slice, 2026-08-17: bias Group Order's def_star ───────
#
# Followed up on the retracted scheduling-priority attempt's hypothesis:
# def_star's OWN identity draw (`g: _sample_identity_axis_cell(group_cat,
# chain, -1)`) was unbiased, pure bookkeeping (never rendered, never
# produces a name_group fact), and could still land on Pitch even when
# group_cat=Colour — possibly spending a scarce singleton-pitch cell on
# nothing. Added `bias_name=true` to that ONE call, reusing the already-
# verified _weighted_category_excluding machinery — no new mechanism, no
# scheduling change (Group Order still runs wherever the main loop puts
# it, unlike the reverted priority pass).
#
# Matched-seed comparison, same 8 x 5 as every prior slice:
#     overall untouched:     25% (baseline) -> 26% (priority, reverted) -> 24% (this)
#     singleton-pitch:        32%           -> 37% (priority, reverted) -> 33% (this)
#     Group Order volume:     38            -> 73                       -> 62
# Still 0/40 contradictions.
#
# RESULT: modest, real, SAFE overall gain (25%->24%) with nothing
# regressed anywhere — unlike the priority pass, there is no reason to
# walk this back. But the hypothesis was only PARTIALLY confirmed:
# singleton-pitch specifically landed at 33%, essentially flat against
# the 32% baseline, not the clear win the mechanism predicted. It undid
# the priority pass's damage on that metric without actually fixing it.
# Group Order's volume rose even without scheduling priority — plausibly
# because NAME-anchored candidates are basically always available (never
# "used up" the way one specific pitch cell can be), so biasing toward
# NAME makes MORE of its attempts succeed at all, not just changes which
# category wins when it does.
#
# NEXT: singleton-pitch coverage is still the softest number (33% vs 24%
# overall). The def_star mechanism alone doesn't close it. Untested:
# whether Mutual Exclusion / Distance Existential / Dual Negation (the
# non-feeding consumers) could be made to prefer NON-singleton pitch
# stars when a singleton alternative exists elsewhere in their own
# candidate pool — a different Form's code, not Group Order's.
#
# ── Superseded numbers, kept for the process trail ────────────────────────
#   sixth slice (NAME bias, standing baseline before this slice): 25%
#     untouched, singleton-pitch 32%
#   RETRACTED same-day attempt (scheduling priority): 26% untouched,
#     singleton-pitch 37% — reverted, zero diff against that commit
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
#     Scheduling Group Order first was a reasonable hypothesis and a
#     clean, matched-seed measurement showed it made singleton-pitch
#     coverage WORSE, not better — reverted rather than kept "because it
#     seemed like it should help."
#   * A FIX CAN BE SAFE AND STILL NOT BE THE WIN THE HYPOTHESIS PREDICTED.
#     Biasing def_star undid the regression and moved the OVERALL number,
#     but the SPECIFIC metric it targeted (singleton-pitch) barely moved —
#     reported plainly as a partial result, not oversold as "fixed."

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
