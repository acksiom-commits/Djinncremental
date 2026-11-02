extends "res://dev_tests/test_base.gd"
# The Rune inscription board (rune_board.gd).
#
#  - Each Beginner Rune uses the number of cells the author's prototype counted
#    (stars plus the cells their lines cross), and keeps it in every turn.
#  - Six sixth-turns come back to the start, and a click lands in the cell drawn.
#  - The 7-cell board takes the Triangle and both Arrows and nothing larger.
#  - Runes never share a cell, and lifting one keeps the cell under the pointer.

const Board = preload("res://rune_board.gd")

## Cells per Rune, as the author's prototype counted them (2026-11-01).
const CELLS := {
	"Triangle": 3, "Right Arrow": 5, "Left Arrow": 5,
	"Sideways Question Mark": 11, "Inverted Sideways Question Mark": 11,
	"Spiked Less-Than": 7, "Reversed Angular C": 9,
	"Rectangle": 10, "Elongated M": 9,
	"Jar Cap": 8, "Jar Body": 11, "Upper Ring": 9, "Lower Ring": 11,
	"Lamp Body": 14, "Lamp Base": 10,
}
const FITS_SEVEN := ["Triangle", "Right Arrow", "Left Arrow"]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _all_runes(cd) -> Array:
	var out: Array = []
	for c in cd.BUILT_IN:
		if c.has("easy_layout"):
			out.append_array(c["easy_layout"].get("runes", []))
		if c.has("vessel_layouts"):
			for v in c["vessel_layouts"]:
				var layout = c["vessel_layouts"][v]
				if layout is Dictionary and layout.get("easy_layout") is Dictionary:
					out.append_array(layout["easy_layout"].get("runes", []))
	return out


func _by_name(runes: Array, nm: String) -> Dictionary:
	for r in runes:
		if str(r["name"]) == nm:
			return r
	return {}


