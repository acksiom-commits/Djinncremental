extends "res://dev_tests/test_base.gd"
# Firmament's card row (carousel.gd, 2026-11-04): three cards show at a time,
# and arrow buttons below step it one card each way. Click-and-drag scrolling
# was replaced as too finicky.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## Cards wholly inside the carousel, and cards only partly inside, by index.
func _showing(car: Control) -> Array:
	var whole: Array = []
	var part: int = 0
	for i in car.panels.size():
		var x: float = car.panels[i].position.x
		var w: float = car.panel_width
		if x >= -0.5 and x + w <= car.size.x + 0.5:
			whole.append(i)
		elif x + w > 0.5 and x < car.size.x - 0.5:
			part += 1
	whole.sort_custom(func(a, b): return car.panels[a].position.x < car.panels[b].position.x)
	return [whole, part]


func _settle() -> void:
	# By time, not frames: headless runs are not held to 60 fps.
	await root.get_tree().create_timer(1.5).timeout


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	await _settle()
	var car: Control = firm.find_child("Carousel", true, false)
	var left: Button = firm.find_child("LeftArrowButton", true, false)
	var right: Button = firm.find_child("RightArrowButton", true, false)

	print("=== three cards show ===")
	var s: Array = _showing(car)
	ok(is_equal_approx(car.size.x, car.visible_width()) and s[0].size() == 3 and s[1] == 0,
		"three whole cards and no cut-off ones (%s, %d cut off, %.0f px wide)" % [str(s[0]), s[1], car.size.x])
	ok(car.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the row no longer takes drags")

	print("\n=== the arrows step one card ===")
	ok(left != null and right != null and left.get_global_rect().position.y > car.get_global_rect().end.y,
		"the arrow buttons sit below the cards")
	var first: int = s[0][0]
	var second: int = s[0][1]
	right.pressed.emit()
	await _settle()
	s = _showing(car)
	ok(s[0].size() == 3 and s[0][0] == second, "the right arrow brings in the next card (first is now %s)" % str(s[0]))
	left.pressed.emit()
	await _settle()
	s = _showing(car)
	ok(s[0].size() == 3 and s[0][0] == first, "the left arrow goes back (%s)" % str(s[0]))
	right.pressed.emit()
	right.pressed.emit()
	await _settle()
	s = _showing(car)
	ok(s[0][0] == (first + 2) % car.PANEL_COUNT, "two quick clicks move two cards")

	print("\n=== the loop holds up both ways ===")
	var good: int = 0
	for k in 25:
		right.pressed.emit()
		await process_frame
	await _settle()
	if _showing(car)[0].size() == 3 and _showing(car)[1] == 0:
		good += 1
	for k in 60:
		left.pressed.emit()
		await process_frame
	await _settle()
	s = _showing(car)
	if s[0].size() == 3 and s[1] == 0:
		good += 1
	ok(good == 2, "after 25 right and 60 left clicks, still three whole cards (%s)" % str(s[0]))
	ok(absf(car.target_offset) <= (car.panel_width + car.panel_spacing) * car.PANEL_COUNT,
		"the offset stays within one loop (%.0f)" % car.target_offset)

	firm.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
