extends "res://dev_tests/test_base.gd"
# Backstep must take back a name that joined two entries (reported 2026-10-31,
# The Hourglass): Thaloides was checked on the C#4 entry, the refresh folded
# that entry into Thaloides's row, and stepping back through the whole history
# left it there. The step held the name but never the merge.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const NAMES := ["Alpha", "Beta", "Gamma", "Delta"]
const NOTE_C5 := "C5"

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host():
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = NAMES.duplicate()
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37]
	host._star_pitch_index = [0, 1, 2, 3]
	host._sequence_rank_solution = [0, 1, 2, 3]
	# Alpha fires on notes 1 and 6, Beta on 2 and 3, Gamma on 4, Delta on 5.
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._melody_star_sequence = [0, 1, 1, 2, 3, 0]
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


## Every star Listened, and the rows the Sort tabs make as they draw. Name rows
## first, as on a real board: a merge keeps the earlier row, and which one
## survives is what this is about.
func _ready_board(host) -> void:
	var d = host._deduction
	for n in NAMES:
		d._get_or_create_match_record_for_name(n)
	for s in 4:
		await host._on_pitch_listen_star_clicked(s)
	for p in 4:
		d._get_or_create_match_record_for_pitch_slot(host._pitch_freqs[p], 0)
	d._full_propagation_refresh()


## Which star the board says Delta is, -1 for none.
func _delta_star(d) -> int:
	var r: int = d._find_match_record_by_name("Delta")
	return d._effective_star_idx(r) if r >= 0 else -1


func _back_to_start(d) -> void:
	for _i in 30:
		if not d.can_backstep():
			return
		d.board_step(false)


func run() -> void:
	print("=== the wrong name, then a placed note, then back ===")
	var host = await _host()
	var d = host._deduction
	var w = host._widgets
	await _ready_board(host)
	var rows_before: int = d.record_count()
	w._on_slot_name_check(d._find_match_record_by_star_idx(0), "Delta", null)
	await process_frame
	ok(_delta_star(d) == 0, "Delta is on star 0")
	ok(d.record_count() == rows_before - 1, "the name merged the two rows (%d -> %d)" % [rows_before, d.record_count()])
	await w._on_seq_note_select(d._find_match_record_by_star_idx(1), 2)
	await process_frame
	w._on_slot_name_x(d._find_match_record_by_star_idx(2), "Alpha", null)
	await process_frame
	_back_to_start(d)
	ok(_delta_star(d) != 0, "Backstep took Delta off star 0 (with a placed note in between)")
	ok(d.record_count() == rows_before, "the two rows are apart again (%d)" % d.record_count())
	var note_row: int = d._find_match_record_by_star_idx(1)
	ok((d.record_at(note_row).get("melody_ticks", []) as Array).has(2), "the placed note stayed where it was put")
	ok(d._find_match_record_by_star_idx(0) >= 0, "star 0 still has its row")
	var listened: int = 0
	for s in 4:
		var r2: int = d._find_match_record_by_star_idx(s)
		if r2 >= 0 and bool(d.record_at(r2).get("pitch_revealed", false)):
			listened += 1
	ok(listened == 4, "all 4 stars are still Listened (%d)" % listened)
	host.queue_free()
	await process_frame

	print("\n=== the wrong name, then only marks, then back ===")
	host = await _host()
	d = host._deduction
	w = host._widgets
	await _ready_board(host)
	w._on_slot_name_check(d._find_match_record_by_star_idx(0), "Delta", null)
	await process_frame
	w._on_slot_name_x(d._find_match_record_by_star_idx(2), "Alpha", null)
	await process_frame
	_back_to_start(d)
	ok(_delta_star(d) != 0, "Backstep took Delta off star 0 (marks only)")
	host.queue_free()
	await process_frame

	print("\n=== the wrong name is the last thing done ===")
	host = await _host()
	d = host._deduction
	w = host._widgets
	await _ready_board(host)
	w._on_slot_name_check(d._find_match_record_by_star_idx(0), "Delta", null)
	await process_frame
	ok(d._board_undo.size() == 1, "the name and its merge are one step (%d)" % d._board_undo.size())
	d.board_step(false)
	ok(_delta_star(d) != 0, "one Backstep takes it off")
	d.board_step(true)
	ok(_delta_star(d) == 0, "one Forward puts it back")
	d.board_step(false)
	ok(_delta_star(d) != 0, "and Backstep takes it off again")
	host.queue_free()
	await process_frame

	print("\n=== the history is saved with the merge in it ===")
	host = await _host()
	d = host._deduction
	w = host._widgets
	await _ready_board(host)
	w._on_slot_name_check(d._find_match_record_by_star_idx(0), "Delta", null)
	await process_frame
	var saved_rows: Array = d._save_match_records()
	var saved_undo: Array = d._board_undo.duplicate(true)
	d._load_match_records(saved_rows)
	d._load_board_history({"board_undo": saved_undo, "board_redo": [], "record_uid_next": d._next_record_uid})
	d._full_propagation_refresh()
	d.board_step(false)
	ok(_delta_star(d) != 0, "Backstep still takes it off after a reload")
	host.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
