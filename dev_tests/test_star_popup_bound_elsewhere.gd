extends "res://dev_tests/test_base.gd"
# Star Map popup name list (reported 2026-10-26 on The Archon): a popup open
# on an unnamed star still showed Keriion, Nyxaos, Nyxeai, Pyrios and Theryis
# as open, though each was already bound to a different star on the map.
#
# A name bound to one star is ruled out on every other star, whichever route
# bound it. Only the popup's own check route wrote that into the name's row;
# a name bound from a Sort:Name row or through Listen left every other
# star's popup showing it open.
#
# Three routes, one name each, then every (bound name x other star) popup
# cell is judged. Names nobody has placed must stay open on the stars nobody
# has placed, so a fix that leaks ground truth fails here too.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 6
	host._star_names = NAMES.duplicate()
	# Star 1 is the only Blue (3), so a Sort:Name row marked Blue is located.
	# Every other colour is shared, so nothing else locates by colour alone.
	host._star_colors = [0, 3, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 587.33, 659.25, 698.46]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	host._melody_seq_pos_sequence = [1, 2, 3, 4, 5, 6]
	host._repeat_count = [0, 0, 0, 0, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	# The map gives every star its own record the moment its widget renders,
	# before the player does anything. The game always has these.
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	d._full_propagation_refresh()

	var lbl := Label.new()
	var bc := Button.new()
	var bx := Button.new()
	host.add_child(lbl)
	host.add_child(bc)
	host.add_child(bx)

	# Route 1 — the star's own popup: check Alpha on star 0.
	await w._on_name_check(0, "Alpha", lbl, bc, bx)

	# Route 2 — a Sort:Name row: Beta's row marked Blue, which only star 1 is.
	var beta: int = d._get_or_create_match_record_for_name("Beta")
	d._full_propagation_refresh()
	await w._on_record_color_toggle(beta, 3, bc)

	# Route 3 — Listen on star 2, then name that Listened row Gamma from its
	# Sort-tab name checklist.
	await host._on_pitch_listen_star_clicked(2)
	var gamma_rec: int = d._find_match_record_by_star_idx(2)
	w._on_slot_name_check(gamma_rec, "Gamma", null)

	var bound := {"Alpha": 0, "Beta": 1, "Gamma": 2}

	# Setup check first: each name really is placed on its star as far as
	# the engine is concerned. A route that failed to bind would make every
	# popup assertion below meaningless.
	for nm in bound:
		var v: int = NAMES.find(nm)
		var row: Array = d._stars_possible_for_descriptor(ConstellationLogicPuzzle.Category.NAME, v)
		ok(row == [int(bound[nm])],
			"setup: the engine places %s on star %d only (row %s)" % [nm, int(bound[nm]), str(row)])

	var all_names: Array[String] = []
	for n in NAMES:
		all_names.append(str(n))

	var judged: int = 0
	var wrong: Array = []
	for nm in bound:
		for s in host._star_count:
			if s == int(bound[nm]):
				continue
			judged += 1
			var st: int = d._effective_name_display_state(s, str(nm), all_names)
			if st != 2:
				wrong.append("%s on star %d reads %d" % [nm, s, st])
	ok(wrong.is_empty(),
		"every bound name reads ruled out in every other star's popup (%d/%d cells; wrong: %s)"
			% [judged - wrong.size(), judged, str(wrong)])

	# Its own star must not read ruled out.
	var own_wrong: Array = []
	for nm in bound:
		if d._effective_name_display_state(int(bound[nm]), str(nm), all_names) == 2:
			own_wrong.append(str(nm))
	ok(own_wrong.is_empty(), "no bound name reads ruled out on its own star (%d judged; wrong: %s)"
		% [bound.size(), str(own_wrong)])

	# Soundness: unplaced names on unplaced stars stay open. Delta..Zeta are
	# truly stars 3..5, but the player has given nothing that says which.
	var open_judged: int = 0
	var closed: Array = []
	for nm in ["Delta", "Epsilon", "Zeta"]:
		for s in [3, 4, 5]:
			open_judged += 1
			var st2: int = d._effective_name_display_state(s, str(nm), all_names)
			if st2 != 0:
				closed.append("%s on star %d reads %d" % [nm, s, st2])
	ok(closed.is_empty(), "unplaced names stay open on unplaced stars (%d/%d cells; wrong: %s)"
		% [open_judged - closed.size(), open_judged, str(closed)])

	print("  judged %d bound-elsewhere cells, %d own-star cells, %d open cells"
		% [judged, bound.size(), open_judged])

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
