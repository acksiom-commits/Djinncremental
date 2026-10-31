extends "res://dev_tests/test_base.gd"
# A player who only ever enters what is true never sees a contradiction.
#
# The detector and the engine's own conclusions now count a star's notes across
# all its entries (2026-10-31), and a check that fires more often has to be shown
# not to fire falsely. So: real Beginner puzzles, every star Listened, then the
# whole answer entered in a random order the way the player does: names on star
# popups, notes on name rows, pitches on Staff entries, and true X marks. After
# EVERY step there must be no contradiction, no merge-conflict dialog, no true
# name or position dropped from its row, and no true note ruled out.
#
# Control: one false mark on the same board must be flagged, so the silence
# above means something.
#
# Built on the real load path (set_puzzle_cache, show_for_constellation) so the
# puzzle's clues are live: the engine applies Hop facts to the board by itself.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const P = preload("res://constellation_logic_puzzle.gd")

const CASES := [[1, 11], [4, 11], [0, 5]]

var fails: int = 0
var conflicts: Array = []
var steps: int = 0
var faults: Array = []


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _truth_dropped(host, d) -> Array:
	var out: Array = []
	for v in host._star_count:
		for cat in [P.Category.NAME, P.Category.SEQUENCE]:
			if not d._stars_possible_for_descriptor(int(cat), int(v)).has(int(v)):
				out.append("%s (cat %d)" % [str(host._star_names[v]), int(cat)])
	return out


func _fresh_board(host, d) -> void:
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()
	for s2 in host._star_count:
		await host._on_pitch_listen_star_clicked(s2)


