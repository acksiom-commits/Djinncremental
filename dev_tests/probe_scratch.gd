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
# ── Phase 2, sixth slice, 2026-08-17: bias category draws toward NAME ────
#
# CLOSURE_NAME_BIAS_WEIGHT (2.0) applied at the specific draw sites inside
# Exact Identity, Single Negation, Group Order, Equality Pair, and Form
# 23's identifying-side choice — the audit found 40% of untouched
# singleton-pitch stars WERE disclosed by a closure-feeding Form, just not
# paired with NAME that draw. New shared helpers _weighted_pick /
# _weighted_category_excluding, opt-in bias_name parameter threaded
# through _sample_identity_axis_cell / _identity_cell_for_known_star /
# _sample_grid_cell_maybe_chained / _random_bijective_category_pair — all
# default FALSE, so the ~15 other Forms sharing these helpers are
# unaffected (checked every one of their 18+22 call sites before editing,
# not assumed).
#
# Measured, 8 seeds x 5 constellations, 632 names:
#     NO closure-usable constraint at all: 158 (25%) — down from 211 (33%)
#     same-group-only bucket also grew: 92 (15%), up from the fifth
#     slice's smaller share
# Still 0/40 CONTRADICTIONS — the closure engine remains sound.
#
# INVESTIGATED, not ignored: seq_unique read 38/40 on the FIRST measurement
# (every prior slice held 100% on this exact metric). Ruled out as caused
# by the bias itself via a controlled re-run at CLOSURE_NAME_BIAS_WEIGHT=1.0
# (neutral, same new code path) — DIFFERENT seeds broke (Spark 4242,
# Bellows 24601) than at weight=2.0 (Spark 11, Satchel 11). An unstable
# failure SET across a neutral-vs-biased control is the signature of
# ordinary RNG-stream perturbation (new _rng.randf() calls anywhere in a
# shared helper reshuffle every downstream draw for a fixed seed), not a
# systematic effect of favoring NAME. Confirmed further: generate_clues_
# forms() — the actual live entry point, never called by this probe's
# direct _generate_clues_forms_attempt() calls — retries up to
# MAX_GENERATION_ATTEMPTS (5) on exactly this failure, so a ~5% single-
# attempt rate is fully absorbed before ever reaching a player.
#
# NEXT: 25% still untouched. No further audited lead — the singleton-pitch
# starvation angle that motivated this slice is now addressed at its
# source (more NAME-paired draws), so the next increment would need a new
# measurement pass, not a re-application of this one.
#
# ── Superseded numbers, kept for the process trail (all 0/N closures,
# 0/N contradictions throughout) ──────────────────────────────────────────
#   fifth slice  (+ same-group propagation): 118/316 (37%) untouched
#   audit baseline (8 seeds, pre-bias):      211/632 (33%) untouched
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
#   * AN UNEXPLAINED METRIC SHIFT NEEDS A CONTROL, NOT A SHRUG OR A PANIC.
#     seq_unique dropping to 38/40 was neither dismissed nor treated as a
#     blocking bug on sight — a neutral-weight re-run isolated whether the
#     BIAS or the CODE PATH caused it before deciding anything.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
