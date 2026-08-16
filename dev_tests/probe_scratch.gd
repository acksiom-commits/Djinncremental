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
# Last investigation (2026-08-14) was the ZebraTutor Stage 0 probe: compare
# the generator's own solvability verdict against what the player-side
# engine can reach. It found that the generator calls puzzles fully
# derivable that have TWO solutions, on 3 of 5 Archon seeds. Its findings
# live in test_constellation_topology.gd and in the memory note; the
# oracle itself is not built.
#
# Two process notes from it, both of which cost a wrong conclusion:
#   * a SUMMARY STATISTIC hid the truth. "0 hop-distance differences" was
#     true and the inference drawn from it was wrong — the raw vectors
#     showed 12 of 15 entries were -1 (unreachable), not a symmetry.
#     Print the data, not the score.
#   * a probe can corrupt what it measures. Entering colour cells made the
#     result go DOWN with more true information, which is impossible for a
#     monotone engine — that impossibility was the only signal the probe
#     itself was at fault.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
