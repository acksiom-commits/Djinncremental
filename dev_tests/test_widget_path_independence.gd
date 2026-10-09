extends "res://dev_tests/test_base.gd"
# PATH INDEPENDENCE of the player-facing entry widgets (2026-10-07).
#
# The question this answers: if the player tells the board the SAME facts,
# does it matter WHICH widget they used, which row they entered it on, or in
# what order? It must not. Any difference in the resulting board is a
# propagation failure in whichever path disagrees with the baseline -- no
# oracle needed, because every variant is fed identical information.
#
# Three families, all driven by one step list per scenario:
#
#   A. FULL FACTS  (name, firing position, colour, pitch of an entity) entered
#      through different widgets, rows (the record is fetched by name, by
#      position slot or by colour slot) and orders.
#   B. PARTIAL FACTS  (a candidate set rather than a pin: positions via the
#      list box vs the checker, colours / names / notes ruled out one by one in
#      different orders) -- the same narrowing must read the same everywhere.
#   C. UNDO  (enter, then release through a different control) must leave the
#      board exactly as if the fact had never been entered.
#
# What is compared is RECORD-INDEPENDENT readout, since records legitimately
# differ by path: per entity, every state the record holding it shows (names,
# positions, colours, notes), and -- once something identifies the star -- the
# player-side grid rows too; AND that every record identifying one star shows
# the same thing (a star must not read differently on two rows).
#
# Prints judged/seen denominators so a green run cannot be vacuous.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const CAT = preload("res://constellation_logic_puzzle.gd").Category

var fails: int = 0
var scenarios_judged: int = 0
var scenarios_equal: int = 0
var stars_judged: int = 0


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
	# Truth: star i fires at a scrambled position so index != position.
	host._sequence_rank_solution = [3, 0, 5, 1, 4, 2]
	host._repeat_count = [0, 0, 1, 1, 2, -1]
	host._widgets.clear_pitch_caches()
	return host


# ── truth ──────────────────────────────────────────────────────────────────
func _t_name(host, s: int) -> String:
	return str(host._star_names[s])


func _t_pos(host, s: int) -> int:
	return int(host._sequence_rank_solution[s]) + 1


func _t_color(host, s: int) -> int:
	return int(host._star_colors[s])


func _t_note(host, s: int) -> String:
	return str(host._widgets._note_name_for_star(s))


func _notes(host) -> Array:
	return host._widgets._distinct_note_names()


# ── record access ──────────────────────────────────────────────────────────
func _record_for(host, s: int, getter: String, slot_counts: Dictionary) -> int:
	var d = host._deduction
	match getter:
		"name":
			return d._get_or_create_match_record_for_name(_t_name(host, s))
		"seq":
			return d._get_or_create_match_record_for_seq(_t_pos(host, s))
		_:
			var c: int = _t_color(host, s)
			var n: int = int(slot_counts.get(c, 0))
			slot_counts[c] = n + 1
			return d._get_or_create_match_record_for_color_slot(c, n)


func _index_of(d, ref: Dictionary) -> int:
	for i in d.record_count():
		if is_same(d.record_at(i), ref):
			return i
	return -1


# Best-effort re-find of the record holding entity s after a merge absorbed
# the one we were tracking.
func _resolve(host, s: int) -> int:
	var d = host._deduction
	var r: int = d._find_match_record_by_name(_t_name(host, s))
	if r >= 0:
		return r
	return d._find_match_record_by_exact_seq(_t_pos(host, s))


