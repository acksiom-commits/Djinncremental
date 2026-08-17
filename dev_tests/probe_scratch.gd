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
# ── Phase 2, second slice, 2026-08-16: Form 23 (Group Membership) ────────
#
# Built the bare "X is [not] one of the [colour/pitch] stars" clue — found
# missing by a matrix-up review of negative-exclusion coverage. Registered
# as form_id 23, tier 2, wired into FORM_NAMES/AUTOMATED_FORM_IDS/
# _build_form/FORM_TIER.
#
# CAUGHT AND FIXED before landing: subj_id_cat was drawn via
# _non_distance_category() excluding only group_cat — which let
# (subj_id_cat=PITCH, group_cat=COLOR) through, e.g. "The star that plays
# C#5 is one of the blue stars." — both sides purely observable (map +
# listened pitch), zero Name/Sequence content, same tautology class as the
# F5/E5 bug fixed earlier this session. test_clue_has_hidden_content.gd
# caught it immediately. Fixed by restricting the identifying side to
# NAME/SEQUENCE only — the two axes actually hidden from the player.
#
# MEASURED, and a diagnostic mistake caught along the way: a first
# coverage probe reported "301 of 316 names already pinned," which was
# WRONG — it counted "ordinal_exact" facts, a Sequence-rank bookkeeping
# kind that fires whenever ANY Form incidentally renders a Sequence
# characteristic, unrelated to NAME, and not even read by
# _solve_name_closure() (which only consumes name_group/name_group_neg).
# Redone against the RIGHT fact kinds:
#     exact Sequence pin (name_group, cat==SEQUENCE):      5 of 316  (2%)
#     colour/pitch group fact only (narrows, doesn't pin): 118 of 316 (37%)
#     NO closure-usable constraint at all:                 193 of 316 (61%)
# name_unique_closure is STILL 0/20 — fully explained by this, not a
# regression: 61% of names get literally nothing from the wired Forms, so
# there is no way the closure could reach uniqueness yet. Still 0/20
# CONTRADICTIONS across both slices — the engine remains sound throughout,
# it is coverage that is incomplete. Form 23 measurably moved the needle
# (0 -> 37% weakly covered) even though full closure is still far off.
#
# NEXT: Group Order (comparative colour/pitch-group facts) is the other
# mapped-but-unwired source; wiring it, or biasing Form 23's selection
# frequency upward, are the two obvious next levers — untested which
# matters more.
#
# ── Phase 2, first slice, 2026-08-16 (superseded numbers, kept for the
# process notes) — Exact Identity + Single Negation only:
#     name_unique_closure 0/20, under-constrained 20/20, contradictions 0/20
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