func _play(host, tag: String, order_seed: int) -> void:
	var d = host._deduction
	var w = host._widgets
	await _fresh_board(host, d)
	var rng := RandomNumberGenerator.new()
	rng.seed = order_seed
	var actions: Array = []
	for s in host._star_count:
		actions.append(["name", s])
		actions.append(["x_name_pitch", s])
	for t in range(1, d._melody_tick_count() + 1):
		actions.append(["note" if rng.randf() < 0.6 else "note_pitch", t])
		actions.append(["x_note_name", t])
		actions.append(["x_note_pitch", t])
	for i in range(actions.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var x = actions[i]
		actions[i] = actions[j]
		actions[j] = x
	var lbl := Label.new()
	var bc := Button.new()
	var bx := Button.new()
	host.add_child(lbl)
	host.add_child(bc)
	host.add_child(bx)
	for a in actions:
		var kind: String = str(a[0])
		var at: int = int(a[1])
		var owner: int = at if kind == "name" or kind == "x_name_pitch" else int(host._melody_star_sequence[at - 1])
		var nm: String = str(host._star_names[owner])
		var desc: String = "%s %d (%s)" % [kind, at, nm]
		match kind:
			"name":
				await w._on_name_check(at, nm, lbl, bc, bx)
			"note":
				var rec: int = d._get_or_create_match_record_for_name(nm)
				if d._repeat_note_state_for_record(rec, at) == 2:
					faults.append("%s: %s: a true note reads ruled out" % [tag, desc])
				await w._on_seq_note_select(rec, at)
			"note_pitch":
				var rt: int = d._get_or_create_match_record_for_melody_tick(at)
				d._propagate_pitch_confirmed_same_record(rt, w._note_name_for_star(owner))
				d._save_puzzle_notes()
				d._full_propagation_refresh()
			_:
				# A TRUE X: a name or pitch this entry really is not. Only on an
				# unmarked cell, since the handlers toggle.
				var other: int = rng.randi_range(0, host._star_count - 1)
				if other == owner:
					other = (other + 1) % host._star_count
				var rx: int = d._get_or_create_match_record_for_name(nm) if kind == "x_name_pitch" \
					else d._get_or_create_match_record_for_melody_tick(at)
				host._staff_popup_tick = 1 if kind == "x_name_pitch" else at
				if kind == "x_note_name":
					if int((d.record_at(rx).get("name_states", {}) as Dictionary).get(str(host._star_names[other]), 0)) == 0:
						w._on_staff_name_x(rx, str(host._star_names[other]), null)
				else:
					var wrong_note: String = w._note_name_for_star(other)
					if int((d.record_at(rx).get("pitch_states", {}) as Dictionary).get(wrong_note, 0)) == 0:
						w._on_staff_pitch_x(rx, wrong_note, null)
		steps += 1
		for c in d._contradictions:
			faults.append("%s after %s: %s" % [tag, desc, str((c as Dictionary).get("text", ""))])
		var drop: Array = _truth_dropped(host, d)
		if not drop.is_empty():
			faults.append("%s after %s: dropped %s" % [tag, desc, str(drop)])
		for cf in conflicts:
			faults.append("%s after %s: conflict dialog %s" % [tag, desc, str(cf)])
		conflicts.clear()
		if not faults.is_empty():
			break
	lbl.queue_free()
	bc.queue_free()
	bx.queue_free()


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._deduction._conflict_dialog_fn = func(what: String, a: String, b: String) -> String:
		conflicts.append("%s: %s vs %s" % [what, a, b])
		return "choice_a"
	var cd = load("res://constellation_data.gd").new()
	var gc = host._gc
	cd._game_context = gc
	host._cd = cd
	gc.ui_unlocks["kaleb_identity_revealed"] = true

	var plays: int = 0
	for case_ in CASES:
		var cid: int = int(case_[0])
		var seed: int = int(case_[1])
		gc.constellation_identity_revealed[cid] = true
		gc.constellation_difficulty[cid] = "easy"
		cd.player_seed = seed
		var def: Dictionary = cd.get_constellation_def(cid)
		var eng = load("res://click_sequence_puzzle_engine.gd").new()
		eng.set_constellation(cid, cd, gc)
		var sq: Array = eng.get_correct_star_sequence(cid)
		var g = P.new()
		g.difficulty = "easy"
		g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		await g.generate_clues_forms()
		ok(bool(g.gate_passed), "c%d seed %d: the puzzle passes the ship gate" % [cid, seed])
		cd.set_puzzle_cache(cid, g.to_cache_dict())
		host.show_for_constellation(cid)
		await process_frame
		for order in 2:
			await _play(host, "c%d seed %d order %d" % [cid, seed, order], seed * 31 + order)
			plays += 1

		if cid == CASES[0][0]:
			# Control, on this same board: two notes on a star that fires once
			# is impossible, and must be flagged by the same checks.
			print("\n=== control: false marks ===")
			var d = host._deduction
			await _fresh_board(host, d)
			var solo: int = host._repeat_count.find(0)
			var placed: int = 0
			for tick in range(1, d._melody_tick_count() + 1):
				if placed == 2 or int(host._melody_star_sequence[tick - 1]) == solo:
					continue
				var entry: int = d._get_or_create_match_record_for_melody_tick(tick)
				d._propagate_pitch_confirmed_same_record(entry, host._widgets._note_name_for_star(solo))
				d._save_puzzle_notes()
				d._full_propagation_refresh()
				placed += 1
			var flagged: Array = []
			for c2 in d._contradictions:
				flagged.append(str((c2 as Dictionary).get("text", "")))
			ok(placed == 2 and not flagged.is_empty(), "two notes on a once-firing star are flagged (%s)" % str(flagged))
			print("")

	print("  %d plays, %d correct steps, %d faults" % [plays, steps, faults.size()])
	for f in faults.slice(0, 10):
		print("    %s" % str(f))
	ok(plays == CASES.size() * 2 and steps > 300, "every play ran (%d plays, %d steps)" % [plays, steps])
	ok(faults.is_empty(), "correct play is never flagged, loses no truth and meets no conflict (%d faults)" % faults.size())

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