# ── one step ───────────────────────────────────────────────────────────────
# A step is [action, param]. The entity is implied by the caller.
func _do(host, rec: int, s: int, step: Array) -> void:
	var d = host._deduction
	var w = host._widgets
	var action: String = str(step[0])
	var param = step[1] if step.size() > 1 else null
	var lo := LineEdit.new()
	var mid := LineEdit.new()
	var hi := LineEdit.new()
	host.add_child(lo)
	host.add_child(mid)
	host.add_child(hi)
	var nm: String = _t_name(host, s)
	var p: int = _t_pos(host, s)
	var c: int = _t_color(host, s)
	var note: String = _t_note(host, s)
	match action:
		# names
		"name_select":
			await w._on_record_name_selected(rec, nm)
		"name_check":
			w._on_slot_name_check(rec, nm, null)
		"name_xothers":
			for other in host._star_names:
				if str(other) != nm:
					w._on_slot_name_x(rec, str(other), null)
		"name_x":
			w._on_slot_name_x(rec, str(param), null)
		# sequence
		"seq_typed":
			lo.text = str(d._first_tick_for_rank(p))
			hi.text = str(d._first_tick_for_rank(p))
			await w._commit_sequence_range(rec, lo, mid, hi)
		"seq_list":
			var ticks := PackedStringArray()
			for q in (param as Array):
				ticks.append(str(q))
			mid.text = ",".join(ticks)
			await w._commit_sequence_candidates(rec, lo, mid, hi)
		"seq_list_decoy":
			var decoy: int = 1 if p != 1 else 2
			mid.text = "%d,%d" % [p, decoy]
			await w._commit_sequence_candidates(rec, lo, mid, hi)
			mid.text = str(p)
			await w._commit_sequence_candidates(rec, lo, mid, hi)
		"seq_checker_only":
			for q in range(1, host._star_count + 1):
				if q != p:
					await w._on_seq_checker_toggle(rec, q, lo, mid, hi)
		"seq_checker_off":
			for q in (param as Array):
				await w._on_seq_checker_toggle(rec, int(q), lo, mid, hi)
		"seq_checker_on":
			for q in (param as Array):
				await w._on_seq_checker_toggle(rec, int(q), lo, mid, hi)
		"seq_undo":
			w._undo_sequence_entry(rec, lo, mid, hi)
		# colours
		"color_toggle":
			await w._on_record_color_toggle(rec, c, Button.new())
		"color_xothers":
			for ci in host.COLOR_NAME_LABELS.size():
				if ci != c:
					await w._on_record_color_eliminate(rec, ci, Button.new())
		"color_x":
			await w._on_record_color_eliminate(rec, int(param), Button.new())
		# pitch
		"pitch_check":
			w._on_pitch_checklist_check(rec, note, null)
		"pitch_xothers":
			for n2 in _notes(host):
				if str(n2) != note:
					w._on_pitch_checklist_x(rec, str(n2), null)
		"pitch_x":
			w._on_pitch_checklist_x(rec, str(param), null)
		# repeat count
		"repeat_check":
			w._on_repeat_checklist_check(rec, int(host._repeat_count[s]), null)
		"repeat_xothers":
			for v in d._get_repeat_bucket_values():
				if int(v) != int(host._repeat_count[s]):
					w._on_repeat_checklist_x(rec, int(v), null)
		_:
			print("      (unknown step %s)" % action)
	await process_frame


# ── readout ────────────────────────────────────────────────────────────────
func _record_readout(host, rec: int) -> String:
	var d = host._deduction
	var ns: Array = []
	for n in host._star_names:
		ns.append(d._effective_name_state(rec, str(n)))
	var cs: Array = []
	for ci in host.COLOR_NAME_LABELS.size():
		cs.append(d._effective_color_state(rec, ci))
	var ps: Array = []
	for note in _notes(host):
		ps.append(d._effective_pitch_state(rec, str(note)))
	var rs: Array = []
	for v in d._get_repeat_bucket_values():
		rs.append(d._effective_repeat_state(rec, int(v)))
	return "names=%s pos=%s col=%s pitch=%s rep=%s" % [str(ns), str(d._effective_seq_candidates(rec)), str(cs), str(ps), str(rs)]


# Every record the PLAYER can link to the entity's own record, read the way
# each widget would. Linked = shares an effectively-confirmed name, or the same
# single position (both alldiff, so sharing one means one star). Deliberately
# NOT d._records_identifying_star(): that keys a position descriptor to the
# star that truly fires there, which the player has not established -- a
# "position 6" row and the "Pyrios" row are only one star once the player
# says so, so comparing them is a false alarm.
func _linked_records(host, start: int) -> Array:
	var d = host._deduction
	var comp: Array = [start]
	var changed: bool = true
	while changed:
		changed = false
		for i in d.record_count():
			if comp.has(i):
				continue
			for j in comp:
				if _player_linked(host, i, int(j)):
					comp.append(i)
					changed = true
					break
	return comp


func _player_linked(host, a: int, b: int) -> bool:
	var d = host._deduction
	for n in host._star_names:
		if d._effective_name_state(a, str(n)) == 1 and d._effective_name_state(b, str(n)) == 1:
			return true
	var sa: Array = d._seq_candidate_set_for(a)
	var sb: Array = d._seq_candidate_set_for(b)
	return sa.size() == 1 and sb.size() == 1 and int(sa[0]) == int(sb[0])


