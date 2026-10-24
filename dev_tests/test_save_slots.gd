extends "res://dev_tests/test_base.gd"
# Save slots + the Autosave toggle (2026-10-23).
#
# What must hold:
#  - Slot 1 IS the pre-slot save file, so existing saves need no migration.
#  - A write to another slot lands in that slot only: slot 1's files and the
#    device settings file are byte-for-byte untouched, and the active slot
#    doesn't move.
#  - Resetting a NON-active slot deletes its files without pausing saving.
#  - autosave() writes nothing while autosave is off, and does write once
#    it's back on (A/B, so the "nothing" isn't vacuous).
#  - The Settings popout builds one button per slot and relabels Save/Load
#    for the selected slot.
#
# Real files: this runs against the developer's real user://, so every
# write targets slot 3 and the whole section is SKIPPED if slot 3 already
# holds a save. active_slot/autosave_enabled are flipped in memory only
# (never through _save_settings), so an abort can't change the boot slot.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _fingerprint(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "absent"
	return "%d:%s" % [FileAccess.get_modified_time(path), FileAccess.get_file_as_string(path).md5_text()]


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("SaveManager")
	ok(sm != null, "SaveManager autoload is reachable")
	if sm == null:
		finish()
		return

	# The two age scenes' hosts aren't instantiated anywhere below, so a
	# broken signature in their slot handlers would otherwise go unseen.
	print("=== every script the slot change touched compiles ===")
	for p in ["res://save_manager.gd", "res://settings_popout.gd", "res://root_ui.gd", "res://firmament_ui.gd"]:
		var s = load(p)
		ok(s != null and s.can_instantiate(), "%s compiles" % p)

	print("\n=== slot paths ===")
	ok(sm.slot_save_path(1) == sm.SAVE_PATH, "slot 1 is the pre-slot save file")
	var paths: Dictionary = {}
	for slot in range(1, sm.SLOT_COUNT + 1):
		paths[sm.slot_save_path(slot)] = true
	ok(paths.size() == sm.SLOT_COUNT, "all %d slots have distinct paths" % sm.SLOT_COUNT)

	print("\n=== writes stay in their slot ===")
	const TEST_SLOT := 3
	var orig_active: int = sm.active_slot
	var orig_autosave: bool = sm.autosave_enabled
	if sm.slot_has_save(TEST_SLOT) or orig_active == TEST_SLOT or sm.saving_paused():
		print("  SKIP  slot %d holds a save, is active, or saving is paused -- not touching real files" % TEST_SLOT)
	else:
		var slot1_primary: String = _fingerprint(sm.SAVE_PATH)
		var slot1_backup: String = _fingerprint(sm.BAK_PATH)
		var settings_before: String = _fingerprint(sm.SETTINGS_PATH)

		ok(sm._write_slot(TEST_SLOT), "a write to slot %d reports success" % TEST_SLOT)
		ok(sm.slot_has_save(TEST_SLOT), "slot %d now has a save" % TEST_SLOT)
		ok(sm.slot_saved_unix(TEST_SLOT) > 0, "slot %d has a save time" % TEST_SLOT)
		ok(sm._read_save(sm.slot_save_path(TEST_SLOT)) is Dictionary, "slot %d's file parses" % TEST_SLOT)
		ok(sm.active_slot == orig_active, "the active slot did not move (%d)" % orig_active)
		ok(_fingerprint(sm.SAVE_PATH) == slot1_primary, "slot 1's primary is untouched")
		ok(_fingerprint(sm.BAK_PATH) == slot1_backup, "slot 1's backup is untouched")

		sm.reset_slot(TEST_SLOT)
		ok(not sm.slot_has_save(TEST_SLOT), "resetting slot %d removed its files" % TEST_SLOT)
		ok(not FileAccess.file_exists(sm.slot_save_path(TEST_SLOT) + ".tmp"), "no stray temp file left")
		ok(not sm.saving_paused(), "resetting a non-active slot leaves saving on")

		print("\n=== the Autosave toggle gates autosave() ===")
		sm.active_slot = TEST_SLOT
		sm.autosave_enabled = false
		sm.autosave()
		var wrote_while_off: bool = sm.slot_has_save(TEST_SLOT)
		sm.autosave_enabled = true
		sm.autosave()
		var wrote_while_on: bool = sm.slot_has_save(TEST_SLOT)
		sm.active_slot = orig_active
		sm.autosave_enabled = orig_autosave
		sm.reset_slot(TEST_SLOT)
		ok(not wrote_while_off, "autosave() wrote nothing with autosave off")
		ok(wrote_while_on, "autosave() did write with autosave on (A/B)")
		ok(not sm.slot_has_save(TEST_SLOT), "slot %d cleaned up" % TEST_SLOT)
		ok(_fingerprint(sm.SAVE_PATH) == slot1_primary, "slot 1's primary is still untouched")
		ok(_fingerprint(sm.SETTINGS_PATH) == settings_before, "the device settings file is untouched")

	print("\n=== Settings popout ===")
	var popout = load("res://SettingsPopout.tscn").instantiate()
	root.add_child(popout)
	await process_frame
	ok(popout._slot_btns.size() == sm.SLOT_COUNT, "one slot button per slot (%d)" % popout._slot_btns.size())
	ok(popout._autosave_tog.button_pressed == sm.autosave_enabled, "Autosave toggle shows the saved preference")
	ok(popout._selected_slot == sm.active_slot, "the active slot starts selected")
	ok(popout._save_btn.text == "Save Game", "Save reads 'Save Game' on the active slot")
	var other: int = 1 if sm.active_slot != 1 else 2
	popout._select_slot(other)
	ok(popout._save_btn.text == "Save to Slot %d" % other, "Save relabels for slot %d: '%s'" % [other, popout._save_btn.text])
	var expect_load: String = ("Load Slot %d" % other) if sm.slot_has_save(other) else "New Game"
	ok(popout._load_btn.text == expect_load, "Load relabels for slot %d: '%s'" % [other, popout._load_btn.text])
	ok(popout._reset_btn.disabled == not sm.slot_has_save(other), "Reset is disabled exactly when the slot is empty")
	popout.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
