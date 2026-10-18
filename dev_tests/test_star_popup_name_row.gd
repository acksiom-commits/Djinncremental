extends "res://dev_tests/test_base.gd"
# The star popup's name list (reported 2026-10-17 on The Bellows): confirming
# a name in a star's popup left every other name in that popup open.
#
# A star has one name. Once a name is confirmed on a star, the popup must show
# every other name ruled out on that star, and the confirmed name ruled out on
# every other star (that half already held). The player's own check or cross
# on a name still decides that name.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

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
	host._star_count = 4
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = [1, 2, 3, 4]
	host._repeat_count = [0, 0, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	d._load_match_records([])

	# The popup's own controls, as the star widget passes them.
	var lbl := Label.new()
	var bc := Button.new()
	var bx := Button.new()
	host.add_child(lbl)
	host.add_child(bc)
	host.add_child(bx)
	await host._widgets._on_name_check(0, "Alpha", lbl, bc, bx)

	ok(d._star_elim_state(0, "Alpha") == 1, "Alpha reads confirmed on star 0")
	var row: Array = []
	for nm in ["Beta", "Gamma", "Delta"]:
		row.append(d._star_elim_state(0, nm))
	ok(row == [2, 2, 2], "every other name reads ruled out on star 0 (got %s)" % str(row))
	var col: Array = []
	for s in [1, 2, 3]:
		col.append(d._star_elim_state(s, "Alpha"))
	ok(col == [2, 2, 2], "Alpha reads ruled out on every other star (got %s)" % str(col))
	ok(d._star_elim_state(1, "Beta") == 0, "an untouched name on another star stays open (got %d)" % d._star_elim_state(1, "Beta"))
	var all_names: Array[String] = ["Alpha", "Beta", "Delta", "Gamma"]
	ok(d._effective_name_display_state(0, "Beta", all_names) == 2, "and the popup draws Beta as ruled out on star 0")

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
