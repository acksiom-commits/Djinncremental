extends RefCounted
# Test double for ConstellationData: just enough for
# ConstellationContentCertifier.report_builtin (a BUILT_IN list and a note
# assignment), so the report's sorting can be exercised on defs the test
# controls instead of only the real, mostly clean ones.

var BUILT_IN: Array = []
var assignments: Dictionary = {}   # id -> star -> note table


func get_note_assignment(id: int) -> Array:
	return assignments.get(id, [])


## report_builtin() calls this directly (not get_note_assignment) so it can
## certify a specific def variant (e.g. an easy_layout) without depending on
## live difficulty state -- see constellation_content_certifier.gd's own
## EASY_LAYOUT_ID_OFFSET comment. None of this stub's own fixture defs carry
## an "easy_layout", so `def` is unused here; keyed by id exactly like
## get_note_assignment, kept as a separate method only to match the real
## ConstellationData's interface.
func _note_assignment_for_def(_def: Dictionary, id: int) -> Array:
	return assignments.get(id, [])
