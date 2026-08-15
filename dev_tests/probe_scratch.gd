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
# Last investigation (2026-08-14) printed the rendered PITCH-axis clue
# sentences after _order_verb became "is pitched". Reading them — rather
# than reasoning about the code — is what exposed "is pitched before", a
# temporal word on a frequency axis that had been wrong since the
# Betweenness Form was written. Wording is one of the few things that
# cannot be verified by inspection.

var fails: int = 0


func run() -> void:
	print("  (idle — no investigation in progress)")
	print("ALL PASS (%d failures)" % fails)
	finish()
