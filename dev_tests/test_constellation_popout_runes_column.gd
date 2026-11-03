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
	ok(p._runes_slot_grid.get_parent() == right, "the Runes column has its own slot grid")

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
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
