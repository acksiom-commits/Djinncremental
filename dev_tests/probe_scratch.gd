extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path.
#
# IDLE. Deliberately asserts nothing.
#
# LEAVE IT GREEN when an investigation ends, and keep the `fails` counter
# even while idle. A standing failure makes the whole suite red, and a suite
# that is permanently red is one whose red stops meaning anything — which
# would quietly defeat test_matrix_up_lint.gd. Dropping the counter is the
# softer version of the same erosion: the runner then scores this module
# "unscored" and the summary stops reading ALL MODULES PASS. Open findings
# belong in a real test, or in the lint's KNOWN_UNTRIAGED entry, never here.
#
# Last investigation (2026-08-13) reproduced the live "impossible state"
# report. Both findings now have permanent tests:
#   * test_same_star_contradiction.gd — two VIEWS of one star were being
#     called impossible; only provably-distinct records are a real clash
#   * test_clue_has_hidden_content.gd — Form 12 could emit a clue whose
#     labels AND assertion were all map-readable

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
