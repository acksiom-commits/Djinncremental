extends "res://dev_tests/test_base.gd"
# Authored-content certification (critical-pass review item 4).
#
# The runtime degrades gracefully on bad constellation content -- a dropped
# line endpoint, a star that never fires, a "Star-N" placeholder name -- which
# is the right policy for a live game and is UNCHANGED. It also means bad
# authoring never announces itself. constellation_content_certifier.gd turns
# each of those silent fallbacks into a named finding; this test makes them
# fail loudly in CI.
#
#   1. every BUILT_IN constellation is certified; there must be no
#      unexpected errors or warnings, and the reviewed allowlists must not
#      have rotted (a placeholder that now certifies clean, or a known
#      warning that no longer occurs, is itself a failure);
#   2. the certifier's melody simulation is checked against the REAL engine;
#   3. each kind of corruption is injected one at a time into a known-good
#      def and must be caught with the right code;
#   4. the position-observability condition holds for every authored
#      constellation across several player seeds.

const Certifier = preload("res://constellation_content_certifier.gd")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const EngineScript = preload("res://click_sequence_puzzle_engine.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _codes(findings: Array) -> Array:
	var out: Array = []
	for f in findings:
		out.append(str((f as Dictionary)["code"]))
	return out


## Corrupt a deep copy of `good`, certify it, and require `code` among the
## findings (and, first, that the untouched control is clean).
func _catches(good: Dictionary, assignment: Array, label: String, code: String, mutate: Callable) -> void:
	var bad: Dictionary = good.duplicate(true)
	mutate.call(bad)
	var codes: Array = _codes(Certifier.certify(bad, assignment))
	ok(codes.has(code), "%s is caught as '%s' (found: %s)" % [label, code, str(codes)])


func run() -> void:
	var cd = load("res://constellation_data.gd").new()

	print("=== every authored constellation, certified ===")
	var report: Dictionary = Certifier.report_builtin(cd)
	var by_id: Dictionary = {}
	for f in report["all"]:
		var fd: Dictionary = f
		var key: int = int(fd["id"])
		if not by_id.has(key):
			by_id[key] = []
		by_id[key].append("%s:%s" % [fd["severity"], fd["code"]])
	for def in cd.BUILT_IN:
		var id: int = int((def as Dictionary)["id"])
		print("    c%d %-14s %s" % [id, str((def as Dictionary).get("name", "?")), str(by_id.get(id, "clean"))])
	print("    %d constellation(s) certified; %d finding(s) in total" % [cd.BUILT_IN.size(), report["all"].size()])
	ok(cd.BUILT_IN.size() >= 7, "the real content was actually certified (%d defs) -- otherwise the checks below are vacuous" % cd.BUILT_IN.size())

	var unexpected: Array = []
	for e in report["errors"]:
		unexpected.append("c%d %s: %s" % [int((e as Dictionary)["id"]), (e as Dictionary)["code"], (e as Dictionary)["message"]])
	ok(report["errors"].is_empty(), "no unexpected content ERRORS on any non-placeholder constellation (%s)" % str(unexpected))
	var unexpected_w: Array = []
	for w in report["warnings"]:
		unexpected_w.append("c%d %s" % [int((w as Dictionary)["id"]), (w as Dictionary)["code"]])
	ok(report["warnings"].is_empty(), "no NEW warnings beyond the reviewed ones (%s)" % str(unexpected_w))
	ok(report["stale"].is_empty(), "the reviewed allowlists have not rotted (%s)" % str(report["stale"]))
	ok(not report["placeholders"].is_empty(),
		"the placeholder constellation's gaps are REPORTED, not hidden (%d finding(s) for %s)" % [report["placeholders"].size(), str(Certifier.PLACEHOLDERS.keys())])

	# A clean, real constellation to corrupt.
	var good: Dictionary = (cd.get_constellation_def(0) as Dictionary).duplicate(true)
	var good_assign: Array = cd.get_note_assignment(0)
	ok(Certifier.certify(good, good_assign).is_empty(), "control: constellation 0 certifies with NO findings")

	print("\n=== the melody simulation matches the real engine ===")
	var diffs: int = 0
	var compared: int = 0
	for def in cd.BUILT_IN:
		var d2: Dictionary = def
		var id2: int = int(d2["id"])
		var assign2: Array = cd.get_note_assignment(id2)
		var engine = EngineScript.new()
		engine.cd = cd
		var real: Array = engine._compute_correct_star_sequence(id2, assign2)
		var mine: Array = Certifier.correct_star_sequence(d2.get("puzzle_sequence", []), assign2)
		compared += 1
		if real != mine:
			diffs += 1
			print("    DIFF c%d: engine %s vs certifier %s" % [id2, str(real), str(mine)])
	ok(compared >= 7 and diffs == 0,
		"the certifier's correct-star-sequence equals the engine's on every constellation (%d compared, %d differ)" % [compared, diffs])

	print("\n=== each corruption is caught ===")
	var n: int = int(good["star_count"])
	_catches(good, good_assign, "star_count 1", "star_count_range", func(d): d["star_count"] = 1)
	_catches(good, good_assign, "star_count 500", "star_count_range", func(d): d["star_count"] = 500)
	_catches(good, good_assign, "no line_pairs", "no_lines", func(d): d.erase("line_pairs"))
	_catches(good, good_assign, "an odd-length line_pairs", "line_pairs_odd", func(d): d["line_pairs"].append(3))
	_catches(good, good_assign, "a line endpoint past the last star", "line_pairs_bounds", func(d): d["line_pairs"][0] = n + 2)
	_catches(good, good_assign, "a negative line endpoint", "line_pairs_bounds", func(d): d["line_pairs"][1] = -1)
	_catches(good, good_assign, "a self-loop", "line_pairs_self_loop", func(d): d["line_pairs"][1] = d["line_pairs"][0])
	_catches(good, good_assign, "a duplicated line (reversed)", "line_pairs_duplicate", func(d):
		d["line_pairs"].append(d["line_pairs"][1])
		d["line_pairs"].append(d["line_pairs"][0]))
	_catches(good, good_assign, "an isolated star", "isolated_star", func(d):
		d["star_count"] = n + 1
		d["fixed_star_positions"].append([0.0, 0.0, 1.0]))
	_catches(good, good_assign, "no note_freqs", "note_freqs_empty", func(d): d["note_freqs"] = [])
	_catches(good, good_assign, "a negative frequency", "note_freqs_invalid", func(d): d["note_freqs"][0] = -5.0)
	_catches(good, good_assign, "an inaudible frequency", "note_freqs_invalid", func(d): d["note_freqs"][0] = 900000.0)
	_catches(good, good_assign, "a non-numeric frequency", "note_freqs_invalid", func(d): d["note_freqs"][0] = "loud")
	_catches(good, good_assign, "two pitch indices that are the same note", "note_names_duplicate", func(d): d["note_freqs"][1] = d["note_freqs"][0])
	_catches(good, good_assign, "two pitch indices a hair apart (same note name)", "note_names_duplicate", func(d): d["note_freqs"][1] = d["note_freqs"][0] * 1.002)
	_catches(good, good_assign, "no melody", "melody_empty", func(d): d["puzzle_sequence"] = [])
	_catches(good, good_assign, "a melody note past the last pitch", "melody_note_range", func(d): d["puzzle_sequence"][0] = 99)
	_catches(good, good_assign, "a negative melody note", "melody_note_range", func(d): d["puzzle_sequence"][0] = -2)
	# A note no star is assigned: keep the melody, drop every star's copy of it.
	var target_note: int = int(good["puzzle_sequence"][0])
	var starved: Array = []
	for note in good_assign:
		starved.append(int(note) if int(note) != target_note else (target_note + 1) % 10)
	var codes_unplayed: Array = _codes(Certifier.certify(good, starved))
	ok(codes_unplayed.has("melody_note_unplayed"),
		"a melody note that NO star plays is caught as 'melody_note_unplayed' (found: %s)" % str(codes_unplayed))
	# A star that never fires: a melody shorter than the star count.
	_catches(good, good_assign, "a melody too short to reach every star", "star_never_fires", func(d):
		d["puzzle_sequence"] = (d["puzzle_sequence"] as Array).slice(0, 5))
	_catches(good, good_assign, "missing star positions", "positions_missing", func(d): d.erase("fixed_star_positions"))
	_catches(good, good_assign, "the wrong number of star positions", "positions_count", func(d): d["fixed_star_positions"].pop_back())
	_catches(good, good_assign, "a malformed star position", "positions_malformed", func(d): d["fixed_star_positions"][0] = [1.0, 0.0])
	_catches(good, good_assign, "a star position off the unit sphere", "positions_off_sphere", func(d): d["fixed_star_positions"][0] = [5.0, 0.0, 0.0])
	# A theme too small for the star count: 1 prefix x 1 mid x 1 suffix = 1 name.
	_catches(good, good_assign, "a name theme too small for the stars", "names_fallback", func(d):
		d["name_theme"] = {"prefixes": ["A"], "mids": ["b"], "suffixes": ["c"]})

	print("\n=== the report sorts findings into errors / placeholders / warnings / stale ===")
	const StubScript = preload("res://dev_tests/support/certifier_stub_data.gd")
	var stub = StubScript.new()
	var clean_def: Dictionary = good.duplicate(true)
	var no_lines_def: Dictionary = good.duplicate(true)
	no_lines_def.erase("line_pairs")
	var isolated_def: Dictionary = good.duplicate(true)
	isolated_def["star_count"] = n + 1
	isolated_def["fixed_star_positions"].append([0.0, 0.0, 1.0])
	# Give the isolated star a note and a place in the melody so ONLY the
	# isolated_star warning fires, not star_never_fires as well.
	var isolated_assign: Array = good_assign.duplicate()
	isolated_assign.append(int(good["puzzle_sequence"][0]))
	isolated_def["puzzle_sequence"] = (isolated_def["puzzle_sequence"] as Array).duplicate()
	isolated_def["puzzle_sequence"].append(int(good["puzzle_sequence"][0]))
	var unexpected_broken: Dictionary = no_lines_def.duplicate(true)
	unexpected_broken["id"] = 91
	var placeholder_broken: Dictionary = no_lines_def.duplicate(true)
	placeholder_broken["id"] = 6
	var isolated_case: Dictionary = isolated_def.duplicate(true)
	isolated_case["id"] = 92
	var clean_case: Dictionary = clean_def.duplicate(true)
	clean_case["id"] = 90
	stub.BUILT_IN = [clean_case, unexpected_broken, placeholder_broken, isolated_case]
	for d in stub.BUILT_IN:
		stub.assignments[int((d as Dictionary)["id"])] = isolated_assign if int((d as Dictionary)["id"]) == 92 else good_assign
	var rep: Dictionary = Certifier.report_builtin(stub)
	var err_ids: Array = []
	for e in rep["errors"]:
		err_ids.append(int((e as Dictionary)["id"]))
	var ph_ids: Array = []
	for p in rep["placeholders"]:
		ph_ids.append(int((p as Dictionary)["id"]))
	var warn_ids: Array = []
	for w in rep["warnings"]:
		warn_ids.append(int((w as Dictionary)["id"]))
	ok(err_ids.has(91) and not err_ids.has(6) and not err_ids.has(90),
		"a broken NON-placeholder is an unexpected error, the clean one and the placeholder are not (errors from: %s)" % str(err_ids))
	ok(ph_ids.has(6) and not ph_ids.has(91), "a broken PLACEHOLDER is reported as a placeholder gap, not an error (%s)" % str(ph_ids))
	ok(warn_ids.has(92), "an UNREVIEWED warning is surfaced (%s)" % str(warn_ids))
	var stale_text: String = str(rep["stale"])
	ok(stale_text.contains("3:isolated_star"),
		"a known warning that no longer occurs is flagged stale, so the allowlist cannot rot (%s)" % stale_text)
	# A placeholder that now certifies clean must be flagged for removal.
	var healed: Dictionary = clean_def.duplicate(true)
	healed["id"] = 6
	stub.BUILT_IN = [healed]
	stub.assignments = {6: good_assign}
	var rep2: Dictionary = Certifier.report_builtin(stub)
	ok(str(rep2["stale"]).contains("placeholder 6 now certifies clean"),
		"a placeholder that has been authored and now certifies clean is flagged for removal from PLACEHOLDERS (%s)" % str(rep2["stale"]))

	print("\n=== position observability holds for every authored constellation ===")
	var checked: int = 0
	var failed_sep: Array = []
	for def in cd.BUILT_IN:
		var d3: Dictionary = def
		var id3: int = int(d3["id"])
		if Certifier.PLACEHOLDERS.has(id3):
			continue
		var scn: int = int(d3["star_count"])
		var sq: Array = []
		for i in range(scn):
			sq.append(i)
		for seed in [11, 12, 13, 14, 15, 16]:
			var g = PuzzleScript.new()
			g.setup(scn, d3["line_pairs"], sq, seed, id3, d3.get("name_theme", {}),
				cd.get_note_assignment(id3), cd.get_note_freqs(id3), null)
			checked += 1
			if bool(g._color_separation_failed) or not g._observables_separate_every_position():
				failed_sep.append("c%d seed %d" % [id3, seed])
	print("    %d (constellation, seed) setups checked" % checked)
	ok(checked >= 30, "enough setups were checked (%d) -- otherwise 'none failed' proves nothing" % checked)
	ok(failed_sep.is_empty(), "every position is distinguishable by colour/pitch/hop pattern in all of them (failures: %s)" % str(failed_sep))

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
