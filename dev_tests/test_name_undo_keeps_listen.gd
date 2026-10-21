extends "res://dev_tests/test_base.gd"
# The star widget's Name "Undo ✓" / "Undo all" on a LISTENED star (reported
# 2026-10-20 on the Phial: every star Listened, but the A5 star's tag read
# "R?"). Both buttons unbound whatever record sat on the star, and a Listened
# record's binding is the Listen click itself. The Listen was left on a record
# with no star, colour wiped, and the Repeats counter (which only counts a
# Listen still bound to its star) fell back to "R?".
#
# Now, on a Listened record, the undo takes the NAME off and leaves the
# binding, colour and Listen. A star that was only named, never Listened,
# still unbinds exactly as before.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


# Same fixture as test_star_tag_repeats.gd. True counts: Alpha 1, Beta 1,
# Gamma 0, Delta 0; Alpha's colour is index 0.
func _host():
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
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._repeat_count = [1, 1, 0, 0]
	host._star_map_control.size = Vector2(600, 400)
	host._star_screen_pos = [Vector2(150, 100), Vector2(450, 100), Vector2(150, 300), Vector2(450, 300)]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _tag(host, star: int) -> Array:
	host._widgets._build_star_tags_impl()
	var out: Array = []
	for c in (host._star_tags[star] as Control).get_children():
		out.append((c as Label).text)
	return out


func _own_colour(host) -> Dictionary:
	var d = host._deduction
	var rec: int = d._find_match_record_by_star_idx(0)
	return (d.record_at(rec).get("color_states", {}) as Dictionary).duplicate() if rec >= 0 else {}


func _name_alpha(host) -> void:
	var d = host._deduction
	var rec: int = d._get_or_create_match_record_for_name("Alpha")
	await d._confirm_match_record_identity(rec, 0, "Alpha")
	d._full_propagation_refresh()


# Everything the Listen gave must survive: still bound, colour still there,
# pitch and repeat count still on the tag.
func _check_listen_intact(host, label: String, colour_before: Dictionary) -> void:
	var d = host._deduction
	var rec: int = d._find_match_record_by_star_idx(0)
	var r: Dictionary = d.record_at(rec) if rec >= 0 else {}
	ok(rec >= 0 and int(r.get("star_idx", -1)) == 0 and bool(r.get("pitch_revealed", false)),
		"%s: the Listened record is still bound to its star (star_idx %d)" % [label, int(r.get("star_idx", -1))])
	ok(rec >= 0 and d._effective_color_state(rec, 0) == 1, "%s: the star's colour still reads as known" % label)
	ok(str(r.get("color_states", {})) == str(colour_before),
		"%s: the record's own colour marks are untouched (%s -> %s)" % [label, str(colour_before), str(r.get("color_states", {}))])
	var unbound_listens := 0
	for i in d.record_count():
		var o: Dictionary = d.record_at(i)
		if bool(o.get("pitch_revealed", false)) and int(o.get("star_idx", -1)) < 0:
			unbound_listens += 1
	ok(unbound_listens == 0, "%s: no Listen left on a record with no star (%d)" % [label, unbound_listens])
	var t: Array = _tag(host, 0)
	ok(t[2] == "A4" and t[3] == "R1", "%s: the tag still shows the pitch and count (got %s)" % [label, str(t)])


func run() -> void:
	print("=== Listened, never named: Undo ✓ changes nothing ===")
	var h1 = await _host()
	await h1._on_pitch_listen_star_clicked(0)
	h1._deduction._full_propagation_refresh()
	ok(_tag(h1, 0)[3] == "R1", "setup: after Listen the tag reads R1")
	var c1: Dictionary = _own_colour(h1)
	h1._widgets._on_undo_name_selects(0)
	_check_listen_intact(h1, "Undo ✓", c1)
	h1.queue_free()
	await process_frame

	print("\n=== Listened and named: Undo ✓ takes the name, keeps the Listen ===")
	var h2 = await _host()
	await h2._on_pitch_listen_star_clicked(0)
	await _name_alpha(h2)
	var d2 = h2._deduction
	ok(d2._star_elim_state(0, "Alpha") == 1, "setup: Alpha is confirmed on the star")
	var c2: Dictionary = _own_colour(h2)
	h2._widgets._on_undo_name_selects(0)
	ok(d2._star_elim_state(0, "Alpha") != 1, "Alpha is no longer confirmed on the star (state %d)" % d2._star_elim_state(0, "Alpha"))
	ok(d2._star_elim_state(1, "Alpha") == 0, "and is not left ruled out on another star (state %d)" % d2._star_elim_state(1, "Alpha"))
	_check_listen_intact(h2, "Undo ✓", c2)
	h2.queue_free()
	await process_frame

	print("\n=== Listened and named: Undo all takes the name, keeps the Listen ===")
	var h3 = await _host()
	await h3._on_pitch_listen_star_clicked(0)
	await _name_alpha(h3)
	var c3: Dictionary = _own_colour(h3)
	h3._widgets._on_undo_name_all(0)
	ok(h3._deduction._star_elim_state(0, "Alpha") != 1, "Alpha is no longer confirmed on the star")
	_check_listen_intact(h3, "Undo all", c3)
	h3.queue_free()
	await process_frame

	print("\n=== named but never Listened: Undo ✓ still unbinds, as before ===")
	var h4 = await _host()
	await _name_alpha(h4)
	var d4 = h4._deduction
	var named: int = d4._find_match_record_by_name("Alpha")
	ok(named >= 0 and int(d4.record_at(named)["star_idx"]) == 0, "setup: Alpha's record is bound to star 0")
	h4._widgets._on_undo_name_selects(0)
	named = d4._find_match_record_by_name("Alpha")
	ok(named >= 0 and int(d4.record_at(named)["star_idx"]) == -1, "Alpha's record is unbound, unchanged behaviour")
	h4.queue_free()
	await process_frame

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
