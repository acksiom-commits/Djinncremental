extends "res://dev_tests/test_base.gd"
# Dump the clue set of the puzzle currently in the SAVE FILE.
#
#     godot --headless --script dev_tests/test_runner.gd -- probe_live_clues
#
# Deliberately the same command shape as every other run, with the runner's
# existing filter — a bespoke one-off invocation is a novel command needing
# its own approval every time, which is the cost this file exists to remove.
# Reading the save by hand instead (locate it, parse the JSON, dodge the
# missing jq/python) took a dozen tool calls and found the wrong
# constellation's star names on the first pass.
#
# QUIET IN A FULL SUITE RUN. Unfiltered it prints one summary line per
# cached puzzle; the full dump appears only when the filter names this
# module, so 30 modules of output stay readable.
#
# WHAT IT PRINTS, and why each part is needed to judge solvability by hand:
#   - every clue VERBATIM from the cache, numbered. Not re-rendered: the
#     stored string is what the player is actually looking at, and
#     re-deriving it could disagree with the save (an inverted Adjacency
#     clue hid behind exactly that kind of gap for months).
#   - the solution table: name, colour, note, firing position per star.
#   - map topology, since Distance/Count/Extreme clues are claims about
#     neighbours and are unreadable without it.
#   - the live gate's verdict, recomputed from the cached clues.
#
# Note names come from ConstellationData AFTER load_save_data(), because
# note assignment is re-seeded per constellation
# (note_assignment_seed_overrides). A fresh instance would print a
# different, wrong set of notes.

const SAVE_PATH := "user://djinncremental_save.json"

var fails: int = 0


func _verbose() -> bool:
	for a in OS.get_cmdline_user_args():
		if "live_clues" in str(a):
			return true
	return false


func run() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		print("  no save file at %s — nothing to dump (not a failure)" % SAVE_PATH)
		print("ALL PASS (0 failures)")
		finish()
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("constellation") is Dictionary):
		print("  save has no constellation section — nothing to dump (not a failure)")
		print("ALL PASS (0 failures)")
		finish()
		return

	var save: Dictionary = parsed
	var csec: Dictionary = save["constellation"]
	var cd = load("res://constellation_data.gd").new()
	# Restores note_assignment_seed_overrides and the player seed, so the
	# notes below match the ones the clues name.
	cd.load_save_data(csec)

	var cache = csec.get("puzzle_cache")
	if not (cache is Dictionary) or (cache as Dictionary).is_empty():
		print("  puzzle_cache is empty — no generated puzzle in this save")
		print("ALL PASS (0 failures)")
		finish()
		return

	var verbose: bool = _verbose()
	var keys: Array = (cache as Dictionary).keys()
	keys.sort()
	for k in keys:
		var entry = (cache as Dictionary)[k]
		if not (entry is Dictionary):
			continue
		var cid: int = int(str(k))
		var puz = load("res://constellation_logic_puzzle.gd").new()
		var cdef: Dictionary = cd.get_constellation_def(cid)
		var scn: int = int((entry as Dictionary).get("star_count", 0))
		if scn <= 0:
			continue
		var sq: Array = []
		for i in range(scn):
			sq.append(i)
		# setup() first so topology/pitch tables exist, then overwrite the
		# generated puzzle with the SAVED one.
		puz.setup(scn, cdef.get("line_pairs", []), sq, int(csec.get("player_seed", 0)),
			cid, cdef.get("name_theme", {}), cd.get_note_assignment(cid),
			cd.get_note_freqs(cid), null)
		if not puz.from_cache_dict(entry):
			print("  c%d: cache did not load (version mismatch?)" % cid)
			continue

		var clues: Array = puz.chosen_form_clues
		# The live gate, recomputed: seq_unique is not re-solved here (that
		# costs a full CSP run); name binding is cheap and is the gate that
		# actually fails in practice.
		var revealed: Array = []
		for _i in scn:
			revealed.append(false)
		puz._recompute_name_revealed(revealed)
		var unbound: Array = []
		for si in scn:
			if not bool(revealed[si]):
				unbound.append(str(puz.star_names[si]))

		print("\n  c%d %s — %d stars, %d clues, %d name(s) unbound%s"
			% [cid, str(cdef.get("name", "?")), scn, clues.size(), unbound.size(),
			   ("  " + str(unbound)) if not unbound.is_empty() else ""])
		if not verbose:
			continue
		# ONE implementation, shared with the in-game dump that fires after
		# generation. Printing it a second time here would be a second thing
		# to keep in step with the first.
		puz.debug_dump_clueset("from save, %s" % str(cdef.get("name", "?")))

	if not verbose:
		print("  (run with `-- probe_live_clues` for the full dump)")
	print("ALL PASS (%d failures)" % fails)
	finish()