## The popout lists every Beginner Rune of the six Sigils that have them (the
## Djinn's two being the player's Vessel's), greys all but the three that fit,
## and a click picks one up that a right-click then turns.
func _check_popout() -> void:
	await process_frame
	var pop = load("res://rune_fitting_popout.gd").new()
	root.add_child(pop)
	await process_frame
	ok(pop._entries.size() == 11, "the column lists 11 Runes (got %d)" % pop._entries.size())
	var open_names: Array = []
	for e in pop._entries:
		if bool(e["fits"]):
			open_names.append(str(e["rune"]["name"]))
	open_names.sort()
	var want: Array = FITS_SEVEN.duplicate()
	want.sort()
	ok(open_names == want, "only %s can be picked up (got %s)" % [str(want), str(open_names)])

	pop.open()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var big: int = -1
	var arrow: int = -1
	for i in pop._entries.size():
		if not bool(pop._entries[i]["fits"]):
			big = i
		elif str(pop._entries[i]["rune"]["name"]) == "Right Arrow":
			arrow = i
	pop._on_entry_input(click, big)
	ok(pop.held.is_empty(), "clicking a greyed Rune picks nothing up")
	pop._on_entry_input(click, arrow)
	ok(not pop.held.is_empty() and str(pop.held["rune"]["name"]) == "Right Arrow", "clicking the Right Arrow puts it on the pointer")
	var turn := InputEventMouseButton.new()
	turn.button_index = MOUSE_BUTTON_RIGHT
	turn.pressed = true
	pop._input(turn)
	pop._input(turn)
	ok(int(pop.held["sixths"]) == 2, "two right-clicks turn it two sixths")
	pop.close()
	ok(pop.held.is_empty() and not pop.visible, "closing lets go and hides the panel")
	pop.queue_free()
	await process_frame


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var runes: Array = _all_runes(cd)
	ok(runes.size() == CELLS.size(), "%d Runes found, %d expected" % [runes.size(), CELLS.size()])

	print("\n  cells per Rune (stars + crossed), every turn:")
	var judged: int = 0
	for r in runes:
		var nm: String = str(r["name"])
		var n: int = Board.rune_cells(r).size()
		var turns_ok: bool = true
		for sixths in 6:
			if Board.held_cells(r, Board.middle_cell(r), sixths).size() != n:
				turns_ok = false
		print("    %-32s %2d  (author %s)" % [nm, n, str(CELLS.get(nm, "?"))])
		ok(n == int(CELLS.get(nm, -1)), "%s uses %d cells" % [nm, n])
		ok(turns_ok, "%s keeps its cell count in all six turns" % nm)
		judged += 1
	print("  judged %d of %d Runes" % [judged, runes.size()])

	var spun: int = 0
	for c in Board.hexagon(3):
		if Board.rotated(c, 6) == c and Board.rotated(c, 1) != c or c == Vector2i.ZERO:
			spun += 1
	ok(spun == 37, "six turns return every cell of a 37-cell board, one turn moves all but the centre (%d/37)" % spun)
	ok(Board.rotated(Vector2i(2, 0), 1) == Vector2i(1, 1), "a sixth turn takes east to down-right (clockwise on screen)")

	var landed: int = 0
	for c in Board.hexagon(3):
		var p: Vector2 = Board.cell_point(c, 40.0)
		if Board.point_cell(p + Vector2(7.0, -9.0), 40.0) == c:
			landed += 1
	ok(landed == 37, "a click near a cell's centre lands in that cell (%d/37)" % landed)

	ok(Board.hexagon(1).size() == 7 and Board.hexagon(2).size() == 19 and Board.hexagon(3).size() == 37,
		"hexagon boards hold 7, 19 and 37 cells")

	var seven = Board.new(1)
	var fit_names: Array = []
	for r in runes:
		if seven.fits_empty(r):
			fit_names.append(str(r["name"]))
	fit_names.sort()
	var want: Array = FITS_SEVEN.duplicate()
	want.sort()
	ok(fit_names == want, "the 7-cell board fits exactly %s (got %s)" % [str(want), str(fit_names)])

	var tri: Dictionary = _by_name(runes, "Triangle")
	var arrow: Dictionary = _by_name(runes, "Right Arrow")
	var mid: Vector2i = Board.middle_cell(arrow)
	var placed_at: Vector2i = Vector2i.ZERO
	var placed_turn: int = -1
	for sixths in 6:
		for at in seven.cells:
			if placed_turn < 0 and seven.can_place(arrow, mid, sixths, at):
				placed_at = at
				placed_turn = sixths
	ok(seven.place(arrow, mid, placed_turn, placed_at) == 0, "an Arrow drops on the empty 7-cell board")
	ok(seven.used_count() == 5, "the Arrow uses 5 of the 7 cells")
	var tri_fits: bool = false
	for sixths in 6:
		for at in seven.cells:
			if seven.can_place(tri, Board.middle_cell(tri), sixths, at):
				tri_fits = true
	ok(not tri_fits, "no Triangle fits beside the Arrow (it would share a cell)")

	var lifted_cell: Vector2i = seven.placed[0]["cells"][3]
	var lifted: Dictionary = seven.take(lifted_cell)
	ok(not lifted.is_empty() and seven.used_count() == 0, "clicking the Arrow lifts it off")
	ok(seven.can_place(arrow, lifted["anchor"], int(lifted["sixths"]), lifted_cell),
		"the lifted Arrow drops back where it was, held by the clicked cell")
	seven.place(arrow, lifted["anchor"], int(lifted["sixths"]), lifted_cell)
	ok(seven.used_count() == 5 and (seven.placed[0]["cells"] as Array).has(lifted_cell),
		"and covers the same cells again")
	seven.clear()

	var two: int = 0
	for sixths in 6:
		for at in seven.cells:
			if seven.place(tri, Board.middle_cell(tri), sixths, at) >= 0:
				two += 1
	# Three cells that all touch, on a 7-cell board, always include the centre.
	ok(two == 1 and seven.used_count() == 3, "one Triangle at a time on the 7-cell board (%d placed)" % two)

	await _check_popout()

	print(("ALL PASS (%d failures)" if fails == 0 else "FAILURES (%d failures)") % fails)
	finish()
