extends "res://dev_tests/test_base.gd"
# The Staff popup's note section follows the Entry switch (reported
# 2026-10-20: it kept the note buttons in Classic, while the Sort rows and the
# star popups switched).
#
#  - Checks: "Same star as note:" with a button per note.
#  - Classic: the three note boxes (lower < list < upper), the row the Sort
#    tabs show, writing the same marks.
#  - An entry in the boxes writes the marks and redraws the popup; leaving the
#    boxes unchanged (as closing the popup does) does not reopen it.
#
# Sets the mode in memory, not through the button: the button saves the
# player's own preference file.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _count(n: Node, cls: String) -> int:
	return n.find_children("*", cls, true, false).size()


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
	# Alpha fires on notes 1 and 6, Beta on 2 and 3, Gamma on 4, Delta on 5.
	host._melody_seq_pos_sequence = [1, 2, 2, 3, 4, 1]
	host._melody_star_sequence = [0, 1, 1, 2, 3, 0]
	host._repeat_count = [1, 1, 0, 0]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	ok(d._notes_hidden(), "precondition: a Beginner board (first notes hidden)")

	var was_loaded: bool = w._seq_checker_loaded
	var was_mode: bool = w._seq_checker_mode
	w._seq_checker_loaded = true

	print("=== Checks ===")
	w._seq_checker_mode = true
	w._open_staff_popup(2, Vector2(100, 100))
	var row = host._staff_popup._identity_row
	ok(row != null and _count(row, "Button") >= 5 and _count(row, "LineEdit") == 0,
		"the note section is a button per note (%d buttons, %d boxes)" % [_count(row, "Button") if row else 0, _count(row, "LineEdit") if row else 0])

	print("\n=== Classic ===")
	w._seq_checker_mode = false
	w._open_staff_popup(2, Vector2(100, 100))
	row = host._staff_popup._identity_row
	var edits: Array = row.find_children("*", "LineEdit", true, false) if row else []
	ok(edits.size() == 3, "the note section is the three note boxes (%d)" % edits.size())

	# Leaving the boxes unchanged must not reopen the popup.
	var before = host._staff_popup._identity_row
	(edits[0] as LineEdit).focus_exited.emit()
	await process_frame
	await process_frame
	ok(host._staff_popup._identity_row == before, "an unchanged box does not redraw or reopen the popup")

	# "=3" in the list: note 2's star also fires on note 3.
	(edits[1] as LineEdit).text = "=3"
	(edits[1] as LineEdit).text_submitted.emit("=3")
	for _i in 4:
		await process_frame
	var rec: int = d._find_match_record_by_melody_tick(2)
	ok(rec >= 0 and d._repeat_note_state_for_record(rec, 3) == 1, "the entry wrote the mark: note 3 is note 2's star")
	ok(host._staff_popup._identity_row != before and is_instance_valid(host._staff_popup._identity_row),
		"and the popup redrew itself")
	var edits2: Array = host._staff_popup._identity_row.find_children("*", "LineEdit", true, false)
	ok(edits2.size() == 3 and (edits2[1] as LineEdit).text.contains("=3"), "showing the entry back (%s)" % ((edits2[1] as LineEdit).text if edits2.size() == 3 else "-"))

	w._seq_checker_loaded = was_loaded
	w._seq_checker_mode = was_mode
	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