func _star_views(host, start: int) -> Array:
	var seen: Array = []
	for rec in _linked_records(host, start):
		var line: String = _record_readout(host, int(rec))
		if not seen.has(line):
			seen.append(line)
	return seen


func _signature(host, entities: Array, refs: Dictionary, label: String) -> String:
	var d = host._deduction
	var parts: PackedStringArray = PackedStringArray()
	for s in entities:
		var rec: int = _index_of(d, refs[s])
		if rec < 0:
			rec = _resolve(host, s)
		if rec < 0:
			parts.append("e%d own: NO RECORD" % s)
			continue
		parts.append("e%d own: %s" % [s, _record_readout(host, rec)])
		var views: Array = _star_views(host, rec)
		stars_judged += 1
		if views.size() > 1:
			ok(false, "[%s] entity %d reads DIFFERENTLY on records the player has linked:\n        %s" % [label, s, "\n        ".join(views)])
			parts.append("e%d views: DISAGREE" % s)
		# The star-keyed grid rows only once the player has actually named it
		# (the grid is keyed by true star index, so before that it is a
		# readout of the fixture, not of the player's knowledge).
		var named: bool = false
		for n in host._star_names:
			if d._effective_name_state(rec, str(n)) == 1:
				named = true
		if named:
			parts.append("e%d grid: pos=%s colvals=%s" % [s, str(d._player_positions_for_star(s)), str(d._possible_values_for_star(s, CAT.COLOR))])
	return "\n".join(parts)


# scenario = {getter, steps: [[entity_slot_ignored..]]}; steps are
# [step-array, ...] applied to EVERY entity, fact-major so order interleaves
# across entities. `per_entity` (optional) maps entity index -> extra steps.
func _run(entities: Array, getter: String, steps: Array, label: String) -> String:
	var host = await _make_host()
	var d = host._deduction
	d._load_match_records([])
	var refs: Dictionary = {}
	var slot_counts: Dictionary = {}
	for s in entities:
		refs[s] = d.record_at(_record_for(host, s, getter, slot_counts))
	for step in steps:
		for s in entities:
			var rec: int = _index_of(d, refs[s])
			if rec < 0:
				rec = _resolve(host, s)
			if rec < 0:
				print("      (driver lost the record for entity %d before %s)" % [s, str(step)])
				continue
			await _do(host, rec, s, step)
			if _index_of(d, refs[s]) < 0:
				var found: int = _resolve(host, s)
				if found >= 0:
					refs[s] = d.record_at(found)
	d._full_propagation_refresh()
	await process_frame
	var sig: String = _signature(host, entities, refs, label)
	host.queue_free()
	return sig


func _first_diff(a: String, b: String) -> String:
	var la: PackedStringArray = a.split("\n")
	var lb: PackedStringArray = b.split("\n")
	for i in maxi(la.size(), lb.size()):
		var x: String = la[i] if i < la.size() else "<none>"
		var y: String = lb[i] if i < lb.size() else "<none>"
		if x != y:
			return "baseline: %s\n         variant:  %s" % [x, y]
	return ""


# Compare `variants` (each [label, getter, steps]) against the first.
func _compare(title: String, entities: Array, variants: Array) -> void:
	print("\n=== %s  entities %s ===" % [title, str(entities)])
	var base: Array = variants[0]
	var base_sig: String = await _run(entities, str(base[1]), base[2], str(base[0]))
	print("  baseline (%s)\n  %s" % [str(base[0]), base_sig.replace("\n", "\n  ")])
	for i in range(1, variants.size()):
		var v: Array = variants[i]
		var sig: String = await _run(entities, str(v[1]), v[2], str(v[0]))
		scenarios_judged += 1
		if sig == base_sig:
			scenarios_equal += 1
		else:
			ok(false, "differs from baseline: %s" % str(v[0]))
			print("      " + _first_diff(base_sig, sig))


