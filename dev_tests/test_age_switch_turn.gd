extends "res://dev_tests/test_base.gd"
# Switching ages turns the view across the sky (age_switch_turn.gd, author
# 2026-11-03): later ages lie to the right, closed edge panels stay hidden
# while the pages slide, and the starfield holds the view it is given while a
# turn is on. The whole switch was checked by frames with a save loaded; it
# swaps the running scene, so it isn't run here.

const Turn = preload("res://age_switch_turn.gd")
const Starfield = preload("res://starfield_background.gd")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame

	print("=== later ages lie to the right ===")
	var order: Array = Turn.AGE_SCENES
	ok(order.find("res://FirmamentUI.tscn") > order.find("res://RootUI.tscn"),
		"Firmament is right of Primordial, so going there turns right")

	print("\n=== pages are loaded ahead, so a switch doesn't wait on loading ===")
	Turn._scenes.clear()
	Turn.warm_neighbours("res://FirmamentUI.tscn")
	ok(Turn._scenes.has("res://FirmamentUI.tscn") and Turn._scenes.has("res://RootUI.tscn"),
		"Firmament keeps its own page and loads Primordial's (%s)" % str(Turn._scenes.keys()))
	ok(not Turn._scenes.has("res://WorldUI.tscn") or ResourceLoader.exists("res://WorldUI.tscn"),
		"an age with no page yet is skipped")
	Turn._scenes.clear()

	print("\n=== pages made ahead on hover are kept, and freed by their own tab ===")
	var tab_a := Node.new()
	var tab_b := Node.new()
	Turn.prepare("res://FirmamentUI.tscn", tab_a)
	Turn.prepare("res://RootUI.tscn", tab_b)
	var made = Turn._prebuilt.get("res://FirmamentUI.tscn")
	ok(made != null and not made.is_inside_tree(), "hovering makes the page without adding it (no setup runs)")
	Turn.prepare("res://FirmamentUI.tscn", tab_a)
	ok(Turn._prebuilt.get("res://FirmamentUI.tscn") == made, "hovering again reuses it")
	Turn.release_prebuilt(tab_a)
	ok(not is_instance_valid(made) and Turn._prebuilt.has("res://RootUI.tscn"),
		"a tab frees only the pages it made")
	Turn.release_prebuilt(tab_b)
	ok(Turn._prebuilt.is_empty(), "and none are left over")
	tab_a.free()
	tab_b.free()

	print("\n=== the Journal (History and Notices) is handed to the new page ===")
	# 2026-11-04: pages own their Journal. Saves made on Firmament wrote its
	# empty Journal over the history, and Primordial's re-read on arrival put
	# the saved Journal into the old page. Now the switch hands it over.
	var JournalScene = load("res://JournalPopout.tscn")
	var old_page := Node.new()
	var old_j = JournalScene.instantiate()
	old_page.add_child(old_j)
	root.add_child(old_page)
	var new_page := Node.new()
	var new_j = JournalScene.instantiate()
	new_page.add_child(new_j)
	root.add_child(new_page)
	await process_frame
	old_j.append_sequence("Earlier talk", ["a line"])
	old_j.append_notification("Earlier notice")
	new_j.append_notification("Arrival notice")
	Turn._hand_on_journal(Turn._journal_data(old_page), new_page)
	var got: Dictionary = new_j.get_save_data()
	ok(got["sequences"].size() == 1 and str(got["sequences"][0].get("name")) == "Earlier talk",
		"History carries over (%d entries)" % got["sequences"].size())
	ok(got["notifications"].size() == 2 and str(got["notifications"][0]).contains("Earlier notice")
		and str(got["notifications"][1]).contains("Arrival notice"),
		"Notices carry over, followed by the new page's own (%s)" % str(got["notifications"]))
	old_page.queue_free()
	new_page.queue_free()

	var firm = load("res://FirmamentUI.tscn").instantiate()
	root.add_child(firm)
	await process_frame
	var fui = firm.find_child("FirmRootUI", true, false)
	ok(fui._journal_popout != null, "Firmament finds its Journal, so it records History and Notices")
	firm.queue_free()
	await process_frame

	print("\n=== edge panels hide while the pages slide ===")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var page := Control.new()          # a page root: on screen across, taller than the window
	page.position = Vector2.ZERO
	page.size = Vector2(1280, 1300)
	layer.add_child(page)
	var tab := Control.new()           # an edge tab, on screen
	tab.position = Vector2(1256, 40)
	tab.size = Vector2(22, 400)
	page.add_child(tab)
	var panel := Control.new()         # its closed panel, 2 px inside the edge
	panel.position = Vector2(1278, 40)
	panel.size = Vector2(380, 400)
	page.add_child(panel)
	var left_panel := Control.new()    # a closed left-edge panel
	left_panel.position = Vector2(-700, 200)
	left_panel.size = Vector2(700, 465)
	page.add_child(left_panel)
	await process_frame
	var hidden: Array = Turn._hide_offside(layer, 1280.0)
	ok(hidden.has(panel) and hidden.has(left_panel) and not panel.visible and not left_panel.visible,
		"closed panels past either edge are hidden (%d hidden)" % hidden.size())
	ok(page.visible and tab.visible and hidden.size() == 2,
		"the page root (taller than the window) and the tab stay")
	layer.queue_free()

	print("\n=== the starfield holds a set view while turning ===")
	var sf: ColorRect = Starfield.new()
	sf.material = ShaderMaterial.new()
	sf.material.shader = load("res://starfield.gdshader")
	root.add_child(sf)
	var view := Basis(Vector3.UP, 0.7)
	sf.set_turning(true)
	sf.set_view_matrix(view)
	for i in 10:
		await process_frame
	ok(sf.get_effective_view_matrix().is_equal_approx(view), "while turning, nothing else moves the view")
	sf.set_turning(false)
	for i in 10:
		await process_frame
	ok(not sf.get_effective_view_matrix().is_equal_approx(view), "after the turn its slow drift carries on")
	sf.queue_free()

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
