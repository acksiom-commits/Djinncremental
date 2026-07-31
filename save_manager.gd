extends Node

const SAVE_PATH := "user://djinncremental_save.json"
# Atomic-write scratch + rolling backup. See save_game() for the rotation
# invariant these enforce: at least one of {SAVE_PATH, BAK_PATH} is always a
# complete, valid save at every instant, so a crash/kill/power-loss mid-write
# can never destroy more than the most recent autosave cycle.
const TMP_PATH := "user://djinncremental_save.json.tmp"
const BAK_PATH := "user://djinncremental_save.json.bak"

signal game_loaded(offline_seconds: float)
signal save_reset()
## Emitted when BOTH the primary save and its backup exist but neither can be
## read/parsed. Saving is disabled (see _save_disabled) so the corrupt files
## are preserved for manual recovery instead of being clobbered by the next
## autosave. A UI handler can surface this to the player; even with no handler,
## the save-disable alone prevents the silent data loss that used to happen
## here (load would just start a fresh game, then autosave over the corruption).
signal save_load_failed()

## Set true only when load found existing-but-unreadable save files. While set,
## save_game() refuses to write, so nothing overwrites the corrupt files.
var _save_disabled: bool = false


func save_game() -> void:
    if _save_disabled:
        # A prior load found corrupt save files; writing now would overwrite
        # them and destroy any chance of manual recovery. Stay hands-off.
        return
    var gc:      Node = get_node_or_null("/root/GameContext")
    var cd:      Node = get_node_or_null("/root/ConstellationData")
    var adm:     Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:      Node = get_node_or_null("/root/AchievementRegistry")
    # JournalPopout is a scene node owned by the current age's UI scene, not
    # an autoload — reach it the same way root_ui.gd itself does.
    var journal: Node = null
    if get_tree().current_scene:
        journal = get_tree().current_scene.find_child("JournalPopout", true, false)
    if not gc:
        push_error("SaveManager: GameContext not found.")
        return
    var data: Dictionary = gc.get_save_data()
    if cd and cd.has_method("get_save_data"):
        data["constellation"] = cd.get_save_data()
    if adm and adm.has_method("get_save_data"):
        data["dialogue"] = adm.get_save_data()
    if ar and ar.has_method("get_save_data"):
        data["achievements"] = ar.get_save_data()
    if journal and journal.has_method("get_save_data"):
        data["journal"] = journal.get_save_data()
    data["save_timestamp"] = Time.get_unix_time_from_system()

    # ── Atomic write ──────────────────────────────────────────────────
    # 1. Write the new save to a temp file. Until this fully succeeds the
    #    live save (SAVE_PATH) is never touched, so a failure here leaves
    #    the existing good save completely intact.
    var json_text: String = JSON.stringify(data)
    var tmp := FileAccess.open(TMP_PATH, FileAccess.WRITE)
    if not tmp:
        push_error("SaveManager: could not open temp save file for writing.")
        return
    tmp.store_string(json_text)
    tmp.close()

    # 2. Verify the temp file actually landed intact (catches a truncated
    #    write, a full disk, or a stringify that produced garbage) BEFORE
    #    we trust it enough to rotate the live save out. Never promote an
    #    unverified temp into the primary slot.
    if not _is_readable_save(TMP_PATH):
        push_error("SaveManager: temp save failed verification, keeping previous save.")
        return

    # 3. Rotate. Preserve the current primary as the backup, THEN move the
    #    verified temp into the primary slot. Moving primary→bak first means
    #    the temp→primary rename below always has an absent destination (no
    #    non-atomic remove-then-rename window on Windows). If a crash lands
    #    in the tiny gap between these two renames, primary is momentarily
    #    absent but BAK_PATH holds the last-good save and TMP_PATH holds the
    #    new-good save — load() falls back to the backup either way.
    if FileAccess.file_exists(SAVE_PATH):
        if FileAccess.file_exists(BAK_PATH):
            DirAccess.remove_absolute(BAK_PATH)
        DirAccess.rename_absolute(SAVE_PATH, BAK_PATH)
    DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)


