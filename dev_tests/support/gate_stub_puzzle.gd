extends "res://constellation_logic_puzzle.gd"
# Test double: replaces the (expensive) clue-generation attempt with a scripted
# sequence of pass/fail results, so the retry loop and the refusal path can be
# tested without generating a real puzzle.

var scripted: Array = []   # one bool per attempt; past the end, repeats the last
var calls: int = 0


func _generate_clues_forms_attempt() -> Dictionary:
	var passes: bool = bool(scripted[mini(calls, scripted.size() - 1)])
	calls += 1
	return {
		"seq_unique": passes,
		"name_unique": passes,
		"name_unique_closure": passes,
		"seq_solutions_count": 1 if passes else 2,
		"name_solutions_count": 1 if passes else 2,
	}
