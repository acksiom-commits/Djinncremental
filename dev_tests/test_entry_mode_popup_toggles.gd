extends "res://dev_tests/test_base.gd"
# The Entry switch (Classic / Checks) in the popups (2026-10-28, author: the
# design aim is to reduce menu switching). The Star Map popup and the Staff
# popup each carry a button that flips the SAME setting as the Markers bar's
# "Entry:" button, and redraw in place.
#
#  - Star Map popup: the button leads the Sequence line; pressing it swaps
#    the typed boxes for a button per note, and back.
#  - Staff popup: the button sits beside the title on a board whose note
#    section follows the switch (first notes hidden), and redraws that
#    section; hidden on a 1:1 melody, where nothing in the popup follows it.
#  - The Markers bar's button reads the new style after either press.
#
# Pressing the button saves the player's preference file, so its bytes are
# put back afterwards.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## Visible ones only: the checker row keeps three hidden LineEdits as plumbing
## for its handlers (_make_sequence_checker_row_for_record).
func _count(n: Node, cls: String) -> int:
	if n == null:
		return -1
	var c: int = 0
	for x in n.find_children("*", cls, true, false):
		if (x as Control).visible:
			c += 1
	return c


func _button_named(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func run() -> void:
	var prefs_path: String = "user://study_prefs.cfg"
	var had_prefs: bool = FileAccess.file_exists(prefs_path)
	var prefs_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prefs_path) if had_prefs else PackedByteArray()

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
	host._star_screen_pos = [Vector2(50, 50), Vector2(150, 50), Vector2(50, 150), Vector2(150, 150)]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	var w = host._widgets
	d._load_match_records([])
	ok(d._notes_hidden(), "precondition: a Beginner board (first notes hidden)")

	w._seq_checker_loaded = true
	w._seq_checker_mode = false
	# The bar was labelled from the player's saved preference in _ready.
	host._refresh_seq_mode_button()
	if host._seq_mode_btn != null:
		ok(host._seq_mode_btn.text == "Entry: Classic", "precondition: the Markers bar reads Classic")

	print("=== Star Map popup ===")
	w._build_star_widgets_impl()
	var widget: Node = host._star_widgets[0]
	var btn: Button = _button_named(widget, "Classic")
	ok(btn != null, "the star popup carries a Classic button in Classic")
	ok(_count(widget, "LineEdit") == 3, "Classic: the Sequence line is the three note boxes (%d)" % _count(widget, "LineEdit"))
	if btn != null:
		btn.pressed.emit()
	await process_frame
	await process_frame
	ok(w._seq_checker_enabled(), "pressing it switches Entry to Checks")
	widget = host._star_widgets[0]
	ok(_button_named(widget, "Checks") != null, "the rebuilt star popup's button reads Checks")
	ok(_count(widget, "LineEdit") == 0, "Checks: no note boxes left (%d)" % _count(widget, "LineEdit"))
	if host._seq_mode_btn != null:
		ok(host._seq_mode_btn.text == "Entry: Checks", "the Markers bar follows (%s)" % host._seq_mode_btn.text)

	print("\n=== Staff popup ===")
	w._open_staff_popup(2, Vector2(100, 100))
	var sp = host._staff_popup
	ok(sp._entry_mode_btn != null and sp._entry_mode_btn.visible and sp._entry_mode_btn.text == "Checks",
		"the Staff popup shows the switch, reading Checks")
	ok(_count(sp._identity_row, "Button") >= 5 and _count(sp._identity_row, "LineEdit") == 0,
		"Checks: a button per note (%d buttons)" % _count(sp._identity_row, "Button"))
	sp.entry_mode_pressed.emit()
	await process_frame
	ok(not w._seq_checker_enabled(), "pressing it switches Entry back to Classic")
	ok(sp._entry_mode_btn.text == "Classic", "the popup's button reads Classic (%s)" % sp._entry_mode_btn.text)
	ok(_count(sp._identity_row, "LineEdit") == 3,
		"Classic: the note section is redrawn as the three boxes (%d)" % _count(sp._identity_row, "LineEdit"))
	ok(sp.current_tick == 2, "still the popup for note 2 (%d)" % sp.current_tick)
	if host._seq_mode_btn != null:
		ok(host._seq_mode_btn.text == "Entry: Classic", "the Markers bar follows (%s)" % host._seq_mode_btn.text)
	ok(_button_named(host._star_widgets[0], "Classic") != null, "the star popup follows too")

	print("\n=== 1:1 melody ===")
	host._melody_seq_pos_sequence = [1, 2, 3, 4]
	host._melody_star_sequence = [0, 1, 2, 3]
	host._repeat_count = [0, 0, 0, 0]
	ok(not d._notes_hidden(), "precondition: nothing hidden")
	w._open_staff_popup(2, Vector2(100, 100))
	ok(not sp._entry_mode_btn.visible, "the Staff popup hides the switch: nothing in it follows Entry")

	host.queue_free()
	await process_frame
	if had_prefs:
		var f := FileAccess.open(prefs_path, FileAccess.WRITE)
		f.store_buffer(prefs_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs_path))
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
