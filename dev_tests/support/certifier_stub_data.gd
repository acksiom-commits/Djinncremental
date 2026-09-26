extends RefCounted
# Test double for ConstellationData: just enough for
# ConstellationContentCertifier.report_builtin (a BUILT_IN list and a note
# assignment), so the report's sorting can be exercised on defs the test
# controls instead of only the real, mostly clean ones.

var BUILT_IN: Array = []
var assignments: Dictionary = {}   # id -> star -> note table


func get_note_assignment(id: int) -> Array:
	return assignments.get(id, [])
