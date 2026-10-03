extends "res://dev_tests/test_base.gd"
# Closing the window on the opening vessel-selection screen used to save a
# blank-vessel playthrough (SaveManager's WM_CLOSE_REQUEST hook saves
# unconditionally); intro_screen.gd treats ANY save on disk as "returning
# player", so every launch after skipped the vessel choice for good.
#
# SaveManager.save_game() now refuses to write while the current scene says
# it is still awaiting that choice.
#
# What must hold:
#  - intro_screen.gd reports "awaiting" only once its choice is actually on
#    screen, and stops reporting it the moment a vessel is confirmed.
#  - A gated save_game() writes NOTHING: no temp file, and the real save
#    files on disk (if this machine has any) are byte-for-byte untouched.
#
# Deliberately never exercises an UNgated save_game() -- that would
# overwrite the developer's real save in user://. The gate's absence is
# therefore not A/B-tested here; the gated half is what this proves.

var fails: int = 0

const SAVE_PATH := "user://djinncremental_save.json"
const BAK_PATH := "user://djinncremental_save.json.bak"
const TMP_PATH := "user://djinncremental_save.json.tmp"


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


class StubScene extends Node:
	var awaiting: bool = true
	func is_awaiting_vessel_choice() -> bool:
		return awaiting


func run() -> void:
	var IntroScreen = load("res://intro_screen.gd")

	print("=== the intro screen's own flag ===")
	var intro = IntroScreen.new()
	ok(not intro.is_awaiting_vessel_choice(), "not awaiting before the choice is on screen")
	intro._awaiting_choice = true
	ok(intro.is_awaiting_vessel_choice(), "awaiting while the choice is on screen")
	intro._confirmed_vessel = ""
	intro._awaiting_choice = false
	ok(not intro.is_awaiting_vessel_choice(), "no longer awaiting once a vessel is confirmed")
	intro.free()

	print("\n=== a gated save_game() writes nothing ===")
	await process_frame
	var sm = root.get_node_or_null("SaveManager")
	ok(sm != null, "SaveManager autoload is reachable")
	if sm == null:
		finish()
		return

	var before_primary: String = _fingerprint(SAVE_PATH)
	var before_backup: String = _fingerprint(BAK_PATH)
	ok(not FileAccess.file_exists(TMP_PATH), "precondition: no stray temp save file")

	var stub := StubScene.new()
	root.add_child(stub)
	var prior_scene = tree.current_scene
	tree.current_scene = stub

	stub.awaiting = true
	sm.save_game()
	ok(not FileAccess.file_exists(TMP_PATH), "no temp file was created while awaiting the vessel choice")
	ok(_fingerprint(SAVE_PATH) == before_primary, "the primary save file is untouched (%s)" % before_primary.substr(0, 12))
	ok(_fingerprint(BAK_PATH) == before_backup, "the backup save file is untouched (%s)" % before_backup.substr(0, 12))

	tree.current_scene = prior_scene
	stub.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
