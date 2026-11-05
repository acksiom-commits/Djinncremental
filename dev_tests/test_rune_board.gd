extends "res://dev_tests/test_base.gd"
# The Rune inscription board (rune_board.gd).
#
#  - Each Beginner Rune uses the number of cells the author's prototype counted
#    (stars plus the cells their lines cross), and keeps it in every turn.
#  - Six sixth-turns come back to the start, and a click lands in the cell drawn.
#  - The 7-cell board takes the Triangle and both Arrows and nothing larger.
#  - Runes share a cell only where each has a star of the same colour there,
#    never share a line, and lifting one keeps the cell under the pointer.
#  - Runes sharing stars are reported as linked (link_groups()).
#  - The popout colours each Rune star as its constellation's Beginner puzzle
#    coloured that star, and greys it with no Beginner puzzle.

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
## Runes the popout lets the player pick: no more cells than the board's 7.
const USABLE := ["Triangle", "Right Arrow", "Left Arrow", "Spiked Less-Than"]

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
## Djinn's two being the player's Vessel's), greys those needing more than the
## board's 7 cells, and a click picks one up that a right-click then turns.
## The board starts empty with its 7 cells in the left column (2026-11-04),
## and the two columns take turns.
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
	var want: Array = USABLE.duplicate()
	want.sort()
	ok(open_names == want, "only Runes of 7 cells or fewer can be picked up: %s (got %s)" % [str(want), str(open_names)])

	pop.open()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	ok(pop.board.cells.is_empty() and pop.cells_left() == 7, "the board opens empty, 7 cells in the column")
	pop._on_stock_input(click)
	ok(pop.held_cell and pop.cells_left() == 6, "clicking the column takes a cell")
	var first_fit: int = -1
	for i in pop._entries.size():
		if bool(pop._entries[i]["fits"]):
			first_fit = i
			break
	pop._on_entry_input(click, first_fit)
	ok(pop.held.is_empty(), "while a cell is held, Runes can't be picked")
	pop._on_stock_input(click)
	ok(not pop.held_cell and pop.cells_left() == 7, "clicking the column again puts the cell back")
	pop._on_entry_input(click, first_fit)
	pop._on_stock_input(click)
	ok(not pop.held.is_empty() and not pop.held_cell, "while a Rune is held, cells can't be taken")
	pop.held = {}
	pop._refresh()
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

	# Star colours come from the constellation's Beginner puzzle (the Archon's
	# has 10 stars; Hard has 15). The live cache is put back afterwards.
	var cd: Node = root.get_node("/root/ConstellationData")
	var saved: Dictionary = cd.get_puzzle_cache(0)
	var tri: Dictionary = pop._entries[0]["rune"]
	cd.set_puzzle_cache(0, {"star_colors": [3, 2, 0, 1, 1, 1, 1, 1, 1, 1]})
	pop.open()
	ok(pop._entries[0]["star_colors"] == {0: 3, 1: 2, 2: 0},
		"%s's stars take the Beginner puzzle's colours on open (%s)" % [tri["name"], str(pop._entries[0]["star_colors"])])
	cd.set_puzzle_cache(0, {"star_colors": [3, 2, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]})
	ok(pop.rune_star_colors(0, tri).values().all(func(v): return v == Board.NO_COLOUR),
		"a Hard puzzle's colours are not used: its stars aren't the Rune's")
	cd.clear_puzzle_cache(0)
	ok(pop.rune_star_colors(0, tri).values().all(func(v): return v == Board.NO_COLOUR),
		"with no puzzle the stars have no colour")
	if not saved.is_empty():
		cd.set_puzzle_cache(0, saved)
	pop.close()
	pop.queue_free()
	await process_frame


