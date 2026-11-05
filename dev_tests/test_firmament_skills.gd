extends "res://dev_tests/test_base.gd"
# Firmament skills (2026-11-04): GameData.SKILLS names Mold, Carve and Forge on
# red skill cards and Distill on a blue one, and puts each on the Manifold
# dial as a clickable name that turns the spout to it.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _settle(seconds: float = 1.5) -> void:
	# By time, not frames: headless runs are not held to 60 fps.
	await root.get_tree().create_timer(seconds).timeout


func _angle_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gd = root.get_node_or_null("/root/GameData")
	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	# Cards and dial buttons are built in _ready; this only lets layout settle.
	await _settle(0.3)
	var car: Control = firm.find_child("Carousel", true, false)
	var dial: Control = firm.find_child("ManifoldDial", true, false)

	print("=== the skill list ===")
	var names: Array = []
	for s in gd.SKILLS:
		names.append(s["name"])
	ok(names == ["Mold", "Carve", "Forge", "Distill"], "skills in order: %s" % str(names))

	print("\n=== skill cards ===")
	var red: Color = gd.CARD_COLORS[0]
	var blue: Color = gd.CARD_COLORS[1]
	var expect: Dictionary = {0: ["Mold", red], 1: ["Carve", red], 2: ["Forge", red], 6: ["Distill", blue]}
	var labelled: int = 0
	var right: int = 0
	for i in car.panels.size():
		var lbl: Label = car.panels[i].get_node_or_null("SkillLabel")
		if lbl == null:
			continue
		labelled += 1
		# The property, not get_theme_stylebox(): theme getters can hang headless.
		var style: StyleBoxFlat = car.panels[i].get("theme_override_styles/panel")
		if expect.has(i) and lbl.text == expect[i][0] and style.border_color.is_equal_approx(expect[i][1]):
			right += 1
		else:
			print("    card %d shows %s" % [i, lbl.text])
	ok(labelled == 4 and right == 4,
		"4 of %d cards carry a skill name, %d on the right card and colour" % [car.panels.size(), right])

	print("\n=== the dial's skill names turn the spout ===")
	var turned: int = 0
	var want: float = 0.0
	for k in gd.SKILLS.size():
		var btn: Button = dial.find_child("DialSkill_" + String(gd.SKILLS[k]["key"]), false, false)
		if btn == null:
			print("    no dial button for %s" % gd.SKILLS[k]["name"])
			continue
		btn.pressed.emit()
		want = -90.0 + float(gd.SKILLS[k]["dial_hour"]) * 30.0
		var gap: float = _angle_gap(dial._spout_target_deg, want)
		var inside: bool = btn.position.distance_to(dial._center() - btn.size * 0.5) < dial.DIAL_RADIUS
		if gap < 0.01 and dial._selected_skill == k and dial._selected_index == -1 and inside:
			turned += 1
		else:
			print("    %s: spout target %.1f, wanted %.1f, inside %s" % [btn.text, dial._spout_target_deg, want, inside])
	ok(turned == gd.SKILLS.size(), "%d of %d skill names aim the spout at themselves" % [turned, gd.SKILLS.size()])
	await _settle()
	ok(_angle_gap(dial._channel_angle_deg, want) < 1.0,
		"the spout turns there (%.1f, wanted %.1f)" % [dial._channel_angle_deg, want])

	print("\n=== the outputs show ===")
	var shown: int = 0
	var inside: int = 0
	var box: Rect2 = dial.get_parent().get_global_rect()
	for key in dial.OUTPUT_KEYS:
		var b: BaseButton = dial.find_child("DialIcon_" + key, false, false)
		var has_face: bool = b != null and ((b is TextureButton and (b as TextureButton).texture_normal != null) \
			or (b is Button and (b as Button).text != ""))
		if has_face and b.size.x > 4.0 and b.size.y > 4.0:
			shown += 1
		else:
			print("    %s shows nothing" % key)
		if b != null and box.encloses(b.get_global_rect()):
			inside += 1
		elif b != null:
			print("    %s sticks out of the dial's panel (%s, panel %s)" % [key, str(b.get_global_rect()), str(box)])
	ok(shown == dial.OUTPUT_KEYS.size(), "%d of %d outputs show an icon or their name" % [shown, dial.OUTPUT_KEYS.size()])
	ok(inside == dial.OUTPUT_KEYS.size(), "%d of %d sit wholly inside the dial's panel" % [inside, dial.OUTPUT_KEYS.size()])

	var icon: BaseButton = dial.find_child("DialIcon_steam", false, false)
	icon.pressed.emit()
	await _settle()
	ok(_angle_gap(dial._channel_angle_deg, 180.0) < 1.0 and dial._selected_skill == -1 and dial._selected_index == 9,
		"an output icon still turns it, and clears the skill (spout %.1f)" % dial._channel_angle_deg)

	firm.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