# ── F. Staff popup <-> Sort rows ───────────────────────────────────────────
# The Staff popup's record is keyed by the NOTE the player clicked (a melody
# tick), not by a position. The note a star fires on is public (it is where
# the player clicked), so a Sort row pinned to that note and the popup for
# that note are one star and must agree.
func _family_staff_link() -> void:
	print("\n=== F staff popup vs Sort row for the same note ===")
	for repeating in [false, true]:
		var host = await _make_host()
		var d = host._deduction
		if repeating:
			# 8 notes, 6 stars: stars 1 and 2 fire twice.
			host._melody_seq_pos_sequence = [1, 2, 3, 1, 4, 5, 2, 6]
		d._load_match_records([])
		var s: int = 2
		var rec: int = d._get_or_create_match_record_for_name(_t_name(host, s))
		await _do(host, rec, s, ["name_select"])
		await _do(host, d._find_match_record_by_name(_t_name(host, s)), s, ["seq_typed"])
		await _do(host, d._find_match_record_by_name(_t_name(host, s)), s, ["color_toggle"])
		d._full_propagation_refresh()
		var tick: int = d._first_tick_for_rank(_t_pos(host, s))
		var pop: int = d._get_or_create_match_record_for_melody_tick(tick)
		d._full_propagation_refresh()
		var row_rec: int = d._find_match_record_by_name(_t_name(host, s))
		var tag: String = "repeating melody" if repeating else "1:1 melody"
		print("  [%s] note %d" % [tag, tick])
		print("    Sort row : %s" % _record_readout(host, row_rec))
		print("    Staff pop: %s" % _record_readout(host, pop))
		scenarios_judged += 1
		var same: bool = _record_readout(host, row_rec) == _record_readout(host, pop)
		if same:
			scenarios_equal += 1
		ok(same, "[%s] the Staff popup for note %d shows what the Sort row pinned to that note knows" % [tag, tick])
		host.queue_free()


# ── G. the other direction: facts entered ON the Staff popup must reach the
# Sort row for that note, whichever was created first.
func _family_staff_to_row() -> void:
	print("\n=== G Staff popup facts reach the Sort row ===")
	for popup_first in [true, false]:
		var host = await _make_host()
		var d = host._deduction
		var w = host._widgets
		d._load_match_records([])
		var s: int = 2
		var tick: int = d._first_tick_for_rank(_t_pos(host, s))
		if popup_first:
			w._open_staff_popup(tick, Vector2.ZERO)
		var pop: int = d._get_or_create_match_record_for_melody_tick(tick)
		await w._on_staff_color_check(pop, _t_color(host, s), null)
		w._on_staff_pitch_check(pop, _t_note(host, s), null)
		# the Sort row, built after (or before) the popup facts
		var rec: int = d._get_or_create_match_record_for_name(_t_name(host, s))
		await _do(host, rec, s, ["name_select"])
		await _do(host, d._find_match_record_by_name(_t_name(host, s)), s, ["seq_typed"])
		d._full_propagation_refresh()
		var row_rec: int = d._find_match_record_by_name(_t_name(host, s))
		pop = d._get_or_create_match_record_for_melody_tick(tick)
		var tag: String = "popup first" if popup_first else "popup opened late"
		print("  [%s]\n    Sort row : %s\n    Staff pop: %s" % [tag, _record_readout(host, row_rec), _record_readout(host, pop)])
		var same: bool = _record_readout(host, row_rec) == _record_readout(host, pop)
		scenarios_judged += 1
		if same:
			scenarios_equal += 1
		ok(same, "[%s] popup and Sort row for note %d agree" % [tag, tick])
		var row_text: String = _record_readout(host, row_rec)
		ok(row_text.contains("col=[2, 1, 2, 2]"), "[%s] and the colour entered on the popup is on the Sort row" % tag)
		host.queue_free()


