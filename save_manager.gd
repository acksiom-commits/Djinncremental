extends Node

# Bumped whenever a future patch changes the *shape* of the top-level save
# dict in a way older code can't already handle gracefully (a field rename,
# removal, or restructuring — not a plain new field, since every
# load_save_data() already treats a missing key as "use the default").
# load_game() reads this into loaded_save_format_version before dispatching
# to any subsystem; a version-gated migration step (mirroring the existing
# precedent at game_context.gd's _migrate_flat_volitions_to_slots(), which
# was keyed on key-presence before this field existed) belongs here, run
# once on the raw `data` dict before the per-subsystem load calls below.
# Nothing to migrate yet — this is the alpha's first save format.
const SAVE_FORMAT_VERSION: int = 1

## The save_format_version load_game() most recently read, or -1 before any
## load has happened. 0 means "predates this field" (every save written
## before this version stamp existed) — distinct from "field present but
## wrong-typed", which also falls back to 0 since there's nothing coherent
## to migrate from a value that isn't even the right type.
var loaded_save_format_version: int = -1

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
## Emitted when the atomic-write rotation's final tmp->primary rename fails
## (locked by antivirus/cloud-sync, permissions, disk error, etc.) — the
## verified new save data is stranded in TMP_PATH and never went live.
## Not fatal on its own: the previous good save is untouched (rename never
## got that far), and the next autosave 60s later is a fresh, independent
## attempt that will likely succeed once the lock clears. A UI handler can
## surface this; even with no handler, at minimum it's now logged instead
## of silently discarded.
signal save_failed()

## Set true only when load found existing-but-unreadable save files. While set,
## save_game() refuses to write, so nothing overwrites the corrupt files.
var _save_disabled: bool = false


# Nothing in this project previously saved on quit at all — the game relied
# entirely on the 60s autosave timer (root_ui.gd's _process()). A player who
# quits (via the OS window's close button, Alt+F4, etc.) before that timer
# has ever fired — trivially possible in the first minute of a brand-new
# game, e.g. mid-way through the very first Monad tutorial dialogue — has no
# save file at all yet, so the next load falls into load_game()'s legitimate
# "no save file found, starting fresh" branch. From the player's side that's
# indistinguishable from "reloading wiped my progress", even though nothing
# was actually lost that had ever been written. This notification is Godot's
# standard hook for "the OS asked this window to close" and runs synchronously
# before the engine proceeds to quit, so a blocking save_game() call here
# (no async/await anywhere in this function) completes before exit.
# Does NOT cover a direct get_tree().quit() call from in-game UI (e.g. the
# Settings panel's Quit button) — that bypasses this notification entirely;
# see root_ui.gd's quit_requested handler for that path's own save call.
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_game()


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
    data["save_format_version"] = SAVE_FORMAT_VERSION

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
    #
    #    None of these three calls' return values were checked before — a
    #    transient lock (antivirus/cloud-sync scanning the save folder is
    #    common on Windows, exactly what itch.io testers are likely to have
    #    running) could silently no-op a save with no error, no signal,
    #    nothing — the player would only find out when they next relaunch
    #    and their progress isn't there. Confirmed directly: rename_absolute
    #    returns OK (and actually overwrites) when the destination already
    #    exists, and a non-OK Error code when it genuinely can't complete —
    #    that return value just needs to be looked at.
    if FileAccess.file_exists(SAVE_PATH):
        if FileAccess.file_exists(BAK_PATH):
            var remove_err: Error = DirAccess.remove_absolute(BAK_PATH)
            if remove_err != OK:
                # Not fatal by itself — rename_absolute overwrites an
                # existing destination fine, so still attempt the rotation.
                push_warning("SaveManager: could not remove stale backup (error %d), attempting rotation anyway." % remove_err)
        var to_backup_err: Error = DirAccess.rename_absolute(SAVE_PATH, BAK_PATH)
        if to_backup_err != OK:
            # Backup rotation failed but the primary is untouched — still
            # worth promoting the verified new save over it directly rather
            # than discarding a good write over one failed housekeeping
            # step; BAK_PATH just ends up one cycle staler than usual.
            push_warning("SaveManager: could not rotate primary save to backup (error %d)." % to_backup_err)
    var to_primary_err: Error = DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
    if to_primary_err != OK:
        push_error("SaveManager: could not promote new save into primary slot (error %d) — the new save is stranded in %s and never went live; the previous save is untouched." % [to_primary_err, TMP_PATH])
        emit_signal("save_failed")


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

    var raw_version = data.get("save_format_version")
    loaded_save_format_version = int(raw_version) if (raw_version is int or raw_version is float) else 0
    # Version-gated migrations on the raw `data` dict (renamed/removed/
    # restructured fields, as opposed to a plain new field — see the
    # SAVE_FORMAT_VERSION comment) would run here, before any subsystem's
    # load_save_data() sees `data`. None exist yet.

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
    # Return values checked for the same reason as save_game()'s rotation
    # (see its comment): a transient lock (antivirus/cloud-sync on Windows)
    # can silently no-op a delete with no error otherwise. A failed delete
    # here isn't catastrophic on its own — the in-memory state still resets
    # and the next autosave would normally overwrite the stale file within
    # 60s — but if the player quits before that autosave fires, the next
    # load would silently resurrect the pre-reset save, making Reset look
    # like it did nothing. Warn so it's at least visible in the logs.
    if FileAccess.file_exists(SAVE_PATH):
        var err: Error = DirAccess.remove_absolute(SAVE_PATH)
        if err != OK:
            push_warning("SaveManager: could not remove primary save on reset (error %d)." % err)
    if FileAccess.file_exists(BAK_PATH):
        var err: Error = DirAccess.remove_absolute(BAK_PATH)
        if err != OK:
            push_warning("SaveManager: could not remove backup save on reset (error %d)." % err)
    if FileAccess.file_exists(TMP_PATH):
        var err: Error = DirAccess.remove_absolute(TMP_PATH)
        if err != OK:
            push_warning("SaveManager: could not remove temp save on reset (error %d)." % err)
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
