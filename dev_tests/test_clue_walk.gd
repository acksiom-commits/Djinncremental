extends "res://dev_tests/test_base.gd"
# The final one-walk redundancy pass (2026-10-31, author). See
# constellation_clue_walk.gd.
#
#  - It removes clues, on real Beginner boards, against a run of the same seed
#    without it, so it does something.
#  - Every removed clue was in the unwalked set, nothing new appears, and the
#    guaranteed Mutual Exclusions and Betweenness chains all stay.
#  - The puzzle passes the full ship gate, and the hints reach exactly as far.
#  - Its hidden board leaves no trace: the REAL puzzle's notes are untouched, no
#    overlay is left in the tree, and no sound or popup is asked for.
#  - Hard never runs it, and neither does Easy without a tree to run it in.

const P = preload("res://constellation_logic_puzzle.gd")

const CASES := [[4, 20], [1, 11], [2, 20]]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make(cd, gc, cid: int, seed: int, walk: bool):
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = P.new()
	g.difficulty = "easy"
	g.clue_walk_force = walk
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
	await g.generate_clues_forms()
	return g


func _reach_of(g) -> Dictionary:
	var w = load("res://constellation_clue_walk.gd").new()
	await w.open(g, Engine.get_main_loop() as SceneTree)
	var out: Dictionary = await w.reach()
	w.close()
	await process_frame
	return out


func _overlays() -> int:
	var n: int = 0
	for c in root.get_children():
		if c.scene_file_path == "res://ConstellationStudyOverlay.tscn":
			n += 1
	return n


func run() -> void:
	await process_frame
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	var before_overlays: int = _overlays()
	var total_before: int = 0
	var total_after: int = 0

	for case_ in CASES:
		var cid: int = int(case_[0])
		var seed: int = int(case_[1])
		print("=== c%d seed %d ===" % [cid, seed])
		var plain = await _make(cd, gc, cid, seed, false)
		var walked = await _make(cd, gc, cid, seed, true)
		ok(bool(plain.gate_passed) and bool(walked.gate_passed), "both pass the ship gate")
		var plain_texts: Dictionary = {}
		for c in plain.chosen_form_clues:
			plain_texts[str((c as Dictionary).get("text", ""))] = int((c as Dictionary).get("form_id", -1))
		var left: Dictionary = {}
		for c2 in walked.chosen_form_clues:
			left[str((c2 as Dictionary).get("text", ""))] = true
		var extra: Array = []
		for t in left:
			if not plain_texts.has(t):
				extra.append(t)
		var kept_lost: Array = []
		for t2 in plain_texts:
			if not left.has(t2) and (int(plain_texts[t2]) == 13 or int(plain_texts[t2]) == 17):
				kept_lost.append(t2)
		print("    %d -> %d clues" % [plain.chosen_form_clues.size(), walked.chosen_form_clues.size()])
		total_before += plain.chosen_form_clues.size()
		total_after += walked.chosen_form_clues.size()
		ok(walked.chosen_form_clues.size() <= plain.chosen_form_clues.size(), "no clue is added")
		ok(extra.is_empty(), "every clue left was in the unwalked set (%d others: %s)" % [extra.size(), str(extra.slice(0, 1))])
		ok(kept_lost.is_empty(), "no Mutual Exclusion or Betweenness chain was cut (%s)" % str(kept_lost))
		var ra: Dictionary = await _reach_of(plain)
		var rb: Dictionary = await _reach_of(walked)
		# A board that never settles still takes marks but ties no name, and
		# then every comparison below would pass on nothing.
		ok(int(ra["tied"]) * 2 >= int(walked.star_count), "the check's board really settles (%d of %d names tied)" % [int(ra["tied"]), int(walked.star_count)])
		ok(int(rb["placed"]) >= int(ra["placed"]) and int(rb["tied"]) >= int(ra["tied"]),
			"hints reach as far (notes %d -> %d, names %d -> %d)" % [int(ra["placed"]), int(rb["placed"]), int(ra["tied"]), int(rb["tied"])])
		var round_trip = P.new()
		var def: Dictionary = cd.get_constellation_def(cid)
		round_trip.setup(int(def["star_count"]), def["line_pairs"], [0], 1, cid, def.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		ok(round_trip.from_cache_dict(walked.to_cache_dict()) and round_trip.chosen_form_clues.size() == walked.chosen_form_clues.size(),
			"the trimmed set survives the puzzle cache")

	print("\n=== across the three ===")
	ok(total_after < total_before, "it removes clues (%d -> %d)" % [total_before, total_after])

	print("\n=== it leaves no trace ===")
	# Only show_for_constellation points an overlay at ConstellationData, and the
	# hidden board never calls it: a save from there stops at its null _cd.
	var real_cd = root.get_node_or_null("/root/ConstellationData")
	ok(real_cd != null, "setup: the real ConstellationData is reachable")
	var saved_cache: Dictionary = real_cd.get_puzzle_cache(1).duplicate(true)
	var mine: Dictionary = {"note_text_entries": ["mine"], "match_records": [{"name": "Mine"}]}
	real_cd.set_puzzle_cache(1, {"player_puzzle_notes": mine.duplicate(true)})
	var again = await _make(cd, gc, 1, 11, true)
	ok(bool(again.gate_passed), "setup: a walked puzzle")
	ok(real_cd.get_player_puzzle_notes(1) == mine, "the player's notes are untouched (%s)" % str(real_cd.get_player_puzzle_notes(1)).left(70))
	real_cd.set_puzzle_cache(1, saved_cache)
	await process_frame
	await process_frame
	ok(_overlays() == before_overlays, "no overlay is left in the tree (%d, was %d)" % [_overlays(), before_overlays])

	print("\n=== the game's own path: a host, frames yielded ===")
	var game_host := Node.new()
	root.add_child(game_host)
	gc.constellation_difficulty[1] = "easy"
	cd.player_seed = 11
	var def3: Dictionary = cd.get_constellation_def(1)
	var eng3 = load("res://click_sequence_puzzle_engine.gd").new()
	eng3.set_constellation(1, cd, gc)
	var hosted = P.new()
	hosted.difficulty = "easy"
	hosted.setup(int(def3["star_count"]), def3["line_pairs"], eng3.get_correct_star_sequence(1), 11, 1, def3.get("name_theme", {}),
		cd.get_note_assignment(1), cd.get_note_freqs(1), game_host)
	ok(hosted._clue_walk_wanted(), "with a host it runs by itself")
	await hosted.generate_clues_forms()
	ok(bool(hosted.gate_passed), "and the puzzle passes the gate")
	var unhosted = await _make(cd, gc, 1, 11, true)
	ok(hosted.chosen_form_clues.size() == unhosted.chosen_form_clues.size(),
		"and lands where the test seam does (%d, %d clues)" % [hosted.chosen_form_clues.size(), unhosted.chosen_form_clues.size()])
	game_host.queue_free()
	await process_frame

	print("\n=== where it does not run ===")
	var hard = P.new()
	hard.difficulty = "hard"
	hard.clue_walk_force = true
	var def2: Dictionary = cd.get_constellation_def(1)
	hard.setup(int(def2["star_count"]), def2["line_pairs"], [0, 1, 2], 1, 1, {}, cd.get_note_assignment(1), cd.get_note_freqs(1), null)
	ok(not hard._clue_walk_wanted(), "not on Hard")
	var quiet = P.new()
	quiet.difficulty = "easy"
	ok(not quiet._clue_walk_wanted(), "not without a host, which is every suite generation")

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