func load_game() -> void:
    var gc:      Node = get_node_or_null("/root/GameContext")
    var cd:      Node = get_node_or_null("/root/ConstellationData")
    var adm:     Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:      Node = get_node_or_null("/root/AchievementRegistry")
    var journal: Node = null
    if get_tree().current_scene:
        journal = get_tree().current_scene.find_child("JournalPopout", true, false)
    if not gc:
        push_error("SaveManager: GameContext not found.")
        return

    # Try the primary save first, then the rolling backup. _read_save returns
    # null for a missing OR unparseable file, so this transparently recovers
    # from a torn primary write by loading the previous good save.
    var data = _read_save(SAVE_PATH)
    var source := "primary"
    if data == null:
        data = _read_save(BAK_PATH)
        source = "backup"

    if data == null:
        # Distinguish "no save exists yet" (legitimate fresh start) from
        # "save files exist but are all unreadable" (real corruption). The
        # old code lumped these together and started a fresh game on
        # corruption — which the next autosave then wrote over the top of,
        # destroying any recovery chance. Now corruption halts loading and
        # disables saving so the files are preserved.
        if FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BAK_PATH):
            push_error("SaveManager: save AND backup are both unreadable — halting load and disabling saves to preserve the files for recovery.")
            _save_disabled = true
            emit_signal("save_load_failed")
            return
        push_warning("SaveManager: no save file found, starting fresh.")
        emit_signal("game_loaded", 0.0)
        return

    if source == "backup":
        push_warning("SaveManager: primary save was unreadable, recovered from backup.")

    gc.load_save_data(data)
    # `data.get(key) is Dictionary` checks both "key present" and "value is
    # the right type" in one expression — replaces the old `data.has(key)`
    # check, which only verified the key existed. Each load_save_data()
    # below has a typed `data: Dictionary` parameter, and passing a wrong-
    # typed value (a corrupted save could put a String/Array there instead
    # of a nested object) hangs the engine at the call boundary rather than
    # raising a catchable error — confirmed directly — so it has to be
    # checked here, before the call, not inside the callee's own body.
    if cd and cd.has_method("load_save_data") and data.get("constellation") is Dictionary:
        cd.load_save_data(data["constellation"])
    if adm and adm.has_method("load_save_data") and data.get("dialogue") is Dictionary:
        adm.load_save_data(data["dialogue"])
    if ar and ar.has_method("load_save_data") and data.get("achievements") is Dictionary:
        ar.load_save_data(data["achievements"])
    if journal and journal.has_method("load_save_data") and data.get("journal") is Dictionary:
        journal.load_save_data(data["journal"])
    var raw_timestamp = data.get("save_timestamp")
    var timestamp: float = float(raw_timestamp) if (raw_timestamp is int or raw_timestamp is float) else -1.0
    var elapsed := 0.0
    if timestamp > 0.0:
        elapsed = Time.get_unix_time_from_system() - timestamp
    emit_signal("game_loaded", elapsed)


func reset_save() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(SAVE_PATH)
    if FileAccess.file_exists(BAK_PATH):
        DirAccess.remove_absolute(BAK_PATH)
    if FileAccess.file_exists(TMP_PATH):
        DirAccess.remove_absolute(TMP_PATH)
    # A fresh reset clears any prior corrupt-file lockout so saving resumes.
    _save_disabled = false
    emit_signal("save_reset")


# Reads and parses a save file. Returns the parsed Dictionary, or null if the
# file is missing, unreadable, or not a valid JSON object. Shared by load_game()
# (recovery fallback) and _is_readable_save() (post-write verification).
func _read_save(path: String):
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return null
    var text := file.get_as_text()
    file.close()
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return null
    return parsed


func _is_readable_save(path: String) -> bool:
    return _read_save(path) != null
