extends "res://dev_tests/test_base.gd"
# The number beside each note in the pitch popups (the Sort entries' pitch
# checklist and the Staff note popup), 2026-10-16, author:
#
#  - On a repeating (Beginner) melody it is how many times the note FIRES. It
#    used to count the stars playing the note, which on Beginner is always 1.
#  - It waits for Listen like the repeat count on the star tags: "(?)" until
#    every star playing the note has been Listened.
#  - On a 1:1 (Hard) melody it still counts stars, which there is also the
#    number of firings, and needs no Listen.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const RowScript = preload("res://staff_popup_row.gd")

const FREQS := [440.0, 493.88, 523.25, 554.37]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _host(melody: Array, pitch_index: Array, repeats: Array):
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 4
	host._star_names = ["Alpha", "Beta", "Gamma", "Delta"]
	host._star_colors = [0, 1, 2, 3]
	host._star_degrees = [2, 2, 2, 2]
	host._pitch_freqs = FREQS.duplicate()
	host._star_pitch_index = pitch_index
	host._sequence_rank_solution = [0, 1, 2, 3]
	host._melody_seq_pos_sequence = melody
	host._repeat_count = repeats
	host._widgets.clear_pitch_caches()
	host._deduction._load_match_records([])
	return host


func _note(i: int) -> String:
	return PuzzleScript.note_name_for_freq(float(FREQS[i]))


func _row_counts(popup: Node) -> Dictionary:
	var out: Dictionary = {}
	for n in popup.find_children("*", "", true, false):
		if n.get_script() == RowScript and not n.is_queued_for_deletion():
			out[str(n.label_text)] = str(n._count_label.text)
	return out


func run() -> void:
	print("=== a repeating melody: firings, once Listened ===")
	# Alpha and Beta fire twice, Gamma and Delta once: 6 notes.
	var host = await _host([1, 2, 2, 3, 4, 1], [0, 1, 2, 3], [1, 1, 0, 0])
	var d = host._deduction
	var unknown_before: int = 0
	for i in 4:
		if d._pitch_row_count(_note(i)) == -1:
			unknown_before += 1
	ok(unknown_before == 4, "before any Listen every note's count is unknown (%d of 4)" % unknown_before)
	await host._on_pitch_listen_star_clicked(0)
	ok(d._pitch_row_count(_note(0)) == 2, "after Listening to Alpha its note shows 2 firings (got %d)" % d._pitch_row_count(_note(0)))
	ok(d._pitch_row_count(_note(1)) == -1, "Beta's note stays unknown until Beta is Listened (got %d)" % d._pitch_row_count(_note(1)))
	for s in [1, 2, 3]:
		await host._on_pitch_listen_star_clicked(s)
	var got: Array = []
	var total: int = 0
	for i2 in 4:
		got.append(d._pitch_row_count(_note(i2)))
		total += int(got[i2])
	ok(got == [2, 2, 1, 1], "every note shows how many times it fires (got %s)" % str(got))
	ok(total == 6, "the counts add up to the melody's notes (%d of 6)" % total)

	print("\n=== what the popup shows ===")
	var host2 = await _host([1, 2, 2, 3, 4, 1], [0, 1, 2, 3], [1, 1, 0, 0])
	var d2 = host2._deduction
	await host2._on_pitch_listen_star_clicked(0)
	var rec: int = d2._get_or_create_match_record_for_star_idx(0)
	host2._widgets._open_pitch_checklist_popup(rec, Vector2(100, 100))
	var shown: Dictionary = _row_counts(host2._pitch_checklist_popup)
	ok(shown.size() == 4, "the pitch checklist has a row per note (%d)" % shown.size())
	ok(str(shown.get(_note(0), "")) == "(2)", "Alpha's note reads (2) (got %s)" % str(shown.get(_note(0), "")))
	ok(str(shown.get(_note(1), "")) == "(?)", "an un-Listened note reads (?) (got %s)" % str(shown.get(_note(1), "")))

	print("\n=== a 1:1 melody: stars, with or without Listen ===")
	# Alpha and Beta share the first note.
	var host3 = await _host([1, 2, 3, 4], [0, 0, 1, 2], [0, 0, 0, 0])
	var d3 = host3._deduction
	ok(d3._pitch_row_count(_note(0)) == 2, "a note two stars play reads 2 before any Listen (got %d)" % d3._pitch_row_count(_note(0)))
	ok(d3._pitch_row_count(_note(1)) == 1, "a note one star plays reads 1 (got %d)" % d3._pitch_row_count(_note(1)))

	host.queue_free()
	host2.queue_free()
	host3.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
