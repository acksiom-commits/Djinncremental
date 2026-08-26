extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# COMPLETE PREFIX-SOLVE TRACE for c0, seed 4079140045, 31 clues -- the
# puzzle the user is working through by hand. Loads the EXACT cached
# puzzle from the save (not a regeneration), so there is zero drift risk.
#
# FIXED BUG from the first attempt: _solve(clues: Array[Dictionary], ...)
# is a TYPED parameter. Passing a plain `Array` crashed the coroutine
# silently (test_runner's "ABORTED partway" with no script-error text) --
# this was a typed-array mismatch, not a puzzle bug.
#
# For i = 1..31: accumulate ordinal_* facts (Sequence) and everything else
# (Name closure) from clues[0:i]. Report BOTH milestones exactly, plus, at
# the sequence-unique point, print the full firing order so it can be
# checked directly against the physical stars' colour/pitch.

const SEED := 4079140045
const CID := 0

var fails: int = 0


func run() -> void:
	var f := FileAccess.open("user://djinncremental_save.json", FileAccess.READ)
	if f == null:
		print("  no save file found")
		finish()
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var csec: Dictionary = (parsed as Dictionary)["constellation"]
	var cd = load("res://constellation_data.gd").new()
	cd.load_save_data(csec)
	var cached: Dictionary = csec["puzzle_cache"][str(CID)]

	var cdef: Dictionary = cd.get_constellation_def(CID)
	var scn: int = int(cdef["star_count"])
	var puz = load("res://constellation_logic_puzzle.gd").new()
	var sq: Array = []
	for i in range(scn):
		sq.append(i)
	puz.setup(scn, cdef["line_pairs"], sq, SEED, CID, cdef.get("name_theme", {}),
		cd.get_note_assignment(CID), cd.get_note_freqs(CID), null)
	if not puz.from_cache_dict(cached):
		print("  cache did not load")
		finish()
		return

	var clues: Array = puz.chosen_form_clues
	print("  %d clues loaded, %s\n" % [clues.size(), str(cdef.get("name", "?"))])

	var seq_facts: Array[Dictionary] = []
	var seq_locked_at: int = -1
	var name_locked_at: int = -1

	for i in clues.size():
		var c: Dictionary = clues[i]
		for d in (c.get("disclosures", []) as Array):
			if d is Dictionary and str((d as Dictionary).get("kind", "")).begins_with("ordinal_"):
				seq_facts.append(d as Dictionary)

		var seq_sols: Array = puz._solve(seq_facts, 2)
		if seq_sols.size() == 1 and seq_locked_at == -1:
			seq_locked_at = i + 1
			print("  >> SEQUENCE fully pinned at clue %d/%d: %s"
				% [i + 1, clues.size(), str(c.get("text", ""))])
			var sol: Array = seq_sols[0]
			var order: Array = []
			for s in scn:
				order.append(s)
			order.sort_custom(func(a, b): return int(sol[a]) < int(sol[b]))
			print("     firing order (star index : colour : pitch):")
			for s2 in order:
				print("       P%-2d  S%-2d  %-6s %s" % [int(sol[s2]) + 1, s2,
					str(puz.COLOR_NAMES[int(puz.star_colors[s2])]),
					str(puz.note_name_for_freq(puz._freq_for_star(s2)))])

		if seq_sols.size() == 1 and name_locked_at == -1:
			var saved: Array = puz.chosen_form_clues
			puz.chosen_form_clues = clues.slice(0, i + 1)
			var name_sols: Array = puz._solve_name_closure(seq_sols, 3)
			puz.chosen_form_clues = saved
			if name_sols.size() == 1:
				name_locked_at = i + 1
				print("\n  >> NAMES fully pinned at clue %d/%d: %s"
					% [i + 1, clues.size(), str(c.get("text", ""))])

	print("\n  Sequence locked at clue %d, Names locked at clue %d, of %d total."
		% [seq_locked_at, name_locked_at, clues.size()])
	if seq_locked_at == -1 or name_locked_at == -1:
		print("  !! never locked with the full clue set !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
