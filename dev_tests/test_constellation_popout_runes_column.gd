extends "res://dev_tests/test_base.gd"
# The Constellation slideout's Runes column (2026-11-02, author): the panel
# grew to the right so a second column, a layout shell to be built out like
# the Constellation one, sits beside it. Its button opens the Rune fitting
# board, which draws over the slideout and leaves it open behind it.

const PopoutScene = preload("res://ConstellationPopout.tscn")
const RuneFittingPopout = preload("res://rune_fitting_popout.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame  # autoloads unreachable from root before one frame
	var p = PopoutScene.instantiate()
	root.add_child(p)
	var board: Control = RuneFittingPopout.new()
	root.add_child(board)
	p.set_rune_board(board)
	for i in 3:
		await process_frame

	print("=== the panel holds two columns side by side ===")
	ok(is_equal_approx(p._panel.size.x, p.PANEL_WIDTH),
		"PANEL_WIDTH is the panel's real width (%.0f)" % p._panel.size.x)
	var left: Control = p.get_node(p.PANEL_BASE_PATH)
	var right: Control = p.get_node(p.RUNES_BASE_PATH)
	ok(right.global_position.x > left.global_position.x + left.size.x,
		"the Runes column is right of the Constellation column")
	ok(absf(left.size.x - right.size.x) <= 1.0,  # an odd leftover pixel
		"the columns are the same width (%.0f, %.0f)" % [left.size.x, right.size.x])
	ok(left.size.x >= 330.0, "the Constellation column kept its width (%.0f)" % left.size.x)
	ok(p._slot_grid.get_parent() == left and p._title_label.get_parent() == left,
		"the Constellation slot grid and title are still found")
	ok(right.get_node_or_null("RunesSlotGrid") is GridContainer, "the Runes column has its own slot grid")

	print("\n=== the Runes button opens the board over the open slideout ===")
	p._on_tab_pressed()
	for i in 20:
		await process_frame
	ok(not board.visible, "test setup: the board starts closed")
	p._inscribe_runes_btn.pressed.emit()
	ok(board.visible, "the Inscribe Runes button opens the board")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.global_position = Vector2(1000, 300)  # outside the slideout
	p._input(click)
	ok(p._is_open, "a click on the board leaves the slideout open")
	board.close()
	p._input(click)
	for i in 20:
		await process_frame
	ok(not p._is_open, "with the board closed, a click outside still closes the slideout")

	p.queue_free()
	board.queue_free()

	print("\n=== Firmament has the slideout where Primordial has it ===")
	# 2026-11-03: same left-edge column, under the Ages tab and a 100 px gap,
	# with the Runes column wired to Firmament's own Rune board.
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	for i in 5:
		await process_frame
	var fp: Control = firm.find_child("ConstellationPopout", true, false)
	ok(fp != null, "FirmamentUI has a ConstellationPopout")
	if fp:
		var names: Array = []
		for c in fp.get_parent().get_children():
			names.append(str(c.name))
		ok(str(fp.get_parent().name) == "LeftEdgePopoutsVBox"
			and names == ["AgesPopout", "LeftPlaceholder1", "ConstellationPopout"],
			"it sits in the left edge column after Ages and the gap, as on Primordial (%s)" % str(names))
		ok(fp._rune_board != null and str(fp._rune_board.name) == "RuneFittingPopout",
			"its Runes column opens Firmament's Rune board")
		ok(is_equal_approx(fp._tab_btn.get_global_rect().position.x, 0.0),
			"its tab is on the window's left edge (x %.0f)" % fp._tab_btn.get_global_rect().position.x)
		# 2026-11-03: with its scene minimum (195) the column needed 478 px and
		# grew the top band past its 400, pushing the card row down 78 px. The
		# band only shows its real height with a save loaded, so compare minimums.
		var band: Control = firm.find_child("FirmTopBandHBox", true, false)
		var column_min: float = fp.get_parent().get_combined_minimum_size().y
		ok(column_min <= band.custom_minimum_size.y,
			"the left-edge column (min %.0f) doesn't make the top band taller than its %.0f"
				% [column_min, band.custom_minimum_size.y])

		# 2026-11-03: the Constellation box under the dial works as on
		# Primordial: picking shows the constellation there and loads its
		# puzzle through the shared pipeline; Study opens it; RESET resets it.
		var box: Node = firm.find_child("ConstellationPanel", true, false)
		ok(box != null and str(box.get_parent().get_parent().name) == "MidBandHBox",
			"Firmament has the Constellation box, left of the card row")
		var picks: Array = []
		for c in fp.constellation_selected.get_connections():
			picks.append(c["callable"].get_method())
		ok(picks.has("on_constellation_selected") and picks.has("select"),
			"picking a constellation goes to the box and the puzzle pipeline (%s)" % str(picks))
		var study: Node = firm.get_node_or_null("ConstellationStudyOverlay")
		ok(study != null and study.reset_requested.get_connections().size() == 1,
			"the Study overlay is on the page and its RESET is connected")
		# 2026-11-03: the tab runs down beside the middle band (from y 440 with
		# a save loaded), which took the mouse there first, so the tab's lower
		# half ignored hover and clicks. The band is layout only.
		var mid: Control = firm.find_child("MidBandHBox", true, false)
		ok(mid != null and mid.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the middle band leaves the mouse to the tab beside it")
		var sky: Node = firm.get_node_or_null("ConstellationOverlay")
		ok(sky != null and sky._synth != null and study != null and study._synth != null,
			"the sky overlay and Study overlay find the page's synth")
	firm.queue_free()
	await process_frame

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