# ── D. map-star (location) facts vs the same facts on a Sort row ───────────
# "Name N is the star drawn HERE" gives the colour and degree for free (both
# are painted on the map); "this star fires at position p" typed on the star's
# own widget is the same Sequence fact as typing it on N's Sort row.
func _family_location() -> void:
	print("\n=== D map-star facts vs Sort row facts ===")
	var sig_row: String = ""
	var sig_map: String = ""
	for via_map in [false, true]:
		var host = await _make_host()
		var d = host._deduction
		var w = host._widgets
		d._load_match_records([])
		var s: int = 2
		var nm: String = _t_name(host, s)
		if via_map:
			await w._on_name_check(s, nm, Label.new(), Button.new(), Button.new())
			var lo := LineEdit.new()
			var mid := LineEdit.new()
			var hi := LineEdit.new()
			host.add_child(lo)
			host.add_child(mid)
			host.add_child(hi)
			lo.text = str(d._first_tick_for_rank(_t_pos(host, s)))
			hi.text = lo.text
			await w._on_widget_range_committed(s, lo, mid, hi)
		else:
			var rec: int = d._get_or_create_match_record_for_name(nm)
			await _do(host, rec, s, ["name_select"])
			await _do(host, d._find_match_record_by_name(nm), s, ["seq_typed"])
			await _do(host, d._find_match_record_by_name(nm), s, ["color_toggle"])
		d._full_propagation_refresh()
		await process_frame
		var r2: int = d._find_match_record_by_name(nm)
		var line: String = _record_readout(host, r2) if r2 >= 0 else "NO NAME RECORD"
		# pitch is not part of a map fact (needs Listen); compare the rest
		line = line.substr(0, line.find(" pitch="))   # also drops rep=
		print("  [%s] %s" % ["via map star" if via_map else "via Sort row", line])
		if via_map:
			sig_map = line
		else:
			sig_row = line
		host.queue_free()
	scenarios_judged += 1
	if sig_row == sig_map:
		scenarios_equal += 1
	ok(sig_row == sig_map, "naming a map star and pinning its position there reads like the same facts on the Sort row")


# ── E. facts split over two records, linked later ───────────────────────────
# Record 1 holds name+colour, record 2 holds position+pitch; telling the board
# record 2's name afterwards must leave exactly what one record holding all
# four would have.
func _family_link_later() -> void:
	print("\n=== E facts on two records, linked afterwards ===")
	var sigs: Array = []
	for split in [false, true]:
		var host = await _make_host()
		var d = host._deduction
		d._load_match_records([])
		var s: int = 2
		var nm: String = _t_name(host, s)
		if split:
			var r1: int = d._get_or_create_match_record_for_name(nm)
			await _do(host, r1, s, ["color_toggle"])
			var r2: int = d._get_or_create_match_record_for_seq(_t_pos(host, s))
			await _do(host, r2, s, ["pitch_check"])
			await _do(host, d._find_match_record_by_exact_seq(_t_pos(host, s)), s, ["name_check"])
		else:
			var r: int = d._get_or_create_match_record_for_name(nm)
			await _do(host, r, s, ["name_select"])
			await _do(host, d._find_match_record_by_name(nm), s, ["seq_typed"])
			await _do(host, d._find_match_record_by_name(nm), s, ["color_toggle"])
			await _do(host, d._find_match_record_by_name(nm), s, ["pitch_check"])
		d._full_propagation_refresh()
		await process_frame
		var views: Array = []
		var r3: int = d._find_match_record_by_name(nm)
		if r3 >= 0:
			views = _star_views(host, r3)
		print("  [%s] %s" % ["split then linked" if split else "one record", str(views)])
		sigs.append(str(views))
		host.queue_free()
	scenarios_judged += 1
	if sigs[0] == sigs[1]:
		scenarios_equal += 1
	ok(sigs[0] == sigs[1], "linking two records by name afterwards yields what one record would hold")


# ── H. the Repeats section on the new surfaces ─────────────────────────────
# The Staff popup and the Star Map widget edit the repeat-count axis too (added
# 2026-10-08). A repeat count entered on one record of a star must be what every
# other record of that star shows: the Sort row, the popup for its note, and the
# star's own widget record.
func _repeat_line(host, rec: int) -> String:
	var d = host._deduction
	var out: Array = []
	for v in d._get_repeat_bucket_values():
		out.append(d._effective_repeat_state(rec, int(v)))
	return str(out)


