extends "res://dev_tests/test_base.gd"
# Sort:tab Sequence entry, checker version (2026-10-07): one on/off button per
# position instead of the typed lo < list < hi boxes. What must hold:
#
#  - the row has one button per position, labelled with its first staff note;
#  - turning a position OFF removes it from the record's effective candidates,
#    turning it back ON restores it, and restoring everything clears the
#    record's Sequence info entirely (no explicit all-positions list left);
#  - narrowing down to one position is an exact pin, same as typing it;
#  - the last remaining position cannot be turned off (an empty set is a
#    contradiction, not information);
#  - the checker row is NOT wider than the typed row it replaces (its scroll
#    area has a small minimum and fills whatever the row is given).
#
# Like the other overlay-scene modules, verify through the FULL suite.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25]
	host._star_pitch_index = [0, 1, 2, 0, 1, 2]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	host._repeat_count = [0, 0, 1, 1, 2, -1]
	return host


func _strip_buttons(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is ScrollContainer:
			for b in c.get_child(0).get_children():
				out.append(b)
	return out


func run() -> void:
	await process_frame
	var host = await _make_host()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	var rec: int = d._get_or_create_match_record_for_name("Pyrios")

	# Typed row first, for the width comparison.
	w._seq_checker_loaded = true
	w._seq_checker_mode = false
	var typed_row: Control = w._make_sequence_range_row_for_record(rec, Color.WHITE)
	var typed_w: float = typed_row.get_combined_minimum_size().x
	typed_row.free()

	w._seq_checker_mode = true
	var row: Control = w._make_sequence_range_row_for_record(rec, Color.WHITE)
	host.add_child(row)
	var btns: Array = _strip_buttons(row)

	print("=== one button per position ===")
	ok(btns.size() == 6, "six buttons for six stars (got %d)" % btns.size())
	ok(btns.size() == 6 and (btns[0] as Button).text == "1" and (btns[5] as Button).text == "6",
		"labelled with the first staff note")

	print("\n=== width does not grow ===")
	var checker_w: float = row.get_combined_minimum_size().x
	ok(checker_w <= typed_w, "checker row min width %.0f <= typed row %.0f" % [checker_w, typed_w])

	print("\n=== off / on / all-restored ===")
	var lo_e := LineEdit.new()
	var mid_e := LineEdit.new()
	var hi_e := LineEdit.new()
	host.add_child(lo_e)
	host.add_child(mid_e)
	host.add_child(hi_e)
	ok(d._effective_seq_candidates(rec).size() == 6, "precondition: all six open")
	w._on_seq_checker_toggle(rec, 3, lo_e, mid_e, hi_e)
	await process_frame
	var eff: Array = d._effective_seq_candidates(rec)
	ok(eff.size() == 5 and not eff.has(3), "turning 3 off leaves the other five (got %s)" % str(eff))
	w._on_seq_checker_toggle(rec, 3, lo_e, mid_e, hi_e)
	await process_frame
	ok(d._effective_seq_candidates(rec).size() == 6, "turning 3 back on restores all six")
	var r: Dictionary = d.record_at(rec)
	ok((r.get("seq_candidates", []) as Array).is_empty() and int(r.get("seq_lo", 0)) == 0 and int(r.get("seq_hi", 0)) == 0,
		"and leaves no explicit all-positions list behind")

	print("\n=== down to one is an exact pin ===")
	for p in [1, 2, 3, 4, 5]:
		w._on_seq_checker_toggle(rec, p, lo_e, mid_e, hi_e)
		await process_frame
	r = d.record_at(d._get_or_create_match_record_for_name("Pyrios"))
	var eff2: Array = d._effective_seq_candidates(d._get_or_create_match_record_for_name("Pyrios"))
	ok(eff2 == [6], "only position 6 is left (got %s)" % str(eff2))
	ok(int(r.get("seq_lo", 0)) == 6 and int(r.get("seq_hi", 0)) == 6, "stored as an exact pin, as if 6 had been typed")

	print("\n=== the last position cannot be turned off ===")
	var prec: int = d._get_or_create_match_record_for_name("Pyrios")
	w._on_seq_checker_toggle(prec, 6, lo_e, mid_e, hi_e)
	await process_frame
	ok(d._effective_seq_candidates(prec) == [6], "still pinned to 6")

	# 2026-10-12: EVERY note is on the row (author ruling, "Put them on it").
	# History: before 2026-10-10 the row had one button per note with a star's
	# notes LINKED, which gave the repeats away; from 2026-10-10 repeat notes
	# had no button. Now each note has its own button and nothing links them:
	# a first note is the pick-one position, a repeat note is "fires here
	# again or not", marked note by note.
	#
	# SEAM ONLY since later on 2026-10-12: which notes are first firings is no
	# longer shown to the player, so the game does not behave like this any
	# more. These two sections run with notes_hidden_enabled = false and pin
	# the older behaviour that seam keeps; the game's own behaviour is the
	# "first notes hidden" section after them.
	print("\n=== (seam: first notes shown) repeating melody: one button per note ===")
	var host2 = await _make_host()
	var d2 = host2._deduction
	var w2 = host2._widgets
	d2.notes_hidden_enabled = false
	host2._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]   # 8 notes, 6 stars
	d2._load_match_records([])
	var rec2: int = d2._get_or_create_match_record_for_name("Pyrios")
	w2._seq_checker_loaded = true
	w2._seq_checker_mode = true
	var row2: Control = w2._make_sequence_range_row_for_record(rec2, Color.WHITE)
	host2.add_child(row2)
	var b2: Array = _strip_buttons(row2)
	ok(b2.size() == 8, "eight buttons for eight notes (got %d)" % b2.size())
	var labels: Array = []
	for b in b2:
		labels.append((b as Button).text)
	ok(labels == ["1", "2", "3", "4", "5", "6", "7", "8"], "labelled with the notes in order (got %s)" % str(labels))
	var same_look: bool = true
	for b in b2:
		if (b as Button).modulate != (b2[0] as Button).modulate or (b as Button).disabled:
			same_look = false
	ok(same_look, "on an open row first notes and repeat notes look alike")
	var lo2 := LineEdit.new()
	var mid2 := LineEdit.new()
	var hi2 := LineEdit.new()
	host2.add_child(lo2)
	host2.add_child(mid2)
	host2.add_child(hi2)
	ok(d2._seq_pos_for_melody_tick(4) == 0 and d2._seq_pos_for_melody_tick(7) == 0,
		"the board has no position for repeat notes 4 and 7 (got %d, %d)" % [d2._seq_pos_for_melody_tick(4), d2._seq_pos_for_melody_tick(7)])
	# The button labelled 5 is the 4th star to fire: ruling it out removes rank 4 only.
	w2._on_seq_checker_toggle(rec2, d2._seq_pos_for_melody_tick(5), lo2, mid2, hi2)
	await process_frame
	var eff3: Array = d2._effective_seq_candidates(rec2)
	ok(eff3 == [1, 2, 3, 5, 6], "ruling out note 5 turns the 4th star off, leaving five (got %s)" % str(eff3))
	row2.free()
	row2 = w2._make_sequence_range_row_for_record(rec2, Color.WHITE)
	host2.add_child(row2)
	b2 = _strip_buttons(row2)
	var off_look: Color = (b2[4] as Button).modulate
	var only_one_off: bool = true
	for bi in b2.size():
		if bi != 4 and (b2[bi] as Button).modulate == off_look:
			only_one_off = false
	ok((b2[4] as Button).text == "5" and only_one_off, "only the note-5 button has the off look; no other note went with it")

	print("\n=== a repeat note: fires here again, or not, note by note ===")
	# Notes 4 and 7 are repeat notes. Nothing below reads which star they are.
	ok(d2._repeat_note_state_for_record(rec2, 4) == 0 and d2._repeat_note_state_for_record(rec2, 7) == 0,
		"both repeat notes start open on Pyrios's row")
	w2._on_seq_note_toggle(rec2, 4)
	ok(d2._repeat_note_state_for_record(rec2, 4) == 3, "right-click on note 4: ruled out by the player's own mark")
	ok(d2._effective_seq_candidates(rec2) == [1, 2, 3, 5, 6], "which changes nothing about Pyrios's position (got %s)" % str(d2._effective_seq_candidates(rec2)))
	row2.free()
	row2 = w2._make_sequence_range_row_for_record(rec2, Color.WHITE)
	host2.add_child(row2)
	b2 = _strip_buttons(row2)
	ok((b2[3] as Button).text == "4" and (b2[3] as Button).modulate == off_look and not (b2[3] as Button).disabled,
		"its button has the off look and can be clicked back")
	w2._on_seq_note_toggle(rec2, 4)
	ok(d2._repeat_note_state_for_record(rec2, 4) == 0, "right-click again restores it")

	await w2._on_seq_note_select(rec2, 4)
	rec2 = d2._get_or_create_match_record_for_name("Pyrios")
	ok(d2._repeat_note_state_for_record(rec2, 4) == 1, "left-click on note 4: Pyrios fires there again")
	ok(d2._find_match_record_by_melody_tick(4) == rec2, "the note now belongs to Pyrios's record")
	ok(d2._effective_seq_candidates(rec2) == [1, 2, 3],
		"so Pyrios first fired before note 4: positions 1 to 3 only (got %s)" % str(d2._effective_seq_candidates(rec2)))
	ok(d2._repeat_note_state_for_record(rec2, 7) == 0, "note 7 is untouched: a star may hold several repeat notes")
	var helios: int = d2._get_or_create_match_record_for_name("Helios")
	ok(d2._repeat_note_state_for_record(helios, 4) == 2, "on Helios's row note 4 is ruled out by deduction: it is Pyrios's")
	rec2 = d2._get_or_create_match_record_for_name("Pyrios")
	await w2._on_seq_note_select(rec2, 7)
	rec2 = d2._get_or_create_match_record_for_name("Pyrios")
	ok(d2._repeat_note_state_for_record(rec2, 4) == 1 and d2._repeat_note_state_for_record(rec2, 7) == 1,
		"notes 4 and 7 can both be confirmed on the one row")
	await w2._on_seq_note_select(rec2, 7)
	rec2 = d2._get_or_create_match_record_for_name("Pyrios")
	ok(d2._repeat_note_state_for_record(rec2, 7) == 0 and d2._repeat_note_state_for_record(rec2, 4) == 1,
		"left-click on a confirmed note lets that one note go and no other")
	await w2._on_seq_note_select(rec2, 4)
	rec2 = d2._get_or_create_match_record_for_name("Pyrios")
	ok(d2._repeat_note_state_for_record(rec2, 4) == 0 and d2._effective_seq_candidates(rec2) == [1, 2, 3, 5, 6],
		"letting note 4 go reopens Pyrios's positions (got %s)" % str(d2._effective_seq_candidates(rec2)))

	print("\n=== what rules a repeat note out ===")
	# Reported 2026-10-12: ruling out note 1 on a row silently removed note 2
	# too, because note 2 is a repeat note and only note 1's star could be
	# it -- a fact the player is not shown. A row's position marks must not
	# remove a repeat note nobody has opened or placed.
	var hostz = await _make_host()
	var dz = hostz._deduction
	var wz = hostz._widgets
	dz.notes_hidden_enabled = false
	hostz._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]
	dz._load_match_records([])
	var zeta: int = dz._get_or_create_match_record_for_name("Zeta")
	var loz := LineEdit.new()
	var midz := LineEdit.new()
	var hiz := LineEdit.new()
	for ez in [loz, midz, hiz]:
		hostz.add_child(ez)
	wz._on_seq_checker_select(zeta, 6, loz, midz, hiz)   # position 6 first fires on note 8
	await process_frame
	zeta = dz._get_or_create_match_record_for_name("Zeta")
	ok(dz._effective_seq_candidates(zeta) == [6], "precondition: Zeta is pinned to the star that first fires on note 8")
	ok(dz._find_match_record_by_melody_tick(4) < 0, "precondition: nobody has opened note 4")
	ok(dz._repeat_note_state_for_record(zeta, 4) == 0,
		"note 4 stays open on Zeta's row although it comes before note 8 (state %d)" % dz._repeat_note_state_for_record(zeta, 4))
	hostz.queue_free()
	# The player's "not here" mark makes the note's own record a different star.
	helios = d2._get_or_create_match_record_for_name("Helios")
	w2._on_seq_note_toggle(helios, 7)
	var n7: int = d2._get_or_create_match_record_for_melody_tick(7)
	d2._full_propagation_refresh()
	helios = d2._get_or_create_match_record_for_name("Helios")
	ok(d2._records_provably_distinct(helios, n7), "Helios marked 'not note 7': note 7's own record is provably not Helios")
	# Same single position on both sides reads as confirmed without a merge.
	var selion: int = d2._get_or_create_match_record_for_name("Selion")
	w2._on_seq_checker_select(selion, 2, lo2, mid2, hi2)
	await process_frame
	n7 = d2._get_or_create_match_record_for_melody_tick(7)
	d2.record_at(n7)["seq_lo"] = 2
	d2.record_at(n7)["seq_hi"] = 2
	d2._full_propagation_refresh()
	selion = d2._get_or_create_match_record_for_name("Selion")
	ok(d2._repeat_note_state_for_record(selion, 7) == 1,
		"note 7 placed on position 2 from the staff shows as confirmed on Selion's row, pinned to position 2 (state %d)" % d2._repeat_note_state_for_record(selion, 7))

	# FIRST NOTES HIDDEN (author ruling 2026-10-12). The player is never told
	# which notes are a star's first firing and the game must not act on it.
	# So on a repeating melody every note is the same kind of button, nothing
	# is pick-one, and nothing is filled in or removed that the player did not
	# mark -- except what the star's own firing count allows.
	print("\n=== first notes hidden: every note is the same kind of button ===")
	var hosth = await _make_host()
	var dh = hosth._deduction
	var wh = hosth._widgets
	hosth._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]   # notes 4 and 7 are repeats, which nothing below may use
	dh._load_match_records([])
	ok(dh._notes_hidden(), "the notes are hidden on a repeating melody")
	wh._seq_checker_loaded = true
	wh._seq_checker_mode = true
	var hrec: int = dh._get_or_create_match_record_for_name("Pyrios")
	var hrow: Control = wh._make_sequence_range_row_for_record(hrec, Color.WHITE)
	hosth.add_child(hrow)
	var hb: Array = _strip_buttons(hrow)
	ok(hb.size() == 8, "in Checks entry the row is the eight note buttons (got %d)" % hb.size())
	var tips_alike: bool = true
	var mentions_kind: bool = false
	for b3 in hb:
		var tip: String = (b3 as Button).tooltip_text
		if tip.replace((b3 as Button).text, "N") != (hb[0] as Button).tooltip_text.replace((hb[0] as Button).text, "N"):
			tips_alike = false
		if tip.contains("repeat") or tip.contains("first"):
			mentions_kind = true
		if (b3 as Button).modulate != (hb[0] as Button).modulate or (b3 as Button).disabled:
			tips_alike = false
	ok(tips_alike, "all eight buttons look alike and carry the same tooltip but for the note number")
	ok(not mentions_kind, "no tooltip says 'first' or 'repeat'")
	var all_open: bool = true
	for t3 in range(1, 9):
		if dh._repeat_note_state_for_record(hrec, t3) != 0:
			all_open = false
	ok(all_open, "every note starts open on the row")

	# The reported case: ruling out note 1 must not touch note 2 (or any note).
	wh._on_seq_note_toggle(hrec, 1)
	var only_one: bool = dh._repeat_note_state_for_record(hrec, 1) == 3
	for t4 in range(2, 9):
		if dh._repeat_note_state_for_record(hrec, t4) != 0:
			only_one = false
	ok(only_one, "right-click on note 1 rules out note 1 and nothing else")
	wh._on_seq_note_toggle(hrec, 1)

	# No note is pick-one: confirming a first-firing note leaves the others open.
	await wh._on_seq_note_select(hrec, 3)
	hrec = dh._get_or_create_match_record_for_name("Pyrios")
	var rest_open: bool = dh._repeat_note_state_for_record(hrec, 3) == 1
	for t5 in [1, 2, 4, 5, 6, 7, 8]:
		if dh._repeat_note_state_for_record(hrec, t5) != 0:
			rest_open = false
	ok(rest_open, "left-click on note 3 confirms note 3 and leaves the other seven open")
	# A CONFIRMED CHECK IS NOT DIMMED (2026-10-13). It used to be tinted by
	# multiplying the whole button by green, which made the one settled value
	# the darkest button on the row. It keeps full brightness and is marked by
	# its text colour.
	var crow: Control = wh._make_sequence_range_row_for_record(hrec, Color.WHITE)
	hosth.add_child(crow)
	var cb: Array = _strip_buttons(crow)
	var c3: Button = cb[2]
	var c1: Button = cb[0]
	ok(c3.text == "3" and c3.modulate == Color.WHITE and c3.modulate == c1.modulate,
		"the confirmed note-3 button is as bright as an open one beside it (modulate %s)" % str(c3.modulate))
	ok(c3.get_theme_color("font_color") == wh.STATE_COLORS.confirmed and c1.get_theme_color("font_color") != wh.STATE_COLORS.confirmed,
		"and is told apart by its text colour alone")
	crow.free()
	ok(dh._effective_seq_candidates(hrec).size() == 6, "and the board has worked out no firing-order position from it (got %s)" % str(dh._effective_seq_candidates(hrec)))

	# A clicked note opens a blank entry.
	var note5_rec: int = dh._get_or_create_match_record_for_melody_tick(5)
	dh._full_propagation_refresh()
	note5_rec = dh._find_match_record_by_melody_tick(5)
	var blank: bool = dh._effective_seq_candidates(note5_rec).size() == 6 and dh._seq_pos_for_melody_tick(5) == 0
	for t6 in [1, 2, 3, 4, 6, 7, 8]:
		# note 3 is Pyrios's, and nothing says note 5 is not Pyrios too
		if dh._repeat_note_state_for_record(note5_rec, t6) != 0:
			blank = false
	ok(blank, "clicking note 5 on the staff opens an entry with every other note open and no position")
	var note4_rec: int = dh._get_or_create_match_record_for_melody_tick(4)
	dh._full_propagation_refresh()
	note4_rec = dh._find_match_record_by_melody_tick(4)
	var blank4: bool = dh._effective_seq_candidates(note4_rec).size() == 6
	for t7 in [1, 2, 3, 5, 6, 7, 8]:
		if dh._repeat_note_state_for_record(note4_rec, t7) != 0:
			blank4 = false
	ok(blank4, "and so does note 4, which is secretly a repeat: nothing ties it to note 1")

	# The Staff popup's row: every note's popup has it, offering every other note.
	for popup_tick in [1, 4]:
		wh._open_staff_popup(popup_tick, Vector2.ZERO)
		var idrow: Control = hosth._staff_popup._identity_row
		var offered: Array = []
		if idrow != null:
			for b4 in idrow.find_children("*", "Button", true, false):
				if (b4 as Button).text.is_valid_int():
					offered.append(int((b4 as Button).text))
		var want: Array = []
		for t8 in range(1, 9):
			if t8 != popup_tick:
				want.append(t8)
		ok(offered == want, "note %d's popup has 'Same star as note' offering every other note (got %s)" % [popup_tick, str(offered)])
		hosth._staff_popup.hide()
	await wh._on_staff_note_link(4, 8, false)
	ok(dh._find_match_record_by_melody_tick(8) == dh._find_match_record_by_melody_tick(4) and dh._find_match_record_by_melody_tick(4) >= 0,
		"marking 'same star as note 8' on note 4's popup puts both notes on one entry")
	hosth._staff_popup.hide()
	await wh._on_staff_note_link(4, 2, true)
	hosth._staff_popup.hide()
	var note2_rec: int = dh._get_or_create_match_record_for_melody_tick(2)
	dh._full_propagation_refresh()
	ok(dh._records_provably_distinct(dh._find_match_record_by_melody_tick(4), dh._find_match_record_by_melody_tick(2)),
		"marking 'not the same star as note 2' makes the two notes provably different stars")
	ok(note2_rec >= 0 and dh._repeat_note_state_for_record(dh._find_match_record_by_melody_tick(2), 8) == 2,
		"so on note 2's entry note 8 is ruled out too: it is note 4's star")

	# THE COUNT CAPS THE ROW. Zeta is known to fire twice (repeats once): once it
	# holds two notes every other note is ruled out; before that none is.
	var zh: int = dh._get_or_create_match_record_for_name("Zeta")
	dh.record_at(zh)["repeat_states"] = {1: 1}
	dh._full_propagation_refresh()
	zh = dh._get_or_create_match_record_for_name("Zeta")
	ok(dh._known_fire_count_for_record(zh) == 2, "Zeta, marked 'repeats once', is known to fire twice (got %d)" % dh._known_fire_count_for_record(zh))
	await wh._on_seq_note_select(zh, 6)
	zh = dh._get_or_create_match_record_for_name("Zeta")
	ok(dh._repeat_note_state_for_record(zh, 1) == 0, "with one note confirmed the others are still open")
	await wh._on_seq_note_select(zh, 1)
	zh = dh._get_or_create_match_record_for_name("Zeta")
	var capped: bool = dh._repeat_note_state_for_record(zh, 6) == 1 and dh._repeat_note_state_for_record(zh, 1) == 1
	for t9 in [5, 7]:
		if dh._repeat_note_state_for_record(zh, t9) != 2:
			capped = false
	ok(capped, "with both its notes confirmed every other note is ruled out on Zeta's row")
	await wh._on_seq_note_select(zh, 1)
	zh = dh._get_or_create_match_record_for_name("Zeta")
	ok(dh._repeat_note_state_for_record(zh, 5) == 0, "letting one go reopens them")
	# The other way: holding notes bounds the count.
	var eh: int = dh._get_or_create_match_record_for_name("Eos")
	await wh._on_seq_note_select(eh, 5)
	eh = dh._get_or_create_match_record_for_name("Eos")
	await wh._on_seq_note_select(eh, 7)
	dh._full_propagation_refresh()
	eh = dh._get_or_create_match_record_for_name("Eos")
	ok(dh._effective_repeat_state(eh, 0) == 2, "Eos, holding two notes, cannot be a star that never repeats (state %d)" % dh._effective_repeat_state(eh, 0))
	# (The finder was switched off on these boards for a few hours on
	# 2026-10-12; it is back, re-based on notes -- see test_owner_hints.gd.)
	ok(not dh.hints_unavailable() and dh.hint_next_steps([]).is_empty(), "the hint finder is on, and with no clues offers nothing")

	# A star's map tag lists the notes the board has it firing on, no position.
	var star0: int = dh._get_or_create_match_record_for_star_idx(0)
	ok(wh._held_notes_str_for_star(0) == "?", "a map star with no note placed reads '?' (got '%s')" % wh._held_notes_str_for_star(0))
	await wh._on_seq_note_select(star0, 2)
	ok(wh._held_notes_str_for_star(0) == "2", "after its row confirms note 2 the tag reads '2' (got '%s')" % wh._held_notes_str_for_star(0))

	# The Staff popup's sections sit in two columns (author direction
	# 2026-10-12), so the taller popup stays clear of the pinned clue.
	var pop = hosth._staff_popup
	var left: Node = pop._pitch_columns_box.get_parent()
	var right: Node = pop._name_columns_box.get_parent()
	ok(left != right and left.get_parent() == right.get_parent() and left.get_parent() is HBoxContainer,
		"Pitch and Name sit in two different columns of one row")
	ok(pop._color_columns_box.get_parent() == left and pop._repeat_columns_box.get_parent() == right,
		"Colour shares the left column with Pitch; Repeats sits under Name on the right")

	# IS THE POPUP OVER THE PINNED CLUE? (2026-10-13: it still was, on screen.)
	# The check reads where the window actually is, after it has been placed.
	wh._open_staff_popup(5, Vector2.ZERO)
	var floor_y: float = wh._popup_min_screen_y()
	print("    header ends at %d, view ends at %d, room %d; popup top %d, content height %d, built at %d rows a column" % [
		int(floor_y), int(wh._popup_max_screen_y()), int(wh._popup_room_under_header()), int(pop.position.y),
		int(pop.get_contents_minimum_size().y), wh.staff_popup_rows_per_column])
	ok(not wh._popup_covers_header(pop), "as placed, the Staff popup is not over the header (top %d, header ends %d)" % [int(pop.position.y), int(floor_y)])
	var covers_before: int = wh.popup_header_cover_count
	pop.position = Vector2i(pop.position.x, int(floor_y) - 40)
	ok(wh._popup_covers_header(pop), "moved 40 px up, it is detected as covering the header")
	ok(wh._keep_popup_off_header(pop, "test") and int(pop.position.y) >= int(floor_y) and wh.popup_header_cover_count == covers_before + 1,
		"and is put back under it, and counted (top now %d)" % int(pop.position.y))
	ok(not wh._keep_popup_off_header(pop, "test") and wh.popup_header_cover_count == covers_before + 1,
		"a popup already clear of the header is left alone")
	pop.hide()
	# A popup too tall for the room is rebuilt with fewer rows a column.
	var tall_height: int = int(pop.get_contents_minimum_size().y)
	var room_before: float = wh._popup_room_under_header()
	wh.popup_room_override = float(tall_height - 40)   # the runner's own view is a stub; see the seam
	wh._open_staff_popup(5, Vector2.ZERO)
	print("    with the view shortened: room %d (was %d); popup content height %d (was %d), built at %d rows a column" % [
		int(wh._popup_room_under_header()), int(room_before), int(pop.get_contents_minimum_size().y), tall_height, wh.staff_popup_rows_per_column])
	ok(wh._popup_room_under_header() < float(tall_height), "precondition: the popup as first built no longer fits (room %d < %d)" % [int(wh._popup_room_under_header()), tall_height])
	ok(wh.staff_popup_rows_per_column < wh.STAFF_POPUP_MAX_ROWS_PER_COLUMN and int(pop.get_contents_minimum_size().y) < tall_height,
		"so it was rebuilt shorter, with fewer rows a column (%d rows, height %d)" % [wh.staff_popup_rows_per_column, int(pop.get_contents_minimum_size().y)])
	ok(not wh._popup_covers_header(pop), "and it is still not over the header")
	wh.popup_room_override = -1.0
	pop.hide()
	# PITCH ROWS READ LOWEST FIRST whatever order the constellation's table
	# stores them in (reported 2026-10-12 on the Phial: E5, second lowest, sat
	# second from last and read as second highest). This board's table is
	# deliberately out of order.
	hosth._pitch_freqs = [523.25, 440.0, 493.88]   # C5, A4, B4
	wh.clear_pitch_caches()
	wh._open_staff_popup(5, Vector2.ZERO)
	var pitch_order: Array = []
	for col in pop._pitch_columns:
		for prow in (col as Node).get_children():
			pitch_order.append(str(prow.label_text))
	ok(pitch_order == ["A4", "B4", "C5"], "the Staff popup lists pitches lowest first, down the columns (got %s)" % str(pitch_order))
	pop.hide()
	wh._open_pitch_checklist_popup(dh._get_or_create_match_record_for_name("Pyrios"), Vector2.ZERO)
	var checklist_order: Array = []
	for prow2 in hosth._pitch_checklist_popup.find_children("*", "StaffPopupRow", true, false):
		checklist_order.append(str(prow2.label_text))
	ok(checklist_order == ["A4", "B4", "C5"], "and so does the Classic 'Select Pitch' list (got %s)" % str(checklist_order))
	hosth._pitch_checklist_popup.hide()
	wh._open_staff_popup(5, Vector2.ZERO)
	ok(pop._identity_row != null and pop._identity_row.get_parent() == pop._title_label.get_parent(),
		"the 'Same star as note' row spans the full width above both columns")
	pop.hide()
	hosth.queue_free()

	# CLASSIC ENTRY WITH THE FIRST NOTES HIDDEN (reported 2026-10-13: switching
	# to Classic left the Sequence line on the check buttons). The three boxes
	# are back, speaking about notes: `lower < list < upper`, "=N" for a note
	# the star does fire on. They write the same marks the checks write.
	print("\n=== first notes hidden, Classic entry: the three boxes, about notes ===")
	var hostt = await _make_host()
	var dt = hostt._deduction
	var wt = hostt._widgets
	hostt._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]
	dt._load_match_records([])
	wt._seq_checker_loaded = true
	wt._seq_checker_mode = false
	var trec: int = dt._get_or_create_match_record_for_name("Pyrios")
	var trow: Control = wt._make_sequence_range_row_for_record(trec, Color.WHITE)
	hostt.add_child(trow)
	var tedits: Array = trow.find_children("*", "LineEdit", true, false)
	ok(tedits.size() == 3 and _strip_buttons(trow).is_empty(), "Classic entry shows three boxes and no note buttons (%d boxes)" % tedits.size())
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-8", ""], "an untouched row reads _ < 1-8 < _: every note possible (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	trow.free()
	# REPORTED 2026-10-13 from a live Archon board: with only the upper bound
	# set to 7 the list stayed blank where 1-6 belonged, and typing 1-6 into it
	# read straight back as blank. The list was only shown once something
	# INSIDE the bounds had been marked.
	await wt._commit_sequence_notes_typed(trec, "", "1-8", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-6", "7"], "upper bound 7 alone reads _ < 1-6 < 7 (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	await wt._commit_sequence_notes_typed(trec, "", "1-6", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-6", "7"], "typing 1-6 into the list keeps it there (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# A mark inside the bounds survives a change to a bound...
	await wt._commit_sequence_notes_typed(trec, "", "1-3,5-6", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	await wt._commit_sequence_notes_typed(trec, "1", "1-3,5-6", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["1", "2-3,5-6", "7"], "raising the lower bound keeps note 4 ruled out (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# ...and widening a bound, with the list left as it was shown, reopens
	# what the old bound covered.
	await wt._commit_sequence_notes_typed(trec, "", "2-3,5-6", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-3,5-8", ""], "clearing both bounds reopens notes 1, 7 and 8 and still keeps 4 out (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	await wt._commit_sequence_notes_typed(trec, "", "", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	# lower 2: no note up to 2. upper 7: no note from 7 on.
	await wt._commit_sequence_notes_typed(trec, "2", "", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	var st_typed: Array = []
	for tt in range(1, 9):
		st_typed.append(dt._repeat_note_state_for_record(trec, tt))
	ok(st_typed == [3, 3, 0, 0, 0, 0, 3, 3], "'2 < _ < 7' rules out notes 1, 2, 7, 8 and leaves 3 to 6 open (states %s)" % str(st_typed))
	ok(wt._seq_notes_typed_texts(trec) == ["2", "3-6", "7"], "and reads back as 2 < 3-6 < 7 (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# The list: 3 and 5-6 possible, so 4 is ruled out.
	await wt._commit_sequence_notes_typed(trec, "2", "3,5-6", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(dt._repeat_note_state_for_record(trec, 4) == 3 and dt._repeat_note_state_for_record(trec, 5) == 0,
		"a note left out of the list (4) is ruled out; one listed (5) stays open")
	ok(wt._seq_notes_typed_texts(trec) == ["2", "3,5-6", "7"], "reads back as typed (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# "=5" confirms note 5 on the row, exactly as a left-click on the checks would.
	await wt._commit_sequence_notes_typed(trec, "2", "3,=5,6", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(dt._repeat_note_state_for_record(trec, 5) == 1 and dt._find_match_record_by_melody_tick(5) == trec,
		"'=5' puts note 5 on Pyrios's row")
	ok(wt._seq_notes_typed_texts(trec) == ["2", "3,=5,6", "7"], "reads back with the = (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# The checks show the very same marks.
	wt._seq_checker_mode = true
	var same_marks: Array = []
	var crow2: Control = wt._make_sequence_range_row_for_record(trec, Color.WHITE)
	hostt.add_child(crow2)
	for cbtn in _strip_buttons(crow2):
		same_marks.append(dt._repeat_note_state_for_record(trec, int((cbtn as Button).text)))
	ok(same_marks == [3, 3, 0, 3, 1, 0, 3, 3], "switching to Checks shows the same marks, note for note (%s)" % str(same_marks))
	crow2.free()
	wt._seq_checker_mode = false
	# Taking the "=" away lets the note go; widening the bounds takes marks back.
	await wt._commit_sequence_notes_typed(trec, "", "3,5,6", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(dt._repeat_note_state_for_record(trec, 5) == 0 and dt._repeat_note_state_for_record(trec, 1) == 3 and dt._repeat_note_state_for_record(trec, 4) == 3,
		"removing the = lets note 5 go; notes not in the list stay ruled out")
	await wt._commit_sequence_notes_typed(trec, "", "", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	var all_open_again: bool = true
	for tt2 in range(1, 9):
		if dt._repeat_note_state_for_record(trec, tt2) != 0:
			all_open_again = false
	ok(all_open_again, "clearing all three boxes makes every note possible again")
	# Something unreadable changes nothing.
	await wt._commit_sequence_notes_typed(trec, "2", "", "7")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	# (each as the three boxes would read with ONE of them changed from 2 < 3-6 < 7)
	for junk in [["x", "3-6", "7"], ["2", "3,banana", "7"], ["2", "9", "7"], ["6", "3-6", "7"]]:
		await wt._commit_sequence_notes_typed(trec, str(junk[0]), str(junk[1]), str(junk[2]))
		trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["2", "3-6", "7"], "a letter, a note past the end, and bounds leaving nothing are all refused (still %s)" % str(wt._seq_notes_typed_texts(trec)))
	# REPORTED 2026-10-13 (Archon, the F5 row): typing "1-2" into the list
	# snapped back to what was shown before, though typing 3 into the upper
	# box worked. Every commit rebuilds the row; the OLD boxes then lose
	# focus and commit again with their old texts. That second commit carried
	# an upper box still blank where the row now read 3, took the blank for
	# "no upper bound", and reopened everything. The commit is given what the
	# boxes showed when they were built, exactly as the row's own wiring does.
	await wt._commit_sequence_notes_typed(trec, "", "", "", wt._seq_notes_typed_texts(trec))
	await wt._commit_sequence_notes_typed(trec, "", "", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	var built: Array = wt._seq_notes_typed_texts(trec)
	ok(built == ["", "1-8", ""], "precondition: an open row, _ < 1-8 < _ (got %s)" % str(built))
	await wt._commit_sequence_notes_typed(trec, "", "1-2", "", built)
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-2", "3"], "typing 1-2 into the list leaves only notes 1 and 2 (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# the old boxes losing focus: the SAME texts, the SAME 'built' read-out
	await wt._commit_sequence_notes_typed(trec, "", "1-2", "", built)
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-2", "3"], "and the old boxes committing again changes nothing (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# And the fault itself, so this section can fail: the stale repeat WITHOUT
	# what the boxes showed (how it was before) does reopen everything.
	await wt._commit_sequence_notes_typed(trec, "", "1-2", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-8", ""], "(the old way, to show the fault) the same repeat judged against the row as it now stands snaps back to 1-8 (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	# The same for a bound: 5 typed into the upper box, then the stale repeat.
	await wt._commit_sequence_notes_typed(trec, "", "", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	built = wt._seq_notes_typed_texts(trec)
	await wt._commit_sequence_notes_typed(trec, "", "1-8", "5", built)
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	await wt._commit_sequence_notes_typed(trec, "", "1-8", "5", built)
	trec = dt._get_or_create_match_record_for_name("Pyrios")
	ok(wt._seq_notes_typed_texts(trec) == ["", "1-4", "5"], "an upper bound of 5 survives its own stale repeat too (got %s)" % str(wt._seq_notes_typed_texts(trec)))
	await wt._commit_sequence_notes_typed(trec, "", "", "")
	trec = dt._get_or_create_match_record_for_name("Pyrios")

	# The Star Map's widget uses the same boxes in Classic entry.
	var srec: int = dt._get_or_create_match_record_for_star_idx(0)
	ok(wt._seq_notes_typed_texts(srec) == ["", "1-8", ""] and wt._make_sequence_notes_typed_row(srec, Color.WHITE).find_children("*", "LineEdit", true, false).size() == 3,
		"a map star's entry gets the same three boxes")
	hostt.queue_free()

	# A COLOUR SLOT STAYS ANONYMOUS AFTER A NOTE IS PLACED ON A MAP STAR
	# (reported 2026-10-13: "Color Slots are being assigned to specific stars
	# again ... the puzzle thinks that slot is a different star of the same
	# color"). Stars 0 and 1 share a colour. The player places a note on star
	# 0's own widget, then opens the Sort: Color tab and puts star 1's pitch
	# into the first slot of that colour.
	print("\n=== a colour slot is not a map star's own entry ===")
	for old_behaviour in [true, false]:
		var hc = await _make_host()
		var dc = hc._deduction
		var wc = hc._widgets
		hc._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]
		hc._melody_star_sequence = [0, 1, 2, 0, 3, 4, 1, 5]
		hc._repeat_count = [1, 1, 0, 0, 0, 0]
		# one pitch per star, so star 1's pitch names star 1
		hc._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 659.26]
		hc._star_pitch_index = [0, 1, 2, 3, 4, 5]
		wc.clear_pitch_caches()
		dc._load_match_records([])
		dc.color_slot_adopts_star_widgets = old_behaviour
		for s7 in 6:
			dc._get_or_create_match_record_for_star_idx(s7)   # the Star Map's own entries
		await hc._on_pitch_listen_star_clicked(0)
		await hc._on_pitch_listen_star_clicked(1)
		var star0_rec: int = dc._find_match_record_by_star_idx(0)
		await wc._on_seq_note_select(star0_rec, 4)
		star0_rec = dc._find_match_record_by_star_idx(0)
		var shared_colour: int = int(hc._star_colors[0])
		var slot_a: int = dc._get_or_create_match_record_for_color_slot(shared_colour, 0)
		dc._full_propagation_refresh()
		slot_a = dc._get_or_create_match_record_for_color_slot(shared_colour, 0)
		var slot_is_star0: bool = slot_a == star0_rec or int(dc.record_at(slot_a).get("star_idx", -1)) == 0
		# Star 1's pitch goes into that slot.
		dc._propagate_pitch_confirmed_same_record(slot_a, wc._note_name_for_star(1))
		dc._save_puzzle_notes()
		dc._full_propagation_refresh()
		slot_a = dc._get_or_create_match_record_for_color_slot(shared_colour, 0)
		var complaints: int = dc._contradictions.size()
		if old_behaviour:
			ok(slot_is_star0, "(old behaviour, to show the fault) the slot WAS star 0's own entry")
			ok(complaints > 0 or dc._effective_star_idx(slot_a) != 1,
				"(old behaviour) star 1's pitch in it then clashes or does not land on star 1 (%d complaints, slot's star %d)" % [complaints, dc._effective_star_idx(slot_a)])
		else:
			ok(not slot_is_star0 and (dc.record_at(dc._find_match_record_by_star_idx(0)).get("melody_ticks", []) as Array).has(4),
				"the slot is a separate, anonymous entry; star 0's entry keeps its note")
			ok(complaints == 0, "star 1's pitch goes into it with no error (%d complaints)" % complaints)
			ok(dc._effective_star_idx(slot_a) == 1, "and the slot is now worked out to be star 1, the star that data came from (got %d)" % dc._effective_star_idx(slot_a))
			# A save made while the fault was live: the label comes off the
			# star's entry and the slot starts clean.
			dc.record_at(dc._find_match_record_by_star_idx(0))["color_slot_label"] = "%s B" % str(hc.COLOR_NAME_LABELS[shared_colour])
			var slot_b: int = dc._get_or_create_match_record_for_color_slot(shared_colour, 1)
			ok(slot_b != dc._find_match_record_by_star_idx(0) and str(dc.record_at(dc._find_match_record_by_star_idx(0)).get("color_slot_label", "")) == "",
				"a slot label left on a star's own entry by the fault is taken off, and the slot gets a fresh entry")
		hc.queue_free()

	print("\n=== the scroll position survives a rebuild ===")
	# A click rebuilds the whole row; the strip must come back where it was.
	var host3 = await _make_host()
	var d3 = host3._deduction
	var w3 = host3._widgets
	host3._star_count = 6
	d3._load_match_records([])
	var rec3: int = d3._get_or_create_match_record_for_name("Pyrios")
	w3._seq_checker_loaded = true
	w3._seq_checker_mode = true
	var holder := Control.new()
	holder.size = Vector2(300, 40)
	host3.add_child(holder)
	var rowa: Control = w3._make_sequence_range_row_for_record(rec3, Color.WHITE)
	rowa.size = Vector2(60, 30)    # narrower than its six buttons, so it scrolls
	holder.add_child(rowa)
	await process_frame
	await process_frame
	var scrolla: ScrollContainer = null
	for c in rowa.get_children():
		if c is ScrollContainer:
			scrolla = c
	scrolla.scroll_horizontal = 25
	await process_frame
	var moved: int = scrolla.scroll_horizontal
	ok(moved > 0, "precondition: the strip could be scrolled (at %d)" % moved)
	rowa.queue_free()
	await process_frame
	var rowb: Control = w3._make_sequence_range_row_for_record(rec3, Color.WHITE)
	rowb.size = Vector2(60, 30)
	holder.add_child(rowb)
	await process_frame
	await process_frame
	await process_frame
	var scrollb: ScrollContainer = null
	for c2 in rowb.get_children():
		if c2 is ScrollContainer:
			scrollb = c2
	ok(scrollb.scroll_horizontal == moved, "the rebuilt strip is back at %d (got %d)" % [moved, scrollb.scroll_horizontal])

	print("\n=== UNDO on the checker row ===")
	var host5 = await _make_host()
	var d5 = host5._deduction
	var w5 = host5._widgets
	d5._load_match_records([])
	w5._seq_checker_loaded = true
	w5._seq_checker_mode = true
	var rec5: int = d5._get_or_create_match_record_for_name("Pyrios")
	var row5: Control = w5._make_sequence_range_row_for_record(rec5, Color.WHITE)
	host5.add_child(row5)
	var undo5: Button = row5.get_child(row5.get_child_count() - 1) as Button
	ok(undo5 != null and undo5.text == "↶", "the row ends with an UNDO button")
	ok(undo5.disabled, "greyed out while the record has no Sequence entry of its own")
	var l5 := LineEdit.new()
	var m5 := LineEdit.new()
	var h5 := LineEdit.new()
	host5.add_child(l5)
	host5.add_child(m5)
	host5.add_child(h5)
	await w5._on_seq_checker_toggle(rec5, 2, l5, m5, h5)
	await w5._on_seq_checker_toggle(rec5, 4, l5, m5, h5)
	ok(d5._effective_seq_candidates(rec5).size() == 4, "precondition: two positions ruled out")
	row5.free()
	row5 = w5._make_sequence_range_row_for_record(rec5, Color.WHITE)
	host5.add_child(row5)
	undo5 = row5.get_child(row5.get_child_count() - 1) as Button
	ok(not undo5.disabled, "enabled once there is something to take back")
	undo5.pressed.emit()
	await process_frame
	ok(d5._effective_seq_candidates(rec5).size() == 6, "pressing it makes every position possible again")
	var r5: Dictionary = d5.record_at(rec5)
	ok((r5.get("seq_candidates", []) as Array).is_empty() and int(r5.get("seq_lo", 0)) == 0 and int(r5.get("seq_hi", 0)) == 0, "and leaves no Sequence entry behind")
	# an exact pin is undone too
	await w5._commit_sequence_range(rec5, _mk(host5, "3"), _mk(host5, ""), _mk(host5, "3"))
	ok(d5._effective_seq_candidates(rec5) == [3], "an exact pin is in place")
	w5._clear_sequence_info(rec5)
	ok(d5._effective_seq_candidates(rec5).size() == 6, "and undo releases it as well")

	print("\n=== ruled-out notes are hidden until the return button is pressed ===")
	d5._load_match_records([])
	var rec6: int = d5._get_or_create_match_record_for_name("Zeta")
	await w5._on_seq_checker_toggle(rec6, 3, l5, m5, h5)
	var row6: Control = w5._make_sequence_range_row_for_record(rec6, Color.WHITE)
	host5.add_child(row6)
	var s6: Array = _strip_buttons(row6)
	ok(not (s6[2] as Button).visible and (s6[1] as Button).visible, "note 3 (ruled out) is hidden, its neighbours are shown")
	var ret6: Button = null
	for c6 in row6.get_children():
		if c6 is Button and (c6 as Button).text == "→":
			ret6 = c6
	ok(ret6 != null and not ret6.disabled, "the straight-arrow return button is available")
	ret6.pressed.emit()
	await process_frame
	var row7: Control = w5._make_sequence_range_row_for_record(rec6, Color.WHITE)
	host5.add_child(row7)
	ok(((_strip_buttons(row7))[2] as Button).visible, "pressing it brings note 3 back into view")
	var rc_a := InputEventMouseButton.new()
	rc_a.button_index = MOUSE_BUTTON_RIGHT
	rc_a.pressed = true
	_strip_buttons(row7)[2].gui_input.emit(rc_a)
	await process_frame
	ok(d5._effective_seq_candidates(rec6).size() == 6, "and right-clicking it restores the position")

	print("\n=== the Star Map widget shows the checker too ===")
	var host4 = await _make_host()
	var d4 = host4._deduction
	var w4 = host4._widgets
	d4._load_match_records([])
	host4._star_screen_pos = []
	for i4 in host4._star_count:
		host4._star_screen_pos.append(Vector2(40 + i4 * 30, 60))
	host4._selected_star = 0
	w4._seq_checker_loaded = true
	w4._seq_checker_mode = false
	w4._build_star_widgets_impl()
	await process_frame
	var typed_edits: int = 0
	var stack4: Array = [host4._star_widgets[0]]
	while not stack4.is_empty():
		var n4: Node = stack4.pop_back()
		if n4 is LineEdit:
			typed_edits += 1
		stack4.append_array(n4.get_children())
	ok(typed_edits >= 3, "typed mode: the widget has its three Sequence boxes (%d edits)" % typed_edits)

	w4._seq_checker_mode = true
	w4._build_star_widgets_impl()
	await process_frame
	var strip4: Array = []
	var visible_edits: int = 0
	var stack5: Array = [host4._star_widgets[0]]
	while not stack5.is_empty():
		var n5: Node = stack5.pop_back()
		if n5 is ScrollContainer:
			for b4 in n5.get_child(0).get_children():
				strip4.append(b4)
		if n5 is LineEdit and (n5 as LineEdit).visible and (n5 as LineEdit).get_parent() is HBoxContainer and (n5 as LineEdit).get_parent().get_child_count() > 1:
			visible_edits += 1
		stack5.append_array(n5.get_children())
	ok(strip4.size() == 6, "checks mode: one button per note on the star widget (%d)" % strip4.size())
	if strip4.size() == 6:
		var rec4: int = d4._get_or_create_match_record_for_star_idx(0)
		var rc_b := InputEventMouseButton.new()
		rc_b.button_index = MOUSE_BUTTON_RIGHT
		rc_b.pressed = true
		(strip4[2] as Button).gui_input.emit(rc_b)
		await process_frame
		ok(not d4._effective_seq_candidates(rec4).has(3), "right-clicking note 3 on the widget rules it out for that star's record")
	ok(visible_edits == 0, "and the typed boxes are not shown (%d)" % visible_edits)

	print("\n=== left-click selects the position as true ===")
	var host8 = await _make_host()
	var d8 = host8._deduction
	var w8 = host8._widgets
	d8._load_match_records([])
	var rec8: int = d8._get_or_create_match_record_for_name("Pyrios")
	var l8 := LineEdit.new()
	var m8 := LineEdit.new()
	var h8 := LineEdit.new()
	host8.add_child(l8)
	host8.add_child(m8)
	host8.add_child(h8)
	w8._on_seq_checker_select(rec8, 4, l8, m8, h8)
	await process_frame
	ok(d8._effective_seq_candidates(rec8) == [4], "a left-click pins the position (got %s)" % str(d8._effective_seq_candidates(rec8)))
	w8._on_seq_checker_select(rec8, 4, l8, m8, h8)
	await process_frame
	ok(d8._effective_seq_candidates(rec8).size() == 6, "a second left-click lets go of the pin")

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()


func _mk(host, text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	host.add_child(e)
	return e
