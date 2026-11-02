extends "res://dev_tests/test_base.gd"
# The Staff Bar's readouts must not run into each other (reported 2026-11-01):
# a note's pitch sat at its height on a musical staff, so high notes landed on
# the name rows. Each readout now has its own row: names, pitch, line, numeral.
#
# Measured at the panel's minimum height, the tightest it gets, with the font it
# draws in. Whether it LOOKS right is a render, which headless cannot make.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

const PANEL_H: float = 80.0   # MelodyStaffPanel's custom_minimum_size
const PANEL_W: float = 741.0  # measured in the Study panel at 1280x720
const CAP_SHARE: float = 0.8  # of the ascent: how tall digits and capitals stand
const DOT_R: float = 5.0

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	var w = host._widgets
	var font: Font = ThemeDB.fallback_font

	print("=== each row clears the next, top to bottom ===")
	var low_name_bottom: float = w.NAME_ROW_LOW_DY + font.get_descent(w.FONT_SIZE_STAFF_NAME)
	var pitch_top: float = w.PITCH_ROW_DY - font.get_ascent(w.FONT_SIZE_STAFF_PITCH) * CAP_SHARE
	var line_y: float = (w.PITCH_ROW_DY + PANEL_H - w.NUMERAL_BLOCK_H) * 0.5
	var numeral_top: float = PANEL_H - w.NUMERAL_BASELINE_PAD - font.get_ascent(16) * CAP_SHARE
	ok(pitch_top >= low_name_bottom, "pitch clears the names (%.1f >= %.1f)" % [pitch_top, low_name_bottom])
	ok(line_y - DOT_R >= w.PITCH_ROW_DY, "the dot clears pitch (%.1f >= %.1f)" % [line_y - DOT_R, w.PITCH_ROW_DY])
	ok(line_y + DOT_R <= numeral_top, "the numeral clears the dot (%.1f <= %.1f)" % [line_y + DOT_R, numeral_top])
	ok(line_y - w.STAFF_DIVIDER_HALF_H >= w.PITCH_ROW_DY, "the dividers stay off pitch")
	ok(line_y + w.STAFF_DIVIDER_HALF_H <= numeral_top, "and off the numerals")

	print("\n=== pitch fits its column on every melody ===")
	var cd = load("res://constellation_data.gd").new()
	var judged: int = 0
	var longest: int = 0
	var tightest: int = w.FONT_SIZE_STAFF_PITCH
	var all_fit: bool = true
	for c in cd.BUILT_IN:
		var notes: int = (c.get("puzzle_sequence", []) as Array).size()
		if notes < 2:
			continue
		judged += 1
		longest = maxi(longest, notes)
		var step: float = (PANEL_W - 40.0) / float(notes - 1)
		var sz: int = w._staff_pitch_font_size(font, step)
		tightest = mini(tightest, sz)
		if font.get_string_size("G#4", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > step:
			all_fit = false
	ok(judged > 0, "%d melodies judged, the longest %d notes, smallest size %d" % [judged, longest, tightest])
	ok(all_fit, "no pitch is wider than its column")
	ok(w._staff_pitch_font_size(font, 60.0) == w.FONT_SIZE_STAFF_PITCH, "a roomy column keeps the full size")
	ok(w._staff_pitch_font_size(font, 20.0) < w.FONT_SIZE_STAFF_PITCH, "a narrow one shrinks it")

	host.queue_free()
	await process_frame
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
