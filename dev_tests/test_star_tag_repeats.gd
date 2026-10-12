extends "res://dev_tests/test_base.gd"
# The Star Map's FOURTH per-star counter: the star's repeat count (2026-10-11),
# beside the existing Name, Sequence and Pitch.
#
#  - On a repeating melody every star's tag has four labels; the fourth reads
#    "R?" until the board has that star's repeat count, then "R<count>".
#  - It shows the BOARD's count (the player's mark), never the answer: a star
#    whose true count is 1 but which the player marked 0 reads "R0".
#  - The four labels sit in a square: Name over Sequence left of the star,
#    Pitch over Repeats right of it.
#  - On a 1:1 melody (hard mode) there is nothing to count: the fourth label is
#    empty and hidden, and Pitch keeps its old place centred on the star.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host(melody: Array):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = melody
	host._repeat_count = [1, 1, 0, 0]
	host._star_map_control.size = Vector2(600, 400)
	host._star_screen_pos = [Vector2(150, 100), Vector2(450, 100), Vector2(150, 300), Vector2(450, 300)]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _labels(host, star: int) -> Array:
	var out: Array = []
	for c in (host._star_tags[star] as Control).get_children():
		out.append(c)
	return out


func run() -> void:
	print("=== a repeating melody: four counters per star ===")
	var host = await _host([1, 2, 2, 3, 4, 1])
	var d = host._deduction
	var w = host._widgets
	w._build_star_tags_impl()
	ok(host._star_tags.size() == 4, "one tag per star (%d)" % host._star_tags.size())
	var four: bool = true
	var all_unknown: bool = true
	for s in 4:
		var ls: Array = _labels(host, s)
		if ls.size() != 4:
			four = false
		elif (ls[3] as Label).text != "R?" or not (ls[3] as Label).visible:
			all_unknown = false
	ok(four, "every tag has four labels: Name, Sequence, Pitch, Repeats")
	ok(all_unknown, "on an untouched board every Repeats counter reads 'R?' and is shown")

	print("\n=== it shows the board's count, not the answer ===")
	var beta: int = d._get_or_create_match_record_for_star_idx(1)
	d.record_at(beta)["name"] = "Beta"
	d.record_at(beta)["repeat_states"] = {1: 1, 0: 2, 2: 2}
	var gamma: int = d._get_or_create_match_record_for_star_idx(2)
	d.record_at(gamma)["name"] = "Gamma"
	d.record_at(gamma)["repeat_states"] = {1: 1, 0: 2}   # wrong on purpose: Gamma really never repeats
	d._full_propagation_refresh()
	w._build_star_tags_impl()
	ok((_labels(host, 1)[3] as Label).text == "R1", "Beta, marked 'repeats once', reads 'R1' (got '%s')" % (_labels(host, 1)[3] as Label).text)
	ok((_labels(host, 2)[3] as Label).text == "R1", "Gamma, marked 'repeats once' (wrongly), reads 'R1', the player's mark and not the answer 'R0' (got '%s')" % (_labels(host, 2)[3] as Label).text)
	ok((_labels(host, 0)[3] as Label).text == "R?" and (_labels(host, 3)[3] as Label).text == "R?", "stars with no mark still read 'R?'")

	print("\n=== the four labels sit in a square around the star ===")
	var ls1: Array = _labels(host, 1)
	var dot: Vector2 = host._star_screen_pos[1]
	var name_l: Label = ls1[0]
	var seq_l: Label = ls1[1]
	var pitch_l: Label = ls1[2]
	var rep_l: Label = ls1[3]
	ok(name_l.position.x + name_l.size.x <= dot.x and seq_l.position.x + seq_l.size.x <= dot.x, "Name and Sequence are left of the star")
	ok(pitch_l.position.x >= dot.x and rep_l.position.x >= dot.x, "Pitch and Repeats are right of it")
	ok(name_l.position.y < seq_l.position.y and pitch_l.position.y < rep_l.position.y, "Name is above Sequence, Pitch above Repeats")
	ok(not Rect2(pitch_l.position, pitch_l.size).intersects(Rect2(rep_l.position, rep_l.size)), "Pitch and Repeats do not overlap")
	host.queue_free()
	await process_frame

	# LISTEN GIVES THE COUNT (2026-10-11). True counts in this fixture: Alpha 1,
	# Beta 1, Gamma 0, Delta 0. Each star has its own pitch, so its Sort:Pitch
	# slot is that star's row.
	for order in ["slot opened AFTER Listen", "slot opened BEFORE Listen"]:
		print("\n=== Listen gives the repeat count: %s ===" % order)
		var hl = await _host([1, 2, 2, 3, 4, 1])
		var dl = hl._deduction
		var wl = hl._widgets
		var slot: int = -1
		if order == "slot opened BEFORE Listen":
			slot = dl._get_or_create_match_record_for_pitch_slot(493.88, 0)   # Beta's note
			ok(dl._effective_repeat_state(slot, 1) == 0, "before Listen the slot's Repeats entry is open")
		# A star the player has only NAMED gives nothing away.
		var named: int = dl._get_or_create_match_record_for_star_idx(0)
		dl.record_at(named)["name"] = "Alpha"
		dl._full_propagation_refresh()
		await hl._on_pitch_listen_star_clicked(1)
		wl._build_star_tags_impl()
		ok((_labels(hl, 1)[3] as Label).text == "R1", "the Listened star's tag reads its true count, 'R1' (got '%s')" % (_labels(hl, 1)[3] as Label).text)
		ok((_labels(hl, 0)[3] as Label).text == "R?", "a star only named, not Listened, still reads 'R?' (got '%s')" % (_labels(hl, 0)[3] as Label).text)
		ok((_labels(hl, 2)[3] as Label).text == "R?", "an untouched star still reads 'R?'")
		slot = dl._get_or_create_match_record_for_pitch_slot(493.88, 0)
		ok(dl._effective_repeat_state(slot, 1) == 1 and dl._effective_repeat_state(slot, 0) == 2,
			"the Sort:Pitch slot for that note has 'repeats once' confirmed and 'never' ruled out (states %d, %d)" % [
				dl._effective_repeat_state(slot, 1), dl._effective_repeat_state(slot, 0)])
		ok(wl._earned_repeat_for_record(slot) == "Repeats once", "its Repeats entry reads 'Repeats once' (got '%s')" % wl._earned_repeat_for_record(slot))
		var other: int = dl._get_or_create_match_record_for_pitch_slot(523.25, 0)   # Gamma's note, not Listened
		ok(wl._earned_repeat_for_record(other) == "" and dl._repeat_given_for_record(other) == -1, "another note's slot, not Listened, shows nothing")
		# The given count cannot be overwritten from the row.
		wl._repeat_toggle_confirm(slot, 0)
		wl._repeat_toggle_block(slot, 1)
		wl._on_repeat_checker_select(slot, 2)
		ok(dl._effective_repeat_state(slot, 1) == 1 and (dl.record_at(slot).get("repeat_states", {}) as Dictionary).is_empty(),
			"clicking other counts on that row changes nothing (raw marks %s)" % str(dl.record_at(slot).get("repeat_states", {})))
		var row: Control = wl._make_repeat_checker_row_for_record(slot)
		var all_locked: bool = true
		var value_buttons: int = 0
		for b in row.find_children("*", "Button", true, false):
			if (b as Button).text.is_valid_int():
				value_buttons += 1
				if not (b as Button).disabled:
					all_locked = false
		ok(value_buttons >= 2 and all_locked, "the row's count buttons are shown but locked (%d buttons)" % value_buttons)
		row.queue_free()
		hl.queue_free()
		await process_frame

	print("\n=== only the repeat counts that occur are offered ===")
	# Reported 2026-10-11 from a Phial puzzle whose stars repeat 0, 1 or 5 times:
	# the Repeats entries still offered '2' and '3'. Listen shows every star's
	# count, so a count no star has must not be a button on any surface.
	var hp = await _host([1, 2, 2, 3, 4, 1])
	hp._repeat_count = [1, 5, 0, 0]
	var dp = hp._deduction
	var wp = hp._widgets
	dp._load_match_records([])
	ok(dp._repeat_values_shown() == [0, 1, 5], "the shown counts are 0, 1 and 5 (got %s)" % str(dp._repeat_values_shown()))
	var prow_rec: int = dp._get_or_create_match_record_for_name("Alpha")
	var prow: Control = wp._make_repeat_checker_row_for_record(prow_rec)
	var offered: Array = []
	for b2 in prow.find_children("*", "Button", true, false):
		if (b2 as Button).text.is_valid_int():
			offered.append((b2 as Button).text)
	ok(offered == ["0", "1", "5"], "a Sort row's Repeats checks are 0, 1, 5 -- no 2 or 3 (got %s)" % str(offered))
	prow.queue_free()
	wp._open_staff_popup(1, Vector2.ZERO)
	var staff_rows: int = hp._staff_popup._repeat_columns[0].get_child_count() if hp._staff_popup._repeat_columns.size() > 0 else -1
	ok(staff_rows == 3, "the Staff popup's Repeats section has three rows (got %d)" % staff_rows)
	hp._staff_popup.hide()
	hp.queue_free()
	await process_frame

	print("\n=== a 1:1 melody has no Repeats counter and keeps the old layout ===")
	var flat = await _host([1, 2, 3, 4])
	flat._widgets._build_star_tags_impl()
	var lf: Array = _labels(flat, 1)
	ok(lf.size() == 4 and (lf[3] as Label).text == "" and not (lf[3] as Label).visible, "the fourth label is empty and hidden")
	var pf: Label = lf[2]
	var dotf: Vector2 = flat._star_screen_pos[1]
	ok(absf((pf.position.y + pf.size.y * 0.5) - dotf.y) < 1.0, "Pitch is still centred on the star's height (off by %.1f px)" % absf((pf.position.y + pf.size.y * 0.5) - dotf.y))
	flat.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