func _family_repeats() -> void:
	print("\n=== H Repeats on every surface ===")
	var s: int = 2
	var want: int = 1   # _repeat_count[2]
	# H1: entered on the Sort row, read on the popup for that note
	var host = await _make_host()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	var row: int = d._get_or_create_match_record_for_name(_t_name(host, s))
	await _do(host, row, s, ["name_select"])
	await _do(host, d._find_match_record_by_name(_t_name(host, s)), s, ["seq_typed"])
	w._on_repeat_checklist_check(d._find_match_record_by_name(_t_name(host, s)), want, null)
	d._full_propagation_refresh()
	var pop: int = d._get_or_create_match_record_for_melody_tick(d._first_tick_for_rank(_t_pos(host, s)))
	d._full_propagation_refresh()
	var r_row: String = _repeat_line(host, d._find_match_record_by_name(_t_name(host, s)))
	var r_pop: String = _repeat_line(host, pop)
	print("  Sort row: %s   Staff popup: %s" % [r_row, r_pop])
	scenarios_judged += 1
	var same1: bool = r_row == r_pop
	if same1:
		scenarios_equal += 1
	ok(same1, "H1 a repeat count entered on the Sort row shows on the Staff popup for that note")
	host.queue_free()

	# H2: entered on the popup, read on the Sort row
	var host2 = await _make_host()
	var d2 = host2._deduction
	var w2 = host2._widgets
	d2._load_match_records([])
	var tick: int = d2._first_tick_for_rank(_t_pos(host2, s))
	var pop2: int = d2._get_or_create_match_record_for_melody_tick(tick)
	w2._open_staff_popup(tick, Vector2.ZERO)
	w2._on_staff_repeat_check(pop2, want, null)
	var row2: int = d2._get_or_create_match_record_for_name(_t_name(host2, s))
	await _do(host2, row2, s, ["name_select"])
	await _do(host2, d2._find_match_record_by_name(_t_name(host2, s)), s, ["seq_typed"])
	d2._full_propagation_refresh()
	var r_row2: String = _repeat_line(host2, d2._find_match_record_by_name(_t_name(host2, s)))
	var r_pop2: String = _repeat_line(host2, d2._get_or_create_match_record_for_melody_tick(tick))
	print("  Sort row: %s   Staff popup: %s" % [r_row2, r_pop2])
	scenarios_judged += 1
	var same2: bool = r_row2 == r_pop2 and r_row2.contains("1")
	if same2:
		scenarios_equal += 1
	ok(same2, "H2 a repeat count entered on the Staff popup shows on the Sort row for that star")
	host2.queue_free()

	# H3: entered on the star's own widget record, read on the name row
	var host3 = await _make_host()
	var d3 = host3._deduction
	var w3 = host3._widgets
	d3._load_match_records([])
	await w3._on_name_check(s, _t_name(host3, s), Label.new(), Button.new(), Button.new())
	var star_rec: int = d3._get_or_create_match_record_for_star_idx(s)
	w3._repeat_toggle_confirm(star_rec, want)
	d3._full_propagation_refresh()
	var name_rec: int = d3._find_match_record_by_name(_t_name(host3, s))
	var r_name: String = _repeat_line(host3, name_rec)
	var r_star: String = _repeat_line(host3, d3._get_or_create_match_record_for_star_idx(s))
	print("  name record: %s   star widget record: %s" % [r_name, r_star])
	scenarios_judged += 1
	var same3: bool = r_name == r_star and r_name.contains("1")
	if same3:
		scenarios_equal += 1
	ok(same3, "H3 a repeat count entered on the star widget shows on the star's name row")
	host3.queue_free()


