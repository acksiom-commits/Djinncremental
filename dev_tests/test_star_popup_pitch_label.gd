extends "res://dev_tests/test_base.gd"
# The star popup's pitch label (reported 2026-10-16 on The Bellows: it read
# "PITCH" for a Listened star whose map tag showed D#4).
#
# A star can have two board entries the engine knows are the same star: the
# one Listen marked, and one the player named. The popup read only its own
# entry's Listened flag, and its entry was the named one. It now asks of the
# STAR (_pitch_earned_for_star), like the map tag. A star nobody Listened to
# still reads "PITCH".

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _popup_pitch(host, star: int) -> String:
	for l in (host._star_widgets[star] as Node).find_children("*", "Label", true, false):
		var t: String = (l as Label).text
		if t == "PITCH" or t in ["A4", "B4", "C5", "C#5"]:
			return t
	return ""


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
	host._star_map_control.size = Vector2(600, 400)
	host._star_screen_pos = [Vector2(150, 100), Vector2(450, 100), Vector2(150, 300), Vector2(450, 300)]
	host._widgets.clear_pitch_caches()
	var d = host._deduction
	d._load_match_records([])

	# Listen to Beta: that marks Beta's star entry.
	await host._on_pitch_listen_star_clicked(1)
	var listened: int = d._find_match_record_by_star_idx(1)
	# A second entry the player named Beta, tied to star 1 by ruling out every
	# other star: the board knows it is the same star, through the name.
	var named: int = d._get_or_create_match_record_for_name("Beta")
	d.record_at(named)["star_elim"] = {0: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	await process_frame
	host._widgets._build_star_widgets_impl()

	var popup_rec: int = d._get_or_create_match_record_for_star_idx(1)
	ok(d._effective_star_idx(named) == 1, "precondition: the named entry is tied to Beta's star (%d)" % d._effective_star_idx(named))
	ok(popup_rec != listened and not bool(d.record_at(popup_rec).get("pitch_revealed", false)),
		"precondition: the popup's own entry is not the Listened one (popup %d, Listened %d)" % [popup_rec, listened])
	ok(_popup_pitch(host, 1) == "B4", "Beta's popup shows its Listened pitch (got '%s')" % _popup_pitch(host, 1))
	ok(_popup_pitch(host, 0) == "PITCH", "a star nobody Listened to still reads PITCH (got '%s')" % _popup_pitch(host, 0))

	host.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