## The player builds the board (2026-11-04): each cell touches one placed, stays
## inside the grid, and a cell lifts only with no Rune on it and without
## splitting the board. A 7-cell Rune fits a board shaped for it.
func _check_building(runes: Array) -> void:
	var area: Dictionary = {}
	for c in Board.hexagon(3):
		area[c] = true
	var b = Board.new(0, false)
	ok(b.cells.is_empty(), "an unfilled board starts with no cells")
	ok(not b.add_cell(Vector2i(8, 0), area), "a cell can't go off the grid")
	ok(b.add_cell(Vector2i(0, 0), area), "the first cell goes anywhere on the grid")
	ok(not b.add_cell(Vector2i(4, 0), area), "a cell that touches none is refused")
	ok(b.add_cell(Vector2i(2, 0), area) and b.add_cell(Vector2i(4, 0), area),
		"cells touching the board are set (a row of three)")
	ok(not b.can_remove_cell(Vector2i(2, 0)), "the middle of the row can't lift: it would split the board")
	ok(b.remove_cell(Vector2i(4, 0)) and b.cells.size() == 2, "an end of the row lifts")

	# A board shaped for the 7-cell Spiked Less-Than takes it; the hexagon doesn't.
	var spiked: Dictionary = _by_name(runes, "Spiked Less-Than")
	var shaped = Board.new(0, false)
	var own: Array[Vector2i] = Board.rune_cells(spiked)
	var order: Array = [own[0]]
	var left: Array = own.slice(1)
	while not left.is_empty():
		for c in left:
			if Board.neighbours(c).any(func(n): return order.has(n)):
				order.append(c)
				left.erase(c)
				break
	for c in order:
		shaped.add_cell(c)
	ok(shaped.cells.size() == 7, "the Spiked Less-Than's own 7 cells can be laid one touching the next")
	ok(shaped.place(spiked, own[0], 0, own[0]) == 0, "and the Rune fits the board shaped for it")
	ok(not Board.new(1).fits_empty(spiked), "while the old fixed hexagon could never take it")
	ok(not shaped.can_remove_cell(own[0]), "a cell under a Rune can't lift")


## Two Triangles on the 7-cell board can meet at one star of the same colour,
## and only then. A Triangle's three cells are all stars, so this exercises the
## colour rule and the shared-line rule on their own.
func _check_shared_stars(tri: Dictionary) -> void:
	var blue: Dictionary = {0: 0, 1: 0, 2: 0}
	var board = Board.new(1)
	var mid: Vector2i = Board.middle_cell(tri)
	board.place(tri, mid, 0, Vector2i.ZERO, blue)
	ok(board.placed.size() == 1, "test setup: a blue Triangle on the 7-cell board")
	ok(not board.can_place(tri, mid, 0, Vector2i.ZERO, blue),
		"a second Triangle can't sit on the first: they would share lines")

	# Every way a second blue Triangle can drop, by how many cells it shares.
	var by_shared: Dictionary = {}
	var one_star: Array = []
	for sixths in 6:
		for at in board.cells:
			if not board.can_place(tri, mid, sixths, at, blue):
				continue
			var shared: int = 0
			for c in Board.held_cells(tri, mid, sixths):
				if (board.placed[0]["cells"] as Array).has(at + c):
					shared += 1
			by_shared[shared] = int(by_shared.get(shared, 0)) + 1
			if shared == 1 and one_star.is_empty():
				one_star = [sixths, at]
	ok(by_shared.has(1) and by_shared.keys() == [1],
		"a second blue Triangle drops only sharing one star (%s, shared cells -> drops)" % str(by_shared))
	ok(not one_star.is_empty(), "test setup: found a one-star drop")
	if one_star.is_empty():
		return
	var sixths: int = one_star[0]
	var at: Vector2i = one_star[1]

	# Which of the second Triangle's stars lands on the shared cell.
	var on_shared: int = -1
	var rel: Dictionary = Board.held_stars(tri, mid, sixths)
	for s in rel:
		if (board.placed[0]["cells"] as Array).has(at + (rel[s] as Vector2i)):
			on_shared = s
	var red_there: Dictionary = blue.duplicate()
	red_there[on_shared] = 3
	ok(not board.can_place(tri, mid, sixths, at, red_there), "a red star can't share a blue star's cell")
	var unknown_there: Dictionary = blue.duplicate()
	unknown_there.erase(on_shared)
	ok(not board.can_place(tri, mid, sixths, at, unknown_there), "a star with no colour shares no cell")
	var red_elsewhere: Dictionary = {0: 3, 1: 3, 2: 3}
	red_elsewhere[on_shared] = 0
	ok(board.can_place(tri, mid, sixths, at, red_elsewhere),
		"only the shared star's colour matters (the other two are red)")

	ok(board.place(tri, mid, sixths, at, blue) == 1, "the second Triangle drops, sharing one blue star")
	ok(board.used_count() == 5, "the shared cell counts once: 5 of 7 cells used (%d)" % board.used_count())
	ok(board.link_groups() == [[0, 1]], "the two Triangles are linked (%s)" % str(board.link_groups()))
	var shared_cell: Vector2i = at + (rel[on_shared] as Vector2i)
	var lifted: Dictionary = board.take(shared_cell)
	ok(board.placed.size() == 1 and lifted["at"] == at,
		"clicking the shared star lifts the Triangle placed last")
	ok(board.link_groups().is_empty(), "with one Triangle left nothing is linked")


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
	ok(two == 1 and seven.used_count() == 3,
		"with no star colours, one Triangle at a time on the 7-cell board (%d placed)" % two)

	_check_shared_stars(tri)
	_check_building(runes)

	await _check_popout()

	print(("ALL PASS (%d failures)" if fails == 0 else "FAILURES (%d failures)") % fails)
	finish()