func run() -> void:
	await process_frame

	# ── A. full facts ──────────────────────────────────────────────────────
	var N := ["name_select"]
	var SQ := ["seq_typed"]
	var C := ["color_toggle"]
	var P := ["pitch_check"]
	var full: Array = [
		["name-row, name>seq>col>pitch", "name", [N, SQ, C, P]],
		["name-row, reversed", "name", [P, C, SQ, N]],
		["name-row, checker seq", "name", [N, ["seq_checker_only"], C, P]],
		["name-row, list seq + X-others colour/pitch", "name", [N, ["seq_list_decoy"], ["color_xothers"], ["pitch_xothers"]]],
		["seq-slot, name check", "seq", [SQ, ["name_check"], C, P]],
		["seq-slot, X-others name/colour/pitch", "seq", [SQ, ["color_xothers"], ["pitch_xothers"], ["name_xothers"]]],
		["colour-slot, name check", "color", [C, ["name_check"], SQ, P]],
		["colour-slot, checker seq", "color", [C, ["seq_checker_only"], ["name_check"], ["pitch_xothers"]]],
		["colour-slot, X-others everything", "color", [C, ["seq_list_decoy"], ["pitch_xothers"], ["name_xothers"]]],
	]
	for es in [[2], [0, 3], [1, 4, 5]]:
		await _compare("A full facts", es, full)

	# ── B. partial facts: the same narrowing, different widgets/order ───────
	# Positions: a candidate set via the list box == via the checker.
	var seq_set: Array = [
		["list {1,3,5}", "name", [["name_select"], ["seq_list", [1, 3, 5]]]],
		["checker off {2,4,6}", "name", [["name_select"], ["seq_checker_off", [2, 4, 6]]]],
		["checker off {6,4,2} (other order)", "name", [["name_select"], ["seq_checker_off", [6, 4, 2]]]],
		["list, then narrowed by checker to {1,3}", "name", [["name_select"], ["seq_list", [1, 3, 5]], ["seq_checker_off", [5]], ["seq_checker_on", [5]]]],
	]
	await _compare("B1 position set", [0, 2], seq_set)
	# Colours ruled out one at a time vs the other order.
	var col_set: Array = [
		["X colours 0,1", "name", [["name_select"], ["color_x", 0], ["color_x", 1]]],
		["X colours 1,0", "name", [["name_select"], ["color_x", 1], ["color_x", 0]]],
		["X colours 0,1 before naming", "name", [["color_x", 0], ["color_x", 1], ["name_select"]]],
	]
	await _compare("B2 colour set", [1, 4], col_set)
	# Names ruled out on a position slot, in different orders.
	var name_set: Array = [
		["X names a,b on seq slot", "seq", [["seq_typed"], ["name_x", "Keriion"], ["name_x", "Selion"]]],
		["X names b,a on seq slot", "seq", [["seq_typed"], ["name_x", "Selion"], ["name_x", "Keriion"]]],
		["X names first", "seq", [["name_x", "Keriion"], ["name_x", "Selion"], ["seq_typed"]]],
	]
	await _compare("B3 name set", [2, 5], name_set)
	# Notes ruled out.
	var note_set: Array = [
		["X note A4 then B4", "name", [["name_select"], ["pitch_x", "A4"], ["pitch_x", "B4"]]],
		["X note B4 then A4", "name", [["name_select"], ["pitch_x", "B4"], ["pitch_x", "A4"]]],
	]
	await _compare("B4 note set", [0, 4], note_set)

	# Repeat count (hidden axis): confirm vs rule out the others, and the same
	# fact entered before / after the other facts.
	var rep: Array = [
		["name-row, confirm repeat", "name", [["name_select"], ["seq_typed"], ["repeat_check"], ["color_toggle"]]],
		["name-row, X the other repeats", "name", [["name_select"], ["seq_typed"], ["repeat_xothers"], ["color_toggle"]]],
		["repeat first", "name", [["repeat_check"], ["name_select"], ["seq_typed"], ["color_toggle"]]],
		["colour-slot, repeat X-others, name check", "color", [["repeat_xothers"], ["color_toggle"], ["name_check"], ["seq_typed"]]],
		["seq-slot, repeat confirm, name check", "seq", [["seq_typed"], ["repeat_check"], ["name_check"], ["color_toggle"]]],
	]
	await _compare("A2 repeat count", [0], rep)
	await _compare("A2 repeat count", [2, 4], rep)

	# ── C. undo: enter then release must equal never having entered ─────────
	var undo: Array = [
		["never entered", "name", [["name_select"]]],
		["pin then release (seq undo)", "name", [["name_select"], ["seq_typed"], ["seq_undo"]]],
		["pin then restore all (checker)", "name", [["name_select"], ["seq_list", [1, 2]], ["seq_checker_on", [3, 4, 5, 6]]]],
		["colour toggle on then off", "name", [["name_select"], ["color_toggle"], ["color_toggle"]]],
		# pitch_check on-then-off is deliberately NOT here: un-confirming a note leaves its
		# siblings struck out ("eliminations are sticky", documented in
		# _on_pitch_checklist_check) and the popup has its own Undo row. Colour releases them.
		["X colour on then off", "name", [["name_select"], ["color_x", 3], ["color_x", 3]]],
		["X note on then off", "name", [["name_select"], ["pitch_x", "A4"], ["pitch_x", "A4"]]],
	]
	for es in [[2], [0, 3]]:
		await _compare("C undo", es, undo)

	await _family_staff_link()
	await _family_staff_to_row()
	await _family_repeats()
	await _family_location()
	await _family_link_later()

	print("\n  scenarios judged: %d, identical to baseline: %d, stars read: %d" % [scenarios_judged, scenarios_equal, stars_judged])
	ok(scenarios_judged >= 35, "enough scenarios were actually compared (%d) -- not a vacuous pass" % scenarios_judged)
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
