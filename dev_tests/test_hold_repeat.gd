extends "res://dev_tests/test_base.gd"
# hold_repeat.gd: holding an assignment +/- button keeps assigning — one step
# on press, a pause of INITIAL_DELAY, then repeats that speed up from
# REPEAT_START to REPEAT_MIN. Then the wiring: the allocation wheel repeats on
# Uonite and Focus, the Constellation popout on Focus. Volitions on both stay
# one click per Volition by design.
#
# Timing part: a bare helper drives a real Button that IS in the tree. The
# action is a counter rather than an assignment handler — the assignment
# arithmetic is unchanged by this feature; only how often it fires is new.
#
# The press is a stand-in. A mouse event pushed into root (64x64 here) never
# reached the button headless, so _mouse() reproduces what the repeat code
# reads instead: is_pressed() via toggle mode, plus button_down/button_up.
# The headless mouse sits at (0,0), inside the button, so the drag-off pause
# is NOT exercised here.
const HoldRepeat = preload("res://hold_repeat.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _mouse(btn: Button, btn_pressed: bool) -> void:
	btn.set_pressed_no_signal(btn_pressed)
	if btn_pressed:
		btn.button_down.emit()
	else:
		btn.button_up.emit()


## Steps the repeat for `seconds` of simulated time, returns fires seen.
func _hold_for(hold, calls: Array, seconds: float, dt: float = 1.0 / 60.0) -> int:
	var before: int = calls.size()
	var t: float = 0.0
	while t < seconds - 0.0001:
		hold.tick(dt)
		t += dt
	return calls.size() - before


func _wired(btn) -> bool:
	return btn != null and btn.button_down.get_connections().size() > 0


func run() -> void:
	var hold = HoldRepeat.new()
	var btn := Button.new()
	btn.position = Vector2.ZERO
	btn.size = Vector2(40, 40)
	btn.toggle_mode = true
	root.add_child(btn)
	await process_frame

	var calls: Array = []
	hold.connect_button(btn, func(): calls.append(1))

	print("=== press fires once, immediately ===")
	_mouse(btn, true)
	ok(btn.is_pressed(), "the button reads as pressed (precondition)")
	ok(calls.size() == 1, "one step on press (got %d)" % calls.size())
	ok(hold._button == btn, "the hold is tracked")

	print("\n=== nothing repeats inside the initial delay ===")
	var early: int = _hold_for(hold, calls, HoldRepeat.INITIAL_DELAY - 0.05)
	ok(early == 0, "no repeat in the first %.2fs (got %d)" % [HoldRepeat.INITIAL_DELAY - 0.05, early])
	var first: int = _hold_for(hold, calls, 0.1)
	ok(first == 1, "first repeat lands at the delay (got %d)" % first)

	print("\n=== repeats accelerate ===")
	var slow: int = _hold_for(hold, calls, 1.0)
	_hold_for(hold, calls, 1.0)
	var fast: int = _hold_for(hold, calls, 1.0)
	print("    fires/sec just after the delay: %d   once ramped: %d" % [slow, fast])
	ok(slow >= 4 and slow < fast, "ramped rate beats the starting rate")
	ok(fast <= int(ceil(1.0 / HoldRepeat.REPEAT_MIN)), "never faster than REPEAT_MIN (got %d/s)" % fast)

	print("\n=== a slow frame fires one step, not a burst ===")
	var burst: int = _hold_for(hold, calls, 1.0, 1.0)
	ok(burst == 1, "one 1-second frame fires once (got %d)" % burst)

	print("\n=== release ends the hold ===")
	_mouse(btn, false)
	ok(hold._button == null, "button_up cleared the hold")
	ok(_hold_for(hold, calls, 1.0) == 0, "no fires after release")

	print("\n=== a pool running dry (button disabled) ends the hold ===")
	_mouse(btn, true)
	var n: int = calls.size()
	btn.disabled = true
	ok(_hold_for(hold, calls, 1.0) == 0, "no fires once disabled")
	ok(hold._button == null, "hold dropped on disable")
	btn.disabled = false
	ok(_hold_for(hold, calls, 1.0) == 0, "re-enabling mid-hold does not resume it")
	ok(calls.size() == n, "count unchanged since the press (%d -> %d)" % [n, calls.size()])
	_mouse(btn, false)

	btn.queue_free()

	print("\n=== wiring: allocation wheel, Uonite + Focus only ===")
	var wheel = load("res://AllocationWheelControl.tscn").instantiate()
	root.add_child(wheel)
	await process_frame
	await process_frame
	var wheel_buttons: Array = [wheel._plus_uonites, wheel._minus_uonites,
		wheel._plus_foci, wheel._minus_foci]
	var wheel_wired: int = 0
	for b in wheel_buttons:
		if _wired(b):
			wheel_wired += 1
	ok(wheel_wired == 4, "hold-repeat on %d/4 wheel Uonite/Focus buttons" % wheel_wired)
	ok(wheel._plus_volitions != null and wheel._minus_volitions != null, "wheel Volition buttons resolved (precondition)")
	ok(not _wired(wheel._plus_volitions) and not _wired(wheel._minus_volitions), "wheel Volition +/- have NO hold-repeat")
	ok(wheel._plus_volitions.pressed.get_connections().size() > 0
		and wheel._minus_volitions.pressed.get_connections().size() > 0, "wheel Volition +/- still assign on click")

	print("\n=== wiring: Constellation popout, Focus only ===")
	var pop = load("res://ConstellationPopout.tscn").instantiate()
	root.add_child(pop)
	await process_frame
	await process_frame
	ok(_wired(pop._foci_plus) and _wired(pop._foci_minus), "Focus +/- hold-repeat")
	ok(pop._vol_plus != null and pop._vol_minus != null, "Volition buttons resolved (precondition)")
	ok(not _wired(pop._vol_plus) and not _wired(pop._vol_minus), "Volition +/- have NO hold-repeat")
	ok(pop._vol_plus.pressed.get_connections().size() > 0
		and pop._vol_minus.pressed.get_connections().size() > 0, "Volition +/- still assign on click")

	wheel.queue_free()
	pop.queue_free()
	await process_frame

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
