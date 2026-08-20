extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# IDLE. Last investigation (2026-08-18) verified that pruning does not
# remove opening anchors, after discovering the original check was VACUOUS
# — it ran on difficulty "hard", whose opening_anchors is [], so nothing
# was ever protected and "anchor losses: 0" proved nothing.
#
# That check is now a permanent test: dev_tests/test_prune_protects_anchors.gd
# (forces difficulty = "easy", the only profile with anchors, and asserts a
# non-zero anchor count BEFORE asserting none were lost).
#
# Findings worth keeping from that run, easy profile, 20 puzzles:
#     anchors built 96, lost 0
#     seq_unique 20/20, closures 20/20, contradictions 0
#     clues/puzzle median 53 (vs 37 on hard)
# Easy closes 20/20 even though it EXCLUDES Form 3 (Dual Negation), the
# Form that took closure from 1/20 to 20/20 on hard — real robustness
# evidence, and it refuted the prediction that easy would fail to close.
#
# REMINDER: run via the runner, never directly —
#     --script dev_tests/test_runner.gd -- probe_scratch
# This extends the RefCounted test base, not SceneTree; invoking the file
# directly exits 0 with no output.

var fails: int = 0


func run() -> void:
	print("  probe idle — nothing under investigation")
	print("ALL PASS (%d failures)" % fails)
	finish()
